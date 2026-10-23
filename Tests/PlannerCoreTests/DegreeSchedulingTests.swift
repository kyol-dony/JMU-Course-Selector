import Foundation
import Testing
@testable import PlannerCore

/// The generator plans each declared major's B.A./B.S. degree requirements
/// inside 120 credits: the language sequence as real courses, the others by
/// a qualifying course already in the plan or a pick-a-course placeholder.
@Suite("Degree requirement scheduling")
struct DegreeSchedulingTests {
    private static let coreIDs = (1...20).map { String(format: "C%02d", $0) }

    private static func course(_ id: String, title: String? = nil, after prerequisite: String? = nil) -> Course {
        Course(id: id, code: id, title: title ?? id, credits: 3, availability: [.fall, .spring],
               prerequisites: prerequisite.map { [$0] } ?? [])
    }

    private static let courses: [Course] = coreIDs.map { course($0) } + [
        course("MATH220", title: "Elementary Statistics [C3QR]"), course("MATH231"), course("PHIL101"), course("BIO140"), course("COB191"),
        course("SPAN101"), course("SPAN102", after: "SPAN101"), course("SPAN231", after: "SPAN102"), course("SPAN232", after: "SPAN231")
    ]

    private static func required(_ id: String, _ courseIDs: [String]) -> RequirementCategory {
        RequirementCategory(id: id, name: "Required Courses", requiredCredits: 3 * courseIDs.count,
                            courseOptions: courseIDs.map { [$0] }, selection: .allRequired, choices: courseIDs.map { [$0] })
    }

    /// 60 listed credits, so the open-elective top-up applies.
    private static let core = required("core", coreIDs)
    private static let genEdQuantitative = RequirementCategory(
        id: "gened-c3qr", name: "General Education - Quantitative Reasoning [C3QR]", requiredCredits: 3, courseOptions: [["MATH220"]]
    )

    private static func major(_ id: String, _ requirements: [RequirementCategory], _ kinds: [DegreeRequirementKind]) -> Program {
        var program = Program.fixture(id: id, title: id, requirements: requirements)
        program.degreeRequirements = kinds.map { DegreeRequirement(kind: $0, creditsText: $0 == .foreignLanguage ? "0-12" : "3") }
        return program
    }

    private struct Result {
        var ids: [String]
        var pathway: Pathway
        var hours: Double
        func placeholders(_ kind: DegreeRequirementKind) -> [String] {
            ids.filter { pathway.placeholders[$0]?.categoryID == "degree-\(kind.rawValue)" }
        }
        func semester(of id: String) -> Int? { pathway.semesters.firstIndex { $0.courseIDs.contains(id) } }
    }

    private func plan(_ primary: Program, with extras: [Program] = [], language: ForeignLanguagePlan? = nil) throws -> Result {
        let catalog = Catalog(
            source: CatalogSource(catalogYear: "Fixture", issueDate: Date(timeIntervalSince1970: 0), retrievedDate: Date(timeIntervalSince1970: 0), sourceURLs: [], retrievalNotes: []),
            programs: [primary] + extras,
            courses: Self.courses,
            apCreditRules: [],
            degreeEligibility: try DegreeEligibility.load(from: DegreeEligibilityTests.bundledURL)
        )
        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: primary.id, workload: .standard, transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall), additionalPrograms: extras, languagePlan: language
        ).first)
        let hours = AcademicCreditCalculator.projectedHours(in: pathway.semesters, placeholders: pathway.placeholders, transferCredits: [], catalog: catalog)
        return Result(ids: pathway.semesters.flatMap(\.courseIDs), pathway: pathway, hours: hours)
    }

    @Test func baPlanSchedulesSpanishInOrder() throws {
        let result = try plan(Self.major("ba", [Self.core], [.foreignLanguage, .philosophy]),
                              language: ForeignLanguagePlan(subject: "SPAN", placement: .notSure))
        let sequence = ["SPAN101", "SPAN102", "SPAN231", "SPAN232"]
        for id in sequence { #expect(result.ids.filter { $0 == id }.count == 1, "\(id)") }
        let semesters = sequence.compactMap(result.semester(of:))
        #expect(semesters.count == 4 && semesters == semesters.sorted() && Set(semesters).count == 4)
        #expect(result.placeholders(.philosophy).count == 1)
        #expect(result.hours >= 120 && result.hours < 123)
    }

    @Test func bsMajorCourseCoversQuantitative() throws {
        let result = try plan(Self.major("bs", [Self.core, Self.required("math", ["MATH231"])], [.quantitative, .scientificLiteracy]))
        #expect(result.placeholders(.quantitative).isEmpty)
        #expect(result.placeholders(.scientificLiteracy).count == 1)
        #expect(result.hours >= 120 && result.hours < 123)
    }

    @Test func genEdOnlyQuantitativeAddsPlaceholder() throws {
        // MATH 220 fills the Gen Ed QR area, so it can't also meet the B.S. Quantitative requirement
        let result = try plan(Self.major("bs", [Self.core, Self.genEdQuantitative], [.quantitative]))
        #expect(result.ids.contains("MATH220"))
        #expect(result.placeholders(.quantitative).count == 1)
        let spec = try #require(result.placeholders(.quantitative).first.flatMap { result.pathway.placeholders[$0] })
        #expect(spec.categoryName == "Quantitative (B.S.)" && !spec.alternates.contains("MATH220") && spec.alternates.contains("MATH231"))
    }

    @Test func stackedDegreesNeedAllFourOnce() throws {
        let bs = Self.major("bs", [Self.core, Self.required("math", ["MATH231"])], [.quantitative, .scientificLiteracy])
        let ba = Self.major("ba", [Self.required("ba-core", ["COB191"])], [.foreignLanguage, .philosophy, .quantitative])
        let result = try plan(bs, with: [ba], language: ForeignLanguagePlan(subject: "SPAN", placement: .notSure))
        #expect(result.placeholders(.philosophy).count == 1)
        #expect(result.placeholders(.scientificLiteracy).count == 1)
        #expect(result.placeholders(.quantitative).isEmpty)
        #expect(["SPAN101", "SPAN102", "SPAN231", "SPAN232"].allSatisfy(result.ids.contains))
        #expect(result.hours >= 120 && result.hours < 123)
    }

    @Test func noLanguagePlanSchedulesNoLanguage() throws {
        let result = try plan(Self.major("ba", [Self.core], [.foreignLanguage, .philosophy]))
        #expect(!result.ids.contains { $0.hasPrefix("SPAN") })
        #expect(result.placeholders(.philosophy).count == 1)
    }

    @Test func degreeCoursesReplaceOpenElectives() throws {
        // Same major with and without a B.A. degree: the total stays at 120
        let plain = try plan(Self.major("plain", [Self.core], []))
        let ba = try plan(Self.major("ba", [Self.core], [.foreignLanguage, .philosophy]),
                          language: ForeignLanguagePlan(subject: "SPAN", placement: .notSure))
        #expect(abs(plain.hours - ba.hours) < 3)
    }
}
