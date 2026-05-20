import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Plan store concentration selection")
@MainActor
struct PlanStoreConcentrationTests {
    @Test("selecting a major with concentrations requires concentration")
    func majorWithConcentrationsRequiresSelection() {
        let store = PlanStore()
        store.catalog = Catalog.fixture(
            courses: [],
            program: Program.fixture(
                id: "physics-bs",
                title: "Physics, B.S.",
                requirements: [
                    RequirementCategory(id: "core", name: "Core", requiredCredits: 3, courseOptions: [["PHYS240"]])
                ],
                concentrations: [
                    Concentration(id: "applied-physics-concentration", name: "Applied Physics Concentration", requirements: [
                        RequirementCategory(id: "applied", name: "Applied", requiredCredits: 3, courseOptions: [["PHYS360"]])
                    ])
                ]
            )
        )

        store.selectProgram(try! #require(store.catalog?.programs.first))

        #expect(store.requiresConcentrationSelection)
        #expect(!store.majorSelectionComplete)
        store.selectConcentration(id: "applied-physics-concentration")
        #expect(store.plan.concentrationID == "applied-physics-concentration")
        #expect(store.majorSelectionComplete)
    }

    @Test("changing major clears invalid concentration")
    func changingMajorClearsInvalidConcentration() {
        let physics = Program.fixture(
            id: "physics-bs",
            title: "Physics, B.S.",
            requirements: [],
            concentrations: [
                Concentration(id: "applied-physics-concentration", name: "Applied Physics Concentration", requirements: [])
            ]
        )
        let chemistry = Program.fixture(id: "chemistry-bs", title: "Chemistry, B.S.", requirements: [])
        let store = PlanStore()
        store.catalog = Catalog(
            source: CatalogSource(catalogYear: "Fixture", issueDate: .distantPast, retrievedDate: .distantPast, sourceURLs: [], retrievalNotes: []),
            programs: [physics, chemistry],
            courses: [],
            apCreditRules: []
        )

        store.selectProgram(physics)
        store.selectConcentration(id: "applied-physics-concentration")
        store.selectProgram(chemistry)

        #expect(store.plan.programID == "chemistry-bs")
        #expect(store.plan.concentrationID == nil)
        #expect(store.majorSelectionComplete)
    }
}
