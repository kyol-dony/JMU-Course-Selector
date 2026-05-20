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

    @Test("course detail parser extracts official description and prerequisite text")
    func parsesCourseDetailHTML() throws {
        let html = """
        <html>
          <body>
            <td id="acalog-page-content">
              <h1>CS 149. Introduction to Programming</h1>
              <p><strong>Credits:</strong> 3.00</p>
              <p>Students learn computational thinking, problem solving, and basic programming in Python.</p>
              <p><strong>Prerequisite(s):</strong> MATH 155 or sufficient ALEKS score.</p>
            </td>
          </body>
        </html>
        """

        let detail = JMUHTMLCatalogParser().parseCourseDetail(html)

        #expect(detail.description == "Students learn computational thinking, problem solving, and basic programming in Python.")
        #expect(detail.prerequisiteText == "Prerequisite(s): MATH 155 or sufficient ALEKS score.")
    }
}
