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

    @Test("Gen Ed picker includes only eligible alternates")
    func genEdPickerRestrictsCatalog() throws {
        let courses = [
            course(id: "wrtc-103", code: "WRTC 103", title: "Critical Reading and Writing"),
            course(id: "wrtc-200", code: "WRTC 200", title: "Introduction to Studies in Writing"),
            course(id: "cs-149", code: "CS 149", title: "Introduction to Programming")
        ]
        let spec = PlaceholderSpec(
            categoryID: "gened-c1w",
            categoryName: "General Education - Writing [C1W]",
            alternates: ["wrtc-103", "wrtc-200", "missing-course"],
            credits: 3
        )

        let eligible = PlaceholderCoursePickerPolicy.eligibleCourses(
            for: spec,
            catalog: catalog(courses: courses)
        )

        #expect(eligible.map(\.id) == ["wrtc-103", "wrtc-200"])
        #expect(!eligible.contains { $0.id == "cs-149" })
    }

    @Test("non-Gen-Ed placeholders use the same bounded searchable course set")
    func nonGenEdAlternativesUseSearchSheet() {
        let courses = [
            course(id: "cis-330", code: "CIS 330", title: "Database Design"),
            course(id: "cis-331", code: "CIS 331", title: "Intermediate Computer Programming"),
            course(id: "cs-149", code: "CS 149", title: "Introduction to Programming")
        ]
        let spec = PlaceholderSpec(
            categoryID: "cis-elective",
            categoryName: "CIS Elective",
            alternates: ["cis-330", "cis-331"],
            credits: 3
        )

        let eligible = PlaceholderCoursePickerPolicy.eligibleCourses(
            for: spec,
            catalog: catalog(courses: courses)
        )

        #expect(eligible.map(\.id) == ["cis-330", "cis-331"])
        #expect(!eligible.contains { $0.id == "cs-149" })
    }

    @Test("open electives still expose the full catalog")
    func openElectiveUsesFullCatalog() throws {
        let courses = [
            course(id: "cis-330", code: "CIS 330", title: "Database Design"),
            course(id: "cs-149", code: "CS 149", title: "Introduction to Programming")
        ]
        let spec = PlaceholderSpec(
            categoryID: ScheduleGenerator.openElectiveCategoryID,
            categoryName: "Open Elective",
            alternates: [],
            credits: 3
        )

        let eligible = PlaceholderCoursePickerPolicy.eligibleCourses(
            for: spec,
            catalog: catalog(courses: courses)
        )

        #expect(eligible.map(\.id) == courses.map(\.id))
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

    private func catalog(courses: [Course]) -> Catalog {
        Catalog.fixture(
            courses: courses,
            program: .fixture(id: "test", title: "Test", requirements: [])
        )
    }
}
