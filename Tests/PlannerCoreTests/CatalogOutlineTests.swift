import Foundation
import Testing
@testable import JMUCoursePlanner
@testable import PlannerCore

/// The catalog tab's section index: shared requirements, the chosen
/// concentration, then Gen Ed; and the plain-language rule for each.
@Suite("Catalog outline")
struct CatalogOutlineTests {
    private func physics(required: Bool) -> Program {
        func category(_ id: String, _ name: String) -> RequirementCategory {
            RequirementCategory(id: id, name: name, requiredCredits: 3, courseOptions: [["A"]], selection: .allRequired, choices: [["A"]])
        }
        var program = Program.fixture(
            id: "physics",
            title: "Physics, B.S.",
            requirements: [
                category("core", "Core"),
                category("lab", "Lab"),
                category("gened-c1", "General Education - Cluster One"),
                category("gened-c3", "General Education - Cluster Three"),
                category("gened-c4", "General Education - Cluster Four")
            ],
            concentrations: [Concentration(id: "applied", name: "Applied Physics", requirements: [category("applied-core", "Applied Core")])]
        )
        program.concentrationSelectionRequired = required
        return program
    }

    @Test func groupsSharedConcentrationAndEveryMajor() {
        let outline = CatalogOutline(program: physics(required: true), concentrationID: "applied")
        #expect(outline.sections.map(\.title) == ["Shared", "Applied Physics concentration", "Every major"])
        #expect(outline.sections[0].entries.map(\.name) == ["Core", "Lab"])
        #expect(outline.sections[2].entries.map(\.creditsText) == ["3 areas"])
    }

    @Test func noConcentrationHasNoConcentrationSection() {
        #expect(CatalogOutline(program: physics(required: false), concentrationID: nil).sections.map(\.title) == ["Shared", "Every major"])
    }

    @Test func concentrationDefaults() {
        #expect(CatalogOutline.defaultConcentrationID(for: physics(required: true)) == "applied")
        #expect(CatalogOutline.defaultConcentrationID(for: physics(required: false)) == nil)
        #expect(CatalogOutline.defaultConcentrationID(for: .fixture(id: "x", title: "X", requirements: [])) == nil)
    }

    @Test func noListShowsNoList() {
        let program = Program.fixture(id: "x", title: "X", requirements: [
            RequirementCategory(id: "e", name: "Psychology Electives", requiredCredits: 3, courseOptions: [], selection: .chooseCredits(3))
        ])
        let entry = CatalogOutline(program: program, concentrationID: nil).sections[0].entries[0]
        #expect(entry.creditsText == "No list")
        #expect(!entry.hasCourseList)
    }

    @Test func ruleLabels() {
        func label(_ selection: RequirementSelection, _ choices: [[String]]) -> String {
            RequirementRuleText.label(for: RequirementCategory(id: "r", name: "R", requiredCredits: 3, courseOptions: [], selection: selection, choices: choices))
        }
        #expect(label(.allRequired, [["A"]]) == "All required")
        #expect(label(.chooseCourses(3), [["A"], ["B"], ["C"], ["D"]]) == "Choose 3 of 4")
        #expect(label(.chooseCredits(6), [["A"]]) == "Choose 6 credits")
        #expect(label(.chooseGroups(1), [["A", "B"], ["C", "D"]]) == "Choose 1 option")
        #expect(label(.chooseGroups(2), [["A", "B"], ["C", "D"], ["E"]]) == "Choose 2 options")
        #expect(label(.unknown, []) == "See catalog")
    }

    @Test func firstEntryIsFirstShared() {
        let outline = CatalogOutline(program: physics(required: false), concentrationID: nil)
        #expect(outline.firstEntryID == outline.sections[0].entries[0].id)
    }
}
