import Foundation
import Testing
@testable import PlannerCore

/// "Choose one of the following options" groups parse into one requirement
/// carrying `options`, instead of one concentration per option.
@Suite("Requirement options parsing")
struct RequirementOptionsParserTests {
    private static let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    private func parse(_ file: String, kind: ProgramKind) throws -> HTMLProgramRequirements {
        let html = try String(contentsOf: Self.testDir.appendingPathComponent(file), encoding: .utf8)
        return JMUHTMLCatalogParser().parseProgramRequirements(
            html, kind: kind, sourceURL: URL(string: "https://catalog.jmu.edu/programs/x/")!
        )
    }

    private func parseSnippet(_ rows: String) -> [RequirementCategory] {
        let html = """
        <h1>Example, B.S.</h1><h2>Major Requirements</h2>
        <table class="sc_courselist"><tbody>\(rows)</tbody></table>
        """
        return JMUHTMLCatalogParser().parseProgramRequirements(
            html, kind: .major, sourceURL: URL(string: "https://catalog.jmu.edu/programs/x/")!
        ).requirements
    }

    private static func header(_ text: String, hours: String = "") -> String {
        #"<tr class="areaheader"><td colspan="2"><span class="courselistcomment areaheader">\#(text)</span></td><td class="hourscol">\#(hours)</td></tr>"#
    }
    private static func comment(_ text: String, hours: String = "") -> String {
        #"<tr><td colspan="2"><span class="courselistcomment">\#(text)</span></td><td class="hourscol">\#(hours)</td></tr>"#
    }
    private static func link(_ code: String) -> String {
        let query = code.replacingOccurrences(of: " ", with: "%20")
        return #"<a href="/search/?P=\#(query)" class="bubblelink code">\#(code)</a>"#
    }
    private static func course(_ code: String, _ title: String) -> String {
        #"<tr><td class="codecol">\#(link(code))</td><td>\#(title)</td><td class="hourscol">3</td></tr>"#
    }
    /// "PHYS 140 & 140L" on one row; the second link shows only the number.
    private static func pair(_ first: String, _ second: String, hours: String = "4", or: Bool = false) -> String {
        let secondQuery = second.replacingOccurrences(of: " ", with: "%20")
        let secondShown = second.split(separator: " ").last.map(String.init) ?? second
        let rowClass = or ? #" class="orclass odd""# : ""
        let cellClass = or ? "codecol orclass" : "codecol"
        let prefix = or ? "or " : ""
        let hoursCell = or ? "" : #"<td class="hourscol">\#(hours)</td>"#
        let titleSpan = or ? #" colspan="2""# : ""
        return #"<tr\#(rowClass)><td class="\#(cellClass)">\#(prefix)\#(link(first))<br/><span class="blockindent">&amp; <a href="/search/?P=\#(secondQuery)" class="bubblelink code">\#(secondShown)</a></span></td><td\#(titleSpan)>First<br/><span class="blockindent">and Second</span></td>\#(hoursCell)</tr>"#
    }

    // MARK: Mathematics B.S.

    @Test func mathBSOptionsAreOneRequirement() throws {
        let parsed = try parse("_live_math_bs.html", kind: .major)
        #expect(parsed.concentrations.allSatisfy { !$0.name.contains("Option") }, "\(parsed.concentrations.map(\.name))")
        let notSeeking = try #require(parsed.concentrations.first { $0.name.contains("Not Seeking") })
        let requirement = try #require(notSeeking.requirements.first { $0.options != nil })
        let options = try #require(requirement.options)
        #expect(options.map(\.label) == ["Option 1", "Option 2"])
        #expect(options.map(\.id) == ["option-1", "option-2"])
        #expect(requirement.requiredCredits == 12)

        let option2 = options[1]
        #expect(option2.parts.count == 2)
        let pool = option2.parts[0]
        #expect(pool.courseOptions.count == 2)
        #expect(pool.courseOptions.allSatisfy { $0.count == 1 && ElectivePool.isToken($0[0]) })
        let chooseTwo = option2.parts[1]
        #expect(chooseTwo.selection == .chooseCourses(2))
        #expect(chooseTwo.courseOptions.count == 2)
        #expect(chooseTwo.courseOptions.allSatisfy { Set($0) == ["MATH440", "MATH441", "MATH448", "MATH449"] })
        #expect(chooseTwo.alternativeGroup == ["MATH426", "MATH427"])

        let option1 = options[0]
        #expect(option1.parts.count == 2)
        #expect(option1.parts[0].courseOptions.allSatisfy { $0.count == 1 && ElectivePool.isToken($0[0]) })
        #expect(option1.parts[1].courseOptions == [["MATH411", "MATH431", "MATH434", "MATH435"]])
    }

    @Test func mathBSOptionLegacyFieldsDescribeTheFirstOption() throws {
        let parsed = try parse("_live_math_bs.html", kind: .major)
        let notSeeking = try #require(parsed.concentrations.first { $0.name.contains("Not Seeking") })
        let requirement = try #require(notSeeking.requirements.first { $0.options != nil })
        let option1 = try #require(requirement.options?.first)
        #expect(requirement.courseOptions == option1.parts.flatMap(\.courseOptions))
        #expect(requirement.choices == option1.parts.flatMap(\.choices))
        #expect(requirement.id == "choose-one-of-the-following-options")
    }

    @Test func requirementIDOutsideOptionsIsUnchanged() throws {
        let parsed = try parse("_live_math_bs.html", kind: .major)
        let pinned = CatalogTrackOptionTests.mathNonOptionRequirementIDs
        #expect(parsed.requirements.filter { $0.options == nil }.map(\.id) == pinned.shared)
        let concentrationIDs = parsed.concentrations.map { concentration in
            concentration.requirements.filter { $0.options == nil }.map(\.id)
        }
        #expect(concentrationIDs == pinned.concentrations)
    }

    // MARK: Political Science minor

    @Test func poscMinorOptionsAreOneRequirement() throws {
        let parsed = try parse("_live_posc_minor.html", kind: .minor)
        #expect(parsed.concentrations.isEmpty)
        let requirement = try #require(parsed.requirements.first { $0.options != nil })
        let options = try #require(requirement.options)
        #expect(options.count == 2)
        let option1 = options[0]
        #expect(option1.parts.count == 2)
        #expect(option1.parts[0].courseOptions == [["POSC230"]])
        #expect(option1.parts[0].selection == .allRequired)
        #expect(option1.parts[1].selection == .chooseCourses(1))
        #expect(option1.parts[1].courseOptions.count == 1)
        #expect(option1.parts[1].courseOptions[0].contains("POSC361"))
    }

    // MARK: Snippets

    @Test func logicAndReasoningPairsStayGroups() throws {
        let category = try #require(parseSnippet(
            Self.header("Logic and Reasoning")
            + Self.comment("Choose one of the following pairs of courses:", hours: "6")
            + Self.pair("MATH 235", "MATH 245", hours: "7")
            + Self.comment("or")
            + Self.pair("MATH/CS 227", "CS 327", hours: "6")
        ).first)
        #expect(category.selection == .chooseGroups(1))
        #expect(category.choices == [["MATH235", "MATH245"], ["MATH227", "CS327"]])
        #expect(category.options == nil)
    }

    @Test func innerOrBecomesAlternativesSlot() throws {
        let category = try #require(parseSnippet(
            Self.header("Physical Science")
            + Self.comment("Choose one of the following options:", hours: "3-8")
            + Self.comment("Option 1:") + Self.course("ISCI 172", "Physical Science")
            + Self.comment("Option 2:")
            + Self.pair("PHYS 140", "PHYS 140L")
            + Self.pair("PHYS 240", "PHYS 240L", or: true)
            + Self.pair("CHEM 131", "CHEM 131L")
        ).first)
        let options = try #require(category.options)
        #expect(options.count == 2)
        #expect(options[0].parts.map(\.courseOptions) == [[["ISCI172"]]])
        let part = try #require(options[1].parts.first)
        #expect(options[1].parts.count == 1)
        #expect(part.selection == .allRequired)
        #expect(part.courseOptions.contains { $0.contains("PHYS140") && $0.contains("PHYS240") })
        #expect(part.courseOptions.contains { $0 == ["CHEM131"] })
        #expect(!part.courseOptions.contains { $0 == ["PHYS240"] })
    }
}
