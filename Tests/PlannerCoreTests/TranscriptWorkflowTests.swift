import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

private struct FailingTranscriptReader: TranscriptTextReading {
    func readPages(from url: URL) async throws -> [String] { throw TranscriptPDFError.noText }
}

@Suite @MainActor struct TranscriptWorkflowTests {
    @Test func sampleReviewSaveReloadAndRegenerate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = TranscriptTestFixtures.sampleCatalog()
        let store = PlanStore(storageDirectory: root)
        store.catalog = catalog; store.plan.programID = "cs"; store.plan.studentYear = .junior
        let parsed = try JMUTranscriptParser.parse(pages: [TranscriptTestFixtures.sampleText()])
        var draft = TranscriptReconciler.makeDraft(parsed: parsed, catalog: catalog, existingRecords: [], existingCredits: [], defaultSemester: .current())
        for row in draft.records where row.courseIDs.isEmpty {
            if row.status == .earned { draft.retainAsGeneralCredit(recordID: row.id) }
            if row.status == .inProgress { draft.retainUnmatchedEnrollment(recordID: row.id) }
        }
        let currentID = SemesterIdentity(year: 2026, term: .fall)
        draft.setCurrentSemester(currentID)
        let history = try TranscriptReconciler.confirm(draft, catalog: catalog)
        try store.confirmAcademicHistory(history)
        await store.generateSchedules()
        #expect(store.plan.programID == "cs")
        #expect(store.effectiveAcademicHistory.earnedHours == 49)
        #expect(store.plan.currentSemester?.courseIDs.count == 5)
        #expect(AcademicCreditCalculator.hours(in: store.plan.currentSemester!, catalog: catalog) == 16)
        #expect(store.plan.pathways.count == 3)
        #expect(store.plan.pathways.allSatisfy { $0.semesters.first == history.currentSemester && $0.semesters.dropFirst().allSatisfy { $0.id.year > 2026 } })
        let decoded = try JSONDecoder().decode(SavedStudentPlan.self, from: JSONEncoder().encode(store.plan))
        let reloaded = PlanStore(storageDirectory: root); reloaded.catalog = catalog; reloaded.plan = decoded
        let reimport = TranscriptReconciler.makeDraft(parsed: parsed, catalog: catalog, existingRecords: decoded.academicRecords, existingCredits: decoded.transferCredits, defaultSemester: currentID)
        #expect(EffectiveCreditBuilder.build(records: reimport.records, legacyCredits: []).earnedHours == 49)
        await reloaded.generateSchedules()
        #expect(reloaded.plan.pathways.allSatisfy { $0.semesters.first == history.currentSemester })
        #expect(reloaded.effectiveAcademicHistory.earnedHours == 49)
        let before = reloaded.plan
        let controller = TranscriptImportController(reader: FailingTranscriptReader())
        await controller.importPDF(at: URL(fileURLWithPath: "/unused.pdf"), catalog: catalog, existingRecords: decoded.academicRecords, existingCredits: decoded.transferCredits, defaultSemester: currentID)
        #expect(controller.state == .failed)
        #expect(reloaded.plan == before)
        controller.beginManual(catalog: catalog, existingRecords: decoded.academicRecords, existingCredits: decoded.transferCredits, defaultSemester: currentID)
        #expect(controller.draft?.records.count == 24)
    }
    @Test func unknownCreditDoesNotInventPrerequisiteAndManualRoutesWork() throws {
        let catalog = TranscriptTestFixtures.prerequisiteCatalog()
        var draft = TranscriptReconciler.makeDraft(parsed: nil, catalog: catalog, existingRecords: [], existingCredits: [], defaultSemester: .init(year: 2026, term: .fall))
        let empty = try TranscriptReconciler.confirm(draft, catalog: catalog)
        #expect(empty.currentSemester?.courseIDs.isEmpty == true)
        let row = AcademicCourseRecord(code: "CSOOO", title: "General CS", earnedCredits: 3, status: .earned, source: .manual)
        draft.records.append(row); draft.retainAsGeneralCredit(recordID: row.id)
        let general = try TranscriptReconciler.confirm(draft, catalog: catalog)
        #expect(!general.completedCourseIDs.contains("CS149"))
        let path = Pathway(id: "p", name: "P", semesters: [.init(id: .init(year: 2027, term: .spring), courseIDs: ["CS159"])])
        #expect(ConflictDetector(catalog: catalog).warnings(for: path, overrides: [], completedAtStart: general.completedCourseIDs).contains { $0.kind == .missingPrerequisite })
        draft.replace(recordID: row.id, with: catalog.coursesByID["CS149"]!)
        let mapped = try TranscriptReconciler.confirm(draft, catalog: catalog)
        #expect(!ConflictDetector(catalog: catalog).warnings(for: path, overrides: [], completedAtStart: mapped.completedCourseIDs).contains { $0.kind == .missingPrerequisite })
        draft.add(course: catalog.coursesByID["CS159"]!, status: .inProgress)
        #expect(try TranscriptReconciler.confirm(draft, catalog: catalog).currentSemester?.courseIDs == ["CS159"])
    }
    @Test func correctedRequiredCreditDoesNotConsumeGeneralHours() {
        let catalog = TranscriptTestFixtures.degreeCatalog()
        let credits = [TransferCredit(sourceDescription: "Corrected", courseIDs: ["REQ1"], credits: 1.5), TransferCredit(sourceDescription: "General", courseIDs: [], credits: 10.5)]
        #expect(AcademicCreditCalculator.generalHours(credits: credits, current: nil, programs: catalog.programs, catalog: catalog) == 10.5)
    }
}
