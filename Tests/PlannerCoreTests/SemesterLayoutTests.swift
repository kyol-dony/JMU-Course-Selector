import Foundation
import Testing
@testable import PlannerCore

@Suite("Semester gaps and next term")
struct SemesterLayoutTests {
    static let f26 = SemesterIdentity(year: 2026, term: .fall)
    static let s27 = SemesterIdentity(year: 2027, term: .spring)
    static let f27 = SemesterIdentity(year: 2027, term: .fall)
    static let s28 = SemesterIdentity(year: 2028, term: .spring)
    static let f28 = SemesterIdentity(year: 2028, term: .fall)

    private func pathway(_ ids: [SemesterIdentity]) -> Pathway {
        Pathway(id: "p", name: "P", semesters: ids.map { SemesterPlan(id: $0, courseIDs: []) })
    }

    @Test("the next semester follows the last one")
    func nextSemester() {
        #expect(pathway([Self.f26]).nextSemester == Self.s27)
        #expect(pathway([Self.f26, Self.s27]).nextSemester == Self.f27)
        #expect(pathway([Self.s27, Self.f26]).nextSemester == Self.f27)
    }

    @Test("an empty pathway starts in Fall 2026, like generated plans")
    func nextSemesterWhenEmpty() {
        #expect(pathway([]).nextSemester == Self.f26)
    }

    @Test("gaps list each missing term after the semester they follow")
    func gaps() {
        #expect(pathway([Self.f26, Self.f27, Self.f28]).semesterGaps == [
            SemesterGap(after: Self.f26, missing: [Self.s27]),
            SemesterGap(after: Self.f27, missing: [Self.s28])
        ])
    }

    @Test("a gap can span several terms")
    func multiTermGap() {
        #expect(pathway([Self.s28, Self.f26]).semesterGaps == [
            SemesterGap(after: Self.f26, missing: [Self.s27, Self.f27])
        ])
    }

    @Test("consecutive semesters have no gaps")
    func noGaps() {
        #expect(pathway([Self.f26, Self.s27, Self.f27]).semesterGaps.isEmpty)
        #expect(pathway([]).semesterGaps.isEmpty)
    }
}
