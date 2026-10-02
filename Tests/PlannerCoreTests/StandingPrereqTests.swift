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

@Suite("Prerequisite list parsing")
struct PrereqListParsingTests {
    /// A parser whose catalog holds `codes`, each with its code minus the
    /// space as its id ("CS 240" → "CS240").
    private func parser(_ codes: String...) -> PrereqParser {
        PrereqParser(coursesByID: Dictionary(uniqueKeysWithValues: codes.map { code in
            let id = code.replacingOccurrences(of: " ", with: "")
            return (id, Course(id: id, code: code, title: code, credits: 3, availability: nil, prerequisites: []))
        }))
    }

    private func courses(_ ids: String...) -> [PrereqExpr] { ids.map(PrereqExpr.course) }

    @Test("an Oxford ', and' list separates items more loosely than 'or'")
    func oxfordAndListBindsLooserThanOr() {
        let ldt = parser("PSYC 160", "EDUC 175", "LDT 370")
        #expect(ldt.parse("Prerequisites: PSYC 160 or EDUC 175 , and LDT 370 . Corequisites: LDT 370 .").prerequisiteExpr
            == .all([.any(courses("PSYC160", "EDUC175")), .course("LDT370")]))

        let math = parser("MATH 245", "MATH 238", "MATH 300", "MATH 318", "MATH 329")
        #expect(math.parse("Prerequisites: MATH 245 , MATH 238 or MATH 300 , and MATH 318 or MATH 329 .").prerequisiteExpr
            == .all([.course("MATH245"), .any(courses("MATH238", "MATH300")), .any(courses("MATH318", "MATH329"))]))

        let geol = parser("GEOL 110L", "GEOL 115L", "GEOL 280", "CHEM 131")
        let result = geol.parse("Prerequisites: GEOL 110L or GEOL 115L , and GEOL 280 and CHEM 131 ; or permission of the instructor.")
        #expect(result.prerequisiteExpr.enforcedCourseOnly
            == .all([.any(courses("GEOL110L", "GEOL115L")), .course("GEOL280"), .course("CHEM131")]))
    }

    @Test("a list closed by a plain 'and' also separates items more loosely than 'or'")
    func plainAndListBindsLooserThanOr() {
        let result = parser("ACTG 244", "COB 242").parse(
            "Prerequisites: ACTG 244 or COB 242 , junior standing (60 hours) and a cumulative 2.0 GPA in all courses taken at JMU."
        )
        #expect(result.prerequisiteExpr.enforcedCourseOnly
            == .all([.any(courses("ACTG244", "COB242")), .standing(StandingRequirement(minimum: .junior))]))
        #expect(result.hasUnknownTokens)
    }

    @Test("a comma list closed by 'or' is one choice")
    func orListIsChoice() {
        let scom = parser("SCOM 121", "SCOM 122", "SCOM 123")
        #expect(scom.parse("Prerequisites: SCOM 121 , SCOM 122 or SCOM 123 .").prerequisiteExpr
            == .any(courses("SCOM121", "SCOM122", "SCOM123")))

        let msse = parser("MSSE 411", "MSSE 412", "MSSE 413", "MSSE 414", "MSSE 415")
        #expect(msse.parse("Prerequisites: MSSE 411 , MSSE 412 , MSSE 413 , or MSSE 414 ; and MSSE 415 .").prerequisiteExpr
            == .all([.any(courses("MSSE411", "MSSE412", "MSSE413", "MSSE414")), .course("MSSE415")]))
    }

    @Test("', or' separates groups that are themselves comma lists")
    func commaOrSeparatesGroups() {
        let eled = parser("ELED 334", "LED 350", "ELED 374", "ELED 375", "LED 370")
        #expect(eled.parse("Prerequisites: ELED 334 and LED 350 , or ELED 374 , ELED 375 and LED 370 .").prerequisiteExpr
            == .any([.all(courses("ELED334", "LED350")), .all(courses("ELED374", "ELED375", "LED370"))]))
    }

    @Test("grade qualifiers before and after courses are stripped", arguments: [
        #"Prerequisites: A minimum grade of "C-" in CHEM 132 ."#,
        #"Prerequisites: Grade of "C-"or higher in CHEM 132 ."#,
        #"Prerequisites: A grade of "C-" or better in CHEM 132 ."#,
        #"Prerequisites: CHEM 132 with a minimum grade of "C-"."#,
        #"Prerequisites: CHEM 132 with a "C" or better."#
    ])
    func gradeQualifiers(input: String) {
        let result = parser("CHEM 132").parse(input)
        #expect(result.prerequisiteExpr == .course("CHEM132"))
        #expect(!result.hasUnknownTokens)
    }

    @Test("plural 'minimum grades of' keeps every listed course")
    func pluralGradeQualifier() {
        let sowk = parser("SOWK 305", "SOWK 317", "SOWK 320", "SOWK 335")
        let result = sowk.parse(
            #"Prerequisites: Social work majors with senior standing and minimum grades of "C" in SOWK 305 , SOWK 317 , SOWK 320 and SOWK 335 ."#
        )
        #expect(result.prerequisiteExpr.enforcedCourseOnly
            == .all([.standing(StandingRequirement(minimum: .senior))] + courses("SOWK305", "SOWK317", "SOWK320", "SOWK335")))
    }

    @Test("'either' groups its alternatives inside an 'and'")
    func eitherGroup() {
        let cs = parser("CS 240", "MATH 220", "MATH 229", "MATH 318")
        #expect(cs.parse(#"Prerequisites: A minimum grade of "C-" in CS 240 and either MATH 220 , MATH 229 or MATH 318 ."#)
            .prerequisiteExpr == .all([.course("CS240"), .any(courses("MATH220", "MATH229", "MATH318"))]))
    }

    @Test("a slash pairs a lecture with its lab, or cross-listed courses")
    func slashPairs() {
        let bio = parser("BIO 240", "BIO 240L", "CHEM 132")
        #expect(bio.parse("Prerequisites: BIO 240 / BIO 240L and CHEM 132 .").prerequisiteExpr
            == .all(courses("BIO240", "BIO240L", "CHEM132")))

        let cs = parser("CS 159", "CS 227", "MATH 227", "MATH 245", "MATH 231")
        #expect(cs.parse(#"Prerequisites: Grades of "C-" or better in CS 159 , CS 227 / MATH 227 or MATH 245 , and MATH 231 ."#)
            .prerequisiteExpr == .all([.course("CS159"), .any(courses("CS227", "MATH227", "MATH245")), .course("MATH231")]))

        // A partner missing from the catalog drops out without flagging.
        let result = parser("BIO 250").parse("Prerequisites: BIO 250 / BIO 250L .")
        #expect(result.prerequisiteExpr == .course("BIO250"))
        #expect(!result.hasUnknownTokens)
    }

    @Test("text the grammar stops before is flagged as unparsed")
    func leftoverTextFlagged() {
        let result = parser("PSYC 101", "PSYC 160").parse(
            "Prerequisites: PSYC 101 or PSYC 160 . A student cannot earn credit for PSYC 250 after completing PSYC 335 ."
        )
        #expect(result.prerequisiteExpr == .any(courses("PSYC101", "PSYC160")))
        #expect(result.hasUnknownTokens)
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
