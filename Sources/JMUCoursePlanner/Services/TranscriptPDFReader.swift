import Foundation
import PDFKit

protocol TranscriptTextReading: Sendable {
    func readPages(from url: URL) async throws -> [String]
}
enum TranscriptPDFError: Error, LocalizedError {
    case unreadable, locked, noText
    var errorDescription: String? {
        switch self {
        case .unreadable: "This PDF could not be opened. Choose another file or enter courses manually."
        case .locked: "This PDF is password protected. Choose an unlocked copy or enter courses manually."
        case .noText: "This PDF has no selectable text. Scanned transcripts are not supported; choose a text PDF or enter courses manually."
        }
    }
}
struct TranscriptPDFReader: TranscriptTextReading {
    func readPages(from url: URL) async throws -> [String] {
        let worker = Task.detached(priority: .userInitiated) { () throws -> [String] in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            try Task.checkCancellation()
            guard let document = PDFDocument(url: url) else { throw TranscriptPDFError.unreadable }
            guard !document.isLocked else { throw TranscriptPDFError.locked }
            var pages: [String] = []
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let page = document.page(at: index) else { throw TranscriptPDFError.unreadable }
                pages.append(page.string ?? "")
            }
            guard pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw TranscriptPDFError.noText }
            return pages
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
}
