import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Placeholder dependency presentation")
@MainActor
struct PlaceholderDependencyPresentationTests {
    typealias F = PlaceholderPrerequisiteFixtures
    static let fall27 = SemesterIdentity(year: 2027, term: .fall)

    @Test func supportingChoiceIsLabeledWithItsDependent() {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let presentation = PlaceholderDependencyPresentation(
            supports: ["A": Set([f.requests[0].key])], coursesByID: f.catalog.coursesByID)
        #expect(presentation.summary == "Prerequisite choice needed")
        #expect(presentation.labelsByCourseID["A"] == "Supports MATH 410 in Spring 2027")
        #expect(presentation.labelsByCourseID["B"] == nil)
        #expect(presentation.detail == "Choose MATH 300 here to support MATH 410 in Spring 2027.")
    }

    @Test func dependentsInSeveralSemestersReadInScheduleOrder() {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A"), .course("A")])
        let spring = ConditionalDependencyKey(courseID: "D0", semester: F.spring, kind: .prerequisite)
        let fall = ConditionalDependencyKey(courseID: "D1", semester: Self.fall27, kind: .prerequisite)
        let presentation = PlaceholderDependencyPresentation(
            supports: ["A": [fall, spring], "B": [spring]], coursesByID: f.catalog.coursesByID)
        #expect(presentation.labelsByCourseID["A"] == "Supports MATH 410 in Spring 2027 and MATH 430 in Fall 2027")
        #expect(presentation.labelsByCourseID["B"] == "Supports MATH 410 in Spring 2027")
        #expect(presentation.detail == "Choose MATH 300 here to support MATH 410 in Spring 2027 and MATH 430 in Fall 2027. Choose MATH 336 here to support MATH 410 in Spring 2027.")
    }

    @Test func unmarkedChoicesStayEligibleAndNothingIsChosenForTheStudent() {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let spec = f.input.pathway.placeholders[F.slotID(0)]!
        let eligible = PlaceholderCoursePickerPolicy.eligibleCourses(for: spec, catalog: f.catalog)
        #expect(eligible.map(\.id) == ["A", "B"])
        #expect(CoursePickerIndex(courses: eligible).entries(matching: "336").map(\.course.id) == ["B"])

        var selected: [String] = []
        _ = CoursePickerSheet(
            title: "Choose a Course",
            courses: eligible,
            dependencyPresentation: PlaceholderDependencyPresentation(supports: ["A": Set([f.requests[0].key])], coursesByID: f.catalog.coursesByID),
            onSelect: { selected.append($0.id) }
        )
        #expect(selected.isEmpty)
    }

    @Test func openPickerRevisionUpdatesSupportingLabels() throws {
        let f = F.makeInput(slots: [["A", "B"]], dependencies: [.course("A")])
        let store = PlanStore.temporary()
        store.catalog = f.catalog
        var pathway = f.input.pathway
        pathway.semesters.append(SemesterPlan(id: Self.fall27, courseIDs: []))
        store.plan.pathways = [pathway]
        store.plan.activePathwayID = pathway.id

        let before = try #require(store.placeholderDependencyPresentation(for: F.slotID(0)))
        #expect(before.labelsByCourseID["A"] == "Supports MATH 410 in Spring 2027")

        store.moveCourse("D0", to: Self.fall27)
        let after = try #require(store.placeholderDependencyPresentation(for: F.slotID(0)))
        #expect(after.labelsByCourseID["A"] == "Supports MATH 410 in Fall 2027")

        store.resolvePlaceholder(F.slotID(0), with: "A")
        #expect(store.placeholderDependencyPresentation(for: F.slotID(0)) == nil)
    }
}
