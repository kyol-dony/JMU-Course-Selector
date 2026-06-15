import Foundation
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

    @Test("concentration electives schedule only required credits")
    func concentrationElectivesScheduleOnlyRequiredCredits() throws {
        let program = Program(
            id: "cis-bba",
            title: "Computer Information Systems, B.B.A.",
            degreeType: "B.B.A.",
            kind: .major,
            college: "College of Business",
            department: "Computer Information Systems",
            catalogPage: nil,
            totalCredits: 9,
            requirements: [
                RequirementCategory(id: "core", name: "CIS Core", requiredCredits: 3, courseOptions: [["CIS221"]])
            ],
            concentrations: [
                Concentration(id: "information-systems", name: "Information Systems", requirements: [
                    RequirementCategory(
                        id: "is-electives",
                        name: "Information Systems Concentration Electives: 6 Credit Hours",
                        requiredCredits: 6,
                        courseOptions: [["CIS330"], ["CIS454"], ["CIS464"], ["CIS484"]]
                    )
                ])
            ],
            verificationStatus: .partial,
            requirementDataComplete: true,
            sourceNote: "Fixture"
        )
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CIS221", code: "CIS 221", title: "Programming", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CIS330", code: "CIS 330", title: "Database", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CIS454", code: "CIS 454", title: "Project Management", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CIS464", code: "CIS 464", title: "Networks", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CIS484", code: "CIS 484", title: "Development", credits: 3, availability: [.fall, .spring], prerequisites: [])
            ],
            program: program
        )

        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "cis-bba",
            concentrationID: "information-systems",
            workload: .standard,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        let scheduledIDs = pathway.semesters.flatMap(\.courseIDs)
        let scheduled = Set(scheduledIDs)
        let electiveIDs: Set<String> = ["CIS330", "CIS454", "CIS464", "CIS484"]
        let placeholderIDs = scheduledIDs.filter(PathwayPlaceholder.isPlaceholder)
        #expect(scheduled.contains("CIS221"))
        #expect(scheduled.intersection(electiveIDs).isEmpty)
        #expect(placeholderIDs.count == 2)
        for placeholderID in placeholderIDs {
            let spec = try #require(pathway.placeholders[placeholderID])
            #expect(Set(spec.alternates) == electiveIDs)
            #expect(spec.credits == 3)
        }
    }

    @Test("scheduler folds added minor's required courses into the major's pathway")
    func schedulerSchedulesMinorRequirements() throws {
        let major = Program.fixture(
            id: "cis-bba",
            title: "CIS, B.B.A.",
            requirements: [
                RequirementCategory(id: "core", name: "Core", requiredCredits: 3, courseOptions: [["CIS221"]])
            ]
        )
        let minor = Program(
            id: "robotics-minor",
            title: "Robotics Minor",
            degreeType: nil,
            kind: .minor,
            college: "X",
            department: "X",
            catalogPage: nil,
            totalCredits: nil,
            requirements: [
                RequirementCategory(id: "rob-core", name: "Robotics Core", requiredCredits: 3, courseOptions: [["ROB200"]])
            ],
            verificationStatus: .partial,
            requirementDataComplete: true,
            sourceNote: "Fixture"
        )
        let catalog = Catalog(
            source: CatalogSource(catalogYear: "Fixture", issueDate: Date(timeIntervalSince1970: 0), retrievedDate: Date(timeIntervalSince1970: 0), sourceURLs: [], retrievalNotes: []),
            programs: [major, minor],
            courses: [
                Course(id: "CIS221", code: "CIS 221", title: "Programming", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "ROB200", code: "ROB 200", title: "Intro Robotics", credits: 3, availability: [.fall, .spring], prerequisites: [])
            ],
            apCreditRules: []
        )

        let pathways = try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "cis-bba",
            workload: .standard,
            transferCredits: [],
            additionalPrograms: [minor]
        )

        let scheduled = pathways.first?.semesters.flatMap(\.courseIDs) ?? []
        #expect(scheduled.contains("CIS221"))
        #expect(scheduled.contains("ROB200"), "minor's required course must be threaded into the pathway")
    }

    @Test("progress calculator surfaces a minor's categories with a Minor: prefix")
    func progressIncludesMinorCategories() throws {
        let major = Program.fixture(
            id: "cis-bba",
            title: "CIS",
            requirements: [
                RequirementCategory(id: "core", name: "Core", requiredCredits: 3, courseOptions: [["CIS221"]])
            ]
        )
        let minor = Program(
            id: "robotics-minor",
            title: "Robotics Minor",
            degreeType: nil,
            kind: .minor,
            college: "X",
            department: "X",
            catalogPage: nil,
            totalCredits: nil,
            requirements: [
                RequirementCategory(id: "rob-core", name: "Robotics Core", requiredCredits: 3, courseOptions: [["ROB200"]])
            ],
            verificationStatus: .partial,
            requirementDataComplete: true,
            sourceNote: "Fixture"
        )
        let catalog = Catalog(
            source: CatalogSource(catalogYear: "Fixture", issueDate: Date(timeIntervalSince1970: 0), retrievedDate: Date(timeIntervalSince1970: 0), sourceURLs: [], retrievalNotes: []),
            programs: [major, minor],
            courses: [
                Course(id: "CIS221", code: "CIS 221", title: "Programming", credits: 3, availability: nil, prerequisites: []),
                Course(id: "ROB200", code: "ROB 200", title: "Intro Robotics", credits: 3, availability: nil, prerequisites: [])
            ],
            apCreditRules: []
        )

        let pathway = Pathway(id: "p1", name: "Test", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["CIS221", "ROB200"])
        ])
        let progress = try ProgressCalculator(catalog: catalog).progress(
            programID: "cis-bba",
            pathway: pathway,
            transferCredits: [],
            additionalPrograms: [minor]
        )

        let names = progress.categories.map { $0.name }
        #expect(names.contains("Core"))
        #expect(names.contains { $0.hasPrefix("Minor (Robotics Minor)") })
    }
}

@Suite("Schedule generator best-effort prereq fallback")
struct ScheduleGeneratorBestEffortTests {
    @Test("best-effort places course when prerequisite is impossible")
    func bestEffortPlacesCourseEvenWhenPrereqUnmet() throws {
        let catalog = Self.catalogWithImpossiblePrereq()
        let generator = ScheduleGenerator(catalog: catalog)

        let pathways = try generator.generatePathways(
            for: "cs-bs",
            workload: .standard,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        )

        let scheduled = pathways.first?.semesters.flatMap(\.courseIDs) ?? []
        #expect(scheduled.contains("cs-240"))
    }

    @Test("best-effort fallback still respects workload credit cap")
    func bestEffortFallbackStillRespectsWorkloadCreditCap() throws {
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS340", code: "CS 340", title: "Databases", credits: 7, availability: nil, prerequisites: ["MISSING"]),
                Course(id: "CS240", code: "CS 240", title: "Data Structures", credits: 7, availability: nil, prerequisites: ["MISSING"]),
                Course(id: "CS140", code: "CS 140", title: "Intro", credits: 7, availability: nil, prerequisites: ["MISSING"])
            ],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(id: "core", name: "Core", requiredCredits: 21, courseOptions: [["CS340"], ["CS240"], ["CS140"]])
                ]
            )
        )

        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "cs-bs",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        #expect(pathway.semesters.map(\.courseIDs) == [["CS140"], ["CS240"], ["CS340"]])
        for semester in pathway.semesters {
            let credits = semester.courseIDs.reduce(0) { total, courseID in
                total + (catalog.coursesByID[courseID]?.credits ?? 0)
            }
            #expect(credits <= WorkloadPreference.light.creditRange.upperBound)
        }
    }

    @Test("strict prereq mode still throws")
    func strictPrereqsStillThrows() {
        let catalog = Self.catalogWithImpossiblePrereq()
        let generator = ScheduleGenerator(catalog: catalog, strictPrereqs: true)

        #expect(throws: PlannerError.self) {
            try generator.generatePathways(
                for: "cs-bs",
                workload: .standard,
                transferCredits: [],
                starting: SemesterIdentity(year: 2026, term: .fall)
            )
        }
    }

    private static func catalogWithImpossiblePrereq() -> Catalog {
        let cs240 = Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: ["cs-159"])
        return Catalog.fixture(
            courses: [cs240],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(id: "core", name: "Core", requiredCredits: 3, courseOptions: [["cs-240"]])
                ]
            )
        )
    }
}

@Suite("Schedule generator parsed prereq expressions")
struct ScheduleGeneratorParsedPrereqTests {
    @Test("unknown-only catalog prose does not force best-effort dump")
    func unknownOnlyCatalogProseDoesNotForceBestEffortDump() throws {
        var cob202 = Course(id: "COB202", code: "COB 202", title: "Interpersonal Skills", credits: 7, availability: [.fall, .spring], prerequisites: [])
        cob202.rawPrerequisiteText = "Prerequisite: Open only to sophomore business majors."
        var cob241 = Course(id: "COB241", code: "COB 241", title: "Financial Accounting", credits: 7, availability: [.fall, .spring], prerequisites: [])
        cob241.rawPrerequisiteText = "Prerequisite: COB 202."
        let catalog = Catalog.fixture(
            courses: [cob241, cob202],
            program: Program.fixture(
                id: "cis-bba",
                title: "Computer Information Systems, B.B.A.",
                requirements: [
                    RequirementCategory(id: "core", name: "Core", requiredCredits: 14, courseOptions: [["COB241"], ["COB202"]])
                ]
            )
        )

        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "cis-bba",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        #expect(pathway.semesters.map(\.courseIDs) == [["COB202"], ["COB241"]])
    }

    @Test("one-of-following prereq only needs one completed option")
    func oneOfFollowingPrereqOnlyNeedsOneCompletedOption() throws {
        let catalog = Self.catalogWithOneOfFollowingPrereq()
        let generator = ScheduleGenerator(catalog: catalog, strictPrereqs: true)

        let pathway = try #require(try generator.generatePathways(
            for: "cs-bs",
            workload: .standard,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        let flattened = pathway.semesters.flatMap(\.courseIDs)
        #expect(flattened.contains("cs-149"))
        #expect(flattened.contains("cs-240"))
        let cs149Semester = try #require(pathway.semesters.first { $0.courseIDs.contains("cs-149") }?.id)
        let cs240Semester = try #require(pathway.semesters.first { $0.courseIDs.contains("cs-240") }?.id)
        #expect(cs149Semester < cs240Semester)
    }

    private static func catalogWithOneOfFollowingPrereq() -> Catalog {
        let cs149 = Course(id: "cs-149", code: "CS 149", title: "Intro", credits: 3, availability: [.fall, .spring], prerequisites: [])
        let cs159 = Course(id: "cs-159", code: "CS 159", title: "Advanced", credits: 3, availability: [.fall, .spring], prerequisites: [])
        var cs240 = Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: [.fall, .spring], prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: a grade of C or better in one of the following: CS 149, CS 159."
        return Catalog.fixture(
            courses: [cs149, cs159, cs240],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(id: "core", name: "Core", requiredCredits: 6, courseOptions: [["cs-240"], ["cs-149"]])
                ]
            )
        )
    }

    @Test("curated overlay any-prereq rule wins during schedule placement")
    func curatedOverlayAnyPrereqWinsDuringSchedulePlacement() throws {
        let cs149 = Course(id: "cs-149", code: "CS 149", title: "Intro", credits: 3, availability: [.fall, .spring], prerequisites: [])
        let cs159 = Course(id: "cs-159", code: "CS 159", title: "Advanced", credits: 3, availability: [.fall, .spring], prerequisites: [])
        var cs240 = Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: [.fall, .spring], prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: CS 159."
        let overlay = PrereqRuleOverlay(schemaVersion: 1, rules: [
            PrereqRule(
                courseID: "cs-240",
                prerequisiteExpr: .any([.course("cs-149"), .course("cs-159")]),
                corequisiteExpr: .empty,
                confidence: .curated,
                basis: .explicit,
                sourceURL: URL(string: "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=123&print")!,
                sourceText: "Prerequisite: CS 149 or CS 159.",
                notes: "Curated OR group should replace stale parser fallback."
            )
        ])
        let catalog = Catalog.fixture(
            courses: [cs149, cs159, cs240],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(id: "core", name: "Core", requiredCredits: 6, courseOptions: [["cs-149"], ["cs-240"]])
                ]
            ),
            prereqRuleOverlay: overlay
        )

        let pathway = try #require(try ScheduleGenerator(catalog: catalog, strictPrereqs: true).generatePathways(
            for: "cs-bs",
            workload: .standard,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        let cs149Semester = try #require(pathway.semesters.first { $0.courseIDs.contains("cs-149") }?.id)
        let cs240Semester = try #require(pathway.semesters.first { $0.courseIDs.contains("cs-240") }?.id)
        #expect(cs149Semester < cs240Semester)
        #expect(!pathway.semesters.flatMap(\.courseIDs).contains("cs-159"))
    }
}

@Suite("Schedule generator course level ramp")
struct ScheduleGeneratorLevelRampTests {
    @Test("scheduler prefers lower-level courses in earlier semesters")
    func schedulerPrefersLowerLevelCoursesEarlier() throws {
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS440", code: "CS 440", title: "Advanced Systems", credits: 7, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CS340", code: "CS 340", title: "Databases", credits: 7, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CS240", code: "CS 240", title: "Data Structures", credits: 7, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CS140", code: "CS 140", title: "Intro Computing", credits: 7, availability: [.fall, .spring], prerequisites: [])
            ],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(
                        id: "core",
                        name: "Core",
                        requiredCredits: 28,
                        courseOptions: [["CS440"], ["CS340"], ["CS240"], ["CS140"]]
                    )
                ]
            )
        )

        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "cs-bs",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        #expect(pathway.semesters.map(\.courseIDs) == [["CS140"], ["CS240"], ["CS340"], ["CS440"]])
    }

    @Test("availability can still force an upper-level course into an early semester")
    func availabilityCanForceUpperLevelEarly() throws {
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS340", code: "CS 340", title: "Databases", credits: 7, availability: [.fall], prerequisites: []),
                Course(id: "CS140", code: "CS 140", title: "Intro Computing", credits: 7, availability: [.spring], prerequisites: [])
            ],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(id: "core", name: "Core", requiredCredits: 14, courseOptions: [["CS340"], ["CS140"]])
                ]
            )
        )

        let pathway = try #require(try ScheduleGenerator(catalog: catalog, strictPrereqs: true).generatePathways(
            for: "cs-bs",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        #expect(pathway.semesters.map(\.courseIDs) == [["CS340"], ["CS140"]])
    }

    @Test("prerequisites still control high-level course placement")
    func prerequisitesStillControlHighLevelPlacement() throws {
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS440", code: "CS 440", title: "Advanced Systems", credits: 7, availability: [.fall, .spring], prerequisites: ["CS140"]),
                Course(id: "CS140", code: "CS 140", title: "Intro Computing", credits: 7, availability: [.fall, .spring], prerequisites: [])
            ],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(id: "core", name: "Core", requiredCredits: 14, courseOptions: [["CS440"], ["CS140"]])
                ]
            )
        )

        let pathway = try #require(try ScheduleGenerator(catalog: catalog, strictPrereqs: true).generatePathways(
            for: "cs-bs",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        #expect(pathway.semesters.map(\.courseIDs) == [["CS140"], ["CS440"]])
    }

    @Test("placeholder level uses median level of dropdown alternates")
    func placeholderLevelUsesMedianAlternateLevel() throws {
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS440", code: "CS 440", title: "Advanced Systems", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CS441", code: "CS 441", title: "Advanced Security", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "WRTC103", code: "WRTC 103", title: "Writing", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "HIST150", code: "HIST 150", title: "History", credits: 3, availability: [.fall, .spring], prerequisites: [])
            ],
            program: Program.fixture(
                id: "any-bs",
                title: "Any Major, B.S.",
                requirements: [
                    RequirementCategory(id: "upper-elective", name: "Upper Elective", requiredCredits: 7, courseOptions: [["CS440", "CS441", "MISSING400"]]),
                    RequirementCategory(id: "lower-gened", name: "Lower Gen Ed", requiredCredits: 7, courseOptions: [["WRTC103", "HIST150", "MISSING100"]])
                ]
            )
        )

        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "any-bs",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        let firstPlaceholderID = try #require(pathway.semesters.first?.courseIDs.first)
        let firstSpec = try #require(pathway.placeholders[firstPlaceholderID])
        #expect(firstSpec.categoryName == "Lower Gen Ed")
    }

    @Test("gen ed placeholders follow JMU recommended timing when otherwise equal")
    func genEdPlaceholdersFollowRecommendedTiming() throws {
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CIS101", code: "CIS 101", title: "Business Technology", credits: 7, availability: [.fall, .spring], prerequisites: []),
                Course(id: "HIST101", code: "HIST 101", title: "American Experience", credits: 7, availability: [.fall, .spring], prerequisites: []),
                Course(id: "HIST102", code: "HIST 102", title: "American Experience II", credits: 7, availability: [.fall, .spring], prerequisites: []),
                Course(id: "WRTC103", code: "WRTC 103", title: "Critical Reading and Writing", credits: 7, availability: [.fall, .spring], prerequisites: []),
                Course(id: "WRTC104", code: "WRTC 104", title: "Writing Workshop", credits: 7, availability: [.fall, .spring], prerequisites: []),
                Course(id: "KIN100", code: "KIN 100", title: "Lifetime Fitness", credits: 7, availability: [.fall, .spring], prerequisites: []),
                Course(id: "HTH100", code: "HTH 100", title: "Personal Wellness", credits: 7, availability: [.fall, .spring], prerequisites: [])
            ],
            program: Program.fixture(
                id: "cis-bba",
                title: "Computer Information Systems, B.B.A.",
                requirements: [
                    RequirementCategory(id: "major", name: "Major Core", requiredCredits: 7, courseOptions: [["CIS101"]]),
                    RequirementCategory(id: "c4ae", name: "The American Experience [C4AE]", requiredCredits: 7, courseOptions: [["HIST101", "HIST102"]]),
                    RequirementCategory(id: "c1w", name: "Writing [C1W]", requiredCredits: 7, courseOptions: [["WRTC103", "WRTC104"]]),
                    RequirementCategory(id: "c5w", name: "Wellness Domain [C5W]", requiredCredits: 7, courseOptions: [["KIN100", "HTH100"]])
                ]
            )
        )

        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "cis-bba",
            workload: .light,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        let scheduledCategories = pathway.semesters.compactMap { semester -> String? in
            guard let courseID = semester.courseIDs.first else { return nil }
            return pathway.placeholders[courseID]?.categoryName ?? courseID
        }
        let wellnessIndex = try #require(scheduledCategories.firstIndex(of: "Wellness Domain [C5W]"))
        let americanExperienceIndex = try #require(scheduledCategories.firstIndex(of: "The American Experience [C4AE]"))

        #expect(scheduledCategories.first == "Writing [C1W]")
        #expect(wellnessIndex < americanExperienceIndex)
        #expect(ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: []).isEmpty)
    }
}
