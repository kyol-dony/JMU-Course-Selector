import Foundation
import XCTest
@testable import PlannerCore

final class PrereqRuleOverlayTests: XCTestCase {
    private let sourceURL = URL(string: "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=123&print")!

    func testOverlayJSONDecodesExplicitAndInferredRules() throws {
        let json = """
        {
          "schemaVersion": 1,
          "rules": [
            {
              "courseID": "CS240",
              "prerequisiteExpr": { "kind": "course", "value": "CS159" },
              "corequisiteExpr": { "kind": "empty" },
              "confidence": "curated",
              "basis": "explicit",
              "sourceURL": "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=123&print",
              "sourceText": "Prerequisite: CS 159.",
              "notes": "Catalog wording directly names CS 159."
            },
            {
              "courseID": "CS345",
              "prerequisiteExpr": { "kind": "course", "value": "CS240" },
              "corequisiteExpr": { "kind": "empty" },
              "confidence": "curated",
              "basis": "inferred",
              "sourceURL": "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=999&print",
              "sourceText": "The program sequence lists CS 240 before CS 345.",
              "notes": "Official sequence presents CS 240 as required preparation before CS 345."
            }
          ]
        }
        """.data(using: .utf8)!

        let overlay = try JSONDecoder().decode(PrereqRuleOverlay.self, from: json)

        XCTAssertEqual(overlay.schemaVersion, 1)
        XCTAssertEqual(overlay.rules.count, 2)
        XCTAssertEqual(overlay.rule(for: "CS240")?.basis, .explicit)
        XCTAssertEqual(overlay.rule(for: "CS345")?.basis, .inferred)
    }

    func testResolverPrefersCuratedOverlayOverRawParserText() throws {
        var cs240 = Course(id: "CS240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: CS 159."
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS149", code: "CS 149", title: "Intro", credits: 3, availability: nil, prerequisites: []),
                Course(id: "CS159", code: "CS 159", title: "Advanced", credits: 3, availability: nil, prerequisites: []),
                cs240
            ],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: []),
            prereqRuleOverlay: PrereqRuleOverlay(schemaVersion: 1, rules: [
                PrereqRule(
                    courseID: "CS240",
                    prerequisiteExpr: .course("CS149"),
                    corequisiteExpr: .empty,
                    confidence: .curated,
                    basis: .explicit,
                    sourceURL: sourceURL,
                    sourceText: "Prerequisite: CS 149.",
                    notes: "Curated rule must win over stale parser text."
                )
            ])
        )

        let resolved = PrereqRuleResolver(catalog: catalog)
            .rule(for: cs240, activeProgramTitle: "Computer Science, B.S.")

        XCTAssertEqual(resolved.prerequisiteExpr, .course("CS149"))
        XCTAssertEqual(resolved.confidence, .curated)
        XCTAssertEqual(resolved.basis, .explicit)
        XCTAssertEqual(resolved.sourceText, "Prerequisite: CS 149.")
    }

    func testResolverFallsBackToRawCatalogParser() throws {
        var cs240 = Course(id: "CS240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: CS 159."
        cs240.descriptionSourceURL = sourceURL
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS159", code: "CS 159", title: "Advanced", credits: 3, availability: nil, prerequisites: []),
                cs240
            ],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: [])
        )

        let resolved = PrereqRuleResolver(catalog: catalog, overlay: .empty)
            .rule(for: cs240, activeProgramTitle: nil)

        XCTAssertEqual(resolved.prerequisiteExpr, .course("CS159"))
        XCTAssertEqual(resolved.confidence, .parsed)
        XCTAssertEqual(resolved.sourceURL, sourceURL)
        XCTAssertEqual(resolved.sourceText, "Prerequisite: CS 159.")
    }

    func testResolverFallsBackToLegacyFlatPrerequisites() throws {
        let cs240 = Course(id: "CS240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: ["CS159", "MATH235"])
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS159", code: "CS 159", title: "Advanced", credits: 3, availability: nil, prerequisites: []),
                Course(id: "MATH235", code: "MATH 235", title: "Calculus", credits: 4, availability: nil, prerequisites: []),
                cs240
            ],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: [])
        )

        let resolved = PrereqRuleResolver(catalog: catalog, overlay: .empty)
            .rule(for: cs240, activeProgramTitle: nil)

        XCTAssertEqual(resolved.prerequisiteExpr, .all([.course("CS159"), .course("MATH235")]))
        XCTAssertEqual(resolved.corequisiteExpr, .empty)
        XCTAssertEqual(resolved.confidence, .parsed)
    }

    func testResolverReturnsNoneForCourseWithoutKnownRequirements() throws {
        let cs149 = Course(id: "CS149", code: "CS 149", title: "Intro", credits: 3, availability: nil, prerequisites: [])
        let catalog = Catalog.fixture(
            courses: [cs149],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: [])
        )

        let resolved = PrereqRuleResolver(catalog: catalog, overlay: .empty)
            .rule(for: cs149, activeProgramTitle: nil)

        XCTAssertEqual(resolved.prerequisiteExpr, .empty)
        XCTAssertEqual(resolved.corequisiteExpr, .empty)
        XCTAssertEqual(resolved.confidence, .none)
    }
}

final class CatalogPrereqOverlayCodableTests: XCTestCase {
    func testCatalogIndexesStayCurrentWhenCollectionsChange() throws {
        let initialCourse = Course(id: "CS149", code: "CS 149", title: "Intro", credits: 3, availability: nil, prerequisites: [])
        let addedCourse = Course(id: "CS159", code: "CS 159", title: "Advanced", credits: 3, availability: nil, prerequisites: [])
        let initialProgram = Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: [])
        let addedProgram = Program.fixture(id: "cis-bba", title: "Computer Information Systems, B.B.A.", requirements: [])
        var catalog = Catalog.fixture(courses: [initialCourse], program: initialProgram)

        catalog.courses.append(addedCourse)
        catalog.programs.append(addedProgram)

        XCTAssertEqual(catalog.coursesByID["CS159"]?.title, "Advanced")
        XCTAssertEqual(catalog.programsByID["cis-bba"]?.title, "Computer Information Systems, B.B.A.")
    }

    func testCatalogDefaultsToEmptyOverlayWhenDecodedFromOldJSON() throws {
        let json = """
        {
          "source": {
            "catalogYear": "Fixture",
            "issueDate": "1970-01-01T00:00:00Z",
            "retrievedDate": "1970-01-01T00:00:00Z",
            "sourceURLs": [],
            "retrievalNotes": []
          },
          "programs": [],
          "courses": [],
          "apCreditRules": []
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let catalog = try decoder.decode(Catalog.self, from: json)

        XCTAssertEqual(catalog.prereqRuleOverlay, .empty)
    }

    func testCatalogRoundTripsOverlay() throws {
        let overlay = PrereqRuleOverlay(schemaVersion: 1, rules: [
            PrereqRule(
                courseID: "CS240",
                prerequisiteExpr: .course("CS159"),
                corequisiteExpr: .empty,
                confidence: .curated,
                basis: .explicit,
                sourceURL: URL(string: "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=123&print")!,
                sourceText: "Prerequisite: CS 159.",
                notes: nil
            )
        ])
        let catalog = Catalog.fixture(
            courses: [],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: []),
            prereqRuleOverlay: overlay
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(catalog)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(Catalog.self, from: data)

        XCTAssertEqual(decoded.prereqRuleOverlay, overlay)
    }
}
