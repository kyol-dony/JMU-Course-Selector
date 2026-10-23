import Foundation
import Testing
@testable import PlannerCore

/// The Registrar's B.A./B.S. degree course list, bundled with the app, and
/// the degree requirement fields on programs and catalogs.
@Suite("Degree eligibility")
struct DegreeEligibilityTests {
    static let bundledURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Data/degree_requirement_courses.json")

    @Test func bundledRegistrarListMatchesSpec() throws {
        let e = try DegreeEligibility.load(from: Self.bundledURL)
        #expect(e.isEligible("PHIL101", for: .philosophy))
        #expect(!e.isEligible("PHIL120", for: .philosophy) && !e.isEligible("PHIL150", for: .philosophy))
        #expect(e.isEligible("BIO140", for: .scientificLiteracy) && e.isEligible("KIN202", for: .scientificLiteracy))
        #expect(e.isEligible("CS139", for: .scientificLiteracy) && !e.isEligible("CS227", for: .scientificLiteracy))
        #expect(e.isEligible("MATH220", for: .quantitative) && e.isEligible("CS227", for: .quantitative) && e.isEligible("BIO454", for: .quantitative))
        #expect(!e.isEligible("BIO140", for: .quantitative))
        #expect(e.languageSubjects.contains("SPAN") && e.languageSubjects.contains("ASL"))
    }

    @Test func legacyProgramAndCatalogDecode() throws {
        let program = Program.fixture(id: "p", title: "P", requirements: [])
        var programJSON = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(program)) as? [String: Any])
        programJSON["degreeRequirements"] = nil
        let decodedProgram = try JSONDecoder().decode(Program.self, from: JSONSerialization.data(withJSONObject: programJSON))
        #expect(decodedProgram.degreeRequirements.isEmpty)

        let catalog = Catalog.fixture(courses: [], program: program)
        var catalogJSON = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(catalog)) as? [String: Any])
        catalogJSON["degreeEligibility"] = nil
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let decodedCatalog = try decoder.decode(Catalog.self, from: JSONSerialization.data(withJSONObject: catalogJSON))
        #expect(decodedCatalog.degreeEligibility == .empty)
    }

    @Test func degreeFieldsRoundTrip() throws {
        var program = Program.fixture(id: "p", title: "P", requirements: [])
        program.degreeRequirements = [DegreeRequirement(kind: .quantitative, creditsText: "3", note: "In addition to General Education.")]
        #expect(try JSONDecoder().decode(Program.self, from: JSONEncoder().encode(program)).degreeRequirements == program.degreeRequirements)
    }
}
