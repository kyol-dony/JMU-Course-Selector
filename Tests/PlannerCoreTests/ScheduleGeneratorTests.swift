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
}
