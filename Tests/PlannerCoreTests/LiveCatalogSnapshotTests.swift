import Foundation
import Testing
@testable import PlannerCore

/// Regression tests against captured snapshots of live catalog.jmu.edu pages.
/// These guard against parser regressions on the actual catalog HTML shape.
@Suite("Live catalog snapshots")
struct LiveCatalogSnapshotTests {
    private static let testDir = "/Users/Kyle/VSC/JMU-Course-Selector/Tests/PlannerCoreTests/"

    private func loadHTML(_ name: String) throws -> String {
        try String(contentsOfFile: Self.testDir + name, encoding: .utf8)
    }

    @Test("CS B.S. core courses parse out of an umbrella Major Requirements block")
    func parsesCSCoreCourses() throws {
        let html = try loadHTML("_live_cs.html")
        let url = URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=27091")!
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: url)

        // The CS print page tucks the 8 core required courses directly under the
        // "Major Requirements" heading rather than in a separate child block. The
        // parser must keep that umbrella heading instead of filtering it out.
        let majorReq = try #require(parsed.requirements.first { $0.name.lowercased().contains("major requirements") })
        let coreIDs = majorReq.courseOptions.flatMap { $0 }
        #expect(coreIDs.contains("CS149"))
        #expect(coreIDs.contains("CS159"))
        #expect(coreIDs.contains("CS240"))
        #expect(coreIDs.contains("CS261"))
        #expect(coreIDs.contains("CS327"))
        #expect(coreIDs.contains("CS345"))
        #expect(coreIDs.contains("CS361"))
        #expect(coreIDs.contains("CS430"))
        // Required credits should reflect the 8 × 3cr core, not the per-course
        // "Credits: 3.00" pattern (which would yield 3 if the body parser was wrong).
        #expect(majorReq.requiredCredits == 24)
    }

    @Test("Accounting program parses its three core component blocks")
    func parsesAccountingComponents() throws {
        let html = try loadHTML("_live_accounting.html")
        let url = URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=27172")!
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: url)

        let headings = parsed.requirements.map(\.name)
        #expect(headings.contains { $0.contains("Lower-Level Core") })
        #expect(headings.contains { $0.contains("Upper-Level Core") })
        #expect(headings.contains { $0.contains("Required Courses") })
        #expect(parsed.courses.contains { $0.id == "ACTG343" })
    }

    @Test("Live programs-of-study index returns 100+ programs")
    func parsesLiveIndex() throws {
        let html = try loadHTML("_live_index.html")
        let entries = JMUHTMLCatalogParser().parseProgramsOfStudy(html)
        #expect(entries.count > 100)
        #expect(entries.contains { $0.kind == .major })
        #expect(entries.contains { $0.kind == .minor })
    }
}
