import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Course detail cache")
struct CourseDetailCacheTests {
    @Test("legacy Course JSON decodes with missing cached detail fields")
    func decodesLegacyCourseJSON() throws {
        let json = """
        {
          "id": "CS149",
          "code": "CS 149",
          "title": "Introduction to Programming",
          "credits": 3,
          "availability": null,
          "prerequisites": [],
          "verificationStatus": "verified",
          "registrarURL": "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=368727&print"
        }
        """.data(using: .utf8)!

        let course = try JSONDecoder().decode(Course.self, from: json)

        #expect(course.id == "CS149")
        #expect(course.description == nil)
        #expect(course.descriptionSourceURL == nil)
        #expect(course.detailRetrievedAt == nil)
    }
}
