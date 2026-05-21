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

    @Test("course detail service maps cached description and RMP search link")
    func courseDetailServiceUsesCachedDescription() async throws {
        let registrarURL = try #require(URL(string: "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=368727&print"))
        let course = Course(
            id: "CS149",
            code: "CS 149",
            title: "Introduction to Programming",
            credits: 3,
            availability: nil,
            prerequisites: [],
            verificationStatus: .verified,
            registrarURL: registrarURL,
            description: "Official cached CS 149 description.",
            descriptionSourceURL: registrarURL,
            detailRetrievedAt: Date(timeIntervalSince1970: 0)
        )

        let detail = await CourseDetailService().detail(for: course)

        #expect(detail.description == "Official cached CS 149 description.")
        #expect(detail.descriptionStatus == "Official JMU catalog description cached from https://catalog.jmu.edu/preview_course.php?catoid=62&coid=368727&print.")
        #expect(detail.rmpStatus == "Automatic Rate My Professors ratings are unavailable because the app does not use unstable scraping.")
        #expect(detail.rmpSearchURL?.absoluteString == "https://www.ratemyprofessors.com/search/professors/457?q=%2A")
        #expect(detail.professors.isEmpty)
    }

    @Test("course detail service explains missing cached descriptions")
    func courseDetailServiceExplainsMissingDescriptions() async throws {
        let registrarURL = try #require(URL(string: "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=368728&print"))
        let courseWithURL = Course(
            id: "CS159",
            code: "CS 159",
            title: "Advanced Programming",
            credits: 3,
            availability: nil,
            prerequisites: ["CS149"],
            verificationStatus: .verified,
            registrarURL: registrarURL
        )
        let courseWithoutURL = Course(
            id: "CS240",
            code: "CS 240",
            title: "Algorithms and Data Structures",
            credits: 3,
            availability: nil,
            prerequisites: ["CS159"],
            verificationStatus: .partial,
            registrarURL: nil
        )

        let withURLDetail = await CourseDetailService().detail(for: courseWithURL)
        let withoutURLDetail = await CourseDetailService().detail(for: courseWithoutURL)

        #expect(withURLDetail.description == nil)
        #expect(withURLDetail.descriptionStatus == "Description unavailable in cached catalog. Open the JMU registrar page to verify details.")
        #expect(withoutURLDetail.description == nil)
        #expect(withoutURLDetail.descriptionStatus == "Description unavailable until the catalog refresh discovers the official JMU course page.")
    }

    @Test("popup-format preview_course.php parses description even without acalog-page-content wrapper")
    func parsesPopupCoursePage() throws {
        let html = """
        <html><body>
        <nav><a href="#course_preview_title" class="skip-nav">Skip to Content</a></nav>
        <table class="toplevel_popup">
        <tr><td><span class="n1_header">Introduction to African Studies</span></td></tr>
        <tr><td>
        <h1 id='course_preview_title'>AAAD 200. Introduction to African Studies [C4GE]</h1>
        <br><em><strong>Credits</strong></em> <em>3.00</em>
        <em><strong>PeopleSoft Course ID</strong></em> <em>011625</em>
        <em><strong>Grading Basis</strong></em> <em>GRD</em>
        <br><hr><br>
        An introductory survey of basic theoretical concepts to analyze the Black experience, with special focus on the general historical process common to Africa and the African Diaspora. Prerequisite(s): None.
        <br><br><br><hr>
        <div style="float: right"><a href="javascript:void(0)">Print this Page</a></div>
        </td></tr></table>
        </body></html>
        """

        let detail = JMUHTMLCatalogParser().parseCourseDetail(html)

        #expect(detail.description?.contains("An introductory survey of basic theoretical concepts") == true)
        #expect(detail.description?.contains("Diaspora") == true)
        #expect(detail.description?.contains("Print this Page") == false)
        #expect(detail.description?.contains("Credits") == false)
        #expect(detail.prerequisiteText?.contains("Prerequisite(s)") == true)
    }
}

@Suite("Prereq overlay repository loading")
struct PrereqOverlayRepositoryTests {
    @MainActor
    @Test("repository decodes prereq overlay JSON")
    func repositoryDecodesPrereqOverlayJSON() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let overlayURL = directory.appending(path: "prereq_coreq_overrides.json")
        try """
        {
          "schemaVersion": 1,
          "rules": [
            {
              "courseID": "CS240",
              "prerequisiteExpr": { "kind": "course", "value": "CS159" },
              "corequisiteExpr": { "kind": "empty" },
              "confidence": "curated",
              "basis": "explicit",
              "sourceURL": "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=123&print",
              "sourceText": "Prerequisite: CS 159.",
              "notes": "Direct catalog rule."
            }
          ]
        }
        """.write(to: overlayURL, atomically: true, encoding: .utf8)

        let overlay = try CatalogRepository().loadPrereqRuleOverlay(from: overlayURL)

        #expect(overlay.schemaVersion == 1)
        #expect(overlay.rule(for: "CS240")?.prerequisiteExpr == .course("CS159"))
    }

    @MainActor
    @Test("repository treats invalid prereq overlay as non-fatal parser fallback")
    func repositoryTreatsInvalidPrereqOverlayAsNonFatalFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let overlayURL = directory.appending(path: "prereq_coreq_overrides.json")
        try "{ invalid json".write(to: overlayURL, atomically: true, encoding: .utf8)

        let status = CatalogRepository().optionalPrereqRuleOverlay(from: overlayURL)

        #expect(status.overlay == .empty)
        #expect(status.note.contains("parser fallback"))
    }

    @MainActor
    @Test("repository attaches current overlay to bundled catalog")
    func repositoryAttachesCurrentOverlayToBundledCatalog() throws {
        let catalog = try CatalogRepository().loadBundledCatalog()

        #expect(catalog.prereqRuleOverlay.schemaVersion == 1)
        #expect(catalog.source.retrievalNotes.contains { $0.contains("prereq/coreq overlay") })
    }
}
