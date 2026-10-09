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

    static let f26 = SemesterIdentity(year: 2026, term: .fall)
    static let s27 = SemesterIdentity(year: 2027, term: .spring)
    static let f27 = SemesterIdentity(year: 2027, term: .fall)

    static func picking() -> RegenerationBoundarySelection {
        var selection = RegenerationBoundarySelection(pathway: Pathway(id: "p", name: "P", semesters: [
            .init(id: f26, courseIDs: []), .init(id: s27, courseIDs: []), .init(id: f27, courseIDs: [])
        ]))
        selection.selected = nil
        return selection
    }

    @Test func nothingPickedHasNoRolesAndPromptsForAClick() {
        let selection = Self.picking()
        #expect(selection.role(of: Self.s27) == nil)
        #expect(selection.prompt == "Click the last semester to keep")
    }

    @Test func anchorSplitsSemestersIntoKeptAndRebuilt() {
        var selection = Self.picking()
        selection.selected = Self.s27
        #expect(selection.role(of: Self.f26) == .kept)
        #expect(selection.role(of: Self.s27) == .anchor)
        #expect(selection.role(of: Self.f27) == .rebuilt)
        #expect(selection.prompt == "Keep through Spring 2027 · rebuild Fall 2027 onward")
    }

    @Test func firstAndLastSemestersCanAnchor() {
        var selection = Self.picking()
        selection.selected = Self.f26
        #expect(selection.role(of: Self.f26) == .anchor)
        #expect(selection.role(of: Self.s27) == .rebuilt)
        selection.selected = Self.f27
        #expect(selection.role(of: Self.f26) == .kept)
        #expect(selection.role(of: Self.f27) == .anchor)
        #expect(selection.prompt == "Keep through Fall 2027 · rebuild Spring 2028 onward")
    }

    @Test func semestersOutsideThePathwayHaveNoRole() {
        var selection = Self.picking()
        selection.selected = Self.s27
        #expect(selection.role(of: SemesterIdentity(year: 2040, term: .fall)) == nil)
    }
}

