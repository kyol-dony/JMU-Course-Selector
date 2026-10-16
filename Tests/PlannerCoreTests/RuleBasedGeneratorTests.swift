import Foundation
import Testing
@testable import PlannerCore

/// The generator schedules each requirement by its parsed selection rule,
/// not by keywords in its name; unknown rules keep the keyword behavior.
@Suite("Rule-based schedule generation")
struct RuleBasedGeneratorTests {
    private static let courseIDs = ["A", "B", "C", "D", "E", "F", "X", "Y", "P1", "P2", "P210", "P211", "P212", "P213"]

    private func requirement(
        _ name: String,
        _ selection: RequirementSelection,
        _ choices: [[String]],
        credits: Int
    ) -> RequirementCategory {
        RequirementCategory(
            id: name.lowercased().replacingOccurrences(of: " ", with: "-"),
            name: name,
            requiredCredits: credits,
            courseOptions: RequirementSelection.slots(choices: choices, selection: selection, credits: { _ in 3 }) ?? choices,
            selection: selection,
            choices: choices
        )
    }

    private func scheduled(_ requirements: [RequirementCategory], transfer: [String] = []) throws -> [String] {
        let catalog = Catalog.fixture(
            courses: Self.courseIDs.map {
                Course(id: $0, code: "TEST \($0)", title: "Course \($0)", credits: 3, availability: [.fall, .spring], prerequisites: [])
            },
            program: Program.fixture(id: "rules", title: "Rules, B.S.", requirements: requirements)
        )
        let credits = transfer.isEmpty ? [] : [TransferCredit(sourceDescription: "Transfer", courseIDs: transfer, credits: Double(3 * transfer.count))]
        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "rules",
            workload: .standard,
            transferCredits: credits,
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)
        return pathway.semesters.flatMap { $0.courseIDs }
    }

    @Test func renamedChoiceIsStillCapped() throws {
        #expect(try scheduled([requirement("SS Content Core", .chooseCourses(3), [["A"], ["B"], ["C"], ["D"]], credits: 9)]).count == 3)
    }

    @Test func chooseCoursesIsCountedNotCappedByLowCredits() throws {
        // Biology: "Choose at least two laboratory courses: 2-8" reads 2 credits
        #expect(try scheduled([requirement("Labs", .chooseCourses(2), [["A"], ["B"], ["C"]], credits: 2)]).count == 2)
    }

    @Test func allRequiredSchedulesEverything() throws {
        #expect(Set(try scheduled([requirement("Biopsychology", .allRequired, [["A"], ["B"]], credits: 6)])) == ["A", "B"])
    }

    @Test func chooseCreditsMakesTwoSlotsForSixCredits() throws {
        #expect(try scheduled([requirement("Upper-Level Courses", .chooseCredits(6), [["A"], ["B"], ["C"], ["D"], ["E"], ["F"]], credits: 6)]).count == 2)
    }

    @Test func groupsScheduleWholePairs() throws {
        let ids = Set(try scheduled([requirement("Methodology Core", .chooseGroups(1), [["P210", "P211"], ["P212", "P213"]], credits: 6)]))
        #expect(ids == ["P210", "P211"])
    }

    @Test func groupsPreferAPairAlreadyStarted() throws {
        let ids = Set(try scheduled(
            [requirement("Methodology Core", .chooseGroups(1), [["P210", "P211"], ["P212", "P213"]], credits: 6)],
            transfer: ["P212"]
        ))
        #expect(ids == ["P213"])
    }

    @Test func mixedGroupsNeverSplitPair() throws {
        let ids = Set(try scheduled([requirement("Mixed", .chooseGroups(2), [["X"], ["P1", "P2"], ["Y"]], credits: 9)]))
        #expect(ids.contains("P1") == ids.contains("P2"))
    }

    @Test func unknownRuleKeepsKeywordBehavior() throws {
        // selection defaults to .unknown: today's "choose" / "elective" keywords still cap these at 2 of 3
        let legacy = RequirementCategory(id: "c", name: "Choose two of the following:", requiredCredits: 6, courseOptions: [["A"], ["B"], ["C"]])
        let elective = RequirementCategory(id: "c", name: "Major Electives", requiredCredits: 6, courseOptions: [["A"], ["B"], ["C"]])
        #expect(try scheduled([legacy]).count == 2)
        #expect(try scheduled([elective]).count == 2)
    }

    @Test func unknownRuleKeepsKeywordsAfterRenaming() throws {
        // Psychology B.A.: renamed from "Earn ..." to its header; the ID still
        // carries the old instruction text and its keywords
        let renamed = RequirementCategory(id: "choose-two-of-the-following", name: "Upper-Level Courses", requiredCredits: 6, courseOptions: [["A"], ["B"], ["C"]])
        #expect(try scheduled([renamed]).count == 2)
    }

    @Test func requirementsWithoutListsStillCountTowardTheTopUp() throws {
        // Individualized Study: 18 listed credits plus 45 credits with no list
        let listed = requirement("Core", .allRequired, [["A"], ["B"], ["C"], ["D"], ["E"], ["F"]], credits: 18)
        let unlisted = RequirementCategory(id: "major-electives", name: "Major Electives", requiredCredits: 45, courseOptions: [], selection: .chooseCredits(45))
        let ids = try scheduled([listed, unlisted])
        #expect(ids.filter(PathwayPlaceholder.isPlaceholder).count >= 30)
    }
}
