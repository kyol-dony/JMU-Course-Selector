import Foundation
import Testing
@testable import PlannerCore

@Suite("Fix suggestions")
struct FixSuggesterTests {
    static let s = [
        SemesterIdentity(year: 2026, term: .fall),
        SemesterIdentity(year: 2027, term: .spring),
        SemesterIdentity(year: 2027, term: .fall),
        SemesterIdentity(year: 2028, term: .spring),
        SemesterIdentity(year: 2028, term: .fall)
    ]

    static let catalog = Catalog.fixture(
        courses: [
            Course(id: "MATH231", code: "MATH 231", title: "Calculus I", credits: 4, availability: [.fall, .spring], prerequisites: []),
            Course(id: "MATH232", code: "MATH 232", title: "Calculus II", credits: 4, availability: [.fall, .spring], prerequisites: ["MATH231"]),
            Course(id: "CS261", code: "CS 261", title: "Computer Systems I", credits: 3, availability: [.fall], prerequisites: []),
            Course(id: "CS361", code: "CS 361", title: "Computer Systems II", credits: 3, availability: [.fall, .spring], prerequisites: ["CS261"])
        ],
        program: Program.fixture(id: "p", title: "P", requirements: [])
    )

    private func suggestions(_ courseID: String, _ kind: ConflictKind, in pathway: Pathway) throws -> [FixSuggestion] {
        let warning = try #require(
            ConflictDetector(catalog: Self.catalog).warnings(for: pathway, overrides: [])
                .first { $0.courseID == courseID && $0.kind == kind }
        )
        let verdicts = DropVerdictCalculator(catalog: Self.catalog).verdicts(moving: courseID, in: pathway, overrides: [])
        return FixSuggester(catalog: Self.catalog).suggestions(for: warning, verdicts: verdicts, in: pathway)
    }

    @Test("suggests the two nearest semesters that clear the warning")
    func nearestTwo() throws {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: Self.s[0], courseIDs: ["MATH232"]),
            SemesterPlan(id: Self.s[1], courseIDs: ["MATH231"]),
            SemesterPlan(id: Self.s[2], courseIDs: []),
            SemesterPlan(id: Self.s[3], courseIDs: []),
            SemesterPlan(id: Self.s[4], courseIDs: [])
        ])
        #expect(try suggestions("MATH232", .missingPrerequisite, in: pathway) == [
            .move(courseID: "MATH232", to: Self.s[2]),
            .move(courseID: "MATH232", to: Self.s[3])
        ])
    }

    @Test("equal distances prefer the earlier semester")
    func tiesPreferEarlier() throws {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: Self.s[0], courseIDs: []),
            SemesterPlan(id: Self.s[1], courseIDs: ["CS261"]),
            SemesterPlan(id: Self.s[2], courseIDs: []),
            SemesterPlan(id: Self.s[3], courseIDs: []),
            SemesterPlan(id: Self.s[4], courseIDs: [])
        ])
        #expect(try suggestions("CS261", .unavailableSemester, in: pathway) == [
            .move(courseID: "CS261", to: Self.s[0]),
            .move(courseID: "CS261", to: Self.s[2])
        ])
    }

    @Test("skips semesters where the move would break another course")
    func skipsNewMustFix() throws {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: Self.s[1], courseIDs: ["CS261"]),
            SemesterPlan(id: Self.s[2], courseIDs: ["CS361"]),
            SemesterPlan(id: Self.s[3], courseIDs: []),
            SemesterPlan(id: Self.s[4], courseIDs: [])
        ])
        #expect(try suggestions("CS261", .unavailableSemester, in: pathway).isEmpty)
    }

    @Test("points at the prerequisite scheduled too late when no move helps")
    func moveEarlier() throws {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: Self.s[0], courseIDs: ["MATH232"]),
            SemesterPlan(id: Self.s[1], courseIDs: ["MATH231"])
        ])
        #expect(try suggestions("MATH232", .missingPrerequisite, in: pathway) == [.moveEarlier(courseID: "MATH231")])
    }

    @Test("semester-level and hidden warnings get no suggestions")
    func noSuggestionsForLoadOrHidden() {
        let pathway = Pathway(id: "p", name: "P", semesters: [SemesterPlan(id: Self.s[0], courseIDs: [])])
        let load = ConflictWarning(courseID: ConflictWarning.semesterSubjectID, semester: Self.s[0], kind: .heavyLoad, summary: "", detail: "", isOverridden: false)
        let hidden = ConflictWarning(courseID: "X", semester: Self.s[0], kind: .unknownAvailability, summary: "", detail: "", isOverridden: false)
        let suggester = FixSuggester(catalog: Self.catalog)
        #expect(suggester.suggestions(for: load, verdicts: [:], in: pathway).isEmpty)
        #expect(suggester.suggestions(for: hidden, verdicts: [:], in: pathway).isEmpty)
    }

    @Test("verdicts record which warnings a move resolves")
    func resolvedKeys() throws {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: Self.s[0], courseIDs: ["MATH232"]),
            SemesterPlan(id: Self.s[1], courseIDs: ["MATH231"]),
            SemesterPlan(id: Self.s[2], courseIDs: [])
        ])
        let verdict = try #require(DropVerdictCalculator(catalog: Self.catalog).verdicts(moving: "MATH232", in: pathway, overrides: [])[Self.s[2]])
        let warning = try #require(ConflictDetector(catalog: Self.catalog).warnings(for: pathway, overrides: []).first)
        #expect(verdict.resolvedKeys == [WarningKey(warning)])
        #expect(verdict.fixedCount == 1)
    }
}
