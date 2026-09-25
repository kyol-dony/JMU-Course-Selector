import AppKit
import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Plan store schedule undo")
@MainActor
struct PlanStoreUndoTests {
    static let fall26 = SemesterIdentity(year: 2026, term: .fall)
    static let spring27 = SemesterIdentity(year: 2027, term: .spring)
    static let fall27 = SemesterIdentity(year: 2027, term: .fall)

    private func makeStore(groupsByEvent: Bool = false) -> (PlanStore, UndoManager) {
        let store = PlanStore()
        store.catalog = Catalog.fixture(
            courses: [
                Course(id: "CS149", code: "CS 149", title: "Intro Programming", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "CS159", code: "CS 159", title: "Advanced Programming", credits: 3, availability: [.fall, .spring], prerequisites: ["CS149"]),
                Course(id: "ART200", code: "ART 200", title: "Studio Art", credits: 3, availability: [.fall, .spring], prerequisites: []),
                Course(id: "WRTC103", code: "WRTC 103", title: "Critical Reading and Writing", credits: 3, availability: [.fall, .spring], prerequisites: [])
            ],
            program: Program.fixture(
                id: "cs-bs",
                title: "CS, B.S.",
                requirements: [RequirementCategory(id: "core", name: "Core", requiredCredits: 3, courseOptions: [["CS149"]])]
            )
        )
        store.plan.pathways = [
            Pathway(id: "path", name: "Balanced", semesters: [
                SemesterPlan(id: Self.fall26, courseIDs: ["CS149", "ART200"]),
                SemesterPlan(id: Self.spring27, courseIDs: ["CS159"])
            ]),
            Pathway(id: "alt", name: "Alternate", semesters: [
                SemesterPlan(id: Self.fall26, courseIDs: ["ART200"])
            ])
        ]
        store.plan.activePathwayID = "path"
        let undoManager = UndoManager()
        undoManager.groupsByEvent = groupsByEvent
        store.undoManager = undoManager
        return (store, undoManager)
    }

    @Test("a move can be undone and redone")
    func moveUndoRedo() {
        let (store, undo) = makeStore()
        let original = store.plan.pathways[0]
        store.moveCourse("ART200", to: Self.spring27)
        let moved = store.plan.pathways[0]
        #expect(moved.semesters[1].courseIDs == ["CS159", "ART200"])
        #expect(undo.undoActionName == "Move ART 200")
        #expect(store.lastScheduleChange?.message == "Moved ART 200 to Spring 2027")
        undo.undo()
        #expect(store.plan.pathways[0] == original)
        #expect(store.lastScheduleChange == nil)
        undo.redo()
        #expect(store.plan.pathways[0] == moved)
    }

    @Test("a reorder can be undone")
    func reorderUndo() {
        let (store, undo) = makeStore()
        let original = store.plan.pathways[0]
        store.moveCourse("ART200", to: Self.fall26, at: 0)
        #expect(store.lastScheduleChange?.message == "Reordered ART 200 in Fall 2026")
        let reordered = store.plan.pathways[0]
        undo.undo()
        #expect(store.plan.pathways[0] == original)
        undo.redo()
        #expect(store.plan.pathways[0] == reordered)
    }

    @Test("remove and add are undoable")
    func removeAndAddUndo() {
        let (store, undo) = makeStore()
        let original = store.plan.pathways[0]
        store.removeCourse("ART200")
        #expect(undo.undoActionName == "Remove ART 200")
        #expect(store.lastScheduleChange?.message == "Removed ART 200")
        let removed = store.plan.pathways[0]
        undo.undo()
        #expect(store.plan.pathways[0] == original)
        undo.redo()
        #expect(store.plan.pathways[0] == removed)
        undo.undo()
        store.moveCourse("WRTC103", to: Self.spring27)
        #expect(undo.undoActionName == "Add WRTC 103")
        #expect(store.lastScheduleChange?.message == "Added WRTC 103 to Spring 2027")
        let added = store.plan.pathways[0]
        undo.undo()
        #expect(store.plan.pathways[0] == original)
        undo.redo()
        #expect(store.plan.pathways[0] == added)
    }

    @Test("choosing a course for a placeholder is undoable")
    func resolvePlaceholderUndo() {
        let (store, undo) = makeStore()
        let placeholderID = PathwayPlaceholder.id(categoryID: ScheduleGenerator.openElectiveCategoryID, optionIndex: 0)
        store.plan.pathways[0].semesters[1].courseIDs.append(placeholderID)
        store.plan.pathways[0].placeholders[placeholderID] = PlaceholderSpec(categoryID: ScheduleGenerator.openElectiveCategoryID, categoryName: "Open Elective", alternates: [], credits: 3)
        let original = store.plan.pathways[0]
        store.resolvePlaceholder(placeholderID, with: "WRTC103")
        #expect(undo.undoActionName == "Choose WRTC 103")
        #expect(store.lastScheduleChange?.message == "Chose WRTC 103 for Open Elective")
        let resolved = store.plan.pathways[0]
        undo.undo()
        #expect(store.plan.pathways[0] == original)
        #expect(store.plan.pathways[0].resolvedPlaceholders.isEmpty)
        undo.redo()
        #expect(store.plan.pathways[0] == resolved)
    }

    @Test("dropping an item back on its own slot records nothing")
    func sameSlotRecordsNothing() {
        let (store, undo) = makeStore()
        store.moveCourse("ART200", to: Self.fall26, at: 1)
        #expect(!undo.canUndo)
        #expect(store.lastScheduleChange == nil)
    }

    @Test("the change summary counts new warnings")
    func changeSummaryCountsNewWarnings() {
        let (store, _) = makeStore()
        store.moveCourse("CS149", to: Self.spring27)
        #expect(store.lastScheduleChange?.message == "Moved CS 149 to Spring 2027")
        #expect(store.lastScheduleChange?.newWarningCount == 1)
    }

    @Test("undoLastScheduleChange undoes and clears the toast")
    func undoLastScheduleChange() {
        let (store, _) = makeStore()
        let original = store.plan.pathways[0]
        store.moveCourse("ART200", to: Self.spring27)
        store.undoLastScheduleChange()
        #expect(store.plan.pathways[0] == original)
        #expect(store.lastScheduleChange == nil)
    }

    @Test("undo after switching pathways restores and re-selects the edited pathway")
    func undoAfterSwitchingPathways() {
        let (store, undo) = makeStore()
        let original = store.plan.pathways[0]
        let alternate = store.plan.pathways[1]
        store.moveCourse("ART200", to: Self.spring27)
        store.plan.activePathwayID = "alt"
        undo.undo()
        #expect(store.plan.activePathwayID == "path")
        #expect(store.plan.pathways[0] == original)
        #expect(store.plan.pathways[1] == alternate)
    }

    @Test("undo is a no-op when the edited pathway no longer exists")
    func undoAfterPathwayRemoved() {
        let (store, undo) = makeStore()
        store.moveCourse("ART200", to: Self.spring27)
        store.plan.pathways = [store.plan.pathways[1]]
        store.plan.activePathwayID = "alt"
        let before = store.plan
        undo.undo()
        #expect(store.plan.pathways == before.pathways)
        #expect(store.plan.activePathwayID == "alt")
    }

    @Test("undo does not resurrect a replaced pathway with the same ID")
    func undoAfterSameIDReplacement() {
        let (store, undo) = makeStore()
        store.moveCourse("ART200", to: Self.spring27)
        store.plan.pathways[0] = Pathway(id: "path", name: "Regenerated", semesters: [SemesterPlan(id: Self.fall27, courseIDs: ["WRTC103"])])
        let before = store.plan
        undo.undo()
        #expect(store.plan == before)
    }

    @Test("undo does not change another saved plan")
    func undoAfterResume() {
        let (store, undo) = makeStore()
        store.moveCourse("ART200", to: Self.spring27)
        var replacement = store.plan
        replacement.id = UUID()
        replacement.name = "Other"
        replacement.pathways[0] = Pathway(id: "path", name: "Other path", semesters: [SemesterPlan(id: Self.fall27, courseIDs: ["WRTC103"])])
        store.resume(replacement)
        #expect(!undo.canUndo)
        undo.undo()
        #expect(store.plan == replacement)
    }

    @Test("changing the major clears schedule undo history")
    func changingMajorClearsHistory() throws {
        let (store, undo) = makeStore()
        store.moveCourse("ART200", to: Self.spring27)
        store.selectProgram(try #require(store.catalog?.programs.first))
        #expect(!undo.canUndo)
        #expect(store.lastScheduleChange == nil)
    }

    @Test("regenerating pathways clears schedule undo history")
    func regeneratingClearsHistory() async {
        let (store, undo) = makeStore()
        store.plan.programID = "cs-bs"
        store.moveCourse("ART200", to: Self.spring27)
        #expect(undo.canUndo)
        await store.generateSchedules()
        #expect(store.errorMessage == nil)
        #expect(!store.plan.pathways.isEmpty)
        #expect(!undo.canUndo)
    }

    @Test("fresh and reset entry points clear history")
    func resetEntryPointsClearHistory() {
        let (store, undo) = makeStore()
        store.moveCourse("ART200", to: Self.spring27)
        store.startFresh()
        #expect(!undo.canUndo)
        #expect(store.lastScheduleChange == nil)
    }

    @Test("drop verdicts reflect the latest plan")
    func dropVerdictsRefreshAfterChanges() {
        let (store, _) = makeStore()
        #expect(store.dropVerdicts(for: "CS149")[Self.spring27]?.level == .blocking)
        #expect(store.dropVerdicts(for: "CS149")[Self.fall26] == .neutral)
        store.moveCourse("CS159", to: Self.fall27)
        #expect(store.dropVerdicts(for: "CS149")[Self.spring27]?.level == .clear)
    }

    @Test("consecutive edits remain separate undo steps", arguments: [false, true])
    func consecutiveEdits(groupsByEvent: Bool) {
        let (store, undo) = makeStore(groupsByEvent: groupsByEvent)
        let original = store.plan.pathways[0]
        store.moveCourse("ART200", to: Self.spring27)
        let firstEdit = store.plan.pathways[0]
        store.moveCourse("CS149", to: Self.spring27, at: 0)
        undo.undo()
        #expect(store.plan.pathways[0] == firstEdit)
        undo.undo()
        #expect(store.plan.pathways[0] == original)
    }

    @Test("background verdicts match synchronous results and refresh after a move")
    func backgroundVerdicts() async {
        let (store, _) = makeStore()
        let initial = await store.loadDropVerdicts(for: "CS149")
        #expect(initial == store.dropVerdicts(for: "CS149"))
        #expect(initial?[Self.spring27]?.level == .blocking)
        store.moveCourse("CS159", to: Self.fall27)
        let refreshed = await store.loadDropVerdicts(for: "CS149")
        #expect(refreshed?[Self.spring27]?.level == .clear)
    }

    @Test("cancelled background requests do not publish verdicts")
    func cancelledVerdicts() async {
        let (store, _) = makeStore()
        let request = Task { await store.loadDropVerdicts(for: "CS149") }
        request.cancel()
        #expect(await request.value == nil)
    }
}
