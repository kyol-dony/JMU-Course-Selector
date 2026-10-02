import AppKit
import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite @MainActor struct PlanStoreTranscriptTests {
    @Test func confirmationReimportAndRegeneration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PlanStore(storageDirectory: root)
        store.catalog = TranscriptTestFixtures.prerequisiteCatalog()
        store.plan.programID = "cs"
        store.plan.studentYear = .sophomore
        let earned = TranscriptReconcilerTests.record("UNKNOWN", credits: 49)
        let current = TranscriptReconcilerTests.record("CS149", status: .inProgress, source: .manual)
        var draft = TranscriptReconciler.makeDraft(parsed: nil, catalog: store.catalog!, existingRecords: [earned, current], existingCredits: [], defaultSemester: .init(year: 2026, term: .fall))
        draft.retainAsGeneralCredit(recordID: earned.id)
        let history = try TranscriptReconciler.confirm(draft, catalog: store.catalog!)
        try store.confirmAcademicHistory(history)
        #expect(store.plan.pathways.isEmpty)
        try store.confirmAcademicHistory(history)
        #expect(store.effectiveAcademicHistory.earnedHours == 49)
        await store.generateSchedules()
        #expect(store.plan.pathways.count == 3)
        #expect(store.plan.pathways.allSatisfy { $0.semesters.first?.courseIDs == ["CS149"] })
        let undo = UndoManager(); store.undoManager = undo
        store.removeCourse("CS149")
        #expect(store.plan.currentSemester?.courseIDs.isEmpty == true)
        undo.undo()
        #expect(store.plan.currentSemester?.courseIDs == ["CS149"])
        undo.redo()
        #expect(store.plan.currentSemester?.courseIDs.isEmpty == true)
    }
    @Test func movingUnknownCourseRetainsItsMetadata() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PlanStore(storageDirectory: root)
        store.catalog = TranscriptTestFixtures.prerequisiteCatalog()
        let current = SemesterPlan(id: .init(year: 2026, term: .fall), courseIDs: ["ZZZ123"], creditOverrides: ["ZZZ123": 1.5], courseTitles: ["ZZZ123": "Independent Study"])
        store.plan.currentSemester = current
        store.plan.pathways = [.init(id: "p", name: "P", semesters: [current, .init(id: .init(year: 2027, term: .spring), courseIDs: [])])]
        store.moveCourse("ZZZ123", to: .init(year: 2027, term: .spring))
        #expect(store.activePathway?.semesters.last?.creditOverrides["ZZZ123"] == 1.5)
        #expect(store.course(forID: "ZZZ123")?.title == "Independent Study")
    }
    @Test func exportSeparatesPriorCreditAndKeepsUnknownEnrollment() {
        let catalog = TranscriptTestFixtures.prerequisiteCatalog()
        let row = TranscriptReconcilerTests.record()
        let prior = EffectiveCreditBuilder.build(records: [row], legacyCredits: [])
        let history = AcademicHistory(records: [row], currentSemester: nil, effectiveCredits: prior.credits, earnedHours: 3)
        let path = Pathway(id: "p", name: "P", semesters: [.init(id: .init(year: 2026, term: .fall), courseIDs: ["ZZZ123"], creditOverrides: ["ZZZ123": 1.5], courseTitles: ["ZZZ123": "Independent Study"])])
        let text = ExportService().printableSummary(planName: "Test", pathway: path, catalog: catalog, history: history)
        #expect(text.contains("JMU coursework"))
        #expect(text.contains("Independent Study (1.5 credits)"))
    }
    @Test func failedSaveLeavesPlanUntouched() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let store = PlanStore(storageDirectory: file.appendingPathComponent("not-a-directory"))
        store.catalog = TranscriptTestFixtures.prerequisiteCatalog()
        let before = store.plan
        #expect(throws: (any Error).self) { try store.confirmAcademicHistory(.init(records: [], currentSemester: .init(id: .current(), courseIDs: []))) }
        #expect(store.plan == before)
    }
    @Test func apRemappingPreservesResidentCredit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PlanStore(storageDirectory: root)
        store.catalog = TranscriptTestFixtures.prerequisiteCatalog()
        let row = TranscriptReconcilerTests.record()
        let effective = EffectiveCreditBuilder.build(records: [row], legacyCredits: [])
        try store.confirmAcademicHistory(.init(records: [row], currentSemester: .init(id: .current(), courseIDs: []), effectiveCredits: effective.credits, earnedHours: effective.earnedHours))
        store.addAPScore(examName: "Computer Science A", score: 5)
        #expect(store.effectiveAcademicHistory.completedCourseIDs.contains("CS149"))
        #expect(store.effectiveAcademicHistory.earnedHours == 3)
    }
}
