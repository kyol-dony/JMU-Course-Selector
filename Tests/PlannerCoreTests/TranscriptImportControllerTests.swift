import AppKit
import PDFKit
import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

actor SuspendedTranscriptReader: TranscriptTextReading {
    var reads: [String: CheckedContinuation<[String], Error>] = [:]
    func readPages(from url: URL) async throws -> [String] { try await withCheckedThrowingContinuation { reads[url.lastPathComponent] = $0 } }
    func waitFor(_ name: String) async { while reads[name] == nil { await Task.yield() } }
    func finish(_ name: String, pages: [String]) { reads.removeValue(forKey: name)?.resume(returning: pages) }
}
@Suite @MainActor struct TranscriptImportControllerTests {
    @Test func canceledAndOlderReadsCannotReplaceNewDraft() async {
        let reader = SuspendedTranscriptReader()
        let controller = TranscriptImportController(reader: reader)
        let c = TranscriptTestFixtures.sampleCatalog()
        let first = Task { await controller.importPDF(at: URL(fileURLWithPath: "/old.pdf"), catalog: c, existingRecords: [], existingCredits: [], defaultSemester: .current()) }
        await reader.waitFor("old.pdf")
        controller.cancel()
        controller.beginManual(catalog: c, existingRecords: [], existingCredits: [], defaultSemester: .init(year: 2027, term: .spring))
        await reader.finish("old.pdf", pages: [TranscriptTestFixtures.sampleText()])
        await first.value
        #expect(controller.state == .reviewing)
        #expect(controller.draft?.records.isEmpty == true)
        #expect(controller.draft?.currentSemester == .init(year: 2027, term: .spring))
        let second = Task { await controller.importPDF(at: URL(fileURLWithPath: "/new.pdf"), catalog: c, existingRecords: [], existingCredits: [], defaultSemester: .current()) }
        await reader.waitFor("new.pdf")
        await reader.finish("new.pdf", pages: [TranscriptTestFixtures.sampleText()])
        await second.value
        #expect(controller.draft?.records.count == 24)
    }
    @Test func pdfReaderRejectsUnreadableAndImageOnly() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = TranscriptPDFReader()
        do { _ = try await reader.readPages(from: root.appendingPathComponent("missing.pdf")); Issue.record("Accepted missing PDF") } catch { #expect(error is TranscriptPDFError) }
        let doc = PDFDocument()
        let image = NSImage(size: .init(width: 100, height: 100))
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        image.addRepresentation(bitmap)
        doc.insert(try #require(PDFPage(image: image)), at: 0)
        let blank = root.appendingPathComponent("image.pdf")
        #expect(doc.write(to: blank))
        do { _ = try await reader.readPages(from: blank); Issue.record("Accepted image-only PDF") } catch { #expect(error is TranscriptPDFError) }
        let view = NSTextView(frame: .init(x: 0, y: 0, width: 500, height: 700))
        view.string = "James Madison University\nUnofficial Transcript\nFall Semester 2026\nCS 149 Intro 3.00 0.00 0.000"
        let text = root.appendingPathComponent("text.pdf")
        try view.dataWithPDF(inside: view.bounds).write(to: text)
        let pages = try await reader.readPages(from: text)
        #expect(pages.joined().contains("CS 149"))
    }
}
