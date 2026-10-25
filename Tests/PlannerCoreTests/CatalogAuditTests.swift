import Foundation
import Testing
@testable import JMUCoursePlanner
@testable import PlannerCore

/// Opt-in audit over a whole cached catalog: generates the first pathway for
/// every major and prints its total credits. Runs only when
/// `CATALOG_AUDIT_JSON` names a `catalog_html_cache_vN.json` file.
@Suite("Catalog audit")
struct CatalogAuditTests {
    private static let path = ProcessInfo.processInfo.environment["CATALOG_AUDIT_JSON"]

    /// History B.A. placing into SPAN 102 or 231 graduates on the same
    /// schedule as starting at 101, with the sequence early in the plan.
    @MainActor @Test(.enabled(if: path != nil))
    func languagePlacementKeepsGraduationOnTime() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Catalog.self, from: Data(contentsOf: URL(fileURLWithPath: try #require(Self.path))))
        let catalog = CatalogRepository.applyingCurrentGenEdCredits(to: decoded).resolvingElectivePools()
        let history = try #require(catalog.programsByID["history-ba"])
        for placement in [LanguagePlacement.level102, .level231] {
            let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
                for: history.id, concentrationID: history.concentrations.first?.id, workload: .standard, transferCredits: [],
                starting: SemesterIdentity(year: 2026, term: .fall), languagePlan: ForeignLanguagePlan(subject: "SPAN", placement: placement)
            ).first)
            let first = pathway.semesters.firstIndex { $0.courseIDs.contains { $0.hasPrefix("SPAN") } }
            #expect(pathway.semesters.count <= 8, "\(placement): \(pathway.semesters.count) semesters")
            #expect((first ?? 99) <= 2, "\(placement): first SPAN course in semester \((first ?? 99) + 1)")
        }
    }

    @MainActor @Test(.enabled(if: path != nil))
    func everyMajorGeneratesAReasonablePlan() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Catalog.self, from: Data(contentsOf: URL(fileURLWithPath: try #require(Self.path))))
        var catalog = CatalogRepository.applyingCurrentGenEdCredits(to: decoded).resolvingElectivePools()
        // CATALOG_AUDIT_NO_DEGREE gives the same catalog without B.A./B.S.
        // degree requirements, as a baseline for comparison.
        if ProcessInfo.processInfo.environment["CATALOG_AUDIT_NO_DEGREE"] != nil {
            catalog.programs = catalog.programs.map { var p = $0; p.degreeRequirements = []; return p }
        }
        let generator = ScheduleGenerator(catalog: catalog)
        for program in catalog.programs where program.kind == .major && program.requirementDataComplete {
            let concentrationID = program.concentrationSelectionRequired ? program.concentrations.first?.id : nil
            let needsLanguage = ForeignLanguagePlan.isRequired(by: [program])
            do {
                let pathway = try #require(try generator.generatePathways(
                    for: program.id,
                    concentrationID: concentrationID,
                    workload: .standard,
                    transferCredits: [],
                    starting: SemesterIdentity(year: 2026, term: .fall),
                    languagePlan: needsLanguage ? ForeignLanguagePlan(subject: "SPAN", placement: .notSure) : nil
                ).first)
                if needsLanguage {
                    let ids = Set(pathway.semesters.flatMap(\.courseIDs))
                    #expect(["SPAN101", "SPAN102", "SPAN231", "SPAN232"].allSatisfy(ids.contains), "\(program.title) lacks the Spanish sequence")
                }
                let hours = AcademicCreditCalculator.projectedHours(
                    in: pathway.semesters, placeholders: pathway.placeholders, transferCredits: [], catalog: catalog
                )
                print("AUDIT\t\(program.id)\t\(Int(hours.rounded()))")
                if ProcessInfo.processInfo.environment["CATALOG_AUDIT_PROGRAM"] == program.id {
                    for id in pathway.semesters.flatMap(\.courseIDs) {
                        let spec = pathway.placeholders[id]
                        print("COURSE\t\(spec.map { "\($0.categoryName) (\($0.credits))" } ?? id)\t\(catalog.coursesByID[id]?.credits ?? 0)")
                    }
                }
                #expect(hours <= 140, "\(program.title): \(hours) credits")
            } catch {
                print("AUDIT\t\(program.id)\tERROR \(error.localizedDescription)")
            }
        }
    }
}
