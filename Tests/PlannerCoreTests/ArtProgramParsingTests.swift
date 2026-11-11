import Foundation
import Testing
@testable import PlannerCore

/// Art B.A. and Art B.F.A. pages captured from the 2026-2027 catalog.
@Suite("Art program parsing")
struct ArtProgramParsingTests {
    private static func parse(_ file: String, slug: String, kind: ProgramKind = .major) throws -> HTMLProgramRequirements {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(file)
        return JMUHTMLCatalogParser().parseProgramRequirements(
            try String(contentsOf: url, encoding: .utf8), kind: kind,
            sourceURL: URL(string: "https://catalog.jmu.edu/programs/\(slug)/")!
        )
    }

    private static func requirement(_ name: String, in parsed: HTMLProgramRequirements) throws -> RequirementCategory {
        try #require(parsed.requirements.first { $0.name == name }, "\(name) missing")
    }

    @Test func degreeTotalIgnoresItsFootnoteMark() throws {
        // "Total<sup>3</sup> 120" read as 3 credits before.
        #expect(try Self.parse("_live_art_ba.html", slug: "art-ba").totalCredits == 120)
        #expect(try Self.parse("_live_art_bfa.html", slug: "art-bfa").totalCredits == 120)
    }

    @Test func artEducationIsOptionalForTheBAButAStudioAreaIsRequiredForTheBFA() throws {
        let ba = try Self.parse("_live_art_ba.html", slug: "art-ba")
        #expect(ba.concentrations.map(\.name) == ["Art Education"])
        #expect(!ba.concentrationSelectionRequired)
        #expect(try Self.parse("_live_art_bfa.html", slug: "art-bfa").concentrationSelectionRequired)
    }

    @Test func studioConcentrationsTakeTwelveCreditsFromTheirLists() throws {
        let bfa = try Self.parse("_live_art_bfa.html", slug: "art-bfa")
        for name in ["Ceramics", "Fibers", "Metals", "Painting", "Printmaking", "Sculpture", "Photography"] {
            let concentration = try #require(bfa.concentrations.first { $0.name == name })
            #expect(concentration.requirements.reduce(0) { $0 + $1.requiredCredits } == 12, "\(name)")
        }
        let painting = try #require(bfa.concentrations.first { $0.name == "Painting" }?.requirements.first)
        #expect(painting.selection == .chooseCredits(12))
        #expect(Set(painting.courseOptions.flatMap { $0 }) == ["ART352", "ART452", "ART459"])
        // Art Education is not one of the listed studio media.
        let education = try #require(bfa.concentrations.first { $0.name == "Art Education" })
        #expect(education.requirements.reduce(0) { $0 + $1.requiredCredits } == 42)
    }

    @Test func photographyChooseThreeIsNineNamedCredits() throws {
        let photography = try #require(try Self.parse("_live_art_bfa.html", slug: "art-bfa").concentrations.first { $0.name == "Photography" })
        let choose = try #require(photography.requirements.first { $0.selection == .chooseCourses(3) })
        // The row's hours read "3-9".
        #expect(choose.requiredCredits == 9)
        #expect(choose.name == "Photography Concentration: Choose three of the following")
        #expect(choose.courseOptions.count == 3)
    }

    @Test func studioAndArtHistoryElectivesBecomePools() throws {
        let ba = try Self.parse("_live_art_ba.html", slug: "art-ba")
        let studio = try Self.requirement("Studio Art Electives", in: ba)
        #expect(studio.courseOptions.count == 6)
        #expect(studio.courseOptions[0] == [
            ElectivePool.token(subject: "ART", minimumNumber: 100, excluding: ["ART200", "ART105", "ART304", "ART305", "ART405", "ART491", "ART493", "ART496"]),
            ElectivePool.token(subject: "FDS", minimumNumber: 100)
        ])
        let emphasis = try Self.requirement("Studio Art Emphasis", in: ba)
        #expect(emphasis.requiredCredits == 6)
        #expect(emphasis.courseOptions == Array(repeating: [ElectivePool.token(subject: "ART", minimumNumber: 300)], count: 2))
        let history = try Self.requirement("Art History Elective", in: ba)
        #expect(history.courseOptions == [[ElectivePool.token(subject: "ARTH", minimumNumber: 300, excluding: ["ARTH397", "ARTH490", "ARTH495", "ARTH497", "ARTH499"])]])

        let bfaHistory = try Self.requirement("Art History Electives (300-400 Level)", in: try Self.parse("_live_art_bfa.html", slug: "art-bfa"))
        #expect(bfaHistory.courseOptions.count == 2)
        #expect(bfaHistory.electivePoolSlots == [0, 1])
    }

    @Test func artHistoryMinorRowBecomesAPool() throws {
        let text = "Required Courses: Art history courses (300-400 level) Art history courses (300-400 level) For studio art, graphic design and architectural design majors, required ARTH courses in the art emphasis program may count toward the art history minor. Excludes ARTH 390 , ARTH 490 , ARTH 495 and ARTH 499 ."
        let pool = try #require(JMUHTMLCatalogParser.levelOrPrefixPool(in: text, subjects: ["ARTH"]))
        #expect(pool.tokens == [ElectivePool.token(subject: "ARTH", minimumNumber: 300, excluding: ["ARTH390", "ARTH490", "ARTH495", "ARTH499"])])
        // No level and no prefix: left for an advisor.
        #expect(JMUHTMLCatalogParser.levelOrPrefixPool(in: "Complete 3 credit hours of psychology electives", subjects: ["PSYC"]) == nil)
    }
}
