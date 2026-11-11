import Foundation
import Testing
@testable import PlannerCore

@Suite("Psychology prose elective")
struct PsychologyCourseworkTests {
    @Test func pendingThreeCreditsScheduleAndNeverAutoComplete() throws {
        let core = RequirementCategory(id: "core", name: "Core", requiredCredits: 3, courseOptions: [["PSYC101"]])
        var elective = RequirementCategory(
            id: "psychology-electives",
            name: "Psychology Electives",
            requiredCredits: 3,
            courseOptions: []
        )
        elective = PsychologyCoursework.applying(to: elective)
        let program = Program.fixture(
            id: PsychologyCoursework.programID,
            title: "Psychology, B.S.",
            requirements: [core, elective]
        )
        let catalog = Catalog.fixture(courses: [
            Course(id: "PSYC101", code: "PSYC 101", title: "General Psychology", credits: 3, availability: nil, prerequisites: []),
            Course(id: "PSYC200", code: "PSYC 200", title: "Unverified elective", credits: 3, availability: nil, prerequisites: [])
        ], program: program)
        let earned = [TransferCredit(sourceDescription: "Unverified elective", courseIDs: ["PSYC200"], credits: 3)]
        let pathway = try #require(ScheduleGenerator(catalog: catalog).generatePathways(
            for: program.id,
            workload: .standard,
            transferCredits: earned
        ).first)
        let planned = Set(pathway.semesters.flatMap(\.courseIDs))
        let pending = pathway.placeholders.filter { planned.contains($0.key) && $0.value.approval == .psychologyElective }
        #expect(pending.count == 1)
        #expect(pending.values.first?.credits == 3)
        #expect(PlaceholderCourseDomain.eligibleCourseIDs(for: try #require(pending.values.first), catalog: catalog).isEmpty)

        let progress = try ProgressCalculator(catalog: catalog).progress(
            programID: program.id,
            pathway: pathway,
            transferCredits: earned
        )
        let row = try #require(progress.categories.first { $0.id == elective.id })
        #expect(row.completedCredits == 0)
        #expect(row.requiredCredits == 3)
    }
}
