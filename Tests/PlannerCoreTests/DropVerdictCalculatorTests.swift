import Foundation
import Testing
@testable import PlannerCore

@Suite("Drop verdicts")
struct DropVerdictCalculatorTests {
    static let fall26 = SemesterIdentity(year: 2026, term: .fall)
    static let spring27 = SemesterIdentity(year: 2027, term: .spring)
    static let fall27 = SemesterIdentity(year: 2027, term: .fall)

    static let catalog = Catalog.fixture(
        courses: [
            Course(id: "MATH231", code: "MATH 231", title: "Calculus I", credits: 4, availability: [.fall, .spring], prerequisites: []),
            Course(id: "MATH232", code: "MATH 232", title: "Calculus II", credits: 4, availability: [.fall, .spring], prerequisites: ["MATH231"]),
            Course(id: "PHYS240", code: "PHYS 240", title: "University Physics I", credits: 4, availability: [.fall, .spring], prerequisites: ["MATH231"]),
            Course(id: "CS261", code: "CS 261", title: "Computer Systems I", credits: 3, availability: [.fall], prerequisites: []),
            Course(id: "CHEM131", code: "CHEM 131", title: "General Chemistry", credits: 3, availability: [.fall, .spring], prerequisites: []),
            Course(
                id: "CHEM140",
                code: "CHEM 140",
                title: "Chemistry Seminar",
                credits: 1,
                availability: [.fall, .spring],
                prerequisites: [],
                corequisiteExpr: .course("CHEM131")
            ),
            Course(id: "ELEC100", code: "ELEC 100", title: "Elective", credits: 3, availability: nil, prerequisites: [])
        ],
        program: Program.fixture(id: "p", title: "Program", requirements: [])
    )

    static let basePathway = Pathway(
        id: "base",
        name: "Base",
        semesters: [
            SemesterPlan(id: fall26, courseIDs: ["MATH231", "CS261", "CHEM131", "CHEM140"]),
            SemesterPlan(id: spring27, courseIDs: ["MATH232"]),
            SemesterPlan(id: fall27, courseIDs: [])
        ]
    )

    private func verdicts(
        moving id: String,
        in pathway: Pathway = Self.basePathway,
        overrides: [ConflictOverride] = [],
        completedAtStart: Set<String> = []
    ) -> [SemesterIdentity: DropVerdict] {
        DropVerdictCalculator(catalog: Self.catalog).verdicts(
            moving: id,
            in: pathway,
            overrides: overrides,
            completedAtStart: completedAtStart
        )
    }

    @Test("the item's own semester is always neutral")
    func originIsNeutral() {
        #expect(verdicts(moving: "MATH231")[Self.fall26] == .neutral)
    }

    @Test("moving a prereq after its dependent breaks the dependent")
    func dependentBreak() throws {
        let result = verdicts(moving: "MATH231")
        let later = try #require(result[Self.fall27])
        #expect(later.level == .blocking)
        #expect(later.affectedCourseIDs == ["MATH232"])
        #expect(later.headline == "Breaks 1 course")
        #expect(later.reason == "MATH 232 loses its prereq")
        #expect(result[Self.spring27]?.level == .blocking)
    }

    @Test("breaking several courses names the first and counts the rest")
    func pluralBreak() throws {
        let pathway = Pathway(
            id: "plural",
            name: "Plural",
            semesters: [
                SemesterPlan(id: Self.fall26, courseIDs: ["MATH231"]),
                SemesterPlan(id: Self.spring27, courseIDs: ["MATH232", "PHYS240"]),
                SemesterPlan(id: Self.fall27, courseIDs: [])
            ]
        )
        let later = try #require(verdicts(moving: "MATH231", in: pathway)[Self.fall27])
        #expect(later.headline == "Breaks 2 courses")
        #expect(later.reason == "MATH 232 and 1 more affected")
        #expect(later.affectedCourseIDs == ["MATH232", "PHYS240"])
    }

    @Test("moving a course before its own prereq is blocking with no affected courses")
    func ownPrereqBreak() throws {
        let earlier = try #require(verdicts(moving: "MATH232")[Self.fall26])
        #expect(earlier.level == .blocking)
        #expect(earlier.affectedCourseIDs.isEmpty)
        #expect(earlier.headline == "Missing prereq")
        #expect(earlier.reason == "Needs MATH 231.")
    }

    @Test("a term the course is not offered in is blocking")
    func notOffered() throws {
        let spring = try #require(verdicts(moving: "CS261")[Self.spring27])
        #expect(spring.level == .blocking)
        #expect(spring.headline == "Not offered in Spring")
        #expect(spring.reason == nil)
        #expect(verdicts(moving: "CS261")[Self.fall27]?.level == .clear)
    }

    @Test("splitting a coreq pair is a caution")
    func coreqSplit() throws {
        let later = try #require(verdicts(moving: "CHEM131")[Self.fall27])
        #expect(later.level == .caution)
        #expect(later.affectedCourseIDs == ["CHEM140"])
        #expect(later.reason == "CHEM 140 loses its coreq")
    }

    @Test("a move that clears an existing warning reports the fix")
    func fixes() throws {
        let broken = Pathway(
            id: "broken",
            name: "Broken",
            semesters: [
                SemesterPlan(id: Self.fall26, courseIDs: ["MATH232"]),
                SemesterPlan(id: Self.spring27, courseIDs: ["MATH231"]),
                SemesterPlan(id: Self.fall27, courseIDs: [])
            ]
        )
        let later = try #require(verdicts(moving: "MATH232", in: broken)[Self.fall27])
        #expect(later.level == .clear)
        #expect(later.fixedCount == 1)
        #expect(later.headline == "Fixes 1")
        #expect(later.newWarnings.isEmpty)
    }

    @Test("overridden warnings neither count as new nor as fixed")
    func overriddenIgnored() throws {
        let pathway = Pathway(
            id: "overridden",
            name: "Overridden",
            semesters: [
                SemesterPlan(id: Self.fall26, courseIDs: ["MATH232", "CS261"]),
                SemesterPlan(id: Self.spring27, courseIDs: []),
                SemesterPlan(id: Self.fall27, courseIDs: [])
            ]
        )
        let override = ConflictOverride(courseID: "MATH232", semester: Self.fall26, kind: .missingPrerequisite)
        let later = try #require(verdicts(moving: "CS261", in: pathway, overrides: [override])[Self.fall27])
        #expect(later == DropVerdict.neutral)
    }

    @Test("unknown availability is ignored")
    func unknownAvailabilityIgnored() throws {
        let pathway = Pathway(
            id: "unknown",
            name: "Unknown",
            semesters: [
                SemesterPlan(id: Self.fall26, courseIDs: ["ELEC100"]),
                SemesterPlan(id: Self.spring27, courseIDs: [])
            ]
        )
        #expect(verdicts(moving: "ELEC100", in: pathway)[Self.spring27] == .neutral)
    }

    @Test("AP and transfer credit satisfies prereqs")
    func transferCreditSatisfies() {
        let pathway = Pathway(
            id: "ap",
            name: "AP",
            semesters: [
                SemesterPlan(id: Self.fall26, courseIDs: []),
                SemesterPlan(id: Self.spring27, courseIDs: ["MATH232"])
            ]
        )
        #expect(verdicts(moving: "MATH232", in: pathway, completedAtStart: ["MATH231"])[Self.fall26] == .neutral)
    }

    @Test("a placeholder nothing depends on is neutral everywhere")
    func placeholdersNeutral() {
        let placeholderID = PathwayPlaceholder.id(categoryID: "gened", optionIndex: 0)
        var pathway = Self.basePathway
        pathway.semesters[0].courseIDs.append(placeholderID)
        let result = verdicts(moving: placeholderID, in: pathway)
        #expect(result.count == 3)
        #expect(result.values.allSatisfy { $0 == .neutral })
    }

    @Test("warning diff keys on course and kind, not semester")
    func warningDiffIgnoresSemester() {
        let before = [ConflictWarning(courseID: "MATH232", semester: Self.fall26, kind: .missingPrerequisite, message: "", isOverridden: false)]
        let after = [ConflictWarning(courseID: "MATH232", semester: Self.fall27, kind: .missingPrerequisite, message: "", isOverridden: false)]
        #expect(WarningDiff.added(before: before, after: after).isEmpty)
        #expect(WarningDiff.removedCount(before: before, after: after) == 0)
    }
}
