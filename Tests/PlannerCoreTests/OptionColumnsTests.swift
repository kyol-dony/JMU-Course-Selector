import Foundation
import Testing
import PlannerCore
@testable import JMUCoursePlanner

/// The catalog tab's side-by-side view of an option requirement.
@Suite("Option columns")
struct OptionColumnsTests {
    private static let token = ElectivePool.token(subject: "MATH", minimumNumber: 310)

    private static func pool(credits: Int) -> RequirementCategory {
        let slots = credits / 3
        return RequirementCategory(
            id: "pool", name: "\(credits) credits of MATH electives at MATH 310 or above", requiredCredits: credits,
            courseOptions: Array(repeating: [token], count: slots), electivePoolSlots: Array(0..<slots)
        )
    }

    private static let category = RequirementCategory(
        id: "additional-requirements", name: "Additional Requirements", requiredCredits: 12, courseOptions: [],
        options: [
            RequirementOption(id: "option-1", label: "Option 1", parts: [
                pool(credits: 9),
                RequirementCategory(
                    id: "choose", name: "Choose one", requiredCredits: 3,
                    courseOptions: [["MATH411", "MATH431", "MATH434", "MATH435"]], selection: .chooseCourses(1)
                )
            ]),
            RequirementOption(id: "option-2", label: "Option 2", parts: [
                pool(credits: 6),
                RequirementCategory(
                    id: "choose", name: "Choose two", requiredCredits: 6,
                    courseOptions: Array(repeating: ["MATH440", "MATH441", "MATH448", "MATH449"], count: 2),
                    selection: .chooseCourses(2), alternativeGroup: ["MATH426", "MATH427"]
                )
            ])
        ]
    )

    @Test func columnsFollowOptionsInOrder() {
        let columns = OptionColumns(category: Self.category, chosenOptionID: "option-2").columns
        #expect(columns.map(\.label) == ["Option 1", "Option 2"])
        #expect(columns.map(\.state) == [.available, .inPlan])
        let option2 = columns[1]
        #expect(option2.parts.map(\.kind) == [
            .pool(credits: 6, rule: "MATH electives at MATH 310 or above"),
            .choose(count: 2)
        ])
        #expect(option2.parts[1].alternative == CatalogBlockGroup(courseIDs: ["MATH426", "MATH427"], isAlternatives: false))
        #expect(option2.parts[1].blocks.map(\.courseIDs) == [["MATH440"], ["MATH441"], ["MATH448"], ["MATH449"]])
        #expect(columns[0].parts[1].alternative == nil)
    }

    @Test func browsingShowsNoPlanState() {
        let columns = OptionColumns(category: Self.category, chosenOptionID: nil).columns
        #expect(columns.map(\.state) == [.browsing, .browsing])
    }

    @Test func poolRuleComesFromTheTokenWhenTheNameHasNoRule() {
        var pool = Self.pool(credits: 6)
        pool.name = "Electives"
        let category = RequirementCategory(
            id: "r", name: "R", requiredCredits: 6, courseOptions: [],
            options: [RequirementOption(id: "option-1", label: "Option 1", parts: [pool])]
        )
        let part = OptionColumns(category: category, chosenOptionID: nil).columns[0].parts[0]
        #expect(part.kind == .pool(credits: 6, rule: "MATH electives at MATH 310 or above"))
    }

    @Test func requiredPartListsItsCourses() {
        let part = RequirementCategory(
            id: "req", name: "Required courses", requiredCredits: 6,
            courseOptions: [["MATH411"], ["MATH431"]], selection: .allRequired
        )
        let category = RequirementCategory(
            id: "r", name: "R", requiredCredits: 6, courseOptions: [],
            options: [RequirementOption(id: "option-1", label: "Option 1", parts: [part])]
        )
        let built = OptionColumns(category: category, chosenOptionID: "option-1").columns[0].parts[0]
        #expect(built.kind == .required)
        #expect(built.title == "Required courses")
        #expect(built.blocks.map(\.courseIDs) == [["MATH411"], ["MATH431"]])
    }

    @Test func liveMathBSOptionsReadAsPoolAndChooseParts() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("_live_math_bs.html")
        let html = try String(contentsOf: url, encoding: .utf8)
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(
            html, kind: .major, sourceURL: URL(string: "https://catalog.jmu.edu/programs/x/")!
        )
        let concentration = try #require(parsed.concentrations.first { $0.name.contains("Not Seeking") })
        let requirement = try #require(concentration.requirements.first { $0.options != nil })
        let columns = OptionColumns(category: requirement, chosenOptionID: "option-2").columns
        #expect(columns[1].parts.map(\.kind) == [
            .pool(credits: 6, rule: "MATH electives at MATH 310 or above"),
            .choose(count: 2)
        ])
        #expect(columns[0].parts.map(\.kind) == [
            .pool(credits: 9, rule: "MATH electives at MATH 310 or above"),
            .choose(count: 1)
        ])
        #expect(columns[0].parts[1].blocks.map(\.courseIDs) == [["MATH411"], ["MATH431"], ["MATH434"], ["MATH435"]])
        #expect(columns[1].parts[1].alternative?.courseIDs == ["MATH426", "MATH427"])
    }
}
