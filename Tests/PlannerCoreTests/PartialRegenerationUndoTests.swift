import AppKit
import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite @MainActor struct PartialRegenerationUndoTests {
    private let fall = PlanStorePartialRegenerationTests.fall
    private func makeStore(worker: any AnchoredScheduleGenerating = LocalAnchoredScheduleGenerator(), storageDirectory: URL? = nil) -> (PlanStore, UndoManager) {
        let store = PlanStorePartialRegenerationTests.makeStore(worker: worker, storageDirectory: storageDirectory)
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        store.plan.pathways[1].semesters[1].courseIDs += ["__pl::old::0", "CHOSEN"]
        store.plan.pathways[1].placeholders = [
            "__pl::old::0": .init(categoryID: "old", categoryName: "Old", alternates: ["CS159"], credits: 3),
            "__pl::old::1": .init(categoryID: "old", categoryName: "Old", alternates: ["CHOSEN"], credits: 1.5)
        ]
        store.plan.pathways[1].resolvedPlaceholders = ["__pl::old::1": "CHOSEN"]
        store.plan.currentSemester = store.plan.pathways[1].semesters[0]
        store.plan.academicRecords = [.init(code: "CS149", title: "Original title", courseIDs: ["CS149"], attemptedCredits: 1.5,
                                          status: .inProgress, source: .transcriptResident, matchConfirmed: true)]
        return (store, undo)
    }
    @Test func oneUndoStepRestoresOldSuffixAndMetadata() async {
        let (store, undo) = makeStore()
        let old = store.activePathway
        let records = store.plan.academicRecords
        await store.regenerateActivePathway(after: fall)
        #expect(undo.undoActionName == "Regenerate after Fall 2026")
        #expect(store.activePathway != old)
        #expect(store.plan.academicRecords == records)
        undo.undo()
        #expect(store.activePathway == old)
        #expect(store.plan.academicRecords == records)
        #expect(!undo.canUndo)
    }
    @Test func redoRestoresNewSuffix() async {
        let (store, undo) = makeStore()
        await store.regenerateActivePathway(after: fall)
        let regenerated = store.activePathway
        undo.undo()
        undo.redo()
        #expect(store.activePathway == regenerated)
        #expect(undo.undoActionName == "Regenerate after Fall 2026")
    }
    @Test func earlierUndoHistoryRemains() async {
        let (store, undo) = makeStore()
        let original = store.activePathway
        store.moveCourse("CS159", to: fall.next)
        let edited = store.activePathway
        await store.regenerateActivePathway(after: fall)
        undo.undo()
        #expect(store.activePathway == edited)
        undo.undo()
        #expect(store.activePathway == original)
    }
    @Test func anchorOverridesAndUnrelatedPathwaysSurvive() async {
        let (store, undo) = makeStore()
        let anchor = ConflictOverride(courseID: "CS149", semester: fall, kind: .missingPrerequisite)
        let obsolete = ConflictOverride(courseID: "OLD", semester: fall.next, kind: .unknownAvailability)
        let remaining = ConflictOverride(courseID: "CS159", semester: fall.next, kind: .missingPrerequisite)
        let unrelated = ConflictOverride(courseID: "CS159", semester: fall, kind: .missingPrerequisite)
        store.plan.overrides = [anchor, obsolete, remaining, unrelated]
        let alternatives = [store.plan.pathways[0], store.plan.pathways[2]]
        await store.regenerateActivePathway(after: fall)
        #expect(Set(store.plan.overrides) == [anchor, remaining, unrelated])
        #expect([store.plan.pathways[0], store.plan.pathways[2]] == alternatives)
        let later = ConflictOverride(courseID: "ANOTHER", semester: fall.next.next, kind: .unknownAvailability)
        store.plan.overrides.append(later)
        undo.undo()
        #expect(Set(store.plan.overrides) == [anchor, obsolete, remaining, unrelated, later])
        undo.redo()
        #expect(Set(store.plan.overrides) == [anchor, remaining, unrelated, later])
    }
    @Test func savedPlanRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, undo) = makeStore(storageDirectory: root)
        await store.regenerateActivePathway(after: fall)
        PlanStore.flushPendingAutosaves()
        let data = try Data(contentsOf: root.appendingPathComponent("\(store.plan.id.uuidString).jmuplan.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reopened = try decoder.decode(SavedStudentPlan.self, from: data)
        #expect(reopened.pathways == store.plan.pathways)
        #expect(reopened.currentSemester == store.plan.currentSemester)
        #expect(reopened.academicRecords == store.plan.academicRecords)
        undo.undo()
        PlanStore.flushPendingAutosaves()
        #expect(store.savedPlans.first { $0.id == store.plan.id }?.pathways == store.plan.pathways)
    }
    @Test func nativeUndoDuringGenerationCancelsPendingWork() async {
        let worker = SuspendedAnchoredGenerator()
        let (store, undo) = makeStore(worker: worker)
        let original = store.activePathway!
        store.removeCourse("OLD")
        let task = Task { await store.regenerateActivePathway(after: fall) }
        await worker.waitForCalls(1)
        undo.undo()
        #expect(store.activePathway == original)
        #expect(store.partialRegeneration == nil)
        await worker.succeed(0, with: PlanStorePartialRegenerationTests.replacement(original))
        await task.value
        #expect(store.activePathway == original)
        undo.redo()
        #expect(!store.activePathway!.semesters.flatMap(\.courseIDs).contains("OLD"))
    }
}
