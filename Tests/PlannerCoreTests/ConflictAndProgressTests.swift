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

    @Test("AP credit mapper grants only the highest qualifying tier per exam")
    func apMapperPicksHighestTier() throws {
        let rules: [TransferCreditRule] = [
            TransferCreditRule(
                source: .apExam(name: "Chemistry", minimumScore: 3),
                awardedCourseIDs: ["CHEM120"],
                credits: 4,
                meetsGeneralEducation: true,
                sourceNote: "score 3 tier"
            ),
            TransferCreditRule(
                source: .apExam(name: "Chemistry", minimumScore: 4),
                awardedCourseIDs: ["CHEM131", "CHEM132"],
                credits: 6,
                meetsGeneralEducation: true,
                sourceNote: "score 4 tier"
            )
        ]
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CHEM120", code: "CHEM 120", title: "Gen Chem", credits: 4, availability: nil, prerequisites: []),
                Course(id: "CHEM131", code: "CHEM 131", title: "Gen Chem I", credits: 3, availability: nil, prerequisites: []),
                Course(id: "CHEM132", code: "CHEM 132", title: "Gen Chem II", credits: 3, availability: nil, prerequisites: [])
            ],
            program: Program.fixture(
                id: "chem-bs",
                title: "Chemistry, B.S.",
                requirements: [
                    RequirementCategory(id: "core", name: "Major Core", requiredCredits: 6, courseOptions: [["CHEM131"], ["CHEM132"]])
                ]
            ),
            apRules: rules
        )

        let mapper = TransferCreditMapper(catalog: catalog)
        let credits = mapper.credits(forAPScores: [APScore(examName: "Chemistry", score: 5)])

        #expect(credits.count == 1, "score 5 must dedupe to a single rule, not stack the score-3 and score-4 awards")
        #expect(credits.first?.courseIDs == ["CHEM131", "CHEM132"])
        #expect(credits.first?.credits == 6)
    }
}
