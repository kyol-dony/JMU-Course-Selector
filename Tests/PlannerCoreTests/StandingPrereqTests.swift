import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Class standing")
struct ClassStandingTests {
    @Test("a four-year plan reaches each standing by semester position")
    func fourYearPositions() {
        let standings = (1...8).map { ClassStanding.forSemester(position: $0, totalSemesters: 8) }
        #expect(standings == [
            .firstYear, .firstYear,
            .sophomore, .sophomore,
            .junior, .junior,
            .senior, .senior
        ])
    }

    @Test("a shorter plan reaches standing by semesters remaining")
    func threeYearRemaining() {
        // 6 semesters: semester 1 has 6 remaining (sophomore), 3 has 4
        // remaining (junior), 5 has 2 remaining (senior).
        let standings = (1...6).map { ClassStanding.forSemester(position: $0, totalSemesters: 6) }
        #expect(standings == [
            .sophomore, .sophomore,
            .junior, .junior,
            .senior, .senior
        ])
    }

    @Test("without a known plan length only the position rule applies")
    func positionOnly() {
        #expect(ClassStanding.forSemester(position: 1, totalSemesters: nil) == .firstYear)
        #expect(ClassStanding.forSemester(position: 5, totalSemesters: nil) == .junior)
        #expect(ClassStanding.forSemester(position: 12, totalSemesters: nil) == .senior)
    }

    @Test("requirements honor both their lower and upper bound")
    func requirementBounds() {
        let juniorPlus = StandingRequirement(minimum: .junior)
        #expect(!juniorPlus.isSatisfied(by: .sophomore))
        #expect(juniorPlus.isSatisfied(by: .junior))
        #expect(juniorPlus.isSatisfied(by: .senior))

        let underclass = StandingRequirement(minimum: .firstYear, maximum: .sophomore)
        #expect(underclass.isSatisfied(by: .firstYear))
        #expect(!underclass.isSatisfied(by: .junior))
    }

    @Test("standing leaves survive enforcement and round-trip through JSON")
    func exprCodableAndEnforced() throws {
        let expr: PrereqExpr = .all([.course("cs-240"), .standing(StandingRequirement(minimum: .junior)), .unknown("permission")])
        #expect(expr.enforcedCourseOnly == .all([.course("cs-240"), .standing(StandingRequirement(minimum: .junior))]))
        let decoded = try JSONDecoder().decode(PrereqExpr.self, from: JSONEncoder().encode(expr))
        #expect(decoded == expr)
    }
}

@Suite("Standing prerequisite parsing")
struct StandingParserTests {
    private let parser = PrereqParser(coursesByID: [
        "CS240": Course(id: "CS240", code: "CS 240", title: "Algorithms", credits: 3, availability: nil, prerequisites: []),
        "MUS144": Course(id: "MUS144", code: "MUS 144", title: "Theory", credits: 3, availability: nil, prerequisites: [])
    ])

    private func standing(_ minimum: ClassStanding, _ maximum: ClassStanding = .senior) -> PrereqExpr {
        .standing(StandingRequirement(minimum: minimum, maximum: maximum))
    }

    @Test("bare standing prerequisites parse cleanly", arguments: [
        ("Prerequisites: Sophomore standing.", ClassStanding.sophomore),
        ("Prerequisites: Junior standing", .junior),
        ("Prerequisites: Senior standing.", .senior),
        ("Prerequisites: Junior or senior standing.", .junior),
        ("Prerequisites: Junior or senior standing only.", .junior),
        ("Prerequisites: Students must have junior /senior standing.", .junior),
        ("Prerequisites: Completion of the focus, jr/sr standing.", .junior)
    ])
    func bareStanding(input: String, minimum: ClassStanding) {
        let result = parser.parse(input)
        let leaves = Self.standingLeaves(result.prerequisiteExpr)
        #expect(leaves == [StandingRequirement(minimum: minimum)])
    }

    @Test("pure standing prerequisites are not flagged as unparsed")
    func pureStandingIsNotUnknown() {
        #expect(parser.parse("Prerequisites: Junior or senior standing only.").hasUnknownTokens == false)
        #expect(parser.parse("Prerequisites: At least junior standing.").hasUnknownTokens == false)
    }

    @Test("standing combines with courses using and/or")
    func combinesWithCourses() {
        #expect(parser.parse("Prerequisite: CS 240 and junior standing.").prerequisiteExpr
            == .all([.course("CS240"), standing(.junior)]))
        #expect(parser.parse("Prerequisites: MUS 144 or junior standing.").prerequisiteExpr
            == .any([.course("MUS144"), standing(.junior)]))
    }

    @Test("first-year or sophomore standing is an upper bound")
    func upperBound() {
        #expect(parser.parse("Prerequisites: First-year or sophomore standing.").prerequisiteExpr
            == standing(.firstYear, .sophomore))
    }

    @Test("leftover text beside a standing phrase stays flagged")
    func residualTextStaysUnknown() {
        let result = parser.parse("Prerequisites: Senior standing in the IA program.")
        #expect(result.prerequisiteExpr == standing(.senior))
        #expect(result.hasUnknownTokens)
    }

    @Test("an Oxford-comma list keeps every item after ', and'")
    func oxfordCommaAnd() {
        let parser = PrereqParser(coursesByID: [
            "ECON200": Course(id: "ECON200", code: "ECON 200", title: "Micro", credits: 3, availability: nil, prerequisites: []),
            "ECON201": Course(id: "ECON201", code: "ECON 201", title: "Macro", credits: 3, availability: nil, prerequisites: [])
        ])
        #expect(parser.parse("Prerequisites: ECON 200 , ECON 201 , and junior or senior standing.").prerequisiteExpr
            == .all([.course("ECON200"), .course("ECON201"), standing(.junior)]))
    }

    @Test("semicolons separate clauses more loosely than 'or'")
    func semicolonPrecedence() {
        let ids = ["MATH238", "MATH300", "MATH318", "MATH329", "SMAD201", "SMAD202"]
        let parser = PrereqParser(coursesByID: Dictionary(uniqueKeysWithValues: ids.map { id in
            let code = id.replacingOccurrences(of: #"(\D+)(\d+)"#, with: "$1 $2", options: .regularExpression)
            return (id, Course(id: id, code: code, title: id, credits: 3, availability: nil, prerequisites: []))
        }))
        #expect(parser.parse("Prerequisites: MATH 238 or MATH 300 ; and MATH 318 or MATH 329 .").prerequisiteExpr
            == .all([.any([.course("MATH238"), .course("MATH300")]), .any([.course("MATH318"), .course("MATH329")])]))
        // "; or permission" is an alternative to everything before it.
        let result = parser.parse("Prerequisites: SMAD 201 , and SMAD 202 ; or permission of the instructor.")
        #expect(result.prerequisiteExpr.enforcedCourseOnly == .all([.course("SMAD201"), .course("SMAD202")]))
    }

    @Test("'standing or higher' and 'standing or above' mean the minimum")
    func orHigher() {
        #expect(parser.parse("Prerequisites: Junior standing or higher.").prerequisiteExpr == standing(.junior))
        #expect(parser.parse("Prerequisites: CS 240 and sophomore standing or above.").prerequisiteExpr
            == .all([.course("CS240"), standing(.sophomore)]))
    }

    @Test("a standing phrase the grammar can't reach is still enforced and flagged")
    func unreachableStandingFallsBack() {
        let result = parser.parse("Prerequisites: Non-business majors only. Junior standing or higher.")
        #expect(Self.standingLeaves(result.prerequisiteExpr) == [StandingRequirement(minimum: .junior)])
        #expect(result.prerequisiteExpr.enforcedCourseOnly == standing(.junior))
        #expect(result.hasUnknownTokens)
    }

    @Test("standing before 'one of the following' survives the choice-list trim")
    func standingBeforeChoiceList() {
        let parser = PrereqParser(coursesByID: [
            "SMAD330": Course(id: "SMAD330", code: "SMAD 330", title: "A", credits: 3, availability: nil, prerequisites: []),
            "SMAD370": Course(id: "SMAD370", code: "SMAD 370", title: "B", credits: 3, availability: nil, prerequisites: [])
        ])
        let result = parser.parse("Prerequisites: Senior standing and one of the following SMAD 330 or SMAD 370.")
        #expect(result.prerequisiteExpr == .all([.any([.course("SMAD330"), .course("SMAD370")]), standing(.senior)]))
    }

    @Test("a standing phrase in another major's clause is not applied")
    func otherMajorClauseIgnored() {
        let parser = PrereqParser(
            coursesByID: ["COB300": Course(id: "COB300", code: "COB 300", title: "Core", credits: 12, availability: nil, prerequisites: [])],
            activeProgramTitle: "CIS, B.B.A."
        )
        let result = parser.parse("Prerequisites: For CIS majors: COB 300. For CIS minors: junior or senior standing.")
        #expect(result.prerequisiteExpr == .course("COB300"))
    }

    @Test("level words without 'standing' are standing requirements", arguments: [
        // "status" is a synonym
        ("Prerequisites: HUMN 201 and junior status.", StandingRequirement(minimum: .junior)),
        ("Prerequisites: At least four hours of lab science, at least sophomore status, and permission of the instructor.", StandingRequirement(minimum: .sophomore)),
        ("Prerequisites: JUST 200 and junior or senior status, or by permission.", StandingRequirement(minimum: .junior)),
        // a level word describing majors / minors / students
        ("Prerequisites: FIN 360 and FIN 365 and senior Finance majors.", StandingRequirement(minimum: .senior)),
        ("Prerequisites: Senior INTA majors.", StandingRequirement(minimum: .senior)),
        ("Prerequisites: JUST 200 , JUST 399 and senior JUST major.", StandingRequirement(minimum: .senior)),
        ("Prerequisites: Senior dance majors only.", StandingRequirement(minimum: .senior)),
        // lists of levels are bounded ranges
        ("Prerequisites: Sophomore, junior and senior dance majors only.", StandingRequirement(minimum: .sophomore)),
        ("Prerequisites: Junior and senior dance majors only.", StandingRequirement(minimum: .junior)),
        ("Prerequisites: First year students and sophomores only; others by permission of the program.", StandingRequirement(minimum: .firstYear, maximum: .sophomore)),
        // a single level with "only" is exact
        ("Prerequisites: Open only to sophomore business majors. Maximum of 2 attempts for COB 202 .", StandingRequirement(minimum: .sophomore, maximum: .sophomore)),
        ("Prerequisites: Sophomore standing only.", StandingRequirement(minimum: .sophomore, maximum: .sophomore))
    ])
    func levelWordsWithoutStanding(input: String, expected: StandingRequirement) {
        #expect(Self.standingLeaves(parser.parse(input).prerequisiteExpr) == [expected])
    }

    @Test("a major condition beside a level word stays flagged")
    func levelWithMajorStaysFlagged() {
        #expect(parser.parse("Prerequisites: Senior INTA majors.").hasUnknownTokens)
        #expect(!parser.parse("Prerequisites: Junior status.").hasUnknownTokens)
    }

    @Test("'or senior X major' becomes a standing alternative")
    func levelAlternative() {
        let parser = PrereqParser(coursesByID: [
            "HTH320": Course(id: "HTH320", code: "HTH 320", title: "A", credits: 3, availability: nil, prerequisites: []),
            "HTH351": Course(id: "HTH351", code: "HTH 351", title: "B", credits: 3, availability: nil, prerequisites: [])
        ])
        let result = parser.parse("Prerequisites: HTH 320 and HTH 351 ; or senior health services administration major.")
        #expect(result.prerequisiteExpr.enforcedCourseOnly
            == .any([.all([.course("HTH320"), .course("HTH351")]), standing(.senior)]))
    }

    @Test("level words that don't describe students are left alone", arguments: [
        "Prerequisites: Completion of the senior thesis proposal.",
        "Prerequisites: Junior year abroad approval.",
        "Prerequisites: ENG 302 or permission of the senior instructor.",
        // an exception clause, not a requirement
        "Prerequisites: THEA 251; second-semester juniors may enroll with instructor permission."
    ])
    func unrelatedLevelWords(input: String) {
        #expect(Self.standingLeaves(parser.parse(input).prerequisiteExpr).isEmpty)
    }

    static func standingLeaves(_ expr: PrereqExpr) -> [StandingRequirement] {
        switch expr {
        case .standing(let requirement): [requirement]
        case .all(let children), .any(let children): children.flatMap(standingLeaves)
        default: []
        }
    }
}

@Suite("Standing prerequisite warnings")
struct StandingWarningTests {
    static let semesters: [SemesterIdentity] = {
        var result = [SemesterIdentity(year: 2026, term: .fall)]
        while result.count < 8 { result.append(result.last!.next) }
        return result
    }()

    static func catalog() -> Catalog {
        Catalog.fixture(
            courses: [
                Course(id: "FILL", code: "FILL 100", title: "Filler", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "MUS144", code: "MUS 144", title: "Theory", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CS440", code: "CS 440", title: "Upper", credits: 3, availability: [.fall, .spring], prerequisites: [], rawPrerequisiteText: "Prerequisites: Junior standing."),
                Course(id: "MUS317", code: "MUS 317", title: "Counterpoint", credits: 3, availability: [.fall, .spring], prerequisites: [], rawPrerequisiteText: "Prerequisites: MUS 144 or junior standing.")
            ],
            program: Program.fixture(id: "p", title: "P", requirements: [])
        )
    }

    /// Eight semesters, each holding a filler so the plan length is 8, with
    /// `extra` courses dropped into the given (0-based) semester.
    static func pathway(_ extra: [String], at index: Int, length: Int = 8) -> Pathway {
        Pathway(id: "p", name: "P", semesters: semesters.prefix(length).enumerated().map { offset, id in
            SemesterPlan(id: id, courseIDs: offset == index ? ["FILL"] + extra : ["FILL"])
        })
    }

    private func standingWarnings(_ pathway: Pathway) -> [ConflictWarning] {
        ConflictDetector(catalog: Self.catalog()).warnings(for: pathway, overrides: [])
            .filter { $0.kind == .missingPrerequisite }
    }

    @Test("a junior-standing course warns in semester 4 and clears in semester 5")
    func positionRuleWarning() throws {
        let early = standingWarnings(Self.pathway(["CS440"], at: 3))
        let warning = try #require(early.first)
        #expect(warning.courseID == "CS440")
        #expect(warning.summary == "Needs junior standing")
        #expect(warning.notes.contains { $0.contains("sophomore standing") && $0.contains("semester 4 of 8") })
        #expect(standingWarnings(Self.pathway(["CS440"], at: 4)).isEmpty)
    }

    @Test("a shorter plan earns standing from semesters remaining")
    func remainingRuleClears() {
        // Semester 3 of 6 has 4 remaining → junior.
        #expect(standingWarnings(Self.pathway(["CS440"], at: 2, length: 6)).isEmpty)
        #expect(!standingWarnings(Self.pathway(["CS440"], at: 1, length: 6)).isEmpty)
    }

    @Test("a course alternative satisfies course-or-standing early")
    func courseOrStanding() {
        var pathway = Self.pathway(["MUS317"], at: 1)
        #expect(!standingWarnings(pathway).isEmpty)
        pathway.semesters[0].courseIDs.append("MUS144")
        #expect(standingWarnings(pathway).isEmpty)
    }

    @Test("dragging a standing course earlier shows a blocking drop verdict")
    func dropVerdictFlagsEarlyMove() throws {
        let pathway = Self.pathway(["CS440"], at: 5)
        let verdicts = DropVerdictCalculator(catalog: Self.catalog()).verdicts(moving: "CS440", in: pathway, overrides: [])
        let early = try #require(verdicts[Self.semesters[1]])
        #expect(early.level == .blocking)
        #expect(early.reason == "Needs junior standing.")
        #expect(verdicts[Self.semesters[6]]?.level == .clear)
    }

    @Test("the generator holds a junior-standing course until semester 5")
    func generatorDelaysStandingCourse() throws {
        let fillers = (1...20).map { Course(id: "F\($0)", code: "FILL \(100 + $0)", title: "Filler", credits: 3, availability: [.fall, .spring], prerequisites: []) }
        // A 100-level code keeps the level-based sort from pushing it late on
        // its own; only the standing rule should hold it back.
        let upper = Course(id: "CS440", code: "CS 140", title: "Upper", credits: 3, availability: [.fall, .spring], prerequisites: [], rawPrerequisiteText: "Prerequisites: Junior standing.")
        let catalog = Catalog.fixture(
            courses: fillers + [upper],
            program: Program.fixture(id: "p", title: "P", requirements: [
                RequirementCategory(id: "core", name: "Required Core", requiredCredits: 30, courseOptions: [["CS440"]] + fillers.map { [$0.id] })
            ])
        )
        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "p", workload: .light, transferCredits: [], starting: Self.semesters[0]
        ).first)
        let position = try #require(pathway.semesters.firstIndex { $0.courseIDs.contains("CS440") })
        #expect(position >= 4)
    }
}

@Suite("Standing re-evaluation on semester delete")
@MainActor
struct StandingSemesterDeleteTests {
    @Test("deleting an earlier empty semester in a long plan re-checks standing, and undo clears it")
    func deleteShiftsStanding() throws {
        // Ten semesters; the third is empty and CS 440 sits in the fifth.
        // Position 5 → junior (remaining 6 → only sophomore), so no warning.
        // Deleting the empty third semester makes it position 4 of 9 →
        // sophomore by both rules, so the junior-standing warning appears.
        var ids = StandingWarningTests.semesters
        while ids.count < 10 { ids.append(ids.last!.next) }
        let pathway = Pathway(id: "p", name: "P", semesters: ids.enumerated().map { offset, id in
            switch offset {
            case 2: SemesterPlan(id: id, courseIDs: [])
            case 4: SemesterPlan(id: id, courseIDs: ["FILL", "CS440"])
            default: SemesterPlan(id: id, courseIDs: ["FILL"])
            }
        })
        let store = PlanStore()
        store.catalog = StandingWarningTests.catalog()
        store.plan.pathways = [pathway]
        store.plan.activePathwayID = pathway.id
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo

        func standingWarnings() -> [ConflictWarning] {
            store.warnings.filter { $0.kind == .missingPrerequisite && $0.courseID == "CS440" }
        }
        #expect(standingWarnings().isEmpty)

        store.deleteSemester(ids[2])
        #expect(standingWarnings().count == 1)
        #expect(store.lastScheduleChange?.newWarningCount == 1)

        undo.undo()
        #expect(store.plan.pathways[0].semesters.count == 10)
        #expect(standingWarnings().isEmpty)
    }

    @Test("trailing empty semesters do not count toward plan length")
    func trailingEmptySemestersIgnored() {
        // CS 440 in semester 4 of 8 warns; appending empty semesters must
        // not change that (they are not part of the plan yet).
        var pathway = StandingWarningTests.pathway(["CS440"], at: 3)
        let before = ConflictDetector(catalog: StandingWarningTests.catalog()).warnings(for: pathway, overrides: [])
        var next = pathway.semesters.last!.id.next
        for _ in 0..<2 {
            pathway.semesters.append(SemesterPlan(id: next, courseIDs: []))
            next = next.next
        }
        let after = ConflictDetector(catalog: StandingWarningTests.catalog()).warnings(for: pathway, overrides: [])
        #expect(before.map(\.id) == after.map(\.id))
        #expect(after.contains { $0.courseID == "CS440" && $0.kind == .missingPrerequisite })
    }
}
