import Foundation
import Testing
@testable import PlannerCore

@Suite("Semester credit load")
struct ConflictLoadTests {
    static let semesters = [
        SemesterIdentity(year: 2026, term: .fall),
        SemesterIdentity(year: 2027, term: .spring),
        SemesterIdentity(year: 2027, term: .fall),
        SemesterIdentity(year: 2028, term: .spring),
        SemesterIdentity(year: 2028, term: .fall)
    ]

    /// Thirty 1-credit courses, so any credit total is easy to build.
    static let catalog = Catalog.fixture(
        courses: (1...30).map {
            Course(id: "U\($0)", code: "UNIT \($0)", title: "Unit \($0)", credits: 1, availability: [.fall, .spring], prerequisites: [])
        },
        program: Program.fixture(id: "p", title: "P", requirements: [])
    )

    /// Builds semesters holding the given credit totals, drawing unique 1-credit courses.
    static func pathway(_ credits: [Int]) -> Pathway {
        var next = 1
        let plans = credits.enumerated().map { index, count -> SemesterPlan in
            let ids = (0..<count).map { offset in "U\(next + offset)" }
            next += count
            return SemesterPlan(id: semesters[index], courseIDs: ids)
        }
        return Pathway(id: "load", name: "Load", semesters: plans)
    }

    static func load(_ pathway: Pathway, _ workload: WorkloadPreference?, overrides: [ConflictOverride] = []) -> [ConflictWarning] {
        ConflictDetector(catalog: catalog)
            .warnings(for: pathway, overrides: overrides, workload: workload)
            .filter(\.isSemesterLevel)
    }

    @Test("heavy starts more than two credits over the preferred range", arguments: [
        (WorkloadPreference.light, 15, false), (WorkloadPreference.light, 16, true),
        (WorkloadPreference.standard, 18, false), (WorkloadPreference.standard, 19, true),
        (WorkloadPreference.heavy, 21, false), (WorkloadPreference.heavy, 22, true)
    ])
    func heavyThreshold(workload: WorkloadPreference, credits: Int, flagged: Bool) {
        // A second full-time semester keeps the first from being the final one.
        let warnings = Self.load(Self.pathway([credits, 12]), workload)
        #expect(warnings.contains { $0.kind == .heavyLoad && $0.semester == Self.semesters[0] } == flagged)
    }

    @Test("heavy text names the credits and the preferred range")
    func heavyText() throws {
        let warning = try #require(Self.load(Self.pathway([19, 12]), .standard).first)
        #expect(warning.summary == "Heavy load (19 cr)")
        #expect(warning.detail == "19 credits is above your Standard load (14–16).")
        #expect(warning.courseID == ConflictWarning.semesterSubjectID)
    }

    @Test("light flags under-12 semesters before the final one, including empty middles")
    func lightRule() {
        // 12, 11, empty, 9 (final non-empty), empty (trailing)
        let warnings = Self.load(Self.pathway([12, 11, 0, 9, 0]), .standard)
        let flagged = Set(warnings.filter { $0.kind == .lightLoad }.map(\.semester))
        #expect(flagged == [Self.semesters[1], Self.semesters[2]])
        let light = warnings.first { $0.semester == Self.semesters[1] }
        #expect(light?.summary == "Light load (11 cr)")
        #expect(light?.detail == "11 credits is below full-time (12).")
    }

    @Test("placeholder credits count toward the load")
    func placeholdersCount() {
        let placeholderID = PathwayPlaceholder.id(categoryID: "gened", optionIndex: 0)
        var pathway = Self.pathway([9, 12])
        pathway.semesters[0].courseIDs.append(placeholderID)
        pathway.placeholders[placeholderID] = PlaceholderSpec(categoryID: "gened", categoryName: "Gen Ed", alternates: [], credits: 3)
        #expect(Self.load(pathway, .standard).isEmpty)
    }

    @Test("no workload means no load warnings")
    func noWorkload() {
        #expect(Self.load(Self.pathway([25, 3, 12]), nil).isEmpty)
    }

    @Test("a kept load warning stays kept, even after the workload changes")
    func keptLoad() throws {
        let override = ConflictOverride(courseID: ConflictWarning.semesterSubjectID, semester: Self.semesters[0], kind: .heavyLoad)
        let standard = try #require(Self.load(Self.pathway([19, 12]), .standard, overrides: [override]).first)
        #expect(standard.isOverridden)
        let light = Self.load(Self.pathway([19, 12]), .light, overrides: [override])
        #expect(light.count == 1)
        #expect(light.first?.isOverridden == true)
    }

    @Test("load warnings are identified by their semester")
    func loadIdentity() {
        let fall = ConflictWarning(courseID: ConflictWarning.semesterSubjectID, semester: Self.semesters[0], kind: .heavyLoad, summary: "", detail: "", isOverridden: false)
        let spring = ConflictWarning(courseID: ConflictWarning.semesterSubjectID, semester: Self.semesters[1], kind: .heavyLoad, summary: "", detail: "", isOverridden: false)
        #expect(WarningDiff.added(before: [fall], after: [spring]).count == 1)
        #expect(WarningDiff.added(before: [fall], after: [fall]).isEmpty)
    }

    // MARK: Drag verdicts

    static let dragCatalog = Catalog.fixture(
        courses: (1...5).map { Course(id: "A\($0)", code: "A \($0)", title: "Four \($0)", credits: 4, availability: [.fall, .spring], prerequisites: []) }
            + (1...4).map { Course(id: "B\($0)", code: "B \($0)", title: "Three \($0)", credits: 3, availability: [.fall, .spring], prerequisites: []) },
        program: Program.fixture(id: "p", title: "P", requirements: [])
    )

    @Test("dropping into a semester that tips over the workload is a heavy-load caution")
    func heavyDrop() throws {
        let pathway = Pathway(id: "d", name: "D", semesters: [
            SemesterPlan(id: Self.semesters[0], courseIDs: ["A1", "A2", "A3", "A4"]),      // 16
            SemesterPlan(id: Self.semesters[1], courseIDs: ["B1", "B2", "B3", "B4", "A5"]) // 16
        ])
        let verdicts = DropVerdictCalculator(catalog: Self.dragCatalog)
            .verdicts(moving: "A5", in: pathway, overrides: [], workload: .standard)
        let fall = try #require(verdicts[Self.semesters[0]])
        #expect(fall.level == .caution)
        #expect(fall.headline == "Heavy load")
        #expect(fall.reason == "20 credits is above your Standard load (14–16).")
        #expect(fall.affectedCourseIDs.isEmpty)
    }

    @Test("moving the course that kept a semester full-time warns it will be light")
    func lightDrop() throws {
        let pathway = Pathway(id: "d", name: "D", semesters: [
            SemesterPlan(id: Self.semesters[0], courseIDs: ["A1", "A2", "B1", "B2"]), // 14
            SemesterPlan(id: Self.semesters[1], courseIDs: ["B3", "B4"])              // 6, final
        ])
        let verdicts = DropVerdictCalculator(catalog: Self.dragCatalog)
            .verdicts(moving: "A1", in: pathway, overrides: [], workload: .standard)
        let spring = try #require(verdicts[Self.semesters[1]])
        #expect(spring.level == .caution)
        #expect(spring.headline == "Leaves Fall 2026 light")
        #expect(spring.reason == "10 credits is below full-time (12).")
        #expect(spring.affectedCourseIDs.isEmpty)
    }
}
