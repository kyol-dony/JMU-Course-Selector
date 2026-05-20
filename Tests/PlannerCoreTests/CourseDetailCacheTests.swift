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

    @MainActor
    @Test("repository merge fills cached description without overwriting existing fields")
    func repositoryMergeFillsDescription() throws {
        let repo = CatalogRepository()
        let registrarURL = try #require(URL(string: "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=368728&print"))
        let retrievedAt = try #require(ISO8601DateFormatter().date(from: "2026-05-19T12:00:00Z"))

        let existing = Course(
            id: "CS159",
            code: "CS 159",
            title: "Advanced Programming",
            credits: 3,
            availability: nil,
            prerequisites: ["CS149"],
            verificationStatus: .verified,
            registrarURL: registrarURL
        )

        let parsed = Course(
            id: "CS159",
            code: "CS 159",
            title: "Parsed Different Title",
            credits: 4,
            availability: nil,
            prerequisites: [],
            verificationStatus: .partial,
            registrarURL: registrarURL,
            description: "Official cached description.",
            descriptionSourceURL: registrarURL,
            detailRetrievedAt: retrievedAt
        )

        let merged = repo.merge(existing: existing, parsed: parsed)

        #expect(merged.title == "Advanced Programming")
        #expect(merged.credits == 3)
        #expect(merged.prerequisites == ["CS149"])
        #expect(merged.registrarURL == registrarURL)
        #expect(merged.description == "Official cached description.")
        #expect(merged.descriptionSourceURL == registrarURL)
        #expect(merged.detailRetrievedAt == retrievedAt)
    }
}
