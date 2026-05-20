import Testing
@testable import PlannerCore

@Suite
struct RequirementSelectionCoreTests {
    @Test
    func schedulerUsesSelectedRequirementOption() throws {
        let catalog = requirementSelectionCatalog()
        let selectionKey = catalog.programs[0].requirements[0].selectionKey

        let pathways = try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "cis-bba",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall),
            requirementSelections: [selectionKey: ["CIS-484"]]
        )

        let scheduled = Set(try #require(pathways.first).semesters.flatMap(\.courseIDs))
        #expect(scheduled.contains("CIS-484"))
        #expect(!scheduled.contains("CIS-464"))
    }

    @Test
    func schedulerSkipsSelectedOptionWhenTransferCreditAlreadyCompletesIt() throws {
        let catalog = requirementSelectionCatalog()
        let selectionKey = catalog.programs[0].requirements[0].selectionKey

        let pathways = try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "cis-bba",
            workload: .light,
            transferCredits: [
                TransferCredit(sourceDescription: "Transfer", courseIDs: ["CIS-484"], credits: 3)
            ],
            starting: SemesterIdentity(year: 2026, term: .fall),
            requirementSelections: [selectionKey: ["CIS-484"]]
        )

        let scheduled = Set(try #require(pathways.first).semesters.flatMap(\.courseIDs))
        #expect(!scheduled.contains("CIS-484"))
        #expect(!scheduled.contains("CIS-464"))
    }

    @Test
    func progressUsesSelectedRequirementOption() throws {
        let catalog = requirementSelectionCatalog()
        let selectionKey = catalog.programs[0].requirements[0].selectionKey
        let pathway = Pathway(
            id: "path-1",
            name: "Path",
            semesters: [
                SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["CIS-484"])
            ]
        )

        let progress = try ProgressCalculator(catalog: catalog).progress(
            programID: "cis-bba",
            pathway: pathway,
            transferCredits: [],
            requirementSelections: [selectionKey: ["CIS-484"]]
        )

        let category = try #require(progress.categories.first)
        #expect(category.completedCredits == 3)
        #expect(progress.overallCompletedCredits == 3)
    }

    @Test
    func invalidSelectionFallsBackToCatalogDefault() throws {
        let catalog = requirementSelectionCatalog()
        let selectionKey = catalog.programs[0].requirements[0].selectionKey

        let pathways = try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "cis-bba",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall),
            requirementSelections: [selectionKey: ["NOT-A-COURSE"]]
        )

        let scheduled = Set(try #require(pathways.first).semesters.flatMap(\.courseIDs))
        #expect(scheduled.contains("CIS-464"))
        #expect(!scheduled.contains("CIS-484"))
    }
}

private func requirementSelectionCatalog() -> Catalog {
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
