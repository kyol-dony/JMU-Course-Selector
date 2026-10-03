import Foundation
import Testing
@testable import PlannerCore

/// Live catalog pages whose requirements split into mutually exclusive tracks
/// ("Students Seeking / Not Seeking Secondary Teaching Licensure") and
/// "Choose one of the following options" groups of "Option N:" blocks.
@Suite("Catalog tracks and options")
struct CatalogTrackOptionTests {
    private static let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    private func parse(_ file: String, kind: ProgramKind) throws -> HTMLProgramRequirements {
        let html = try String(contentsOf: Self.testDir.appendingPathComponent(file), encoding: .utf8)
        return JMUHTMLCatalogParser().parseProgramRequirements(
            html,
            kind: kind,
            sourceURL: URL(string: "https://catalog.jmu.edu/programs/x/")!
        )
    }

    private func courseIDs(_ concentration: Concentration) -> Set<String> {
        Set(concentration.requirements.flatMap { $0.courseOptions.flatMap { $0 } })
    }

    // MARK: Mathematics B.S.

    @Test("licensure tracks and their options become required concentrations")
    func mathTracks() throws {
        let parsed = try parse("_live_math_bs.html", kind: .major)
        #expect(parsed.concentrationSelectionRequired)
        #expect(parsed.concentrations.map(\.name) == [
            "Not Seeking Secondary Teaching Licensure - Option 1",
            "Not Seeking Secondary Teaching Licensure - Option 2",
            "Seeking Secondary Teaching Licensure"
        ])
    }

    @Test("shared requirements keep the core and drop track and option umbrellas")
    func mathShared() throws {
        let parsed = try parse("_live_math_bs.html", kind: .major)
        let names = parsed.requirements.map { $0.name.lowercased() }
        #expect(names.contains("core courses"))
        #expect(!names.contains { $0.contains("seeking") })
        #expect(!names.contains { $0.contains("option") })
    }

    @Test("Option 1 is 9 elective credits plus one of MATH 411/431/434/435")
    func mathOption1() throws {
        let parsed = try parse("_live_math_bs.html", kind: .major)
        let option1 = try #require(parsed.concentrations.first { $0.name.hasSuffix("Option 1") })
        let electives = try #require(option1.requirements.first { $0.name.hasPrefix("9 credits of MATH electives") })
        #expect(electives.requiredCredits == 9)
        #expect(electives.courseOptions.isEmpty)
        let advanced = try #require(option1.requirements.first { $0.courseOptions.contains(["MATH411", "MATH431", "MATH434", "MATH435"]) })
        #expect(advanced.courseOptions.count == 1)
        #expect(advanced.requiredCredits == 3)
        #expect(!courseIDs(option1).contains("MATH440"))
        #expect(!courseIDs(option1).contains("MATH475"))
    }

    @Test("Option 2 is 6 elective credits plus two of its listed courses")
    func mathOption2() throws {
        let parsed = try parse("_live_math_bs.html", kind: .major)
        let option2 = try #require(parsed.concentrations.first { $0.name.hasSuffix("Option 2") })
        let electives = try #require(option2.requirements.first { $0.name.hasPrefix("6 credits of MATH electives") })
        #expect(electives.requiredCredits == 6)
        let chooseTwo = try #require(option2.requirements.first { $0.name.lowercased().hasPrefix("choose two") })
        #expect(chooseTwo.courseOptions.count == 2)
        #expect(chooseTwo.courseOptions.allSatisfy { $0.contains("MATH440") && $0.contains("MATH426") })
        #expect(!courseIDs(option2).contains("MATH411"))
    }

    @Test("the licensure track takes MATH 310 or 315 plus 415, 470, 475 for 12 credits")
    func mathLicensure() throws {
        let parsed = try parse("_live_math_bs.html", kind: .major)
        let licensure = try #require(parsed.concentrations.first { $0.name == "Seeking Secondary Teaching Licensure" })
        let requirement = try #require(licensure.requirements.first { !$0.courseOptions.isEmpty })
        #expect(requirement.courseOptions == [["MATH310", "MATH315"], ["MATH415"], ["MATH470"], ["MATH475"]])
        #expect(requirement.requiredCredits == 12)
        #expect(!courseIDs(licensure).contains("MATH411"))
    }

    // MARK: Political Science minor

    @Test("a minor's Option 1 / Option 2 become required concentrations")
    func poscOptions() throws {
        let parsed = try parse("_live_posc_minor.html", kind: .minor)
        #expect(parsed.concentrationSelectionRequired)
        #expect(parsed.concentrations.map(\.name) == ["Option 1", "Option 2"])
        #expect(!parsed.requirements.map { $0.name.lowercased() }.contains { $0.hasPrefix("option") })
        #expect(parsed.requirements.contains { $0.name == "Required Courses" })

        let option1 = parsed.concentrations[0]
        let option2 = parsed.concentrations[1]
        #expect(option1.requirements.contains { $0.courseOptions == [["POSC230"]] })
        #expect(courseIDs(option1).contains("POSC361"))
        #expect(!courseIDs(option1).contains("POSC240"))
        #expect(option2.requirements.contains { $0.courseOptions == [["POSC240"]] })
        #expect(courseIDs(option2).contains("POSC340"))
        #expect(!courseIDs(option2).contains("POSC230"))
    }
}
