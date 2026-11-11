import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite struct HonorsMinorTests {
    private func requirement() throws -> RequirementCategory {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("_live_honors.html")
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(
            try String(contentsOf: file, encoding: .utf8), kind: .minor,
            sourceURL: URL(string: "https://catalog.jmu.edu/programs/honors-interdisciplinary-studies-minor/")!
        )
        return try #require(parsed.requirements.first { $0.name == "Honors Courses" })
    }

    @Test func proseCourseworkIsAnApprovalObligation() throws {
        let category = try requirement()
        #expect(category.requiredCredits == 12)
        #expect(category.approval == .honors)
        #expect(category.courseOptions.isEmpty)
        #expect(category.choices.isEmpty)
        let decoded = try JSONDecoder().decode(RequirementCategory.self, from: JSONEncoder().encode(category))
        #expect(decoded.approval == .honors)
    }

    @Test func allStrategiesKeepTwelvePendingHoursAndZeroCompletion() throws {
        let category = try requirement()
        let major = Program.fixture(id: "psych", title: "Psychology", requirements: [
            RequirementCategory(id: "core", name: "Core", requiredCredits: 3, courseOptions: [["PSYC101"]])
        ])
        var minor = Program.fixture(id: HonorsCoursework.programID, title: "Honors", requirements: [category])
        minor.kind = .minor
        let catalog = Catalog.fixture(courses: [
            Course(id: "PSYC101", code: "PSYC 101", title: "Psychology", credits: 3, availability: nil, prerequisites: []),
            Course(id: "HON200", code: "HON 200", title: "Honors seminar", credits: 3, availability: nil, prerequisites: [])
        ], program: major)
        let generator = ScheduleGenerator(catalog: catalog)
        let earned = [TransferCredit(sourceDescription: "Seminar without section evidence", courseIDs: ["HON200"], credits: 3)]
        let paths = try generator.generatePathways(for: major.id, workload: .standard,
                                                  transferCredits: earned, additionalPrograms: [minor])
        #expect(paths.count == 3)
        for path in paths {
            let ids = Set(path.semesters.flatMap(\.courseIDs))
            let pending = path.placeholders.filter { $0.value.approval != nil && ids.contains($0.key) }
            #expect(pending.count == 4)
            #expect(pending.values.reduce(0) { $0 + $1.credits } == 12)
            for spec in pending.values {
                #expect(PlaceholderCourseDomain.eligibleCourseIDs(for: spec, catalog: catalog).isEmpty)
            }
            let progress = try ProgressCalculator(catalog: catalog).progress(
                programID: major.id, pathway: path, transferCredits: earned, additionalPrograms: [minor])
            let row = try #require(progress.categories.first { $0.id == "\(minor.id)::\(category.id)" })
            #expect(row.requiredCredits == 12)
            #expect(row.completedCredits == 0)
            let decoded = try JSONDecoder().decode(Pathway.self, from: JSONEncoder().encode(path))
            #expect(decoded.placeholders == path.placeholders)
            let cutoff = try #require(path.semesters.first?.id)
            let regenerated = try generator.regeneratePathway(
                from: path, through: cutoff, for: major.id, strategy: .balanced,
                workload: .standard, transferCredits: earned, additionalPrograms: [minor])
            let regeneratedIDs = Set(regenerated.semesters.flatMap(\.courseIDs))
            let reserved = regenerated.placeholders.filter { $0.value.approval != nil && regeneratedIDs.contains($0.key) }
            #expect(reserved.values.reduce(0) { $0 + $1.credits } == 12)
        }
    }

    @Test func cachedHonorsRequirementGetsApprovalWithoutRefresh() throws {
        var category = try requirement()
        category.approval = nil
        var minor = Program.fixture(id: HonorsCoursework.programID, title: "Honors", requirements: [category])
        minor.kind = .minor
        let updated = HonorsCoursework.applying(to: Catalog.fixture(courses: [], program: minor))
        #expect(updated.programs[0].requirements[0].approval == .honors)
    }

    @MainActor @Test func ordinaryCourseCannotResolveApprovalSlot() {
        let store = PlanStore.temporary()
        let slot = PathwayPlaceholder.id(categoryID: "honors", optionIndex: 0)
        let spec = PlaceholderSpec(categoryID: "honors", categoryName: "Honors Courses", alternates: [], credits: 3.0, approval: .honors)
        store.plan.pathways = [Pathway(id: "p", name: "Plan", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: [slot])
        ], placeholders: [slot: spec])]
        let before = store.plan

        store.resolvePlaceholder(slot, with: "PSYC101")

        #expect(store.plan == before)
        #expect(store.errorMessage != nil)
    }

    @Test func approvalSlotsCannotSupplyPrerequisites() {
        let course = Course(id: "PSYC101", code: "PSYC 101", title: "Psychology", credits: 3, availability: nil, prerequisites: [])
        let catalog = Catalog.fixture(courses: [course], program: .fixture(id: "p", title: "P", requirements: []))
        let spec = PlaceholderSpec(categoryID: "honors", categoryName: "Honors Courses", alternates: [], credits: 3.0, approval: .honors)
        let cache = ConditionalSearchCache(catalog: catalog)
        #expect(!cache.offers(spec, course.id))
    }

    @Test func approvedListsAreMenusAndScholarPathsAreOptional() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("_live_honors.html")
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(
            try String(contentsOf: file, encoding: .utf8), kind: .minor,
            sourceURL: URL(string: "https://catalog.jmu.edu/programs/honors-interdisciplinary-studies-minor/")!
        )
        #expect(parsed.requirements.count == 4)
        #expect(parsed.requirements.reduce(0) { $0 + $1.requiredCredits } == 19)
        #expect(parsed.totalCredits == 19)
        #expect(!parsed.concentrationSelectionRequired)
        #expect(parsed.concentrations.count == 2)
        for path in parsed.concentrations {
            #expect(path.requirements.reduce(0) { $0 + $1.requiredCredits } == 6)
        }
        for name in ["Civic, Cultural or Global Engagement Course", "Research or Experiential Learning Course"] {
            let category = try #require(parsed.requirements.first { $0.name == name })
            #expect(category.requiredCredits == 3)
            #expect(category.courseOptions.count == 1)
            #expect(category.courseOptions.first!.count > 50)
            #expect(category.selection == .chooseCredits(3))
        }
        #expect(!parsed.requirements.contains { $0.name.contains("Non-Minor") })
    }
}
