import Foundation
import Testing
@testable import PlannerCore

/// The real Psychology B.S. catalog page (2026-27): area-header rows, instruction
/// rows with credit hours, paired course rows, and `<sup>` footnotes.
@Suite("Catalog requirement structure")
struct CatalogRequirementStructureTests {
    private static let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    private func parsePsych() throws -> HTMLProgramRequirements {
        let html = try String(contentsOf: Self.testDir.appendingPathComponent("_live_psyc_bs.html"), encoding: .utf8)
        return JMUHTMLCatalogParser().parseProgramRequirements(
            html,
            kind: .major,
            sourceURL: URL(string: "https://catalog.jmu.edu/programs/psychology-bs/")!
        )
    }

    private func psychCourses() throws -> [String: Course] {
        Dictionary(try parsePsych().courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func psychCategory(containing courseID: String) throws -> RequirementCategory {
        try #require(try parsePsych().requirements.first { $0.courseOptions.contains { $0.contains(courseID) } })
    }

    // MARK: Titles, pairs, footnotes (Task 2)

    @Test func pairRowsKeepSeparateTitles() throws {
        let courses = try psychCourses()
        #expect(courses["PSYC210"]?.title == "Psychological Measurement and Statistics")
        #expect(courses["PSYC211"]?.title == "Psychological Research Methods")
    }

    @Test func footnoteMarkersBecomeRemarks() throws {
        #expect(try psychCourses()["PSYC402"]?.title == "Independent Study in Psychology")
        let upper = try psychCategory(containing: "PSYC402")
        #expect(upper.courseRemarks["PSYC402"]?.first?.hasPrefix("Repeatable.") == true)
    }

    @Test func parentheticalRemarksLeaveTheTitle() throws {
        for (_, course) in try psychCourses() {
            #expect(!course.title.contains("("), "\(course.code): \(course.title)")
            #expect(course.title.range(of: #"\s\d+(,\d+)*$|\*"#, options: .regularExpression) == nil, "\(course.code): \(course.title)")
        }
    }

    @Test func genEdClusterCodesStay() throws {
        #expect(try psychCourses()["PSYC101"]?.title.contains("[C5SD]") == true)
    }
}
