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

    @MainActor @Test(.enabled(if: path != nil))
    func everyMajorGeneratesAReasonablePlan() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Catalog.self, from: Data(contentsOf: URL(fileURLWithPath: try #require(Self.path))))
        let catalog = CatalogRepository.applyingCurrentGenEdCredits(to: decoded).resolvingElectivePools()
        let generator = ScheduleGenerator(catalog: catalog)
        for program in catalog.programs where program.kind == .major && program.requirementDataComplete {
            let concentrationID = program.concentrationSelectionRequired ? program.concentrations.first?.id : nil
            do {
                let pathway = try #require(try generator.generatePathways(
                    for: program.id,
                    concentrationID: concentrationID,
                    workload: .standard,
                    transferCredits: [],
                    starting: SemesterIdentity(year: 2026, term: .fall)
                ).first)
                let hours = AcademicCreditCalculator.projectedHours(
                    in: pathway.semesters, placeholders: pathway.placeholders, transferCredits: [], catalog: catalog
                )
                print("AUDIT\t\(program.id)\t\(Int(hours.rounded()))")
                #expect(hours <= 140, "\(program.title): \(hours) credits")
            } catch {
                print("AUDIT\t\(program.id)\tERROR \(error.localizedDescription)")
            }
        }
    }
}
