import Foundation
import Testing
@testable import JMUCoursePlanner
@testable import PlannerCore

/// Opt-in audit of Psychology, Art and Honors stacked as primary majors,
/// second majors and minors, driven through `PlanStore` the way setup does.
/// Runs only when `CATALOG_AUDIT_JSON` names a `catalog_html_cache_vN.json`.
@Suite("Stacked program audit")
struct StackedProgramAuditTests {
    private static let path = ProcessInfo.processInfo.environment["CATALOG_AUDIT_JSON"]

    private struct Pick {
        var id: String
        var concentration: String?
        init(_ id: String, _ concentration: String? = nil) { self.id = id; self.concentration = concentration }
        var label: String { concentration.map { "\(id)[\($0)]" } ?? id }
    }

    private static let primaries: [Pick] = [
        Pick("psychology-ba"), Pick("psychology-bs"),
        Pick("art-ba", "art-education"), Pick("art-bs", "art-education"), Pick("art-bfa", "painting"),
        Pick("art-bfa", "painting-art-education"),
        Pick("computer-science-bs")
    ]
    private static let extras: [[Pick]] = [
        [Pick("honors-interdisciplinary-studies-minor")],
        [Pick("honors-interdisciplinary-studies-minor", "honors-capstone")],
        [Pick("art-minor")],
        [Pick("art-history-minor")],
        [Pick("psychology-ba")], [Pick("psychology-bs")],
        [Pick("art-ba", "art-education")], [Pick("art-bs", "art-education")], [Pick("art-bfa", "painting")],
        [Pick("art-bfa", "photography")], [Pick("art-bfa", "photography-art-education")],
        [Pick("art-minor"), Pick("honors-interdisciplinary-studies-minor", "honors-eportfolio")],
        [Pick("psychology-bs"), Pick("art-minor"), Pick("honors-interdisciplinary-studies-minor")],
        [Pick("art-bfa", "ceramics"), Pick("psychology-ba"), Pick("honors-interdisciplinary-studies-minor", "honors-capstone")],
        [Pick("art-minor"), Pick("art-history-minor"), Pick("honors-interdisciplinary-studies-minor")]
    ]

    @MainActor private static func loadCatalog() throws -> Catalog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Catalog.self, from: Data(contentsOf: URL(fileURLWithPath: try #require(path))))
        var catalog = ArtConcentrationPolicy.applying(to: PsychologyCoursework.applying(
            to: HonorsCoursework.applying(to: CatalogRepository.applyingCurrentGenEdCredits(to: decoded))
        )).resolvingElectivePools()
        let overlayURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Data/prereq_coreq_overrides.json")
        catalog.prereqRuleOverlay = CatalogRepository().optionalPrereqRuleOverlay(from: overlayURL).overlay
        return catalog
    }

    @MainActor @Test(.enabled(if: path != nil))
    func psychologyArtAndHonorsStack() async throws {
        let catalog = try Self.loadCatalog()
        for primary in Self.primaries {
            for extras in [[]] + Self.extras where !extras.contains(where: { $0.id == primary.id }) {
                let label = ([primary.label] + extras.map(\.label)).joined(separator: " + ")
                if let only = ProcessInfo.processInfo.environment["STACK_AUDIT_DETAIL"], only != label { continue }
                let store = PlanStore.temporary()
                store.catalog = catalog
                store.selectProgram(try #require(catalog.programsByID[primary.id], "\(primary.id) missing"))
                store.selectConcentration(id: primary.concentration)
                for extra in extras {
                    store.addMinor(try #require(catalog.programsByID[extra.id], "\(extra.id) missing"))
                    store.selectMinorConcentration(minorProgramID: extra.id, concentrationID: extra.concentration)
                }
                store.plan.planningStart = SemesterIdentity(year: 2026, term: .fall)
                if store.requiresForeignLanguage {
                    store.setForeignLanguage(ForeignLanguagePlan(subject: "SPAN", placement: .notSure))
                }
                await store.generateSchedules()

                if let error = store.errorMessage {
                    print("STACK\t\(label)\tERROR\t\(error)")
                    Issue.record("\(label): \(error)")
                    continue
                }
                let dropped = extras.count - store.selectedMinorPrograms().count
                #expect(dropped == 0, "\(label): \(dropped) added program(s) silently dropped")
                let pathway = try #require(store.activePathway, "\(label): no pathway")
                let ids = pathway.semesters.flatMap(\.courseIDs)
                #expect(Set(ids).count == ids.count, "\(label): a course is scheduled twice")
                let hours = AcademicCreditCalculator.projectedHours(
                    in: pathway.semesters, placeholders: pathway.placeholders, transferCredits: [], catalog: catalog
                )
                let warnings = store.warnings.filter { !$0.isOverridden && $0.kind != .unknownAvailability }
                let counts = Dictionary(grouping: warnings, by: \.kind).map { "\($0.key.rawValue)=\($0.value.count)" }.sorted()
                print("STACK\t\(label)\thours=\(Int(hours.rounded()))\tsemesters=\(pathway.semesters.count)\tdropped=\(dropped)\t\(counts.joined(separator: " "))")
                for warning in warnings where warning.kind != .heavyLoad && warning.kind != .lightLoad {
                    print("WARN\t\(label)\t\(warning.semester.displayName)\t\(warning.kind.rawValue)\t\(warning.courseID)\t\(warning.message)")
                }
                if ProcessInfo.processInfo.environment["STACK_AUDIT_DETAIL"] == label {
                    for semester in pathway.semesters {
                        let names = semester.courseIDs.map { id in pathway.placeholders[id].map { "<\($0.categoryName) \($0.credits)>" } ?? id }
                        print("PLAN\t\(semester.id.displayName)\t\(names.joined(separator: ", "))")
                    }
                }
                let progress = try #require(store.progress, "\(label): no progress")
                for row in progress.categories where row.id.contains("::") {
                    print("ROW\t\(label)\t\(row.name)\t\(row.completedCredits)/\(row.requiredCredits)")
                }
                #expect(warnings.filter { $0.kind == .missingPrerequisite || $0.kind == .missingCorequisite }.isEmpty,
                        "\(label): generated plan has prerequisite or corequisite warnings")
            }
        }
    }
}
