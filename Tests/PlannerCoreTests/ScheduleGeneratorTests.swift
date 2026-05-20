import Testing
@testable import PlannerCore

@Suite("Schedule generation")
struct ScheduleGeneratorTests {
    @Test("generated pathways satisfy prerequisites and known semester availability")
    func generatedPathwayRespectsPrerequisitesAndAvailability() throws {
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS149", code: "CS 149", title: "Introduction to Programming", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CS159", code: "CS 159", title: "Advanced Programming", credits: 3, availability: [.spring], prerequisites: ["CS149"]),
                Course(id: "CS240", code: "CS 240", title: "Algorithms and Data Structures", credits: 3, availability: [.fall], prerequisites: ["CS159"])
            ],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(id: "major-core", name: "Major Core Requirements", requiredCredits: 9, courseOptions: [["CS149"], ["CS159"], ["CS240"]])
                ]
            )
        )

        let generator = ScheduleGenerator(catalog: catalog)
        let pathways = try generator.generatePathways(for: "cs-bs", workload: .light, transferCredits: [], starting: SemesterIdentity(year: 2026, term: .fall))

        #expect(pathways.count == 3)
        let first = try #require(pathways.first)
        #expect(first.semesters.map(\.term) == [.fall, .spring, .fall])
        #expect(first.semesters.flatMap(\.courseIDs) == ["CS149", "CS159", "CS240"])
        #expect(ConflictDetector(catalog: catalog).warnings(for: first, overrides: []).isEmpty)
    }

    @Test("a generated pathway is shorter when AP credit completes a required course")
    func generatedPathwayUsesTransferCredits() throws {
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS149", code: "CS 149", title: "Introduction to Programming", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CS159", code: "CS 159", title: "Advanced Programming", credits: 3, availability: [.spring], prerequisites: ["CS149"])
            ],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(id: "major-core", name: "Major Core Requirements", requiredCredits: 6, courseOptions: [["CS149"], ["CS159"]])
                ]
            ),
            apRules: [
                TransferCreditRule(source: .apExam(name: "Computer Science A", minimumScore: 5), awardedCourseIDs: ["CS149", "CS000"], credits: 6, meetsGeneralEducation: false, sourceNote: "JMU 2025-2026 Undergraduate Catalog, Advanced Placement Chart")
            ]
        )

        let credits = TransferCreditMapper(catalog: catalog).credits(forAPScores: [APScore(examName: "Computer Science A", score: 5)])
        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(for: "cs-bs", workload: .light, transferCredits: credits, starting: SemesterIdentity(year: 2026, term: .fall)).first)

        #expect(credits.flatMap(\.courseIDs).contains("CS149"))
        #expect(pathway.semesters.flatMap(\.courseIDs) == ["CS159"])
        #expect(pathway.projectedGraduation == SemesterIdentity(year: 2027, term: .spring))
    }

    @Test("scheduler includes selected concentration and excludes siblings")
    func schedulerUsesSelectedConcentrationOnly() throws {
        let program = Program(
            id: "physics-bs",
            title: "Physics, B.S.",
            degreeType: "B.S.",
            kind: .major,
            college: "College of Science and Mathematics",
            department: "Physics and Astronomy",
            catalogPage: nil,
            totalCredits: 120,
            requirements: [
                RequirementCategory(id: "core", name: "Physics Core", requiredCredits: 4, courseOptions: [["PHYS240"]])
            ],
            concentrations: [
                Concentration(id: "applied-physics-concentration", name: "Applied Physics Concentration", requirements: [
                    RequirementCategory(id: "applied", name: "Applied Physics Required Courses", requiredCredits: 3, courseOptions: [["PHYS360"]])
                ]),
                Concentration(id: "fundamental-studies-concentration", name: "Fundamental Studies Concentration", requirements: [
                    RequirementCategory(id: "fundamental", name: "Fundamental Studies Required Courses", requiredCredits: 3, courseOptions: [["PHYS390"]])
                ])
            ],
            verificationStatus: .partial,
            requirementDataComplete: true,
            sourceNote: "Fixture"
        )
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "PHYS240", code: "PHYS 240", title: "University Physics I", credits: 4, availability: [.fall, .spring], prerequisites: []),
                Course(id: "PHYS360", code: "PHYS 360", title: "Modern Physics", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "PHYS390", code: "PHYS 390", title: "Advanced Seminar", credits: 3, availability: [.fall, .spring], prerequisites: [])
            ],
            program: program
        )

        let pathways = try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "physics-bs",
            concentrationID: "applied-physics-concentration",
            workload: .standard,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        )

        let scheduled = pathways.first?.semesters.flatMap(\.courseIDs) ?? []
        #expect(scheduled.contains("PHYS240"))
        #expect(scheduled.contains("PHYS360"))
        #expect(!scheduled.contains("PHYS390"))
    }
}
