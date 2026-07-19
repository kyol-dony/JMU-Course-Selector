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

    @Test("removing a course resolved from an open-elective placeholder restores the placeholder")
    func removingResolvedOpenElectiveRestoresPlaceholder() throws {
        let store = PlanStore()
        store.catalog = Catalog.fixture(
            courses: [
                Course(id: "ART200", code: "ART 200", title: "Studio Art", credits: 3, availability: [.fall, .spring], prerequisites: [])
            ],
            program: Program.fixture(
                id: "cs-bs",
                title: "CS, B.S.",
                requirements: [
                    RequirementCategory(id: "core", name: "Core", requiredCredits: 3, courseOptions: [["CS149"]])
                ]
            )
        )
        let placeholderID = PathwayPlaceholder.id(
            categoryID: ScheduleGenerator.openElectiveCategoryID,
            optionIndex: 0
        )
        let spec = PlaceholderSpec(
            categoryID: ScheduleGenerator.openElectiveCategoryID,
            categoryName: "Open Elective",
            alternates: [],
            credits: 3
        )
        store.plan.pathways = [
            Pathway(
                id: "path-1",
                name: "Balanced Path",
                semesters: [
                    SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: [placeholderID])
                ],
                placeholders: [placeholderID: spec]
            )
        ]
        store.plan.activePathwayID = "path-1"

        store.resolvePlaceholder(placeholderID, with: "ART200")
        #expect(store.plan.pathways[0].semesters[0].courseIDs == ["ART200"])
        #expect(store.plan.pathways[0].resolvedPlaceholders[placeholderID] == "ART200")
        // Spec must survive resolution so removal can bring the slot back.
        #expect(store.plan.pathways[0].placeholders[placeholderID] != nil)

        store.removeCourse("ART200")
        #expect(store.plan.pathways[0].semesters[0].courseIDs == [placeholderID])
        #expect(store.plan.pathways[0].resolvedPlaceholders[placeholderID] == nil)
        #expect(store.plan.pathways[0].placeholders[placeholderID] != nil)
    }

    @Test("removing a resolved course rebuilds a missing placeholder spec from stale data")
    func removingResolvedCourseRebuildsMissingSpec() throws {
        let store = PlanStore()
        store.catalog = Catalog.fixture(
            courses: [
                Course(id: "ART200", code: "ART 200", title: "Studio Art", credits: 3, availability: [.fall, .spring], prerequisites: [])
            ],
            program: Program.fixture(id: "cs-bs", title: "CS, B.S.", requirements: [])
        )
        let placeholderID = PathwayPlaceholder.id(
            categoryID: ScheduleGenerator.openElectiveCategoryID,
            optionIndex: 2
        )
        // Simulate a pathway persisted before specs were kept at resolve
        // time: the resolution mapping exists but the spec is gone.
        store.plan.pathways = [
            Pathway(
                id: "path-1",
                name: "Balanced Path",
                semesters: [
                    SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["ART200"])
                ],
                placeholders: [:],
                resolvedPlaceholders: [placeholderID: "ART200"]
            )
        ]
        store.plan.activePathwayID = "path-1"

        store.removeCourse("ART200")

        #expect(store.plan.pathways[0].semesters[0].courseIDs == [placeholderID])
        let spec = try #require(store.plan.pathways[0].placeholders[placeholderID])
        #expect(spec.categoryID == ScheduleGenerator.openElectiveCategoryID)
        #expect(spec.alternates.isEmpty)
        #expect(spec.credits == 3)
    }

    @Test("selecting a major with optional concentrations allows base major")
    func optionalConcentrationsAllowBaseMajorSelection() throws {
        let statistics = Program(
            id: "statistics-bs",
            title: "Statistics, B.S.",
            degreeType: "B.S.",
            kind: .major,
            college: "College of Science and Mathematics",
            department: "Mathematics and Statistics",
            catalogPage: nil,
            totalCredits: 120,
            requirements: [
                RequirementCategory(id: "core", name: "Core", requiredCredits: 3, courseOptions: [["MATH329"]])
            ],
            concentrations: [
                Concentration(id: "data-science", name: "Data Science", requirements: [
                    RequirementCategory(id: "data", name: "Data Science", requiredCredits: 3, courseOptions: [["DATA200"]])
                ])
            ],
            concentrationSelectionRequired: false,
            verificationStatus: .partial,
            requirementDataComplete: true,
            sourceNote: "Fixture"
        )
        let store = PlanStore()
        store.catalog = Catalog.fixture(courses: [], program: statistics)

        store.selectProgram(statistics)

        #expect(!store.requiresConcentrationSelection)
        #expect(store.majorSelectionComplete)
        #expect(store.plan.concentrationID == nil)
        let effective = try #require(store.effectiveActiveProgram)
        #expect(effective.requirements.map(\.id) == ["core"])
    }

    @Test("remaining courses treat GNED AP aliases as completed Gen Ed categories")
    func remainingCoursesTreatGNEDAliasesAsCompleted() {
        let literature = RequirementCategory(
            id: "gened-c2l",
            name: "General Education — Literature [C2L]",
            requiredCredits: 3,
            courseOptions: [["ENG221"]]
        )
        let program = Program.fixture(
            id: "any-bs",
            title: "Some Major",
            requirements: [literature]
        )
        let store = PlanStore()
        store.catalog = Catalog.fixture(
            courses: [
                Course(id: "ENG221", code: "ENG 221", title: "Literature Survey", credits: 3, availability: [.fall, .spring], prerequisites: [])
            ],
            program: program
        )
        store.selectProgram(program)
        store.plan.transferCredits = [
            TransferCredit(sourceDescription: "AP English Literature and Composition score 5", courseIDs: ["GNED123"], credits: 3)
        ]

        #expect(store.remainingCourses(in: literature).isEmpty)
    }

    @Test("progress contributions show AP Lit GNED credit as transfer row")
    func progressContributionsShowAPLitGNEDCreditAsTransferRow() {
        let literature = RequirementCategory(
            id: "gened-c2l",
            name: "General Education — Literature [C2L]",
            requiredCredits: 3,
            courseOptions: [["ENG221"]]
        )
        let rows = ProgressContributionBuilder.contributions(
            for: literature,
            transferCredits: [
                TransferCredit(sourceDescription: "AP English Literature and Composition score 5", courseIDs: ["GNED123"], credits: 3)
            ],
            scheduled: [:],
            coursesByID: [
                "ENG221": Course(id: "ENG221", code: "ENG 221", title: "Literature Survey", credits: 3, availability: [.fall, .spring], prerequisites: [])
            ]
        )

        #expect(rows == [
            CourseContribution(code: "AP English Literature & Composition", source: "Transfer", isTransfer: true)
        ])
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
