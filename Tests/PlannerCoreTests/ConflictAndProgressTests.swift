import Testing
@testable import PlannerCore

@Suite("Conflicts and progress")
struct ConflictAndProgressTests {
    @Test("prerequisite warnings can be overridden without disappearing")
    func prerequisiteWarningCanBeOverridden() throws {
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS149", code: "CS 149", title: "Introduction to Programming", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CS159", code: "CS 159", title: "Advanced Programming", credits: 3, availability: [.fall, .spring], prerequisites: ["CS149"])
            ],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(id: "major-core", name: "Major Core Requirements", requiredCredits: 6, courseOptions: [["CS149"], ["CS159"]])
                ]
            )
        )
        let pathway = Pathway(
            id: "manual",
            name: "Manual Plan",
            semesters: [
                SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["CS159"]),
                SemesterPlan(id: SemesterIdentity(year: 2027, term: .spring), courseIDs: ["CS149"])
            ]
        )

        let warnings = ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: [])
        #expect(warnings.map(\.kind).contains(.missingPrerequisite))

        let override = ConflictOverride(courseID: "CS159", semester: SemesterIdentity(year: 2026, term: .fall), kind: .missingPrerequisite)
        let overridden = ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: [override])
        #expect(overridden.first?.isOverridden == true)
    }

    @Test("progress counts transfer and scheduled credits by category")
    func progressCountsCreditsByRequirementCategory() throws {
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS149", code: "CS 149", title: "Introduction to Programming", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CS159", code: "CS 159", title: "Advanced Programming", credits: 3, availability: [.spring], prerequisites: ["CS149"]),
                Course(id: "WRTC103", code: "WRTC 103", title: "Rhetorical Reading and Writing", credits: 3, availability: nil, prerequisites: [])
            ],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(id: "major-core", name: "Major Core Requirements", requiredCredits: 6, courseOptions: [["CS149"], ["CS159"]]),
                    RequirementCategory(id: "gen-ed", name: "General Education", requiredCredits: 3, courseOptions: [["WRTC103"]])
                ]
            )
        )
        let pathway = Pathway(
            id: "standard",
            name: "Standard Plan",
            semesters: [
                SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["CS159"])
            ]
        )
        let transfer = TransferCredit(sourceDescription: "AP Computer Science A", courseIDs: ["CS149"], credits: 3)

        let progress = try ProgressCalculator(catalog: catalog).progress(programID: "cs-bs", pathway: pathway, transferCredits: [transfer])

        #expect(progress.overallCompletedCredits == 6)
        #expect(progress.overallRequiredCredits == 9)
        #expect(progress.projectedGraduation == SemesterIdentity(year: 2026, term: .fall))
        #expect(progress.categories.first(where: { $0.id == "major-core" })?.remainingCredits == 0)
        #expect(progress.categories.first(where: { $0.id == "gen-ed" })?.remainingCredits == 3)
    }
}
