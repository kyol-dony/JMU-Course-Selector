import Foundation
import Testing
@testable import PlannerCore

/// The "Degree Requirements" table (`table.tbl_degmajreq`) at the top of
/// each program page: its B.A./B.S. rows become degree requirements.
@Suite("Degree requirements table")
struct DegreeTableParserTests {
    private static let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    /// Sociology B.A., copied from the live page.
    private static let baTable = """
    <table class="sc_sctable tbl_degmajreq"><thead><tr class="sctablehead"><th scope="col" class="column0">Degree Requirements</th><th scope="col" class="column1">Credit Hours</th></tr></thead><tbody>
    <tr class="even firstrow"><td class="column0">General Education<sup>1</sup></td><td class="column1">41</td></tr>
    <tr class="odd"><td class="column0">Foreign Language classes (intermediate level required)<sup>2</sup></td><td class="column1">0-12</td></tr>
    <tr class="even"><td class="column0">Philosophy course (in addition to General Education courses)</td><td class="column1">3</td></tr>
    <tr class="odd"><td class="column0">Major requirements</td><td class="column1">39</td></tr>
    <tr class="even"><td class="column0">University electives</td><td class="column1">25-37</td></tr>
    <tr class="odd last lastrow"><td class="column0"><strong>Total</strong></td><td class="column1"><strong>120</strong></td></tr>
    </tbody></table>

    <dl class="sc_footnotes" aria-label="Footnotes"><dt> <sup> 1 </sup> </dt><dd><p class="noindent">The General Education program contains a set of requirements each student must fulfill.</p></dd><dt> <sup> 2 </sup> </dt><dd><p class="noindent">The foreign language requirement may be satisfied by successful completion of the second semester of the intermediate level of the student's chosen language (typically 232).</p></dd></dl>
    """

    @Test func psychologyBSHasQuantitativeAndScientificLiteracy() throws {
        let html = try String(contentsOf: Self.testDir.appendingPathComponent("_live_psyc_bs.html"), encoding: .utf8)
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: URL(string: "https://catalog.jmu.edu/programs/psychology-bs/")!)
        #expect(parsed.degreeRequirements.map(\.kind) == [.quantitative, .scientificLiteracy])
        #expect(parsed.degreeRequirements.map(\.creditsText) == ["3", "3-4"])
    }

    @Test func baTableHasLanguageAndPhilosophy() {
        let reqs = JMUHTMLCatalogParser.degreeRequirements(in: Self.baTable)
        #expect(reqs.map(\.kind) == [.foreignLanguage, .philosophy])
        #expect(reqs.first?.creditsText == "0-12")
        #expect(reqs.first?.note?.hasPrefix("The foreign language requirement may be satisfied") == true)
        #expect(reqs.last?.note == nil)
    }

    @Test func tableWithoutScientificLiteracyRowOmitsIt() {
        // Computer Science B.S.: its major courses cover Scientific Literacy, so the table leaves it out
        let html = """
        <table class="sc_sctable tbl_degmajreq"><tbody>
        <tr><td class="column0">General Education</td><td class="column1">41</td></tr>
        <tr><td class="column0">Quantitative requirement (in addition to General Education)</td><td class="column1">3</td></tr>
        <tr><td class="column0">Major requirements (listed below)</td><td class="column1">49-52</td></tr>
        </tbody></table>
        """
        #expect(JMUHTMLCatalogParser.degreeRequirements(in: html).map(\.kind) == [.quantitative])
    }

    @Test func pageWithoutTableHasNone() {
        #expect(JMUHTMLCatalogParser.degreeRequirements(in: "<h2>Minor Requirements</h2><table class=\"sc_courselist\"></table>").isEmpty)
    }
}
