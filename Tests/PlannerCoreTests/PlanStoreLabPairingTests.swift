import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Plan store keeps lectures and labs together")
@MainActor
struct PlanStoreLabPairingTests {
    static let fall = SemesterIdentity(year: 2026, term: .fall)
    static let spring = SemesterIdentity(year: 2027, term: .spring)
    static let genEd = PathwayPlaceholder.id(categoryID: "gened-c3pp", optionIndex: 0)

    private func makeStore(fall: [String] = [], spring: [String] = []) -> (PlanStore, UndoManager) {
        let store = PlanStore()
        store.catalog = LabPairingTests.catalog()
        store.plan.pathways = [Pathway(
            id: "path",
            name: "Path",
            semesters: [SemesterPlan(id: Self.fall, courseIDs: fall), SemesterPlan(id: Self.spring, courseIDs: spring)],
            placeholders: [Self.genEd: PlaceholderSpec(categoryID: "gened-c3pp", categoryName: "Physical Principles", alternates: ["CHEM132", "PHYS140"], credits: 3)]
        )]
        store.plan.activePathwayID = "path"
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        return (store, undo)
    }

    private func items(_ store: PlanStore) -> [[String]] { store.plan.pathways[0].semesters.map(\.courseIDs) }

    @Test("adding a lecture adds its lab to the same semester")
    func addAddsLab() {
        let (store, _) = makeStore()
        store.moveCourse("BIO140", to: Self.fall)
        #expect(items(store) == [["BIO140", "BIO140L"], []])
        #expect(store.lastScheduleChange?.message == "Added BIO 140 and BIO 140L to Fall 2026")
    }

    @Test("moving a lecture moves its lab, in one undo step")
    func moveMovesPair() {
        let (store, undo) = makeStore(fall: ["BIO140", "BIO140L"])
        store.moveCourse("BIO140", to: Self.spring)
        #expect(items(store) == [[], ["BIO140", "BIO140L"]])
        #expect(store.lastScheduleChange?.message == "Moved BIO 140 and BIO 140L to Spring 2027")
        undo.undo()
        #expect(items(store) == [["BIO140", "BIO140L"], []])
    }

    @Test("choosing a lecture for a placeholder adds its lab choice")
    func resolveAddsLab() throws {
        let (store, _) = makeStore(fall: [Self.genEd])
        store.resolvePlaceholder(Self.genEd, with: "CHEM132")
        let lab = LabPairing.labPlaceholderID(forLecture: "CHEM132")
        #expect(items(store) == [["CHEM132", lab], []])
        #expect(store.plan.pathways[0].placeholders[lab]?.alternates == ["CHEM132L", "CHEM136L"])
    }

    @Test("removing a lecture removes its lab, and undo brings both back")
    func removeRemovesPair() {
        let (store, undo) = makeStore(fall: ["BIO140", "BIO140L", "PHYS140"])
        store.removeCourse("BIO140")
        #expect(items(store) == [["PHYS140"], []])
        undo.undo()
        #expect(items(store) == [["BIO140", "BIO140L", "PHYS140"], []])
    }

    @Test("removing a lecture clears the lab chosen from its lab placeholder")
    func removeClearsChosenLab() {
        let (store, _) = makeStore()
        store.moveCourse("CHEM132", to: Self.fall)
        let lab = LabPairing.labPlaceholderID(forLecture: "CHEM132")
        store.resolvePlaceholder(lab, with: "CHEM136L")
        #expect(items(store) == [["CHEM132", "CHEM136L"], []])
        store.removeCourse("CHEM132")
        #expect(items(store) == [[], []])
        #expect(store.plan.pathways[0].placeholders[lab] == nil)
        #expect(store.plan.pathways[0].resolvedPlaceholders[lab] == nil)
    }

    @Test("removing a lab leaves its lecture, flagged")
    func removeLabKeepsLecture() {
        let (store, _) = makeStore(fall: ["BIO140", "BIO140L"])
        store.removeCourse("BIO140L")
        #expect(items(store) == [["BIO140"], []])
        #expect(store.warnings.contains { $0.courseID == "BIO140" && $0.kind == .labNotPaired })
    }
}
