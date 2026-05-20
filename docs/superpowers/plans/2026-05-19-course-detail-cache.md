# Course Detail Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cache official JMU course descriptions during catalog refresh and show them in the course detail sheet with responsible Rate My Professors search links.

**Architecture:** Extend `PlannerCore.Course` so the catalog cache carries official description metadata. Add a JMU course-detail HTML parser, enrich discovered courses during `CatalogRepository.refreshCatalogFromHTML`, then make `CourseDetailService` map cached data into the existing SwiftUI sheet without network work on click.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI for macOS 14+, Foundation `URLSession`, existing JMU catalog HTML parser.

**Reference spec:** `docs/superpowers/specs/2026-05-19-course-detail-cache-design.md`

---

## File Structure

**Modified files:**

- `Sources/PlannerCore/PlannerCore.swift` — add cached detail fields to `Course`.
- `Sources/PlannerCore/CatalogHTMLParser.swift` — add `HTMLCourseDetail` and `parseCourseDetail(_:)`.
- `Sources/JMUCoursePlanner/Services/CatalogRepository.swift` — fetch and merge cached course descriptions during HTML refresh; bump cache schema.
- `Sources/JMUCoursePlanner/Services/CourseDetailService.swift` — map cached fields and expose RMP search link.
- `Sources/JMUCoursePlanner/Views/CourseDetailSheet.swift` — render RMP search link in professor section.
- `LIMITATIONS.md` — document cached-description behavior and RMP link-only behavior.

**Created files:**

- `Tests/PlannerCoreTests/CourseDetailCacheTests.swift` — parser, model decode, repository merge, and service mapping tests.

---

## Task 1: Add Cached Detail Fields to `Course`

**Files:**
- Modify: `Sources/PlannerCore/PlannerCore.swift`
- Create: `Tests/PlannerCoreTests/CourseDetailCacheTests.swift`

- [ ] **Step 1: Write failing legacy decode test**

Create `Tests/PlannerCoreTests/CourseDetailCacheTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter CourseDetailCacheTests
```

Expected: compile fails because `Course` has no `descriptionSourceURL` or `detailRetrievedAt` members.

- [ ] **Step 3: Extend `Course` model**

In `Sources/PlannerCore/PlannerCore.swift`, replace the existing `public struct Course` with:

```swift
public struct Course: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var code: String
    public var title: String
    public var credits: Int
    public var availability: Set<SemesterTerm>?
    public var prerequisites: [String]
    public var verificationStatus: VerificationStatus
    public var registrarURL: URL?
    public var description: String?
    public var descriptionSourceURL: URL?
    public var detailRetrievedAt: Date?

    public init(
        id: String,
        code: String,
        title: String,
        credits: Int,
        availability: Set<SemesterTerm>?,
        prerequisites: [String],
        verificationStatus: VerificationStatus = .verified,
        registrarURL: URL? = nil,
        description: String? = nil,
        descriptionSourceURL: URL? = nil,
        detailRetrievedAt: Date? = nil
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.credits = credits
        self.availability = availability
        self.prerequisites = prerequisites
        self.verificationStatus = verificationStatus
        self.registrarURL = registrarURL
        self.description = description
        self.descriptionSourceURL = descriptionSourceURL
        self.detailRetrievedAt = detailRetrievedAt
    }
}
```

- [ ] **Step 4: Run test to verify pass**

Run:

```bash
swift test --filter CourseDetailCacheTests
```

Expected: `CourseDetailCacheTests` passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/PlannerCore/PlannerCore.swift Tests/PlannerCoreTests/CourseDetailCacheTests.swift
git commit -m "Add cached course detail fields"
```

---

## Task 2: Parse Official JMU Course Detail HTML

**Files:**
- Modify: `Sources/PlannerCore/CatalogHTMLParser.swift`
- Modify: `Tests/PlannerCoreTests/CourseDetailCacheTests.swift`

- [ ] **Step 1: Write failing parser test**

In `Tests/PlannerCoreTests/CourseDetailCacheTests.swift`, add this method inside `CourseDetailCacheTests`:

```swift
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
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter CourseDetailCacheTests.parsesCourseDetailHTML
```

Expected: compile fails because `JMUHTMLCatalogParser` has no `parseCourseDetail(_:)` member.

- [ ] **Step 3: Add `HTMLCourseDetail` type**

In `Sources/PlannerCore/CatalogHTMLParser.swift`, add this after `HTMLProgramRequirements`:

```swift
public struct HTMLCourseDetail: Equatable, Sendable {
    public var description: String?
    public var prerequisiteText: String?

    public init(description: String?, prerequisiteText: String?) {
        self.description = description
        self.prerequisiteText = prerequisiteText
    }
}
```

- [ ] **Step 4: Add parser entry point**

In `Sources/PlannerCore/CatalogHTMLParser.swift`, add this public method inside `JMUHTMLCatalogParser`, directly after `parseProgramRequirements`:

```swift
    public func parseCourseDetail(_ html: String) -> HTMLCourseDetail {
        let content = courseDetailContent(in: html)
        let paragraphs = paragraphTexts(in: content)
        var descriptionParts: [String] = []
        var prerequisiteText: String?

        for paragraph in paragraphs {
            let text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if isCourseDetailMetadata(text) {
                continue
            }

            if isPrerequisiteLine(text) {
                prerequisiteText = text
                continue
            }

            descriptionParts.append(text)
        }

        let description = descriptionParts
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return HTMLCourseDetail(
            description: description.isEmpty ? nil : description,
            prerequisiteText: prerequisiteText
        )
    }
```

- [ ] **Step 5: Add private parser helpers**

In `Sources/PlannerCore/CatalogHTMLParser.swift`, add these helpers inside `JMUHTMLCatalogParser`, before `private func programKind(forSectionTitle:)`:

```swift
    private func courseDetailContent(in html: String) -> String {
        if let match = html.firstMatch(for: #"(?is)<td\b[^>]*id="acalog-page-content"[^>]*>(.*?)</td>"#),
           match.count > 1 {
            return match[1]
        }

        if let match = html.firstMatch(for: #"(?is)<body\b[^>]*>(.*?)</body>"#),
           match.count > 1 {
            return match[1]
        }

        return html
    }

    private func paragraphTexts(in html: String) -> [String] {
        let paragraphs = html.matches(for: #"(?is)<p\b[^>]*>(.*?)</p>"#)
            .compactMap { match -> String? in
                guard match.count > 1 else { return nil }
                let text = HTMLCleaner.clean(match[1])
                return text.isEmpty ? nil : text
            }

        if !paragraphs.isEmpty {
            return paragraphs
        }

        let fallback = HTMLCleaner.clean(html)
        return fallback.isEmpty ? [] : [fallback]
    }

    private func isCourseDetailMetadata(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("credits:")
            || lower.hasPrefix("credit hours:")
            || lower.hasPrefix("repeat status:")
            || lower.hasPrefix("grading basis:")
            || lower.hasPrefix("course id:")
            || lower.hasPrefix("peoplesoft course id:")
    }

    private func isPrerequisiteLine(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("prerequisite")
            || lower.hasPrefix("prerequisites")
            || lower.hasPrefix("prerequisite(s)")
    }
```

- [ ] **Step 6: Run parser tests**

Run:

```bash
swift test --filter CourseDetailCacheTests
```

Expected: all `CourseDetailCacheTests` pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/PlannerCore/CatalogHTMLParser.swift Tests/PlannerCoreTests/CourseDetailCacheTests.swift
git commit -m "Parse cached JMU course descriptions"
```

---

## Task 3: Enrich Catalog Refresh With Cached Descriptions

**Files:**
- Modify: `Sources/JMUCoursePlanner/Services/CatalogRepository.swift`
- Modify: `Tests/PlannerCoreTests/CourseDetailCacheTests.swift`

- [ ] **Step 1: Write failing merge test**

In `Tests/PlannerCoreTests/CourseDetailCacheTests.swift`, add this method inside `CourseDetailCacheTests`:

```swift
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
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter CourseDetailCacheTests.repositoryMergeFillsDescription
```

Expected: compile fails because `merge(existing:parsed:)` is private or does not fill cached detail fields.

- [ ] **Step 3: Bump catalog cache schema**

In `Sources/JMUCoursePlanner/Services/CatalogRepository.swift`, replace:

```swift
    private static let cacheSchemaVersion = 2
```

with:

```swift
    private static let cacheSchemaVersion = 3
```

- [ ] **Step 4: Add enrichment type**

In `Sources/JMUCoursePlanner/Services/CatalogRepository.swift`, add this near `CatalogRefreshProgress`:

```swift
private struct CourseDetailEnrichment: Sendable {
    var courseID: String
    var description: String
    var sourceURL: URL
    var retrievedAt: Date
}
```

- [ ] **Step 5: Convert `fetchHTML` to static helper**

In `Sources/JMUCoursePlanner/Services/CatalogRepository.swift`, replace:

```swift
    private func fetchHTML(from url: URL) async throws -> String {
```

with:

```swift
    nonisolated private static func fetchHTML(from url: URL) async throws -> String {
```

Then replace each existing call in this file:

```swift
fetchHTML(from:
```

with:

```swift
Self.fetchHTML(from:
```

- [ ] **Step 6: Add bounded course-detail fetch helper**

In `Sources/JMUCoursePlanner/Services/CatalogRepository.swift`, add this private method before `fetchGeneralEducation(coursesByID:)`:

```swift
    private func fetchCourseDetailEnrichments(for courses: [Course]) async -> [String: CourseDetailEnrichment] {
        let candidates = courses
            .filter { $0.registrarURL != nil }
            .filter { ($0.description ?? "").isEmpty }
            .sorted { $0.code < $1.code }

        guard !candidates.isEmpty else { return [:] }

        let parser = htmlParser
        let limit = 4

        return await withTaskGroup(
            of: CourseDetailEnrichment?.self,
            returning: [String: CourseDetailEnrichment].self
        ) { group in
            var nextIndex = 0

            func enqueueNext() {
                guard nextIndex < candidates.count else { return }
                let course = candidates[nextIndex]
                nextIndex += 1

                group.addTask {
                    guard let url = course.registrarURL else { return nil }

                    do {
                        let html = try await Self.fetchHTML(from: url)
                        let detail = parser.parseCourseDetail(html)
                        guard let description = detail.description, !description.isEmpty else {
                            return nil
                        }
                        return CourseDetailEnrichment(
                            courseID: course.id,
                            description: description,
                            sourceURL: url,
                            retrievedAt: Date()
                        )
                    } catch {
                        return nil
                    }
                }
            }

            for _ in 0..<min(limit, candidates.count) {
                enqueueNext()
            }

            var results: [String: CourseDetailEnrichment] = [:]
            while let enrichment = await group.next() {
                if let enrichment {
                    results[enrichment.courseID] = enrichment
                }
                enqueueNext()
            }

            return results
        }
    }
```

- [ ] **Step 7: Apply enrichments before saving catalog**

In `refreshCatalogFromHTML(progress:)`, after the program loop and before `let catalogSource = CatalogSource(`, add:

```swift
        let detailEnrichments = await fetchCourseDetailEnrichments(for: Array(coursesByID.values))
        for enrichment in detailEnrichments.values {
            guard var course = coursesByID[enrichment.courseID] else { continue }
            course.description = enrichment.description
            course.descriptionSourceURL = enrichment.sourceURL
            course.detailRetrievedAt = enrichment.retrievedAt
            coursesByID[enrichment.courseID] = course
        }
```

- [ ] **Step 8: Update merge behavior and test visibility**

In `Sources/JMUCoursePlanner/Services/CatalogRepository.swift`, replace the existing private merge function with:

```swift
    func merge(existing: Course?, parsed: Course) -> Course {
        guard var existing else { return parsed }
        if existing.registrarURL == nil {
            existing.registrarURL = parsed.registrarURL
        }
        if existing.title.isEmpty {
            existing.title = parsed.title
        }
        if existing.credits == 0 {
            existing.credits = parsed.credits
        }
        if existing.prerequisites.isEmpty {
            existing.prerequisites = parsed.prerequisites
        }
        if (existing.description ?? "").isEmpty {
            existing.description = parsed.description
        }
        if existing.descriptionSourceURL == nil {
            existing.descriptionSourceURL = parsed.descriptionSourceURL
        }
        if existing.detailRetrievedAt == nil {
            existing.detailRetrievedAt = parsed.detailRetrievedAt
        }
        return existing
    }
```

- [ ] **Step 9: Run repository tests**

Run:

```bash
swift test --filter CourseDetailCacheTests.repositoryMergeFillsDescription
```

Expected: test passes.

- [ ] **Step 10: Run parser and repository tests**

Run:

```bash
swift test --filter CourseDetailCacheTests
```

Expected: all `CourseDetailCacheTests` pass.

- [ ] **Step 11: Commit**

```bash
git add Sources/JMUCoursePlanner/Services/CatalogRepository.swift Tests/PlannerCoreTests/CourseDetailCacheTests.swift
git commit -m "Cache course descriptions during catalog refresh"
```

---

## Task 4: Map Cached Details Into the Sheet

**Files:**
- Modify: `Sources/JMUCoursePlanner/Services/CourseDetailService.swift`
- Modify: `Sources/JMUCoursePlanner/Views/CourseDetailSheet.swift`
- Modify: `Tests/PlannerCoreTests/CourseDetailCacheTests.swift`

- [ ] **Step 1: Write failing service tests**

In `Tests/PlannerCoreTests/CourseDetailCacheTests.swift`, add these methods inside `CourseDetailCacheTests`:

```swift
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
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter CourseDetailCacheTests.courseDetailService
```

Expected: compile fails because `CourseDetail` has no `rmpSearchURL`, or assertions fail because `CourseDetailService` still returns the old unavailable-state text.

- [ ] **Step 3: Update `CourseDetail` data model and service**

Replace `Sources/JMUCoursePlanner/Services/CourseDetailService.swift` with:

```swift
import Foundation
import PlannerCore

struct CourseDetail: Identifiable {
    var id: String { course.id }
    var course: Course
    var descriptionStatus: String
    var description: String?
    var rmpStatus: String
    var rmpSearchURL: URL?
    var professors: [ProfessorRating]
}

struct ProfessorRating: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var rating: Double?
    var difficulty: Double?
    var reviewCount: Int
    var profileURL: URL?
}

struct CourseDetailService {
    private let rmpSearchURL = URL(string: "https://www.ratemyprofessors.com/search/professors/457?q=%2A")!

    func detail(for course: Course) async -> CourseDetail {
        CourseDetail(
            course: course,
            descriptionStatus: descriptionStatus(for: course),
            description: course.description,
            rmpStatus: "Automatic Rate My Professors ratings are unavailable because the app does not use unstable scraping.",
            rmpSearchURL: rmpSearchURL,
            professors: []
        )
    }

    private func descriptionStatus(for course: Course) -> String {
        if let description = course.description, !description.isEmpty {
            if let source = course.descriptionSourceURL ?? course.registrarURL {
                return "Official JMU catalog description cached from \(source.absoluteString)."
            }
            return "Official JMU catalog description cached."
        }

        if course.registrarURL != nil {
            return "Description unavailable in cached catalog. Open the JMU registrar page to verify details."
        }

        return "Description unavailable until the catalog refresh discovers the official JMU course page."
    }
}
```

- [ ] **Step 4: Render RMP search link in professor section**

In `Sources/JMUCoursePlanner/Views/CourseDetailSheet.swift`, replace `professorSection` with:

```swift
    private var professorSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            SectionHeader("Difficulty and professors")
            let detail = store.courseDetail?.course.id == course.id ? store.courseDetail : nil
            Text(detail?.rmpStatus ?? "Loading professor data...")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            if let url = detail?.rmpSearchURL {
                Link("Search JMU professors on Rate My Professors", destination: url)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.brandPurple)
            }

            if let professors = detail?.professors, !professors.isEmpty {
                ForEach(professors) { professor in
                    HStack {
                        Text(professor.name)
                            .font(DesignTokens.Typography.body)
                        Spacer()
                        Text(professor.rating.map { String(format: "%.1f", $0) } ?? "No reviews yet")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            }
        }
    }
```

- [ ] **Step 5: Run service tests**

Run:

```bash
swift test --filter CourseDetailCacheTests.courseDetailService
```

Expected: service tests pass.

- [ ] **Step 6: Run build smoke test**

Run:

```bash
swift build
```

Expected: build completes without SwiftUI compile errors.

- [ ] **Step 7: Commit**

```bash
git add Sources/JMUCoursePlanner/Services/CourseDetailService.swift Sources/JMUCoursePlanner/Views/CourseDetailSheet.swift Tests/PlannerCoreTests/CourseDetailCacheTests.swift
git commit -m "Show cached descriptions and RMP search link"
```

---

## Task 5: Update Limitations and Run Full Verification

**Files:**
- Modify: `LIMITATIONS.md`

- [ ] **Step 1: Update course detail limitations**

In `LIMITATIONS.md`, replace the `## Course details and Rate My Professor` section with:

```markdown
## Course details and Rate My Professor

- Course detail panels show official JMU descriptions when the catalog HTML refresh has cached the course's registrar detail page.
- Courses without a discovered JMU registrar course URL show an unavailable description state and should be verified through the registrar before registration.
- Rate My Professor data is not scraped or fabricated. The app links to the James Madison University professor search page so students can manually look up instructors.
- Professor lists and automatic RMP ratings are not populated without a future curated local dataset.
```

- [ ] **Step 2: Run targeted tests**

Run:

```bash
swift test --filter CourseDetailCacheTests
```

Expected: all course-detail cache tests pass.

- [ ] **Step 3: Run full test suite**

Run:

```bash
script/run_tests.sh
```

Expected: `swift test --disable-sandbox` completes with all tests passing.

- [ ] **Step 4: Run build**

Run:

```bash
swift build
```

Expected: `Build complete!` and no errors.

- [ ] **Step 5: Inspect final diff**

Run:

```bash
git diff --stat
git diff -- Sources/PlannerCore/PlannerCore.swift Sources/PlannerCore/CatalogHTMLParser.swift Sources/JMUCoursePlanner/Services/CatalogRepository.swift Sources/JMUCoursePlanner/Services/CourseDetailService.swift Sources/JMUCoursePlanner/Views/CourseDetailSheet.swift LIMITATIONS.md Tests/PlannerCoreTests/CourseDetailCacheTests.swift
```

Expected: diff only covers cached course detail fields, parser, repository enrichment, detail sheet link, limitations, and tests.

- [ ] **Step 6: Commit**

```bash
git add LIMITATIONS.md
git commit -m "Document course detail cache limitations"
```

---

## Completion Criteria

- `Course` can decode old cached JSON with no cached detail fields.
- JMU course-detail HTML parser extracts description and prerequisite text.
- Catalog HTML refresh caches descriptions for courses with registrar URLs.
- Failed course-detail fetches do not fail catalog refresh.
- Course detail clicks use cached local data only.
- Course detail sheet shows RMP search link, not scraped ratings.
- `swift test --filter CourseDetailCacheTests` passes.
- `script/run_tests.sh` passes.
- `swift build` passes.
