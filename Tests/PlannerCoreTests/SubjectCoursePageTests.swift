import Foundation
import Testing
@testable import PlannerCore

/// A subject's course listing page (`/courses/span/`): the source for
/// foreign-language sequence courses no program page lists.
@Suite("Subject course page")
struct SubjectCoursePageTests {
    /// SPAN 231 and SPAN 232, copied from the live page.
    private static let html = """
    <div class="courseblock" data-coursecode="SPAN 231"><div class="cols noindent"><span class="text col-3 detail-code margin--tiny text--semibold text--huge"><strong>SPAN 231</strong></span>\u{00A0}\u{00A0}<span class="text col-8 detail-title margin--tiny text--huge">Intermediate Spanish I</span>\u{00A0}\u{00A0}</div><div class="noindent"></div><div class="cols noindent"><span class="text detail-hours_html margin--tiny"><strong> Credits </strong> 3</span>\u{00A0}\u{00A0}<span class="text detail-grade_mode margin--tiny"><strong> Grading Basis </strong> Graded</span>\u{00A0}\u{00A0}</div><div class="noindent"><div class="courseblockdesc noindent">A thorough review of grammar, vocabulary building, conversation, composition and reading.</div></div><div class="noindent"><div class="courseblockextra noindent">Prerequisites: <a href="/search/?P=SPAN%20102" title="SPAN\u{00A0}102" class="bubblelink code" onclick="return showCourse(this, 'SPAN 102');">SPAN\u{00A0}102</a> or <a href="/search/?P=SPAN%20111" title="SPAN\u{00A0}111" class="bubblelink code" onclick="return showCourse(this, 'SPAN 111');">SPAN\u{00A0}111</a>, or per placement exam score.</div></div></div><div class="courseblock" data-coursecode="SPAN 232"><div class="cols noindent"><span class="text col-3 detail-code margin--tiny text--semibold text--huge"><strong>SPAN 232</strong></span>\u{00A0}\u{00A0}<span class="text col-8 detail-title margin--tiny text--huge">Intermediate Spanish II</span>\u{00A0}\u{00A0}</div><div class="noindent"></div><div class="cols noindent"><span class="text detail-hours_html margin--tiny"><strong> Credits </strong> 3</span>\u{00A0}\u{00A0}<span class="text detail-grade_mode margin--tiny"><strong> Grading Basis </strong> Graded</span>\u{00A0}\u{00A0}</div><div class="noindent"><div class="courseblockdesc noindent">A thorough review of grammar, vocabulary building, conversation, composition and reading.</div></div><div class="noindent"><div class="courseblockextra noindent">Prerequisites: <a href="/search/?P=SPAN%20231" title="SPAN\u{00A0}231" class="bubblelink code" onclick="return showCourse(this, 'SPAN 231');">SPAN\u{00A0}231</a> or per placement exam score.</div></div></div>
    """

    @Test func parsesCourseblocks() throws {
        let courses = JMUHTMLCatalogParser.subjectCourses(in: Self.html)
        #expect(courses.map(\.id) == ["SPAN231", "SPAN232"])
        #expect(courses.map(\.code) == ["SPAN 231", "SPAN 232"])
        #expect(courses.map(\.title) == ["Intermediate Spanish I", "Intermediate Spanish II"])
        #expect(courses.allSatisfy { $0.credits == 3 })
        #expect(courses.first?.rawPrerequisiteText?.contains("SPAN 102") == true)
    }

    @Test func creditRangeTakesTheLowerBound() throws {
        let block = #"<div class="courseblock" data-coursecode="ASL 101"><span class="text col-8 detail-title">Elementary ASL I</span><span class="text detail-hours_html"><strong> Credits </strong> 3-4</span></div>"#
        let course = try #require(JMUHTMLCatalogParser.subjectCourses(in: block).first)
        #expect(course.id == "ASL101" && course.credits == 3 && course.rawPrerequisiteText == nil)
    }
}
