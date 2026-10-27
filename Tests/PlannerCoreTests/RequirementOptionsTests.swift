import Foundation
import Testing
@testable import PlannerCore

@Suite("Requirement options")
struct RequirementOptionsTests {
    static let pool = ElectivePool.token(subject: "MATH", minimumNumber: 310)

    static func optionRequirement() -> RequirementCategory {
        let option1 = RequirementOption(id: "option-1", label: "Option 1", parts: [
            RequirementCategory(id: "pool", name: "Electives", requiredCredits: 3, courseOptions: [[pool]]),
            RequirementCategory(id: "one-of", name: "One of four", requiredCredits: 3, courseOptions: [["MATH301", "MATH302", "MATH303", "MATH304"]])
        ])
        let option2 = RequirementOption(id: "option-2", label: "Option 2", parts: [
            RequirementCategory(id: "pool", name: "Electives", requiredCredits: 3, courseOptions: [[pool]]),
            RequirementCategory(
                id: "two",
                name: "Choose two",
                requiredCredits: 6,
                courseOptions: [["MATH421", "MATH422"], ["MATH421", "MATH422", "MATH423"]],
                alternativeGroup: ["MATH426", "MATH427"]
            )
        ])
        return RequirementCategory(id: "r", name: "Choose one of the following options", requiredCredits: 6, courseOptions: [], options: [option1, option2])
    }

    static func program(concentration: Bool = false) -> Program {
        Program.fixture(
            id: "math-bs",
            title: "Math",
            requirements: [optionRequirement()],
            concentrations: concentration ? [Concentration(id: "c", name: "Track", requirements: [optionRequirement()])] : []
        )
    }

    @Test("the chosen option's parts replace the option requirement")
    func choosingOptionsMaterializesTheChosenParts() throws {
        let expanded = Self.program().choosingOptions([RequirementOption.choiceKey(programID: "math-bs", requirementID: "r"): "option-2"], programID: "math-bs")
        #expect(expanded.requirements.map(\.id) == ["r--option-2--0", "r--option-2--1"])
        #expect(expanded.requirements.allSatisfy { $0.name.hasPrefix("Option 2: ") })
        #expect(expanded.requirements.allSatisfy { $0.options == nil })
        let part = expanded.requirements[1]
        #expect(part.courseOptions.count == 2)
        for slot in part.courseOptions {
            #expect(slot.contains("MATH426"))
            #expect(slot.contains("MATH427"))
        }
        // Appended without duplicating, and the original menu keeps its order.
        #expect(part.courseOptions[0] == ["MATH421", "MATH422", "MATH426", "MATH427"])
        // Part without a group is untouched.
        #expect(expanded.requirements[0].courseOptions == [[Self.pool]])
    }

    @Test("a missing choice expands the first option")
    func missingChoiceUsesTheFirstOption() {
        let expanded = Self.program().choosingOptions([:], programID: "math-bs")
        #expect(expanded.requirements.map(\.id) == ["r--option-1--0", "r--option-1--1"])
    }

    @Test("concentration option requirements expand too")
    func concentrationsExpand() {
        let expanded = Self.program(concentration: true).choosingOptions([:], programID: "math-bs")
        #expect(expanded.concentrations.first?.requirements.map(\.id) == ["r--option-1--0", "r--option-1--1"])
    }

    @Test("ordinary requirements pass through unchanged")
    func ordinaryRequirementsPassThrough() {
        let core = RequirementCategory(id: "core", name: "Core", requiredCredits: 3, courseOptions: [["MATH235"]])
        let program = Program.fixture(id: "p", title: "P", requirements: [core, Self.optionRequirement()])
        #expect(program.choosingOptions([:], programID: "p").requirements.first == core)
    }

    @Test("choice keys are scoped to the program")
    func choiceKeysIncludeTheProgram() {
        #expect(RequirementOption.choiceKey(programID: "posc-minor", requirementID: "r") != RequirementOption.choiceKey(programID: "math-bs", requirementID: "r"))
        #expect(RequirementOption.choiceKey(programID: "math-bs", requirementID: "r") == "math-bs/r")
        let choices = [RequirementOption.choiceKey(programID: "posc-minor", requirementID: "r"): "option-2"]
        let expanded = Self.program().choosingOptions(choices, programID: "math-bs")
        #expect(expanded.requirements.map(\.id) == ["r--option-1--0", "r--option-1--1"])
    }

    @Test("the default option follows completed courses")
    func defaultOptionFollowsCompletedCourses() throws {
        let options = try #require(Self.optionRequirement().options)
        #expect(RequirementOption.defaultOptionID(options, completed: ["MATH426", "MATH427"]) == "option-2")
        #expect(RequirementOption.defaultOptionID(options, completed: []) == "option-1")
        #expect(RequirementOption.defaultOptionID(options, completed: ["MATH301", "MATH421"]) == "option-1")
        #expect(RequirementOption.defaultOptionID([], completed: ["MATH301"]) == nil)
    }

    @Test("on the real Math catalog, courses only one option lists pick the default")
    func defaultOptionIgnoresSharedPools() throws {
        // Both options' pools list every MATH 3xx/4xx course.
        let (catalog, requirement) = try RealCatalogFixtures.mathOptionsOnly()
        let options = try #require(requirement.options)
        func pick(_ completed: Set<String>, scheduled: Set<String> = []) -> String? {
            RequirementOption.defaultOptionID(options, completed: completed, scheduled: scheduled, coursesByID: catalog.coursesByID)
        }
        #expect(pick(["MATH426", "MATH427"]) == "option-2")
        #expect(pick(["MATH440", "MATH441"]) == "option-2")
        #expect(pick(["MATH431"]) == "option-1")
        #expect(pick(["MATH310", "MATH354"]) == "option-1")
        // A tie in completed courses goes to the courses the plan schedules.
        #expect(pick(["MATH431", "MATH440"], scheduled: ["MATH441"]) == "option-2")
        #expect(pick([], scheduled: ["MATH448", "MATH449"]) == "option-2")
        #expect(pick(["MATH431"], scheduled: ["MATH448", "MATH449"]) == "option-1")
    }

    @Test("option part ids parse back")
    func optionPartIDRoundTrips() {
        let parsed = OptionPartID.parse("r--option-2--1")
        #expect(parsed?.requirementID == "r")
        #expect(parsed?.optionID == "option-2")
        #expect(parsed?.partIndex == 1)
        #expect(parsed?.programID == nil)
        let extra = OptionPartID.parse("posc-minor/r--option-1--0")
        #expect(extra?.programID == "posc-minor")
        #expect(extra?.requirementID == "r")
        #expect(extra?.optionID == "option-1")
        #expect(OptionPartID.parse("/r--option-1--0") == nil)
        #expect(OptionPartID.parse("core") == nil)
        #expect(OptionPartID.parse("r--option-2--x") == nil)
    }

    @Test("pool tokens inside option parts resolve")
    func poolTokensInsideOptionsResolve() throws {
        let catalog = ElectivePoolTests.catalog(programs: [Self.program()]).resolvingElectivePools()
        let option = try #require(catalog.programsByID["math-bs"]?.requirements.first?.options?.first)
        let part = option.parts[0]
        #expect(part.courseOptions == [["MATH310", "MATH410", "MATH411", "MATH421", "MATH431", "MATH450", "MATH499"]])
        #expect(part.electivePoolSlots == [0])
        #expect(catalog.resolvingElectivePools().programsByID["math-bs"] == catalog.programsByID["math-bs"])
    }

    @Test("a category without options decodes with nil options and group")
    func legacyCategoryDecodesWithoutOptions() throws {
        let json = #"{"id":"x","name":"X","requiredCredits":3,"courseOptions":[["A"]]}"#
        let category = try JSONDecoder().decode(RequirementCategory.self, from: Data(json.utf8))
        #expect(category.options == nil)
        #expect(category.alternativeGroup == nil)
    }

    @Test("options survive an encode/decode round trip")
    func optionsRoundTrip() throws {
        let category = Self.optionRequirement()
        #expect(try JSONDecoder().decode(RequirementCategory.self, from: JSONEncoder().encode(category)) == category)
    }
}
