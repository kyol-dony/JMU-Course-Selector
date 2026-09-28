import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Plan store add and delete semesters")
@MainActor
struct PlanStoreSemesterTests {
    static let f26 = SemesterIdentity(year: 2026, term: .fall)
    static let s27 = SemesterIdentity(year: 2027, term: .spring)
    static let f27 = SemesterIdentity(year: 2027, term: .fall)
    static let s28 = SemesterIdentity(year: 2028, term: .spring)

    static let placeholderID = PathwayPlaceholder.id(categoryID: "gened", optionIndex: 0)

    private func makeStore() -> (PlanStore, UndoManager) {
        let store = PlanStore()
        store.catalog = Catalog.fixture(
            courses: [Course(id: "CS149", code: "CS 149", title: "Intro", credits: 3, availability: [.fall, .spring], prerequisites: [])],
            program: Program.fixture(id: "p", title: "P", requirements: [])
        )
        store.plan.pathways = [
            Pathway(
                id: "path",
                name: "Path",
                semesters: [
                    SemesterPlan(id: Self.f26, courseIDs: ["CS149"]),
                    SemesterPlan(id: Self.s27, courseIDs: []),
                    SemesterPlan(id: Self.f27, courseIDs: [Self.placeholderID])
                ],
                placeholders: [Self.placeholderID: PlaceholderSpec(categoryID: "gened", categoryName: "Gen Ed", alternates: [], credits: 3)]
            )
        ]
        store.plan.activePathwayID = "path"
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        return (store, undo)
    }

    private func ids(_ store: PlanStore) -> [SemesterIdentity] {
        store.plan.pathways[0].semesters.map(\.id)
    }

    @Test("adding a semester keeps calendar order and is undoable")
    func addSemester() {
        let (store, undo) = makeStore()
        let original = store.plan.pathways[0]
        store.addSemester(Self.s28)
        #expect(ids(store) == [Self.f26, Self.s27, Self.f27, Self.s28])
        #expect(store.plan.pathways[0].semesters.last?.courseIDs == [])
        #expect(undo.undoActionName == "Add Spring 2028")
        #expect(store.lastScheduleChange?.message == "Added Spring 2028")
        undo.undo()
        #expect(store.plan.pathways[0] == original)
        undo.redo()
        #expect(ids(store) == [Self.f26, Self.s27, Self.f27, Self.s28])
    }

    @Test("adding a semester into a gap slots it in order")
    func addIntoGap() {
        let (store, _) = makeStore()
        store.deleteSemester(Self.s27)
        store.addSemester(Self.s27)
        #expect(ids(store) == [Self.f26, Self.s27, Self.f27])
    }

    @Test("adding a semester that already exists does nothing")
    func addExisting() {
        let (store, undo) = makeStore()
        let original = store.plan.pathways[0]
        store.addSemester(Self.s27)
        #expect(store.plan.pathways[0] == original)
        #expect(!undo.canUndo)
    }

    @Test("deleting an empty semester is undoable")
    func deleteEmpty() {
        let (store, undo) = makeStore()
        let original = store.plan.pathways[0]
        store.deleteSemester(Self.s27)
        #expect(ids(store) == [Self.f26, Self.f27])
        #expect(undo.undoActionName == "Delete Spring 2027")
        #expect(store.lastScheduleChange?.message == "Deleted Spring 2027")
        undo.undo()
        #expect(store.plan.pathways[0] == original)
    }

    @Test("semesters with courses or placeholders cannot be deleted")
    func deleteNonEmpty() {
        let (store, undo) = makeStore()
        let original = store.plan.pathways[0]
        store.deleteSemester(Self.f26)
        store.deleteSemester(Self.f27)
        #expect(store.plan.pathways[0] == original)
        #expect(!undo.canUndo)
    }

    @Test("the only semester cannot be deleted")
    func deleteOnly() {
        let (store, _) = makeStore()
        store.plan.pathways[0].semesters = [SemesterPlan(id: Self.s27, courseIDs: [])]
        store.deleteSemester(Self.s27)
        #expect(ids(store) == [Self.s27])
    }

    @Test("deleting a semester drops its kept load warnings only")
    func deleteClearsLoadOverrides() {
        let (store, undo) = makeStore()
        let spring = ConflictOverride(courseID: ConflictWarning.semesterSubjectID, semester: Self.s27, kind: .lightLoad)
        let fall = ConflictOverride(courseID: ConflictWarning.semesterSubjectID, semester: Self.f26, kind: .lightLoad)
        store.plan.overrides = [spring, fall]
        store.deleteSemester(Self.s27)
        #expect(store.plan.overrides == [fall])
        undo.undo()
        #expect(Set(store.plan.overrides.map(\.semester)) == [Self.s27, Self.f26])
    }

    @Test("empty and deletable semesters are reported")
    func canDelete() {
        let (store, _) = makeStore()
        #expect(store.canDeleteSemester(Self.s27))
        #expect(!store.canDeleteSemester(Self.f26))
        #expect(!store.canDeleteSemester(Self.f27))
    }
}
