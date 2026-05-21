import Foundation
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

    @Test("progress includes selected concentration and excludes siblings")
    func progressUsesSelectedConcentrationOnly() throws {
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
                Course(id: "PHYS240", code: "PHYS 240", title: "University Physics I", credits: 4, availability: nil, prerequisites: []),
                Course(id: "PHYS360", code: "PHYS 360", title: "Modern Physics", credits: 3, availability: nil, prerequisites: []),
                Course(id: "PHYS390", code: "PHYS 390", title: "Advanced Seminar", credits: 3, availability: nil, prerequisites: [])
            ],
            program: program
        )
        let pathway = Pathway(id: "p", name: "Path", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["PHYS240", "PHYS360"])
        ])

        let progress = try ProgressCalculator(catalog: catalog).progress(
            programID: "physics-bs",
            concentrationID: "applied-physics-concentration",
            pathway: pathway,
            transferCredits: []
        )

        #expect(progress.categories.map(\.id) == ["core", "applied"])
        #expect(progress.overallRequiredCredits == 7)
        #expect(progress.overallCompletedCredits == 7)
    }

    @Test("AP Lit 5 awarding GNED 123 satisfies the C2L Literature cluster via alias and removes the default ENG course from the schedule")
    func apLitSatisfiesLiteratureClusterViaAlias() throws {
        let rules: [TransferCreditRule] = [
            TransferCreditRule(
                source: .apExam(name: "English Literature and Composition", minimumScore: 5),
                awardedCourseIDs: ["GNED123"],
                credits: 3,
                meetsGeneralEducation: true,
                sourceNote: "AP Lit awards GNED 123 toward C2L"
            )
        ]
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "ENG221", code: "ENG 221", title: "Literature Survey", credits: 3, availability: [.fall, .spring], prerequisites: [])
            ],
            program: Program.fixture(
                id: "any-bs",
                title: "Some Major",
                requirements: [
                    RequirementCategory(
                        id: "gened-c2l",
                        name: "General Education — Literature [C2L]",
                        requiredCredits: 3,
                        courseOptions: [["ENG221"]]
                    )
                ]
            ),
            apRules: rules
        )

        let mapper = TransferCreditMapper(catalog: catalog)
        let credits = mapper.credits(
            forAPScores: [APScore(examName: "English Literature and Composition", score: 5)],
            program: catalog.programs.first,
            completedCourseIDs: []
        )

        #expect(credits.first?.courseIDs == ["GNED123"])

        // Now run scheduler with the credit applied.
        let scheduled = try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "any-bs",
            workload: .standard,
            transferCredits: credits
        )
        let scheduledCourses = scheduled.first?.semesters.flatMap(\.courseIDs) ?? []
        #expect(!scheduledCourses.contains("ENG221"), "ENG 221 must NOT be scheduled because GNED 123 already covers the Literature cluster via alias")
    }

    @Test("global AP allocation spreads two complementary exams across distinct option groups instead of stacking both on the same one")
    func globalAllocationSpreadsAPs() throws {
        // Two AP scores. AP Physics C Mechanics can cover C3PP (PHYS150) +
        // C3L (PHYS150L). AP Chemistry can also cover C3PP (CHEM131) +
        // C3L (CHEM131L) AND C3NS (alias via GNED150-equivalent CHEM???
        // For test simplicity: only one of them can hit C3NS. Set up so that
        // Chemistry has a variant that covers C3NS uniquely, Physics has no
        // such variant. Greedy must give Chemistry to C3NS-covering variant
        // (or at least split so C3NS gets covered).
        //
        // Simpler: Both exams have a single tier with two awarded courses
        // each. Physics awards [PHYS150, PHYS150L] (no C3NS overlap).
        // Chemistry awards [CHEM131, CHEM131L, BIO140] where BIO140 is in
        // C3NS alternates. Without joint allocation, both grab C3PP+C3L;
        // C3NS stays uncovered. With joint allocation, mapper must let
        // Physics take C3PP+C3L and Chemistry's BIO140 takes C3NS.
        let rules: [TransferCreditRule] = [
            TransferCreditRule(
                source: .apExam(name: "Physics C: Mechanics", minimumScore: 4),
                awardedCourseIDs: ["PHYS150", "PHYS150L"],
                credits: 4,
                meetsGeneralEducation: true,
                sourceNote: "covers C3PP + C3L only"
            ),
            TransferCreditRule(
                source: .apExam(name: "Chemistry", minimumScore: 5),
                awardedCourseIDs: ["CHEM131", "CHEM131L", "BIO140"],
                credits: 8,
                meetsGeneralEducation: true,
                sourceNote: "covers C3PP, C3L, or C3NS"
            )
        ]
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "PHYS150", code: "PHYS 150", title: "Physics", credits: 3, availability: nil, prerequisites: []),
                Course(id: "PHYS150L", code: "PHYS 150L", title: "Physics Lab", credits: 1, availability: nil, prerequisites: []),
                Course(id: "CHEM131", code: "CHEM 131", title: "Chemistry", credits: 3, availability: nil, prerequisites: []),
                Course(id: "CHEM131L", code: "CHEM 131L", title: "Chem Lab", credits: 1, availability: nil, prerequisites: []),
                Course(id: "BIO140", code: "BIO 140", title: "Biology", credits: 3, availability: nil, prerequisites: [])
            ],
            program: Program.fixture(
                id: "sci-bs",
                title: "Science Major",
                requirements: [
                    RequirementCategory(id: "c3pp", name: "Physical Principles [C3PP]", requiredCredits: 4, courseOptions: [["PHYS150", "CHEM131"]]),
                    RequirementCategory(id: "c3l", name: "Lab Experience [C3L]", requiredCredits: 1, courseOptions: [["PHYS150L", "CHEM131L"]]),
                    RequirementCategory(id: "c3ns", name: "Natural Systems [C3NS]", requiredCredits: 3, courseOptions: [["BIO140"]])
                ]
            ),
            apRules: rules
        )

        let mapper = TransferCreditMapper(catalog: catalog)
        let credits = mapper.credits(
            forAPScores: [
                APScore(examName: "Physics C: Mechanics", score: 5),
                APScore(examName: "Chemistry", score: 5)
            ],
            program: catalog.programs.first,
            completedCourseIDs: []
        )

        let awardedSet = Set(credits.flatMap(\.courseIDs))
        // All three clusters must be covered between the two exams.
        let coversC3PP = awardedSet.contains("PHYS150") || awardedSet.contains("CHEM131")
        let coversC3L  = awardedSet.contains("PHYS150L") || awardedSet.contains("CHEM131L")
        let coversC3NS = awardedSet.contains("BIO140")
        #expect(coversC3PP, "C3PP must be covered")
        #expect(coversC3L, "C3L must be covered")
        #expect(coversC3NS, "C3NS must be covered: the joint allocation must route Chemistry's BIO 140 here instead of stacking both exams on C3PP+C3L")
    }

    @Test("scheduler emits placeholder courses for multi-alternate option groups")
    func schedulerEmitsPlaceholdersForMultiAlternateOptions() throws {
        // Two categories with the same multi-alternate option list. The new
        // contract: the scheduler queues ONE placeholder per option group
        // (the student picks the actual course in the Schedule tab). The
        // catalog's MATH 220 / ISAT 251 IDs must not appear in the pathway.
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "MATH220", code: "MATH 220", title: "Elementary Stats", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "ISAT251", code: "ISAT 251", title: "Stats", credits: 3, availability: [.fall, .spring], prerequisites: [])
            ],
            program: Program.fixture(
                id: "psyc-bs",
                title: "Psych",
                requirements: [
                    RequirementCategory(id: "qr", name: "QR", requiredCredits: 3, courseOptions: [["MATH220", "ISAT251"]]),
                    RequirementCategory(id: "stats", name: "Stats Req", requiredCredits: 3, courseOptions: [["MATH220", "ISAT251"]])
                ]
            )
        )

        let pathways = try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "psyc-bs",
            workload: .standard,
            transferCredits: []
        )

        let pathway = try #require(pathways.first)
        let scheduled = pathway.semesters.flatMap(\.courseIDs)
        #expect(scheduled.contains { PathwayPlaceholder.isPlaceholder($0) }, "must schedule at least one placeholder course")
        #expect(!scheduled.contains("MATH220"), "multi-alternate options stay as placeholders until the student picks")
        #expect(pathway.placeholders.count == 2, "one placeholder per multi-alternate option group")
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

@Suite("Conflict detector prereq/coreq expression wiring")
struct ConflictDetectorPrereqWiringTests {
    @Test("unmet parsed prerequisite emits warning")
    func unmetPrereqInLaterTermFiresWarning() throws {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2025, term: .fall), courseIDs: ["cs-240"])
        ])

        let warnings = ConflictDetector(catalog: Self.catalog).warnings(for: pathway, overrides: [])

        #expect(warnings.contains { $0.kind == .missingPrerequisite && $0.courseID == "cs-240" })
    }

    @Test("missing parsed corequisite emits warning")
    func coreqViolationFires() throws {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2025, term: .fall), courseIDs: ["cs-240"])
        ])

        let warnings = ConflictDetector(catalog: Self.catalog).warnings(for: pathway, overrides: [])

        #expect(warnings.contains { $0.kind == .missingCorequisite && $0.courseID == "cs-240" })
    }

    @Test("parsed prerequisite satisfied by earlier term")
    func prereqSatisfiedByEarlierTerm() throws {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2024, term: .fall), courseIDs: ["cs-159", "math-235"]),
            SemesterPlan(id: SemesterIdentity(year: 2025, term: .fall), courseIDs: ["cs-240"])
        ])

        let warnings = ConflictDetector(catalog: Self.catalog).warnings(for: pathway, overrides: [])

        #expect(!warnings.contains { $0.kind == .missingPrerequisite && $0.courseID == "cs-240" })
    }

    private static let catalog: Catalog = {
        let cs159 = Course(id: "cs-159", code: "CS 159", title: "Intro", credits: 3, availability: nil, prerequisites: [])
        var cs240 = Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: ["cs-159"])
        cs240.prerequisiteExpr = .course("cs-159")
        cs240.corequisiteExpr = .course("math-235")
        let math235 = Course(id: "math-235", code: "MATH 235", title: "Calc I", credits: 3, availability: nil, prerequisites: [])
        return Catalog.fixture(
            courses: [cs159, cs240, math235],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: [])
        )
    }()

    @Test("curated overlay wins over raw parser in conflict detector")
    func curatedOverlayWinsInConflictDetector() throws {
        var cs240 = Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: CS 159."
        let overlay = PrereqRuleOverlay(schemaVersion: 1, rules: [
            PrereqRule(
                courseID: "cs-240",
                prerequisiteExpr: .course("cs-149"),
                corequisiteExpr: .empty,
                confidence: .curated,
                basis: .explicit,
                sourceURL: URL(string: "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=123&print")!,
                sourceText: "Prerequisite: CS 149.",
                notes: nil
            )
        ])
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "cs-149", code: "CS 149", title: "Intro", credits: 3, availability: nil, prerequisites: []),
                Course(id: "cs-159", code: "CS 159", title: "Advanced", credits: 3, availability: nil, prerequisites: []),
                cs240
            ],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: []),
            prereqRuleOverlay: overlay
        )
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["cs-149"]),
            SemesterPlan(id: SemesterIdentity(year: 2027, term: .spring), courseIDs: ["cs-240"])
        ])

        let warnings = ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: [])

        #expect(!warnings.contains { $0.kind == .missingPrerequisite && $0.courseID == "cs-240" })
    }

    @Test("parsed prereq warning identifies low-confidence parser source")
    func parsedPrereqWarningIdentifiesParserSource() throws {
        var cs240 = Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: CS 159."
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "cs-159", code: "CS 159", title: "Advanced", credits: 3, availability: nil, prerequisites: []),
                cs240
            ],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: [])
        )
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["cs-240"])
        ])

        let warning = try #require(ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: []).first {
            $0.kind == .missingPrerequisite && $0.courseID == "cs-240"
        })

        #expect(warning.message.contains("Parsed from catalog text; verify before registering."))
    }

    @Test("curated warning appends source-backed note")
    func curatedWarningAppendsSourceBackedNote() throws {
        let overlay = PrereqRuleOverlay(schemaVersion: 1, rules: [
            PrereqRule(
                courseID: "cs-345",
                prerequisiteExpr: .course("cs-240"),
                corequisiteExpr: .empty,
                confidence: .curated,
                basis: .inferred,
                sourceURL: URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=999&print")!,
                sourceText: "The recommended sequence lists CS 240 before CS 345.",
                notes: "Official sequence supports treating CS 240 as required preparation."
            )
        ])
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: []),
                Course(id: "cs-345", code: "CS 345", title: "Software Engineering", credits: 3, availability: nil, prerequisites: [])
            ],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: []),
            prereqRuleOverlay: overlay
        )
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["cs-345"])
        ])

        let warning = try #require(ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: []).first {
            $0.kind == .missingPrerequisite && $0.courseID == "cs-345"
        })

        #expect(warning.message.contains("Catalog note: Official sequence supports treating CS 240 as required preparation."))
    }
}

@Suite("Conflict detector conditional prereq clauses")
struct ConflictDetectorConditionalPrereqTests {
    @Test("matching major uses major-specific prereq branch")
    func matchingMajorUsesMajorSpecificBranch() {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2024, term: .fall), courseIDs: ["math-235"]),
            SemesterPlan(id: SemesterIdentity(year: 2025, term: .fall), courseIDs: ["cs-240"])
        ])

        let warnings = ConflictDetector(catalog: Self.catalog).warnings(
            for: pathway,
            overrides: [],
            activeProgramTitle: "Computer Science, B.S."
        )

        #expect(warnings.contains { $0.kind == .missingPrerequisite && $0.courseID == "cs-240" })
    }

    @Test("non-matching major uses non-major prereq branch")
    func nonMatchingMajorUsesNonMajorBranch() {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2024, term: .fall), courseIDs: ["math-235"]),
            SemesterPlan(id: SemesterIdentity(year: 2025, term: .fall), courseIDs: ["cs-240"])
        ])

        let warnings = ConflictDetector(catalog: Self.catalog).warnings(
            for: pathway,
            overrides: [],
            activeProgramTitle: "Computer Information Systems, B.B.A."
        )

        #expect(!warnings.contains { $0.kind == .missingPrerequisite && $0.courseID == "cs-240" })
    }

    private static let catalog: Catalog = {
        let cs159 = Course(id: "cs-159", code: "CS 159", title: "Intro", credits: 3, availability: nil, prerequisites: [])
        let math235 = Course(id: "math-235", code: "MATH 235", title: "Calc I", credits: 3, availability: nil, prerequisites: [])
        var cs240 = Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: For Computer Science majors: CS 159. For non Computer Science majors: MATH 235."
        return Catalog.fixture(
            courses: [cs159, math235, cs240],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: [])
        )
    }()
}
