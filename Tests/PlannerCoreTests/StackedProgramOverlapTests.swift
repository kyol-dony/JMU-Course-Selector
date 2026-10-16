import Foundation
import Testing
@testable import PlannerCore

/// A course one program requires outright also fills another program's
/// choice (a Gen Ed cluster, a cognate, an elective pool) instead of the
/// plan scheduling a second, interchangeable course for it; and the 120-CRH
/// top-up still counts that course once.
@Suite("Stacked program overlap")
struct StackedProgramOverlapTests {
    private static let coreIDs = (1...20).map { String(format: "C%02d", $0) }

    /// IDs like "BIO140L" get the catalog's spaced code ("BIO 140L"), which
    /// the corequisite text uses.
    private static func course(_ id: String, _ raw: String? = nil, credits: Int = 3) -> Course {
        let code = id.replacingOccurrences(of: #"^([A-Z]{2,})(\d)"#, with: "$1 $2", options: .regularExpression)
        return Course(id: id, code: code, title: id, credits: credits, availability: [.fall, .spring], prerequisites: [], rawPrerequisiteText: raw)
    }

    private static let courses: [Course] = coreIDs.map { course($0) }
        + ["M1", "M2", "M3", "A", "B", "C", "X"].map { course($0) }
        + [
            course("BIO140", "Prerequisites: BIO 140L . Corequisites: BIO 140L ."),
            course("BIO140L", "Prerequisites: BIO 140 . Corequisites: BIO 140 .", credits: 1),
            course("CHEM131L", "Corequisites: CHEM 131 .", credits: 1),
            course("CHEM131")
        ]

    /// 60 listed credits of required courses, so the open-elective gate opens.
    private static let core = RequirementCategory(
        id: "core", name: "Core", requiredCredits: 60,
        courseOptions: coreIDs.map { [$0] }, selection: .allRequired, choices: coreIDs.map { [$0] }
    )
    private static let quantitative = RequirementCategory(
        id: "gened-c3qr", name: "General Education - Quantitative Reasoning [C3QR]", requiredCredits: 3,
        courseOptions: [["M1", "M2", "M3"]]
    )

    private static func major(_ id: String, _ requirements: [RequirementCategory]) -> Program {
        Program.fixture(id: id, title: id, requirements: requirements)
    }

    private static func minor(_ id: String, _ requirements: [RequirementCategory]) -> Program {
        var program = Program.fixture(id: id, title: id, requirements: requirements)
        program.kind = .minor
        return program
    }

    private static func required(_ id: String, _ courseIDs: [String]) -> RequirementCategory {
        RequirementCategory(id: id, name: "Required Courses", requiredCredits: 3 * courseIDs.count,
                            courseOptions: courseIDs.map { [$0] }, selection: .allRequired, choices: courseIDs.map { [$0] })
    }

    private func plan(_ primary: Program, with extras: [Program] = []) throws -> (ids: [String], pathway: Pathway, hours: Double) {
        let catalog = Catalog(
            source: CatalogSource(catalogYear: "Fixture", issueDate: Date(timeIntervalSince1970: 0), retrievedDate: Date(timeIntervalSince1970: 0), sourceURLs: [], retrievalNotes: []),
            programs: [primary] + extras,
            courses: Self.courses,
            apCreditRules: []
        )
        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: primary.id, workload: .standard, transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall), additionalPrograms: extras
        ).first)
        let hours = AcademicCreditCalculator.projectedHours(in: pathway.semesters, placeholders: pathway.placeholders, transferCredits: [], catalog: catalog)
        return (pathway.semesters.flatMap(\.courseIDs), pathway, hours)
    }

    private func placeholders(_ result: (ids: [String], pathway: Pathway, hours: Double), in categoryID: String) -> [String] {
        result.ids.filter { result.pathway.placeholders[$0]?.categoryID == categoryID }
    }

    @Test func secondMajorsRequiredCourseFillsTheFirstMajorsChoice() throws {
        // Biology B.S. + Biotechnology: MATH 231 is required by one and fills the other's QR cluster
        let result = try plan(Self.major("first", [Self.core, Self.quantitative]),
                              with: [Self.major("second", [Self.required("second-core", ["M2"])])])
        #expect(result.ids.filter { $0 == "M2" }.count == 1)
        #expect(placeholders(result, in: "gened-c3qr").isEmpty)
    }

    @Test func aLaterRequiredCourseFillsAnEarlierChoiceAndStillReaches120() throws {
        let result = try plan(Self.major("single", [Self.quantitative, Self.core, Self.required("more", ["M2"])]))
        #expect(placeholders(result, in: "gened-c3qr").isEmpty)
        #expect(result.hours >= 120 && result.hours < 123)
    }

    @Test func aMinorsRequiredCourseFillsAChoiceAndStillReaches120() throws {
        // Biology B.S. + Pre-Optometry minor fell to 110 when the top-up ignored the overlap
        let result = try plan(Self.major("major", [Self.core, Self.quantitative]),
                              with: [Self.minor("minor", [Self.required("minor-core", ["M2", "X"])])])
        #expect(placeholders(result, in: "gened-c3qr").isEmpty)
        #expect(result.hours >= 120 && result.hours < 123)
    }

    @Test func aRequiredLecturesLabFillsALabChoice() throws {
        // Economics B.A. + B.S.: BIO 140 brings BIO 140L, which fills the Gen Ed lab cluster
        let lab = RequirementCategory(id: "gened-c3l", name: "General Education - Lab Experience [C3L]", requiredCredits: 1,
                                      courseOptions: [["BIO140L", "CHEM131L"]])
        let result = try plan(Self.major("first", [Self.core, lab]),
                              with: [Self.major("second", [Self.required("second-core", ["BIO140"])])])
        #expect(placeholders(result, in: "gened-c3l").isEmpty)
        #expect(result.ids.filter { $0 == "BIO140L" }.count == 1)
    }

    @Test func anElectivePoolMetByARequiredCourseStillReaches120() throws {
        let electives = RequirementCategory(id: "major-electives", name: "Major Electives", requiredCredits: 6, courseOptions: [["A"], ["B"], ["C"]])
        let result = try plan(Self.major("single", [electives, Self.core, Self.required("more", ["A"])]))
        #expect(result.hours >= 120 && result.hours < 123)
    }
}
