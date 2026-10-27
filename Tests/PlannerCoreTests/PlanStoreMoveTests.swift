import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Plan store positional moves")
@MainActor
struct PlanStoreMoveTests {
    static let fall26 = SemesterIdentity(year: 2026, term: .fall)
    static let spring27 = SemesterIdentity(year: 2027, term: .spring)
    static let fall27 = SemesterIdentity(year: 2027, term: .fall)

    private func makeStore() -> PlanStore {
        let store = PlanStore.temporary()
        store.catalog = Catalog.fixture(
            courses: [
                Course(id: "CS149", code: "CS 149", title: "Intro Programming", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "ART200", code: "ART 200", title: "Studio Art", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "WRTC103", code: "WRTC 103", title: "Critical Reading and Writing", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "MATH231", code: "MATH 231", title: "Calculus I", credits: 4, availability: [.fall, .spring], prerequisites: []),
                Course(id: "PHIL101", code: "PHIL 101", title: "Intro Philosophy", credits: 3, availability: [.fall, .spring], prerequisites: [])
            ],
            program: Program.fixture(id: "p", title: "Program", requirements: [])
        )
        store.plan.pathways = [
            Pathway(id: "path", name: "Path", semesters: [
                SemesterPlan(id: Self.fall26, courseIDs: ["CS149", "ART200", "WRTC103"]),
                SemesterPlan(id: Self.spring27, courseIDs: ["MATH231"])
            ])
        ]
        store.plan.activePathwayID = "path"
        return store
    }

    private func ids(_ store: PlanStore, _ semester: SemesterIdentity) -> [String] {
        store.plan.pathways[0].semesters.first { $0.id == semester }?.courseIDs ?? []
    }

    @Test("reorders within a semester")
    func reorderWithinSemester() {
        let store = makeStore()
        store.moveCourse("WRTC103", to: Self.fall26, at: 0)
        #expect(ids(store, Self.fall26) == ["WRTC103", "CS149", "ART200"])
    }

    @Test("inserts at a position in another semester")
    func insertIntoOtherSemester() {
        let store = makeStore()
        store.moveCourse("CS149", to: Self.spring27, at: 0)
        #expect(ids(store, Self.spring27) == ["CS149", "MATH231"])
        #expect(ids(store, Self.fall26) == ["ART200", "WRTC103"])
    }

    @Test("clamps an index past the end")
    func clampsPastEnd() {
        let store = makeStore()
        store.moveCourse("CS149", to: Self.spring27, at: 99)
        #expect(ids(store, Self.spring27) == ["MATH231", "CS149"])
    }

    @Test("nil index appends, matching the old behavior")
    func nilAppends() {
        let store = makeStore()
        store.moveCourse("ART200", to: Self.spring27)
        #expect(ids(store, Self.spring27) == ["MATH231", "ART200"])
    }

    @Test("dropping onto its own slot leaves the pathway unchanged")
    func ownSlotIsNoOp() {
        let store = makeStore()
        let before = store.plan.pathways[0]
        store.moveCourse("ART200", to: Self.fall26, at: 1)
        #expect(store.plan.pathways[0] == before)
    }

    @Test("creates a missing semester in order")
    func createsMissingSemester() {
        let store = makeStore()
        store.moveCourse("CS149", to: Self.fall27, at: 0)
        #expect(store.plan.pathways[0].semesters.map(\.id) == [Self.fall26, Self.spring27, Self.fall27])
        #expect(ids(store, Self.fall27) == ["CS149"])
    }

    @Test("a moved course chosen for a placeholder restores it in its new semester")
    func movedResolvedPlaceholderRestoresInNewSemester() {
        let store = makeStore()
        let placeholderID = PathwayPlaceholder.id(categoryID: ScheduleGenerator.openElectiveCategoryID, optionIndex: 0)
        store.plan.pathways[0].semesters[0].courseIDs.append(placeholderID)
        store.plan.pathways[0].placeholders[placeholderID] = PlaceholderSpec(
            categoryID: ScheduleGenerator.openElectiveCategoryID,
            categoryName: "Open Elective",
            alternates: [],
            credits: 3
        )

        store.resolvePlaceholder(placeholderID, with: "PHIL101")
        store.moveCourse("PHIL101", to: Self.spring27, at: 0)
        store.removeCourse("PHIL101")

        #expect(ids(store, Self.spring27) == [placeholderID, "MATH231"])
        #expect(!ids(store, Self.fall26).contains(placeholderID))
    }
}
