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

    @Test("scheduler skips an option group when any alternate is already completed")
    func schedulerHonorsAnyAlternateMatch() throws {
        // The Physical Principles cluster offers ASTR 120 as its first
        // alternate and CHEM 131 deeper in the list. With CHEM 131 already
        // granted by AP transfer credit, the scheduler must NOT schedule
        // ASTR 120 just because it is the first listed alternate.
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "ASTR120", code: "ASTR 120", title: "Astronomy", credits: 4, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CHEM131", code: "CHEM 131", title: "General Chemistry", credits: 3, availability: [.fall, .spring], prerequisites: [])
            ],
            program: Program.fixture(
                id: "cis-bba",
                title: "CIS, B.B.A.",
                requirements: [
                    RequirementCategory(
                        id: "gened-c3pp",
                        name: "Physical Principles",
                        requiredCredits: 4,
                        courseOptions: [["ASTR120", "CHEM131"]]
                    )
                ]
            )
        )

        let scheduler = ScheduleGenerator(catalog: catalog)
        let pathways = try scheduler.generatePathways(
            for: "cis-bba",
            workload: .standard,
            transferCredits: [TransferCredit(sourceDescription: "AP Chem", courseIDs: ["CHEM131"], credits: 3)]
        )

        let scheduledCourses = pathways.first?.semesters.flatMap(\.courseIDs) ?? []
        #expect(!scheduledCourses.contains("ASTR120"), "ASTR 120 must NOT be scheduled: CHEM 131 already satisfies the Physical Principles option")
        #expect(!scheduledCourses.contains("CHEM131"), "CHEM 131 must NOT be re-scheduled either; it is already a transfer credit")
    }

    @Test("AP mapper weights coverage by credits the variant would rescue")
    func apMapperWeightsByRescuedCredits() throws {
        // Two AP variants. Variant A satisfies a 1cr Lab Experience option.
        // Variant B satisfies a 4cr Physical Principles option. Both award
        // 3 nominal credits, both meet gen ed. Optimizer must pick variant B
        // because it knocks out more catalog credits toward graduation.
        let rules: [TransferCreditRule] = [
            TransferCreditRule(
                source: .apExam(name: "Chemistry", minimumScore: 4),
                awardedCourseIDs: ["CHEM131L"],
                credits: 3,
                meetsGeneralEducation: true,
                sourceNote: "variant A: 1-credit lab"
            ),
            TransferCreditRule(
                source: .apExam(name: "Chemistry", minimumScore: 4),
                awardedCourseIDs: ["CHEM131"],
                credits: 3,
                meetsGeneralEducation: true,
                sourceNote: "variant B: 4-credit physical principles"
            )
        ]
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CHEM131", code: "CHEM 131", title: "Gen Chem", credits: 3, availability: nil, prerequisites: []),
                Course(id: "CHEM131L", code: "CHEM 131L", title: "Gen Chem Lab", credits: 1, availability: nil, prerequisites: [])
            ],
            program: Program.fixture(
                id: "bio-bs",
                title: "Bio",
                requirements: [
                    RequirementCategory(id: "c3pp", name: "Physical Principles", requiredCredits: 4, courseOptions: [["CHEM131"]]),
                    RequirementCategory(id: "c3l", name: "Lab Experience", requiredCredits: 1, courseOptions: [["CHEM131L"]])
                ]
            ),
            apRules: rules
        )

        let mapper = TransferCreditMapper(catalog: catalog)
        let credits = mapper.credits(
            forAPScores: [APScore(examName: "Chemistry", score: 5)],
            program: catalog.programs.first,
            completedCourseIDs: []
        )

        #expect(credits.first?.courseIDs == ["CHEM131"], "must pick variant B; rescues 4 catalog credits vs variant A's 1")
    }

    @Test("AP credit mapper routes a multi-variant exam to the variant that satisfies the most major requirements")
    func apMapperPicksHighestCoverageVariant() throws {
        // Same exam, same score tier, two `or`-style variants.
        // Only the second variant's courses appear in the major requirements.
        // The mapper must pick the second variant even though both qualify.
        let rules: [TransferCreditRule] = [
            TransferCreditRule(
                source: .apExam(name: "Statistics", minimumScore: 4),
                awardedCourseIDs: ["ISAT251"],
                credits: 3,
                meetsGeneralEducation: true,
                sourceNote: "OR alternative #1"
            ),
            TransferCreditRule(
                source: .apExam(name: "Statistics", minimumScore: 4),
                awardedCourseIDs: ["MATH220"],
                credits: 3,
                meetsGeneralEducation: true,
                sourceNote: "OR alternative #2"
            )
        ]
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "ISAT251", code: "ISAT 251", title: "Stats", credits: 3, availability: nil, prerequisites: []),
                Course(id: "MATH220", code: "MATH 220", title: "Elementary Stats", credits: 3, availability: nil, prerequisites: [])
            ],
            program: Program.fixture(
                id: "psyc-bs",
                title: "Psychology, B.S.",
                requirements: [
                    RequirementCategory(id: "stats", name: "Stats Requirement", requiredCredits: 3, courseOptions: [["MATH220"]])
                ]
            ),
            apRules: rules
        )

        let mapper = TransferCreditMapper(catalog: catalog)
        let credits = mapper.credits(
            forAPScores: [APScore(examName: "Statistics", score: 5)],
            program: catalog.programs.first,
            completedCourseIDs: []
        )

        #expect(credits.count == 1)
        #expect(credits.first?.courseIDs == ["MATH220"], "mapper should pick MATH220 because it's in the program's stats requirement")
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
