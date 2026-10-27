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

    /// Requirement IDs outside option requirements, as the parser at b7f7b53
    /// (before options) produced them for Mathematics B.S.: shared, then each
    /// concentration in order. Option groups must not move them.
    static let mathNonOptionRequirementIDs: (shared: [String], concentrations: [[String]]) = (
        shared: [
            "core-courses",
            "all-students-must-take-an-additional-12-credit-hours-of-mathematics-courses-beyond-the-core-there-are-two-options-available-for-students-who-are-not-seeking-secondary-teaching-licensure-and-one-option-available-for-students-seeking-secondary-teaching-licensure-these-options-are-listed-below"
        ],
        concentrations: [
            [],
            ["additional-requirements-for-students-seeking-secondary-teaching-licensure"]
        ]
    )

    @Test("licensure tracks become required concentrations; their options do not")
    func mathTracks() throws {
        let parsed = try parse("_live_math_bs.html", kind: .major)
        #expect(parsed.concentrationSelectionRequired)
        #expect(parsed.concentrations.map(\.name) == [
            "Not Seeking Secondary Teaching Licensure",
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

    private static let mathPool = ElectivePool.token(subject: "MATH", minimumNumber: 310)

    private func mathOptions() throws -> (track: Concentration, requirement: RequirementCategory, options: [RequirementOption]) {
        let parsed = try parse("_live_math_bs.html", kind: .major)
        let track = try #require(parsed.concentrations.first { $0.name == "Not Seeking Secondary Teaching Licensure" })
        let requirement = try #require(track.requirements.first { $0.options != nil })
        return (track, requirement, try #require(requirement.options))
    }

    @Test("the not-seeking track is one 12-credit option requirement")
    func mathOptionRequirement() throws {
        let (track, requirement, options) = try mathOptions()
        #expect(track.requirements.count == 1)
        #expect(requirement.requiredCredits == 12)
        #expect(options.map(\.label) == ["Option 1", "Option 2"])
    }

    @Test("Option 1 is three elective slots, then one of MATH 411/431/434/435")
    func mathOption1() throws {
        let option1 = try mathOptions().options[0]
        #expect(option1.parts.map(\.courseOptions) == [
            [[Self.mathPool], [Self.mathPool], [Self.mathPool]],
            [["MATH411", "MATH431", "MATH434", "MATH435"]]
        ])
        #expect(option1.parts.map(\.requiredCredits) == [9, 3])
        #expect(!option1.parts.flatMap { $0.courseOptions.joined() }.contains("MATH440"))
    }

    @Test("Option 2 is two elective slots, then two of its listed courses or both MATH 426 and 427")
    func mathOption2() throws {
        let option2 = try mathOptions().options[1]
        #expect(option2.parts.count == 2)
        #expect(option2.parts[0].courseOptions == [[Self.mathPool], [Self.mathPool]])
        let chooseTwo = option2.parts[1]
        #expect(chooseTwo.requiredCredits == 6)
        #expect(chooseTwo.courseOptions.count == 2)
        #expect(chooseTwo.courseOptions.allSatisfy { $0 == ["MATH440", "MATH441", "MATH448", "MATH449"] })
        #expect(chooseTwo.alternativeGroup == ["MATH426", "MATH427"])
        #expect(!option2.parts.flatMap { $0.courseOptions.joined() }.contains("MATH411"))
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

    @Test("a minor's Option 1 / Option 2 are one requirement, not concentrations")
    func poscOptions() throws {
        let parsed = try parse("_live_posc_minor.html", kind: .minor)
        #expect(!parsed.concentrationSelectionRequired)
        #expect(parsed.concentrations.isEmpty)
        #expect(parsed.requirements.contains { $0.name == "Required Courses" })

        let requirement = try #require(parsed.requirements.first { $0.options != nil })
        #expect(requirement.name == "International or Comparative Options")
        #expect(requirement.requiredCredits == 6)
        let options = try #require(requirement.options)
        #expect(options.map(\.label) == ["Option 1", "Option 2"])
        let option1 = options[0], option2 = options[1]
        #expect(option1.parts.count == 2)
        #expect(option1.parts.first?.courseOptions == [["POSC230"]])
        #expect(option1.parts.last?.courseOptions.first?.contains("POSC361") == true)
        #expect(!option1.parts.flatMap { $0.courseOptions.joined() }.contains("POSC240"))
        #expect(option2.parts.count == 2)
        #expect(option2.parts.first?.courseOptions == [["POSC240"]])
        #expect(option2.parts.last?.courseOptions.first?.contains("POSC340") == true)
        #expect(!option2.parts.flatMap { $0.courseOptions.joined() }.contains("POSC230"))
    }
}
