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

    // MARK: Names, credits, rules, groups (Task 3)

    private func psychCategory(named name: String) throws -> RequirementCategory {
        try #require(try parsePsych().requirements.first { $0.name == name })
    }

    private func parseSnippet(_ rows: String) -> [RequirementCategory] {
        let html = """
        <h1>Example, B.S.</h1><h2>Major Requirements</h2>
        <table class="sc_courselist"><tbody>\(rows)</tbody></table>
        """
        return JMUHTMLCatalogParser().parseProgramRequirements(
            html, kind: .major, sourceURL: URL(string: "https://catalog.jmu.edu/programs/x/")!
        ).requirements
    }

    private static func header(_ text: String) -> String {
        #"<tr class="areaheader"><td colspan="2"><span class="courselistcomment areaheader">\#(text)</span></td><td class="hourscol"></td></tr>"#
    }
    private static func comment(_ text: String, hours: String = "") -> String {
        #"<tr><td colspan="2"><span class="courselistcomment">\#(text)</span></td><td class="hourscol">\#(hours)</td></tr>"#
    }
    private static func course(_ code: String, _ title: String) -> String {
        let query = code.replacingOccurrences(of: " ", with: "%20")
        return #"<tr><td class="codecol"><a href="/search/?P=\#(query)" class="bubblelink code">\#(code)</a></td><td>\#(title)</td><td class="hourscol">3</td></tr>"#
    }

    @Test func psychologyRequirementsMatchCatalog() throws {
        let categories = try parsePsych().requirements
        #expect(categories.map(\.name) == [
            "Required Courses", "Methodology Core",
            "SS Content Core – Psychology as a Social Science", "NS Content Core – Psychology as a Natural Science",
            "Biopsychology", "Upper-Level Courses", "Psychology Electives",
            "Capstone Course", "Sociocultural Competency", "Cognate Requirement"
        ])
        #expect(categories.map(\.requiredCredits) == [9, 8, 9, 6, 3, 6, 3, 3, 3, 3])
        #expect(categories.map(\.selection) == [
            .allRequired, .chooseGroups(1), .chooseCourses(3), .chooseCourses(2),
            .allRequired, .chooseCredits(6), .chooseCredits(3), .chooseGroups(1), .chooseCourses(1), .unknown
        ])
    }

    @Test func instructionLineBecomesDescription() throws {
        #expect(try psychCategory(named: "Methodology Core").catalogDescription == "Choose one of the following options:")
        let capstone = try psychCategory(named: "Capstone Course").catalogDescription ?? ""
        #expect(capstone.hasPrefix("Departmental approval is required"))
        #expect(capstone.contains("Choose one of the following:"))
    }

    @Test func instructionFootnotesJoinTheDescription() throws {
        let sociocultural = try psychCategory(named: "Sociocultural Competency").catalogDescription ?? ""
        #expect(sociocultural.contains("One sociocultural competency course is required."))
    }

    @Test func pairsBecomeGroupsAndSlots() throws {
        let methodology = try psychCategory(named: "Methodology Core")
        #expect(methodology.choices == [["PSYC210", "PSYC211"], ["PSYC212", "PSYC213"]])
        #expect(methodology.courseOptions == [["PSYC210", "PSYC212"], ["PSYC211", "PSYC213"]])
    }

    @Test func chooseThreeHasThreeSlots() throws {
        #expect(try psychCategory(named: "SS Content Core – Psychology as a Social Science").courseOptions.count == 3)
    }

    @Test func crossListedCodesAreKept() throws {
        let natural = try psychCategory(named: "NS Content Core – Psychology as a Natural Science")
        #expect(natural.choices == [["PSYC375"], ["PSYC380"], ["PSYC390"], ["PSYC395"]])
        #expect(try psychCategory(named: "Biopsychology").choices == [["PSYC385"]])
    }

    @Test func idsAreUnchangedFromTodaysParser() throws {
        // Captured from the parser at d946bbf^ (before this task); Biopsychology is new.
        #expect(try parsePsych().requirements.map(\.id) == [
            "required-courses", "choose-one-of-the-following-options",
            "choose-at-least-three-of-the-following", "choose-at-least-two-of-the-following",
            "biopsychology", "choose-6-credits-of-the-following",
            "choose-three-credit-hours-of-psychology-electives",
            "choose-one-of-the-following", "choose-one-of-the-following-2",
            // New: today's parser dropped this 3-credit requirement because it never read row hours.
            "students-must-take-one-additional-scientific-literacy-courses-beyond-the-b-s-degree-requirements-and-general-education-choose-a-course-from-the-list-of-courses-meeting-the-b-s-degree-scientific-literacy-requirement"
        ])
    }

    @Test func twoInstructionRowsUnderOneHeader() {
        let categories = parseSnippet(
            Self.header("Electives")
            + Self.comment("Choose one of the following:", hours: "3") + Self.course("ART 200", "Art") + Self.course("ART 210", "Design")
            + Self.comment("Choose two of the following:", hours: "6") + Self.course("MUS 200", "Music") + Self.course("MUS 210", "Theory") + Self.course("MUS 220", "History")
        )
        #expect(categories.count == 2)
        #expect(Set(categories.map(\.id)).count == 2)
        #expect(categories.allSatisfy { $0.name.hasPrefix("Electives") })
        #expect(categories.map(\.requiredCredits) == [3, 6])
    }

    @Test func proseHeadingBecomesDescription() throws {
        let prose = "Students in the B.S. biology major must complete at least 24 credit hours of approved biology courses and at least 16 of these must be at the 300 and 400 levels."
        let category = try #require(parseSnippet(Self.header("Biology Electives") + Self.comment(prose, hours: "24")).first)
        #expect(category.name == "Biology Electives")
        #expect(category.catalogDescription?.hasPrefix("Students in the B.S. biology major") == true)
        #expect(category.requiredCredits == 24)
    }

    // MARK: Whole-catalog audit findings (Task 8)

    @Test func hourRangesUseTheLowerBoundUnlessItIsZero() throws {
        // Biology B.A. "Capstone Requirement": hours "0-3"
        let capstone = try #require(parseSnippet(
            Self.header("Capstone Requirement")
            + Self.comment("Students must complete a Capstone experience, decided upon with their advisor. The courses below qualify.", hours: "0-3")
            + Self.course("BIO 497", "Advanced Biological Research") + Self.course("BIO 499A", "Senior Project")
            + Self.comment("Subtotal", hours: "0-3")
        ).first)
        #expect(capstone.requiredCredits == 3)
        let ranged = try #require(parseSnippet(
            Self.header("Upper Electives") + Self.comment("Choose 6 credits of the following:", hours: "6-8")
            + Self.course("ART 300", "Art") + Self.course("ART 310", "Design") + Self.course("ART 320", "Print")
        ).first)
        #expect(ranged.requiredCredits == 6)
    }

    @Test func zeroHourMilestonesKeepTheSubtotal() throws {
        // Music B.A. "Core Courses": 0-credit milestone rows around the courses
        let categories = parseSnippet(
            Self.header("Core Courses")
            + Self.comment("Incoming Music Major Assessment Milestone", hours: "0")
            + Self.course("MUS 206", "Introduction to Global Music") + Self.course("MUS 207", "History of Western Music")
            + Self.comment("School of Music Senior Assessment Milestone", hours: "0")
            + Self.comment("Subtotal", hours: "6")
        )
        #expect(categories.count == 1)
        let core = try #require(categories.first)
        #expect(core.name == "Core Courses")
        #expect(core.requiredCredits == 6)
        #expect(core.id == "incoming-music-major-assessment-milestone")
        #expect(core.choices == [["MUS206"], ["MUS207"]])
    }

    @Test func concentrationChooserIsNotARequirement() {
        // Kinesiology B.S.: "Choose one of the following: 46-54" lists the concentrations
        let categories = parseSnippet(
            Self.header("Kinesiology Concentrations")
            + Self.comment("Choose one of the following:", hours: "46-54")
            + Self.comment("Exercise Science") + Self.comment("Physical and Health Education Teacher Education")
            + Self.comment("Subtotal", hours: "46-54")
        )
        #expect(categories.isEmpty, "\(categories.map { "\($0.name) \($0.requiredCredits)" })")
    }

    @Test func idPrefersTheChoiceLineOverProseWithHours() throws {
        // Anthropology B.A. archaeology concentration: prose with hours, then the choice line
        let category = try #require(parseSnippet(
            Self.header("Electives")
            + Self.comment("Upper-division courses in cultural and biological anthropology:", hours: "3")
            + Self.comment("Choose one of the following:")
            + Self.course("ANTH 313", "Ethnographic Methods") + Self.course("ANTH 325", "Primate Behavior")
        ).first)
        #expect(category.id == "choose-one-of-the-following")
        #expect(category.name == "Electives")
    }

    @Test func moreInstructionPhrasingsHaveRules() {
        func rule(_ text: String) -> RequirementSelection? {
            JMUHTMLCatalogParser.selectionRule(text: text, hasMultiCourseGroups: false)
        }
        #expect(rule("Earn six credit hours from among the following:") == .chooseCredits(6))
        #expect(rule("Choose any 9 credits from the following:") == .chooseCredits(9))
        #expect(rule("Choose a minimum of 2 courses from the following:") == .chooseCourses(2))
        #expect(rule("Complete at least 3 of the following:") == .chooseCourses(3))
        #expect(rule("Students must complete the following courses.") == nil)
    }

    @Test func nestedParenthesesBecomeOneRemark() {
        // Sport Communication minor: "SMAD 295 Practicum in Media Arts and Design ((taken for 3 credits))"
        let cleaned = JMUHTMLCatalogParser.cleanCourseTitle("Practicum in Media Arts and Design ((taken for 3 credits))")
        #expect(cleaned.title == "Practicum in Media Arts and Design")
        #expect(cleaned.remarks == ["Taken for 3 credits"])
    }
}

