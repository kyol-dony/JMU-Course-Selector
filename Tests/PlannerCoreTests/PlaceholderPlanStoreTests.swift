import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Plan store placeholder prerequisite analysis")
@MainActor
struct PlaceholderPlanStoreTests {
    typealias F = PlaceholderPrerequisiteFixtures
    static let fall27 = SemesterIdentity(year: 2027, term: .fall)

    private func makeStore() -> (PlanStore, UndoManager, ConditionalDependencyKey) {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let store = PlanStore.temporary()
        store.catalog = f.catalog
        var pathway = f.input.pathway
        pathway.semesters.append(SemesterPlan(id: Self.fall27, courseIDs: []))
        store.plan.pathways = [pathway]
        store.plan.activePathwayID = pathway.id
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        return (store, undo, f.requests[0].key)
    }

    private func notice(_ store: PlanStore) -> ConflictWarning? {
        store.warnings.first { $0.kind == .pendingPrerequisiteChoice }
    }

    private func d0Missing(_ store: PlanStore) -> Bool {
        store.warnings.contains { $0.courseID == "D0" && $0.kind == .missingPrerequisite }
    }

    @Test func pendingNoticeAndPickerDependencies() {
        let (store, _, key) = makeStore()
        #expect(notice(store)?.courseID == F.slotID(0))
        #expect(!d0Missing(store))
        #expect(store.placeholderPrerequisiteAnalysis?.statusByDependency[key] == .conditional)
        #expect(store.placeholderDependencies(for: F.slotID(0)) == ["A": Set([key])])
        #expect(store.placeholderDependencies(for: "__pl::other::0").isEmpty)
    }

    @Test func incompatibleChoiceKeepsPlacementsThenUndoRestoresTheNotice() {
        let (store, undo, _) = makeStore()
        let before = store.plan.pathways[0].semesters
        store.resolvePlaceholder(F.slotID(0), with: "B")
        #expect(store.plan.pathways[0].semesters.map(\.courseIDs) == [["B"], ["D0"], []])
        #expect(store.plan.pathways[0].semesters.map(\.id) == before.map(\.id))
        #expect(d0Missing(store))
        #expect(notice(store) == nil)
        #expect(store.placeholderDependencies(for: F.slotID(0)).isEmpty)
        undo.undo()
        #expect(notice(store) != nil)
        #expect(!d0Missing(store))
    }

    @Test func compatibleChoiceClearsTheNotice() {
        let (store, _, _) = makeStore()
        store.resolvePlaceholder(F.slotID(0), with: "A")
        #expect(notice(store) == nil)
        #expect(!d0Missing(store))
    }

    @Test func removingTheChosenCourseRestoresTheNotice() {
        let (store, _, _) = makeStore()
        store.resolvePlaceholder(F.slotID(0), with: "A")
        store.removeCourse("A")
        #expect(store.plan.pathways[0].semesters[0].courseIDs == [F.slotID(0)])
        #expect(notice(store) != nil)
    }

    @Test func catalogChangesRecalculate() {
        let (store, _, _) = makeStore()
        #expect(notice(store) != nil)
        var catalog = store.catalog!
        let index = catalog.courses.firstIndex { $0.id == "D0" }!
        catalog.courses[index].prerequisiteExpr = .empty
        store.catalog = catalog
        #expect(notice(store) == nil)
        #expect(store.placeholderDependencies(for: F.slotID(0)).isEmpty)
    }

    @Test func movingNoticeWithoutChangingWarningKeyRefreshesDetail() throws {
        let (store, _, _) = makeStore()
        #expect(notice(store)?.detail.contains("Spring 2027") == true)
        store.moveCourse("D0", to: Self.fall27)
        let moved = try #require(notice(store))
        #expect(moved.detail.contains("Fall 2027"))
        #expect(!moved.detail.contains("Spring 2027"))
        let key = try #require(store.placeholderDependencies(for: F.slotID(0))["A"]?.first)
        #expect(key.semester == Self.fall27)
    }

    @Test func movingTheDependentIntoTheSlotsTermRaisesTheConflict() {
        let (store, _, _) = makeStore()
        store.moveCourse("D0", to: F.fall)
        #expect(d0Missing(store))
        #expect(notice(store) == nil)
    }

    @Test func pendingNoticesAreNotKept() throws {
        let (store, _, _) = makeStore()
        let pending = try #require(notice(store))
        store.override(pending)
        #expect(store.plan.overrides.isEmpty)
    }
}
