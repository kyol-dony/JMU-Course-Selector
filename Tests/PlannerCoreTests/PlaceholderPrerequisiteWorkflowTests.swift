import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

/// Strict generation through an unresolved slot, followed through warnings,
/// choices, undo, progress, export, saving and anchored regeneration.
@Suite("Placeholder prerequisite workflow")
@MainActor
struct PlaceholderPrerequisiteWorkflowTests {
    typealias F = PlaceholderPrerequisiteFixtures

    private func generated() throws -> (catalog: Catalog, path: Pathway) {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let path = try #require(try ScheduleGenerator(catalog: f.catalog, strictPrereqs: true)
            .generatePathways(for: F.programID, workload: .light, transferCredits: [], starting: F.fall).first)
        return (f.catalog, path)
    }

    private func store(_ catalog: Catalog, _ path: Pathway) -> (PlanStore, UndoManager) {
        let store = PlanStore.temporary()
        store.catalog = catalog
        store.plan.programID = F.programID
        store.plan.pathways = [path]
        store.plan.activePathwayID = path.id
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        return (store, undo)
    }

    private func choiceCredits(_ store: PlanStore) -> Double? {
        store.progress?.categories.first { $0.id == F.categoryID }?.completedCredits
    }

    @Test func generatedPlanExplainsTheChoiceWithoutChoosingIt() throws {
        let (catalog, path) = try generated()
        let warnings = ConflictDetector(catalog: catalog).warnings(for: path, overrides: [])
        #expect(warnings.contains { $0.courseID == F.slotID(0) && $0.kind == .pendingPrerequisiteChoice })
        #expect(!warnings.contains { $0.courseID == "D0" && $0.kind == .missingPrerequisite })
        let analysis = try #require(ConflictDetector(catalog: catalog).placeholderPrerequisiteAnalysis(for: path))
        #expect(analysis.supportsByPlaceholder[F.slotID(0)]?.keys.sorted() == ["A"])

        // The supporting option appears nowhere as real work.
        #expect(!path.semesters.flatMap(\.courseIDs).contains("A"))
        #expect(path.resolvedPlaceholders.isEmpty)
        let requirement = try #require(catalog.programsByID[F.programID]?.requirements.first { $0.id == F.categoryID })
        let scheduled = Dictionary(path.semesters.flatMap { semester in semester.courseIDs.map { ($0, semester.id.displayName) } }, uniquingKeysWith: { first, _ in first })
        #expect(ProgressContributionBuilder.contributions(for: requirement, transferCredits: [], scheduled: scheduled, coursesByID: catalog.coursesByID).isEmpty)
        #expect(!ExportService().printableSummary(planName: "Plan", pathway: path, catalog: catalog).contains("MATH 300"))
    }

    @Test func choosingKeepsAccountingHonestAndUndoRestoresTheChoice() throws {
        let (catalog, path) = try generated()
        let (store, undo) = store(catalog, path)
        let slotSemester = path.semesters[0]
        // Before a choice: no completion, the slot's reserved hours only.
        #expect(choiceCredits(store) == 0)
        #expect(AcademicCreditCalculator.projectedHours(in: [slotSemester], placeholders: path.placeholders, transferCredits: [], catalog: catalog) == 3)

        store.resolvePlaceholder(F.slotID(0), with: "B")
        #expect(store.plan.pathways[0].semesters.map(\.courseIDs) == [["B"], ["D0"]])
        #expect(store.warnings.contains { $0.courseID == "D0" && $0.kind == .missingPrerequisite })
        #expect(choiceCredits(store) == 3)

        undo.undo()
        #expect(choiceCredits(store) == 0)
        #expect(store.warnings.contains { $0.kind == .pendingPrerequisiteChoice })

        store.resolvePlaceholder(F.slotID(0), with: "A")
        #expect(!store.warnings.contains { $0.courseID == "D0" && $0.kind == .missingPrerequisite })
        #expect(!store.warnings.contains { $0.kind == .pendingPrerequisiteChoice })
        #expect(choiceCredits(store) == 3)
    }

    @Test func savedPathwayCarriesNoAssumedChoice() throws {
        let (catalog, path) = try generated()
        let restored = try JSONDecoder().decode(Pathway.self, from: JSONEncoder().encode(path))
        #expect(restored == path)
        #expect(restored.resolvedPlaceholders.isEmpty)
        #expect(!restored.semesters.flatMap(\.courseIDs).contains("A"))
        let detector = ConflictDetector(catalog: catalog)
        #expect(detector.placeholderPrerequisiteAnalysis(for: restored) == detector.placeholderPrerequisiteAnalysis(for: path))
        let progress = try ProgressCalculator(catalog: catalog).progress(programID: F.programID, pathway: restored, transferCredits: [])
        #expect(progress.categories.first { $0.id == F.categoryID }?.completedCredits == 0)
    }

    @Test func anchoredRegenerationKeepsTheUnresolvedSlot() throws {
        let (catalog, path) = try generated()
        let regenerated = try ScheduleGenerator(catalog: catalog, strictPrereqs: true).regeneratePathway(
            from: path, through: F.fall, for: F.programID, strategy: .balanced, workload: .light, transferCredits: []
        )
        #expect(regenerated.semesters.first == path.semesters.first)
        #expect(regenerated.placeholders[F.slotID(0)] == path.placeholders[F.slotID(0)])
        #expect(regenerated.resolvedPlaceholders.isEmpty)
        #expect(regenerated.semesters.dropFirst().flatMap(\.courseIDs).contains("D0"))
        let warnings = ConflictDetector(catalog: catalog).warnings(for: regenerated, overrides: [])
        #expect(warnings.contains { $0.courseID == F.slotID(0) && $0.kind == .pendingPrerequisiteChoice })
        #expect(!warnings.contains { $0.kind == .missingPrerequisite })
    }
}
