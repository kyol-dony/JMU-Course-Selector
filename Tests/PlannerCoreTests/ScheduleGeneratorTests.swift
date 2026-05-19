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
}
