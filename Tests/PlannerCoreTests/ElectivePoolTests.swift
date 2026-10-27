import Foundation
import Testing
@testable import PlannerCore

@Suite("Elective pools")
struct ElectivePoolTests {
    static let pool = ElectivePool.token(subject: "MATH", minimumNumber: 310)

    static func course(_ code: String, credits: Int = 3) -> Course {
        Course(id: code.replacingOccurrences(of: " ", with: ""), code: code, title: code, credits: credits, availability: [.fall, .spring], prerequisites: [])
    }

    static func catalog(programs: [Program], extraCourses: [Course] = []) -> Catalog {
        let courses = ["MATH 300", "MATH 310", "MATH 410", "MATH 411", "MATH 421", "MATH 431", "MATH 450", "MATH 499", "MATH 500", "MATH 515", "STAT 400"].map { course($0) }
        return Catalog(
            source: CatalogSource(catalogYear: "Fixture", issueDate: Date(timeIntervalSince1970: 0), retrievedDate: Date(timeIntervalSince1970: 0), sourceURLs: [], retrievalNotes: []),
            programs: programs,
            courses: courses + extraCourses,
            apCreditRules: []
        )
    }

    static func minor(_ id: String, requiring courseIDs: [String]) -> Program {
        Program(
            id: id, title: id, degreeType: nil, kind: .minor, college: "X", department: "X", catalogPage: nil, totalCredits: nil,
            requirements: [RequirementCategory(id: "\(id)-core", name: "Required", requiredCredits: 3 * courseIDs.count, courseOptions: courseIDs.map { [$0] })],
            verificationStatus: .partial, requirementDataComplete: true, sourceNote: "Fixture"
        )
    }

    @Test("pool tokens resolve to MATH 310-499 courses the program doesn't already require")
    func resolvesPool() throws {
        let major = Program.fixture(id: "m", title: "Math", requirements: [
            RequirementCategory(id: "core", name: "Core Courses", requiredCredits: 3, courseOptions: [["MATH410"]]),
            // The parser already records the pool slots alongside the tokens.
            RequirementCategory(id: "opt", name: "Option 1", requiredCredits: 9, courseOptions: [["MATH411", "MATH431"], [Self.pool], [Self.pool]], electivePoolSlots: [1, 2])
        ])
        let resolved = Self.catalog(programs: [major]).resolvingElectivePools()
        let option = try #require(resolved.programsByID["m"]?.requirements.first { $0.id == "opt" })
        let expectedPool = ["MATH310", "MATH411", "MATH421", "MATH431", "MATH450", "MATH499"]
        #expect(option.courseOptions == [["MATH411", "MATH431"], expectedPool, expectedPool])
        #expect(option.electivePoolSlots == [1, 2])
        // Resolving again is a no-op.
        #expect(resolved.resolvingElectivePools().programsByID["m"] == resolved.programsByID["m"])
    }

    @Test("a course one option requires isn't required program-wide, so pools keep it")
    func optionCoursesAreNotRequiredOutright() throws {
        let option1 = RequirementOption(id: "option-1", label: "Option 1", parts: [
            RequirementCategory(id: "required-courses", name: "Required courses", requiredCredits: 3, courseOptions: [["MATH411"]], selection: .allRequired)
        ])
        let option2 = RequirementOption(id: "option-2", label: "Option 2", parts: [
            RequirementCategory(id: "required-courses", name: "Required courses", requiredCredits: 3, courseOptions: [["MATH421"]], selection: .allRequired)
        ])
        // The parser's legacy fields describe option 1: MATH 411 as a one-course slot.
        let options = RequirementCategory(
            id: "choose-one-of-the-following-options", name: "Options", requiredCredits: 3,
            courseOptions: [["MATH411"]], selection: .allRequired, choices: [["MATH411"]], options: [option1, option2]
        )
        var major = Program.fixture(id: "m", title: "Math", requirements: [
            RequirementCategory(id: "core", name: "Core Courses", requiredCredits: 3, courseOptions: [["MATH410"]]),
            options,
            RequirementCategory(id: "electives", name: "Electives", requiredCredits: 3, courseOptions: [[Self.pool]])
        ], concentrations: [
            Concentration(id: "c", name: "Track", requirements: [
                options,
                RequirementCategory(id: "track-electives", name: "Track Electives", requiredCredits: 3, courseOptions: [[Self.pool]])
            ], verificationStatus: .partial)
        ])
        major.concentrationSelectionRequired = true
        let resolved = try #require(Self.catalog(programs: [major]).resolvingElectivePools().programsByID["m"])
        let electives = try #require(resolved.requirements.first { $0.id == "electives" })
        #expect(electives.courseOptions == [["MATH310", "MATH411", "MATH421", "MATH431", "MATH450", "MATH499"]])
        let trackElectives = try #require(resolved.concentrations.first?.requirements.first { $0.id == "track-electives" })
        #expect(trackElectives.courseOptions.first?.contains("MATH411") == true)
        #expect(trackElectives.courseOptions.first?.contains("MATH410") == false)
    }

    @Test("an option's required-courses part takes its credits from the catalog's courses")
    func optionPartCreditsComeFromCourses() throws {
        // The page's estimate (6) for CHEM 241 & 241L, a 3- and a 1-credit
        // course; a slot of alternatives counts its largest course.
        let option1 = RequirementOption(id: "option-1", label: "Option 1", parts: [
            RequirementCategory(id: "required-courses", name: "Required courses", requiredCredits: 6,
                                courseOptions: [["CHEM241"], ["CHEM241L"]], selection: .allRequired)
        ])
        let option2 = RequirementOption(id: "option-2", label: "Option 2", parts: [
            RequirementCategory(id: "required-courses", name: "Required courses", requiredCredits: 12,
                                courseOptions: [["PHYS140", "PHYS240"], ["CHEM131"]], selection: .allRequired),
            RequirementCategory(id: "choose", name: "Choose one", requiredCredits: 3,
                                courseOptions: [["CHEM241", "PHYS240"]], selection: .chooseCourses(1))
        ])
        let option3 = RequirementOption(id: "option-3", label: "Option 3", parts: [
            RequirementCategory(id: "required-courses", name: "Required courses", requiredCredits: 5,
                                courseOptions: [["CHEM131"], ["CHEM999"]], selection: .allRequired)
        ])
        let options = RequirementCategory(
            id: "choose-one-of-the-following-options", name: "Options", requiredCredits: 4,
            courseOptions: [["CHEM241"], ["CHEM241L"]], selection: .allRequired, options: [option1, option2, option3]
        )
        let minor = Program(
            id: "chem", title: "Chem", degreeType: nil, kind: .minor, college: "X", department: "X", catalogPage: nil, totalCredits: nil,
            requirements: [options], verificationStatus: .partial, requirementDataComplete: true, sourceNote: "Fixture"
        )
        let extra = [Self.course("CHEM 241"), Self.course("CHEM 241L", credits: 1), Self.course("PHYS 140"),
                     Self.course("PHYS 240", credits: 4), Self.course("CHEM 131")]
        let resolved = try #require(Self.catalog(programs: [minor], extraCourses: extra).resolvingElectivePools().programsByID["chem"])
        let parts = try #require(resolved.requirements.first?.options).map(\.parts)
        #expect(parts[0][0].requiredCredits == 4)
        #expect(parts[1][0].requiredCredits == 7)
        // Only required courses are summed; a choice keeps its own credits.
        #expect(parts[1][1].requiredCredits == 3)
        // CHEM 999 isn't in the catalog: the page's estimate stays.
        #expect(parts[2][0].requiredCredits == 5)
        #expect(resolved.requirements.first?.requiredCredits == 4)
    }

    @Test("a concentration's pool also excludes the program's own required courses")
    func resolvesConcentrationPool() throws {
        var major = Program.fixture(id: "m", title: "Math", requirements: [
            RequirementCategory(id: "core", name: "Core Courses", requiredCredits: 3, courseOptions: [["MATH410"]])
        ], concentrations: [
            Concentration(id: "c", name: "Track", requirements: [
                RequirementCategory(id: "t", name: "Track Core", requiredCredits: 3, courseOptions: [["MATH450"]]),
                RequirementCategory(id: "opt", name: "Option 1", requiredCredits: 3, courseOptions: [[Self.pool]])
            ], verificationStatus: .partial)
        ])
        major.concentrationSelectionRequired = true
        let resolved = Self.catalog(programs: [major]).resolvingElectivePools()
        let option = try #require(resolved.programsByID["m"]?.concentrations.first?.requirements.first { $0.id == "opt" })
        #expect(option.courseOptions == [["MATH310", "MATH411", "MATH421", "MATH431", "MATH499"]])
    }

    @Test("one course can't fill two identical slots when scheduling")
    func schedulerFillsSlotsDistinctly() throws {
        let major = Program.fixture(id: "m", title: "Math", requirements: [
            RequirementCategory(id: "opt", name: "Option 1", requiredCredits: 6, courseOptions: [[Self.pool], [Self.pool]])
        ])
        let catalog = Self.catalog(programs: [major]).resolvingElectivePools()
        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "m", workload: .standard,
            transferCredits: [TransferCredit(sourceDescription: "MATH 450 transfer", courseIDs: ["MATH450"], credits: 3)]
        ).first)
        let slots = pathway.placeholders.filter { $0.value.categoryID == "opt" }
        #expect(slots.count == 1)
    }

    @Test("one course can't fill two identical slots in progress")
    func progressFillsSlotsDistinctly() throws {
        let major = Program.fixture(id: "m", title: "Math", requirements: [
            RequirementCategory(id: "two", name: "Choose two of the following:", requiredCredits: 6, courseOptions: [["MATH411", "MATH431", "MATH450"], ["MATH411", "MATH431", "MATH450"]])
        ])
        let catalog = Self.catalog(programs: [major])
        let pathway = Pathway(id: "p", name: "P", semesters: [SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["MATH411"])])
        let progress = try ProgressCalculator(catalog: catalog).progress(programID: "m", pathway: pathway, transferCredits: [])
        #expect(progress.categories.first { $0.id == "two" }?.completedCredits == 3)
    }

    @Test("a minor's upper-level MATH course fills a major elective slot instead of adding to it")
    func minorFillsMajorPoolSlot() throws {
        // 60 declared credits of core (one 60-credit placeholder course keeps
        // the fixture small) puts the major over the Open Elective threshold.
        let major = Program.fixture(id: "m", title: "Math", requirements: [
            RequirementCategory(id: "core", name: "Core Courses", requiredCredits: 60, courseOptions: [["BIG100"]]),
            RequirementCategory(id: "opt", name: "Option 1", requiredCredits: 6, courseOptions: [[Self.pool], [Self.pool]])
        ])
        let minor = Self.minor("stats-minor", requiring: ["MATH421"])
        let catalog = Self.catalog(programs: [major, minor], extraCourses: [Self.course("BIG 100", credits: 60)]).resolvingElectivePools()
        let generator = ScheduleGenerator(catalog: catalog)
        let resolvedMinor = try #require(catalog.programsByID["stats-minor"])

        let pathway = try #require(try generator.generatePathways(
            for: "m", workload: .heavy, transferCredits: [], additionalPrograms: [resolvedMinor]
        ).first)
        let scheduled = pathway.semesters.flatMap(\.courseIDs)
        #expect(scheduled.filter { $0 == "MATH421" }.count == 1)
        #expect(pathway.placeholders.filter { $0.value.categoryID == "opt" }.count == 1)

        // MATH 421 counts for both programs, so it doesn't shrink Open Electives.
        let openElectives = pathway.placeholders.values
            .filter { $0.categoryID == ScheduleGenerator.openElectiveCategoryID }
            .reduce(0) { $0 + $1.credits }
        #expect(openElectives == 120 - 66)
        #expect(generator.openElectiveGap(for: try #require(catalog.programsByID["m"]), additionalPrograms: [resolvedMinor]) == 120 - 66)

        let progress = try ProgressCalculator(catalog: catalog).progress(
            programID: "m", pathway: pathway, transferCredits: [], additionalPrograms: [resolvedMinor]
        )
        #expect(progress.categories.first { $0.id == "opt" }?.completedCredits == 3)
        #expect(progress.categories.first { $0.id == "stats-minor::stats-minor-core" }?.completedCredits == 3)
    }

    @Test("anchored pool slots and a minor reserve distinct three-credit slots")
    func regenerationPreservesPoolSlotsWithoutCountingMinorTwice() throws {
        let major = Program.fixture(id: "m", title: "Math", requirements: [
            RequirementCategory(id: "opt", name: "Option 1", requiredCredits: 9,
                                courseOptions: [[Self.pool], [Self.pool], [Self.pool]])
        ])
        let minor = Self.minor("minor", requiring: ["MATH421"])
        var catalog = Self.catalog(programs: [major, minor]).resolvingElectivePools()
        // A four-credit alternate must not inflate a three-credit pool slot.
        let alternateIndex = try #require(catalog.courses.firstIndex { $0.id == "MATH499" })
        catalog.courses[alternateIndex].credits = 4
        let category = try #require(catalog.programsByID["m"]?.requirements.first)
        let slot = PathwayPlaceholder.id(categoryID: "opt", optionIndex: 2)
        let anchor = SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: [slot])
        let spec = PlaceholderSpec(categoryID: "opt", categoryName: "Option 1",
                                   alternates: category.courseOptions[2], credits: 3)
        let source = Pathway(id: "crafted", name: "Crafted", semesters: [anchor], placeholders: [slot: spec])
        let result = try ScheduleGenerator(catalog: catalog).regeneratePathway(
            from: source, through: anchor.id, for: "m", strategy: .balanced,
            workload: .standard, transferCredits: [], additionalPrograms: [minor])
        #expect(result.semesters.first == anchor)
        #expect(result.placeholders[slot] == spec)
        let suffix = result.semesters.dropFirst().flatMap(\.courseIDs)
        #expect(suffix.filter { $0 == "MATH421" }.count == 1)
        let newSlots = suffix.compactMap { result.placeholders[$0] }.filter { $0.categoryID == "opt" }
        #expect(newSlots.count == 1)
        #expect(newSlots.first?.credits == 3)
    }

}
