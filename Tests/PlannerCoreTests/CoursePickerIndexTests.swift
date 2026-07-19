import PlannerCore
import Testing
@testable import JMUCoursePlanner

struct CoursePickerIndexTests {
    @Test("course picker uses natural course-code order")
    func naturalCourseCodeOrder() {
        let index = CoursePickerIndex(courses: [
            course(id: "cs-10", code: "CS 10", title: "Later"),
            course(id: "cs-2", code: "CS 2", title: "Earlier")
        ])

        #expect(index.entries.map(\.course.id) == ["cs-2", "cs-10"])
    }

    @Test("course picker matches all search terms across code and title")
    func multiTermSearch() {
        let index = CoursePickerIndex(courses: [
            course(id: "cis-330", code: "CIS 330", title: "Database Design"),
            course(id: "cs-330", code: "CS 330", title: "Database Systems"),
            course(id: "cis-331", code: "CIS 331", title: "Network Design")
        ])

        let results = index.entries(matching: "design CIS")

        #expect(results.map(\.course.id) == ["cis-330", "cis-331"])
    }

    @Test("empty search returns every indexed course")
    func emptySearchReturnsAllCourses() {
        let courses = (0..<2_000).map { offset in
            course(id: "course-\(offset)", code: "SUBJ \(offset)", title: "Course \(offset)")
        }
        let index = CoursePickerIndex(courses: courses)

        #expect(index.entries(matching: "").count == courses.count)
        #expect(index.entries(matching: "SUBJ 1999").map(\.course.id) == ["course-1999"])
    }

    private func course(id: String, code: String, title: String) -> Course {
        Course(
            id: id,
            code: code,
            title: title,
            credits: 3,
            availability: [.fall, .spring],
            prerequisites: []
        )
    }
}
