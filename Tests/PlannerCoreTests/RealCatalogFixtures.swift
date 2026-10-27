import Foundation
import Testing
@testable import PlannerCore

/// Programs parsed from the catalog pages saved in the test folder, for
/// tests that need the real shape of a requirement rather than a sketch.
enum RealCatalogFixtures {
    static let mathTrack = "not-seeking-secondary-teaching-licensure"

    /// A program parsed from a saved catalog page in the test folder.
    static func program(_ file: String, id: String, kind: ProgramKind) throws -> Program {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let html = try String(contentsOf: testDir.appendingPathComponent(file), encoding: .utf8)
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: kind, sourceURL: URL(string: "https://catalog.jmu.edu/programs/x/")!)
        return Program(
            id: id, title: id, degreeType: nil, kind: kind, college: "X", department: "X", catalogPage: nil,
            totalCredits: parsed.totalCredits, requirements: parsed.requirements, concentrations: parsed.concentrations,
            concentrationSelectionRequired: parsed.concentrationSelectionRequired, verificationStatus: .verified,
            requirementDataComplete: true, sourceNote: "Fixture"
        )
    }

    /// `programs` with the MATH 3xx/4xx courses the Math pools list, pools
    /// resolved: each pool menu holds every one of them, the "choose two"
    /// and "one of MATH 411/431/434/435" courses included. As in the real
    /// catalog, MATH 354 and 364 carry 4 credits and the rest 3.
    static func catalog(_ programs: [Program]) -> Catalog {
        let numbers = ["310", "315", "321", "322", "324", "325", "326", "327", "328", "340", "341", "354", "358", "364", "367",
                       "368", "411", "415", "421", "423", "424", "426", "427", "428", "429", "431", "434", "435", "440", "441",
                       "448", "449", "470", "475", "485", "497"]
        return Catalog(
            source: CatalogSource(catalogYear: "Fixture", issueDate: Date(timeIntervalSince1970: 0), retrievedDate: Date(timeIntervalSince1970: 0), sourceURLs: [], retrievalNotes: []),
            programs: programs,
            courses: numbers.map { Course(id: "MATH\($0)", code: "MATH \($0)", title: "MATH \($0)", credits: ["354", "364"].contains($0) ? 4 : 3, availability: [.fall, .spring], prerequisites: []) },
            apCreditRules: []
        ).resolvingElectivePools()
    }

    /// The Math B.S. "not seeking licensure" option requirement, as parsed.
    static func mathRequirement(_ math: Program) throws -> RequirementCategory {
        try #require(math.concentrations.first { $0.id == mathTrack }?.requirements.first { $0.options != nil })
    }

    /// A major holding only the real Math B.S. option requirement, in a
    /// catalog of its MATH courses.
    static func mathOptionsOnly(id: String = "math-bs") throws -> (catalog: Catalog, requirement: RequirementCategory) {
        let math = try program("_live_math_bs.html", id: id, kind: .major)
        let requirement = try mathRequirement(math)
        let major = Program.fixture(id: id, title: "Math", requirements: [requirement])
        let catalog = catalog([major])
        return (catalog, try #require(catalog.programsByID[id]?.requirements.first))
    }
}
