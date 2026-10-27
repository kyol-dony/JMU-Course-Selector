import Foundation
import Testing
@testable import PlannerCore

@Suite("Option scheduling and progress")
struct OptionSchedulingTests {
    static let requirementID = "choose-one-of-the-following-options"
    static let programID = "math-bs"

    static func course(_ code: String, credits: Int = 3) -> Course {
        Course(id: code.replacingOccurrences(of: " ", with: ""), code: code, title: code, credits: credits, availability: [.fall, .spring], prerequisites: [])
    }

    /// Shaped like Math's: option 1 is four required courses; option 2 is two
    /// elective slots plus a "choose two" part with an "or both 426 and 427" group.
    static func optionRequirement() -> RequirementCategory {
        let electives = ["MATH310", "MATH450", "MATH499"]
        let option1 = RequirementOption(id: "option-1", label: "Option 1", parts: [
            RequirementCategory(
                id: "required-courses", name: "Required courses", requiredCredits: 12,
                courseOptions: [["MATH411"], ["MATH431"], ["MATH434"], ["MATH435"]], selection: .allRequired
            )
        ])
        let option2 = RequirementOption(id: "option-2", label: "Option 2", parts: [
            RequirementCategory(
                id: "electives", name: "Electives", requiredCredits: 6,
                courseOptions: [electives, electives], electivePoolSlots: [0, 1]
            ),
            RequirementCategory(
                id: "choose-two", name: "Choose two", requiredCredits: 6,
                courseOptions: [["MATH421", "MATH422"], ["MATH421", "MATH422", "MATH423"]],
                selection: .chooseCourses(2), alternativeGroup: ["MATH426", "MATH427"]
            )
        ])
        return RequirementCategory(
            id: requirementID, name: "Choose one of the following options", requiredCredits: 12,
            courseOptions: [["MATH411"], ["MATH431"], ["MATH434"], ["MATH435"]], selection: .allRequired,
            options: [option1, option2]
        )
    }

    static func major(id: String = programID) -> Program {
        Program.fixture(id: id, title: "Math", requirements: [
            RequirementCategory(id: "core", name: "Core Courses", requiredCredits: 60, courseOptions: [["BIG100"]]),
            optionRequirement()
        ])
    }

    static func catalog(programs: [Program]) -> Catalog {
        let codes = ["MATH 310", "MATH 411", "MATH 421", "MATH 422", "MATH 423", "MATH 426", "MATH 427", "MATH 431",
                     "MATH 434", "MATH 435", "MATH 450", "MATH 499"]
        return Catalog(
            source: CatalogSource(catalogYear: "Fixture", issueDate: Date(timeIntervalSince1970: 0), retrievedDate: Date(timeIntervalSince1970: 0), sourceURLs: [], retrievalNotes: []),
            programs: programs,
            courses: codes.map { course($0) } + [course("BIG 100", credits: 60)],
            apCreditRules: []
        )
    }

    static let option2 = [RequirementOption.choiceKey(programID: programID, requirementID: requirementID): "option-2"]

    static func pathway(_ courseIDs: [String]) -> Pathway {
        Pathway(id: "p", name: "P", semesters: [SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: courseIDs)])
    }

    static func foldedRow(_ courseIDs: [String]) throws -> CategoryProgress {
        let progress = try ProgressCalculator(catalog: catalog(programs: [major()])).progress(
            programID: programID, pathway: pathway(courseIDs), transferCredits: [], optionChoices: option2
        )
        return try #require(progress.categories.first { $0.id == requirementID })
    }

    @Test("only the chosen option is scheduled")
    func schedulesOnlyTheChosenOption() throws {
        let pathway = try #require(try ScheduleGenerator(catalog: Self.catalog(programs: [Self.major()])).generatePathways(
            for: Self.programID, workload: .heavy, transferCredits: [], optionChoices: Self.option2
        ).first)
        let scheduled = pathway.semesters.flatMap(\.courseIDs)
        for id in ["MATH411", "MATH431", "MATH434", "MATH435"] {
            #expect(!scheduled.contains(id))
        }
        #expect(!scheduled.contains { $0.contains("--option-1--") })
        let slots = pathway.placeholders.filter { $0.value.categoryID.contains("--option-2--") }
        #expect(slots.filter { $0.value.categoryID == "\(Self.requirementID)--option-2--0" }.count == 2)
        #expect(slots.filter { $0.value.categoryID == "\(Self.requirementID)--option-2--1" }.count == 2)
        #expect(!pathway.placeholders.values.contains { $0.categoryID.contains("--option-1--") })
    }

    @Test("a missing choice schedules the first option")
    func defaultsToTheFirstOption() throws {
        let pathway = try #require(try ScheduleGenerator(catalog: Self.catalog(programs: [Self.major()])).generatePathways(
            for: Self.programID, workload: .heavy, transferCredits: []
        ).first)
        let scheduled = pathway.semesters.flatMap(\.courseIDs)
        for id in ["MATH411", "MATH431", "MATH434", "MATH435"] {
            #expect(scheduled.contains(id))
        }
        #expect(!pathway.placeholders.values.contains { $0.categoryID.contains("--option-2--") })
    }

    @Test("the alternative group is offered inside the choose-two slots")
    func alternativeGroupIsOfferedInsideTheSlots() throws {
        let pathway = try #require(try ScheduleGenerator(catalog: Self.catalog(programs: [Self.major()])).generatePathways(
            for: Self.programID, workload: .heavy, transferCredits: [], optionChoices: Self.option2
        ).first)
        let slots = pathway.placeholders.values.filter { $0.categoryID == "\(Self.requirementID)--option-2--1" }
        #expect(slots.count == 2)
        for slot in slots {
            #expect(slot.alternates.contains("MATH426"))
            #expect(slot.alternates.contains("MATH427"))
        }
    }

    @Test("regeneration follows the chosen option too")
    func regenerationFollowsTheChosenOption() throws {
        let generator = ScheduleGenerator(catalog: Self.catalog(programs: [Self.major()]))
        let source = try #require(try generator.generatePathways(
            for: Self.programID, workload: .heavy, transferCredits: [], optionChoices: Self.option2
        ).first)
        let cutoff = try #require(source.semesters.first?.id)
        let regenerated = try generator.regeneratePathway(
            from: source, through: cutoff, for: Self.programID, strategy: .balanced,
            workload: .heavy, transferCredits: [], optionChoices: Self.option2
        )
        #expect(!regenerated.semesters.flatMap(\.courseIDs).contains("MATH411"))
        #expect(regenerated.placeholders.values.contains { $0.categoryID == "\(Self.requirementID)--option-2--1" })
    }

    @Test("progress folds the parts into one row for the requirement")
    func progressFoldsPartsIntoOneRow() throws {
        let progress = try ProgressCalculator(catalog: Self.catalog(programs: [Self.major()])).progress(
            programID: Self.programID, pathway: Self.pathway([]), transferCredits: [], optionChoices: Self.option2
        )
        let rows = progress.categories.filter { $0.id == Self.requirementID }
        #expect(rows.count == 1)
        #expect(rows.first?.name == "Choose one of the following options (Option 2)")
        #expect(rows.first?.requiredCredits == 12)
        #expect(!progress.categories.contains { $0.id.contains("--") })
    }

    @Test("taking both group courses meets the choose part")
    func takingBothMeetsTheChoosePart() throws {
        #expect(try Self.foldedRow(["MATH426", "MATH427"]).completedCredits == 6)
    }

    @Test("one group member alone counts like any single course")
    func oneGroupMemberDoesNotMeetThePart() throws {
        #expect(try Self.foldedRow(["MATH426"]).completedCredits == 3)
    }

    @Test("an expanded minor folds into one prefixed row")
    func extrasFoldToo() throws {
        let minor = Program(
            id: "math-minor", title: "Math Minor", degreeType: nil, kind: .minor, college: "X", department: "X", catalogPage: nil,
            totalCredits: nil, requirements: [Self.optionRequirement()], verificationStatus: .verified,
            requirementDataComplete: true, sourceNote: "Fixture"
        )
        let catalog = Self.catalog(programs: [Self.major(), minor])
        let choices = [RequirementOption.choiceKey(programID: "math-minor", requirementID: Self.requirementID): "option-2"]
        let expanded = minor.choosingOptions(choices, programID: "math-minor")
        let progress = try ProgressCalculator(catalog: catalog).progress(
            programID: Self.programID, pathway: Self.pathway(["MATH426", "MATH427"]), transferCredits: [],
            additionalPrograms: [expanded], optionChoices: Self.option2
        )
        let rows = progress.categories.filter { $0.id.hasPrefix("math-minor::") }
        #expect(rows.map(\.id) == ["math-minor::\(Self.requirementID)"])
        #expect(rows.first?.name == "Minor (Math Minor): Choose one of the following options (Option 2)")
        #expect(rows.first?.requiredCredits == 12)
        #expect(rows.first?.completedCredits == 6)
    }

    // MARK: - The real Math B.S. shape

    // Its elective pools ("MATH 310 or above") list every MATH 3xx/4xx
    // course, the "choose two" and "one of 411/431/434/435" courses too.

    static func realRow(_ courseIDs: [String], option: String) throws -> CategoryProgress {
        let (catalog, requirement) = try RealCatalogFixtures.mathOptionsOnly()
        let progress = try ProgressCalculator(catalog: catalog).progress(
            programID: "math-bs", pathway: pathway(courseIDs), transferCredits: [],
            optionChoices: [RequirementOption.choiceKey(programID: "math-bs", requirementID: requirement.id): option]
        )
        return try #require(progress.categories.first { $0.id == requirement.id })
    }

    @Test("a course counts once across an option's parts")
    func optionPartsShareTheirCourses() throws {
        let option2 = try Self.realRow(["MATH440", "MATH441"], option: "option-2")
        #expect(option2.requiredCredits == 12)
        #expect(option2.completedCredits == 6)
        #expect(try Self.realRow(["MATH431"], option: "option-1").completedCredits == 3)
        // A third "choose two" course goes on to an elective slot.
        #expect(try Self.realRow(["MATH440", "MATH441", "MATH448"], option: "option-2").completedCredits == 9)
        #expect(try Self.realRow(["MATH426", "MATH427", "MATH310", "MATH440"], option: "option-2").completedCredits == 12)
    }

    @Test("a transferred choose-two course leaves the rest of the option scheduled")
    func transferredCourseCountsForOnePart() throws {
        let (catalog, requirement) = try RealCatalogFixtures.mathOptionsOnly()
        let transfer = TransferCredit(sourceDescription: "Transfer", courseIDs: ["MATH440"], credits: 3)
        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "math-bs", workload: .heavy, transferCredits: [transfer],
            optionChoices: [RequirementOption.choiceKey(programID: "math-bs", requirementID: requirement.id): "option-2"]
        ).first)
        let scheduled = pathway.semesters.flatMap(\.courseIDs)
        let optionCredits = scheduled.reduce(0.0) { total, id in
            if let spec = pathway.placeholders[id] {
                return spec.categoryID.hasPrefix("\(requirement.id)--option-2--") ? total + spec.credits : total
            }
            return total
        }
        #expect(optionCredits == 9, "\(scheduled)")
    }
}
