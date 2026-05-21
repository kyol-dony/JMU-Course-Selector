import Foundation
import Testing
@testable import JMUCoursePlanner
@testable import PlannerCore

@Suite
@MainActor
struct RequirementSelectionStoreTests {
    @Test
    func savedStudentPlanDecodesMissingRequirementSelectionsAsEmpty() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Autosave",
          "programID": "cis-bba",
          "workload": "Standard",
          "apScores": [],
          "transferCredits": [],
          "pathways": [],
          "overrides": [],
          "updatedAt": "2026-05-20T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let plan = try decoder.decode(SavedStudentPlan.self, from: Data(json.utf8))

        #expect(plan.requirementSelections.isEmpty)
    }

    @Test
    func selectingRequirementOptionPersistsChoiceAndLeavesPathwaysUnchanged() {
        let store = PlanStore()
        store.catalog = requirementSelectionStoreCatalog()
        store.plan.programID = "cis-bba"
        store.plan.pathways = [
            Pathway(id: "path-1", name: "Old", semesters: [
                SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["CIS-464"])
            ])
        ]
        store.plan.activePathwayID = "path-1"
        let requirement = store.effectiveActiveProgram!.requirements[0]
        let key = store.majorRequirementSelectionKey(for: requirement)!

        store.selectRequirementOption(key: key, courseIDs: ["CIS-484"])

        #expect(store.plan.requirementSelections[key] == ["CIS-484"])
        #expect(store.plan.pathways.count == 1)
        #expect(store.plan.activePathwayID == "path-1")
        #expect(store.plan.pathways[0].semesters[0].courseIDs == ["CIS-464"])
    }

    @Test
    func clearingRequirementOptionRemovesChoiceAndLeavesPathwaysUnchanged() {
        let store = PlanStore()
        store.catalog = requirementSelectionStoreCatalog()
        store.plan.programID = "cis-bba"
        store.plan.pathways = [
            Pathway(id: "path-1", name: "Old", semesters: [
                SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["CIS-484"])
            ])
        ]
        store.plan.activePathwayID = "path-1"
        let requirement = store.effectiveActiveProgram!.requirements[0]
        let key = store.majorRequirementSelectionKey(for: requirement)!
        store.plan.requirementSelections[key] = ["CIS-484"]

        store.selectRequirementOption(key: key, courseIDs: nil)

        #expect(store.plan.requirementSelections[key] == nil)
        #expect(store.plan.pathways.count == 1)
        #expect(store.plan.activePathwayID == "path-1")
        #expect(store.plan.pathways[0].semesters[0].courseIDs == ["CIS-484"])
    }

    @Test
    func selectingRequirementOptionDoesNotInventPlacementBeforeRegeneration() {
        let store = PlanStore()
        store.catalog = requirementSelectionStoreCatalog()
        store.plan.programID = "cis-bba"
        store.plan.pathways = [
            Pathway(id: "path-1", name: "Old", semesters: [
                SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: [])
            ])
        ]
        store.plan.activePathwayID = "path-1"
        let requirement = store.effectiveActiveProgram!.requirements[0]
        let key = store.majorRequirementSelectionKey(for: requirement)!

        store.selectRequirementOption(key: key, courseIDs: ["CIS-484"])

        #expect(store.plan.requirementSelections[key] == ["CIS-484"])
        #expect(store.plan.pathways.count == 1)
        #expect(store.plan.activePathwayID == "path-1")
        #expect(store.plan.pathways[0].semesters[0].courseIDs.isEmpty)
    }

    @Test
    func selectingRequirementOptionKeepsGeneratedPathwaysActive() {
        let store = PlanStore()
        store.catalog = requirementSelectionStoreCatalog()
        store.plan.programID = "cis-bba"
        store.plan.workload = .light
        store.generateSchedules()
        let requirement = store.effectiveActiveProgram!.requirements[0]
        let key = store.majorRequirementSelectionKey(for: requirement)!
        let originalPathwayIDs = store.plan.pathways.map(\.id)
        let originalActivePathwayID = store.plan.activePathwayID

        store.selectRequirementOption(key: key, courseIDs: ["CIS-484"])

        #expect(store.plan.pathways.map(\.id) == originalPathwayIDs)
        #expect(store.plan.activePathwayID == originalActivePathwayID)
        #expect(store.activePathway?.semesters.flatMap(\.courseIDs).contains("CIS-464") == true)
        #expect(store.activePathway?.semesters.flatMap(\.courseIDs).contains("CIS-484") == false)
        #expect(store.progress != nil)
    }

    @Test
    func selectingGenEdOptionLeavesScheduleAndProgressUnchangedBeforeRegeneration() {
        let store = PlanStore()
        store.catalog = genEdRequirementSelectionStoreCatalog()
        store.plan.programID = "gened-fixture"
        store.plan.pathways = [
            Pathway(id: "path-1", name: "Path", semesters: [
                SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["BIO-140"])
            ])
        ]
        store.plan.activePathwayID = "path-1"
        let requirement = store.effectiveActiveProgram!.requirements[0]
        let key = store.majorRequirementSelectionKey(for: requirement)!
        let progressBefore = store.progress

        store.selectRequirementOption(key: key, courseIDs: ["CHEM-131"])

        #expect(store.plan.pathways.count == 1)
        #expect(store.plan.activePathwayID == "path-1")
        #expect(store.plan.pathways[0].semesters[0].courseIDs == ["BIO-140"])
        #expect(store.progress?.overallCompletedCredits == progressBefore?.overallCompletedCredits)
    }

    @Test
    func regeneratingAppliesPendingGenEdOptionSelections() {
        let store = PlanStore()
        store.catalog = genEdRequirementSelectionStoreCatalog()
        store.plan.programID = "gened-fixture"
        let requirement = store.effectiveActiveProgram!.requirements[0]
        let key = store.majorRequirementSelectionKey(for: requirement)!
        store.selectRequirementOption(key: key, courseIDs: ["CHEM-131"])

        store.generateSchedules()

        #expect(store.activePathway?.semesters.flatMap(\.courseIDs).contains("CHEM-131") == true)
        #expect(store.activePathway?.semesters.flatMap(\.courseIDs).contains("ANTH-196") == false)
        #expect(store.progress?.overallCompletedCredits == 3)
    }

    @Test
    func normalizedSelectionsUseRequirementSelectionKeyOnlyForCurrentProgram() {
        let store = PlanStore()
        store.catalog = requirementSelectionStoreCatalog()
        store.plan.programID = "cis-bba"
        let requirement = store.effectiveActiveProgram!.requirements[0]
        let key = store.majorRequirementSelectionKey(for: requirement)!
        store.plan.requirementSelections = [
            key: ["CIS-484"],
            "major:other:no-concentration:cis-elective::CIS Elective": ["CIS-464"]
        ]

        let normalized = store.activeRequirementSelectionsByRequirementKey()

        #expect(normalized == [requirement.selectionKey: ["CIS-484"]])
    }

    @Test
    func validationRemovesSelectionsWhoseOptionNoLongerExists() {
        let store = PlanStore()
        store.catalog = requirementSelectionStoreCatalog()
        store.plan.programID = "cis-bba"
        let requirement = store.effectiveActiveProgram!.requirements[0]
        let key = store.majorRequirementSelectionKey(for: requirement)!
        store.plan.requirementSelections = [key: ["CIS-999"]]

        store.validateRequirementSelections()

        #expect(store.plan.requirementSelections.isEmpty)
    }
}

private func requirementSelectionStoreCatalog() -> Catalog {
    let courses = [
        Course(id: "CIS-464", code: "CIS 464", title: "Information Security", credits: 3, availability: nil, prerequisites: []),
        Course(id: "CIS-484", code: "CIS 484", title: "Cyber Defense", credits: 3, availability: nil, prerequisites: [])
    ]
    let requirement = RequirementCategory(
        id: "cis-elective",
        name: "CIS Elective",
        requiredCredits: 3,
        courseOptions: [["CIS-464", "CIS-484"]]
    )
    let program = Program.fixture(id: "cis-bba", title: "Computer Information Systems", requirements: [requirement])
    return Catalog.fixture(courses: courses, program: program)
}

private func genEdRequirementSelectionStoreCatalog() -> Catalog {
    let courses = [
        Course(id: "ANTH-196", code: "ANTH 196", title: "Biological Anthropology", credits: 3, availability: nil, prerequisites: []),
        Course(id: "BIO-140", code: "BIO 140", title: "Foundations of Biology", credits: 3, availability: nil, prerequisites: []),
        Course(id: "CHEM-131", code: "CHEM 131", title: "General Chemistry I", credits: 3, availability: nil, prerequisites: [])
    ]
    let requirement = RequirementCategory(
        id: "gen-ed-c3ns",
        name: "General Education - Natural Systems [C3NS]",
        requiredCredits: 3,
        courseOptions: [["ANTH-196", "BIO-140", "CHEM-131"]]
    )
    let program = Program.fixture(id: "gened-fixture", title: "Gen Ed Fixture", requirements: [requirement])
    return Catalog.fixture(courses: courses, program: program)
}
