import Foundation
import Testing
@testable import PlannerCore

@Suite("Requirement selection and slots")
struct RequirementSelectionTests {
    let c3: (String) -> Int = { _ in 3 }

    @Test func allRequiredGivesOneSlotPerCourse() {
        #expect(RequirementSelection.slots(choices: [["A"], ["B", "C"]], selection: .allRequired, credits: c3)
            == [["A"], ["B"], ["C"]])
    }

    @Test func chooseCoursesGivesNSlotsOfAllAlternatives() {
        #expect(RequirementSelection.slots(choices: [["A"], ["B"], ["C"], ["D"]], selection: .chooseCourses(3), credits: c3)
            == Array(repeating: ["A", "B", "C", "D"], count: 3))
    }

    @Test func chooseCreditsUsesLargestCourseCredits() {
        // Upper-Level Courses: 6 credits from 3-credit courses -> 2 slots
        #expect(RequirementSelection.slots(choices: [["A"], ["B"], ["C"]], selection: .chooseCredits(6), credits: c3)?.count == 2)
        #expect(RequirementSelection.slots(choices: [["A"]], selection: .chooseCredits(1), credits: c3)?.count == 1)
    }

    @Test func chooseGroupsGivesOneSlotPerPairPosition() {
        // Methodology Core: (210 & 211) or (212 & 213), choose 1
        #expect(RequirementSelection.slots(choices: [["P210", "P211"], ["P212", "P213"]], selection: .chooseGroups(1), credits: c3)
            == [["P210", "P212"], ["P211", "P213"]])
    }

    @Test func noChoicesGiveNoSlots() {
        // Psychology Electives: "Choose three credit hours", no course list
        #expect(RequirementSelection.slots(choices: [], selection: .chooseCredits(3), credits: c3) == [])
    }

    @Test func unknownKeepsLegacyOptions() {
        #expect(RequirementSelection.slots(choices: [["A"]], selection: .unknown, credits: c3) == nil)
    }

    @Test func legacyCategoryDecodes() throws {
        let json = #"{"id":"core","name":"Core","requiredCredits":6,"courseOptions":[["A"],["B"]],"verificationStatus":"verified"}"#
        let category = try JSONDecoder().decode(RequirementCategory.self, from: Data(json.utf8))
        #expect(category.selection == .unknown)
        #expect(category.choices.isEmpty && category.courseRemarks.isEmpty && category.catalogDescription == nil)
        #expect(category.courseOptions == [["A"], ["B"]])
    }

    @Test func newFieldsRoundTrip() throws {
        let category = RequirementCategory(
            id: "m", name: "Methodology Core", requiredCredits: 8, courseOptions: [],
            selection: .chooseGroups(1), choices: [["P210", "P211"]],
            catalogDescription: "Choose one of the following options:",
            courseRemarks: ["P402": ["Repeatable."]]
        )
        #expect(try JSONDecoder().decode(RequirementCategory.self, from: JSONEncoder().encode(category)) == category)
    }
}
