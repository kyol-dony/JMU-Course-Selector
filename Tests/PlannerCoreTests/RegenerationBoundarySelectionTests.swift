import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite struct RegenerationBoundarySelectionTests {
    @Test func choicesAreChronologicalAndDefaultToFirst() {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            .init(id: .init(year: 2027, term: .fall), courseIDs: []),
            .init(id: .init(year: 2026, term: .fall), courseIDs: []),
            .init(id: .init(year: 2027, term: .spring), courseIDs: [])
        ])
        var selection = RegenerationBoundarySelection(pathway: pathway)
        #expect(selection.semesters == [.init(year: 2026, term: .fall), .init(year: 2027, term: .spring), .init(year: 2027, term: .fall)])
        #expect(selection.selected == .init(year: 2026, term: .fall))
        selection.selected = .init(year: 2027, term: .fall)
        #expect(selection.summary == "Keep everything through Fall 2027. Rebuild Spring 2028 onward.")
        #expect(selection.canConfirm)
    }
    @Test func emptyAndInvalidSelectionsCannotConfirm() {
        var empty = RegenerationBoundarySelection(pathway: .init(id: "p", name: "P", semesters: []))
        #expect(empty.selected == nil && !empty.canConfirm)
        empty.selected = .init(year: 2026, term: .fall)
        #expect(!empty.canConfirm)
        var selection = RegenerationBoundarySelection(pathway: AnchoredRegenerationFixtures.pathway())
        selection.selected = nil
        #expect(!selection.canConfirm)
        selection.selected = .init(year: 2040, term: .fall)
        #expect(!selection.canConfirm)
    }
}
