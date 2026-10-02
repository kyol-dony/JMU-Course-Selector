import Foundation
import SwiftUI
import PlannerCore

enum TranscriptImportState: Equatable { case idle, processing, reviewing, failed }
@MainActor final class TranscriptImportController: ObservableObject {
    @Published private(set) var state = TranscriptImportState.idle
    @Published var draft: TranscriptReviewDraft?
    @Published private(set) var errorMessage: String?
    private let reader: any TranscriptTextReading
    private var operationID = UUID()
    private var operation: Task<ParsedTranscript, Error>?
    init(reader: any TranscriptTextReading = TranscriptPDFReader()) { self.reader = reader }
    func cancel() {
        operationID = UUID(); operation?.cancel(); operation = nil
        draft = nil; errorMessage = nil; state = .idle
    }
    func beginManual(catalog: Catalog, existingRecords: [AcademicCourseRecord], existingCredits: [TransferCredit], defaultSemester: SemesterIdentity) {
        cancel()
        draft = TranscriptReconciler.makeDraft(parsed: nil, catalog: catalog, existingRecords: existingRecords, existingCredits: existingCredits, defaultSemester: defaultSemester)
        state = .reviewing
    }
    func importPDF(at url: URL, catalog: Catalog, existingRecords: [AcademicCourseRecord], existingCredits: [TransferCredit], defaultSemester: SemesterIdentity) async {
        cancel(); state = .processing
        let token = operationID
        let reader = reader
        let worker = Task.detached(priority: .userInitiated) {
            let pages = try await reader.readPages(from: url)
            try Task.checkCancellation()
            return try JMUTranscriptParser.parse(pages: pages)
        }
        operation = worker
        do {
            let parsed = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            guard token == operationID, !Task.isCancelled else { return }
            draft = TranscriptReconciler.makeDraft(parsed: parsed, catalog: catalog, existingRecords: existingRecords, existingCredits: existingCredits, defaultSemester: defaultSemester)
            state = .reviewing
        } catch {
            guard token == operationID else { return }
            if error is CancellationError { state = .idle } else { state = .failed; errorMessage = error.localizedDescription }
        }
        if token == operationID { operation = nil }
    }
}
