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

    private static func header(_ text: String, hours: String = "") -> String {
        #"<tr class="areaheader"><td colspan="2"><span class="courselistcomment areaheader">\#(text)</span></td><td class="hourscol">\#(hours)</td></tr>"#
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

    @Test func idFollowsTheLastCountedLineLikeTheOldParser() throws {
        // Biology A&P: "Complete 9 hours" (with hours) then a choice line the old parser didn't count
        let anatomy = try #require(parseSnippet(
            Self.header("Anatomy and Physiology Electives")
            + Self.comment("Complete 9 hours from the following:", hours: "9")
            + Self.comment("Choose at least one course from the following:")
            + Self.course("BIO 320", "Anatomy") + Self.course("BIO 370", "Physiology")
        ).first)
        #expect(anatomy.id == "complete-9-hours-from-the-following")
        // Dance B.A.: a rule sentence without hours leaves the header as the ID
        let technique = try #require(parseSnippet(
            Self.header("Technique Courses")
            + Self.comment("The student is required to complete 10 credits of technique courses.")
            + Self.course("DANC 140", "Ballet I") + Self.course("DANC 141", "Modern I")
        ).first)
        #expect(technique.id == "technique-courses")
    }

    // MARK: Final review findings

    @Test func subtotalOnlyFillsASectionsOnlyRequirement() {
        // Economics: a second instruction without hours must not take the section subtotal
        let split = parseSnippet(
            Self.header("Additional Required Courses")
            + Self.comment("Choose two of the following:", hours: "6")
            + Self.course("ECON 300", "Micro") + Self.course("ECON 301", "Macro") + Self.course("ECON 302", "Money")
            + Self.comment("Choose one of the following statistics courses:")
            + Self.course("MATH 220", "Statistics") + Self.course("COB 191", "Business Statistics")
            + Self.comment("Subtotal", hours: "9")
        )
        #expect(split.map(\.requiredCredits) == [6, 3])
        // Biology Neuroscience: the instruction's own range, not the section's
        let generic = parseSnippet(
            Self.header("Neuroscience Concentration")
            + Self.comment("Choose one of the following:", hours: "3-4")
            + Self.course("BIO 365", "Neurobiology") + Self.course("PSYC 385", "Biopsychology")
            + Self.comment("Subtotal", hours: "6-7")
        )
        #expect(generic.map(\.requiredCredits) == [3])
    }

    @Test func areaOptionRowsBecomeOptions() throws {
        // Psychology B.A. Methodology Core: "Option 1:" / "Option 2:" comment rows.
        // Was optionRowsInsideASectionBecomeGroups (chooseGroups(1) of two
        // groups); each option is now one all-required part.
        let methodology = try #require(parseSnippet(
            Self.header("Methodology Core")
            + Self.comment("Choose one of the following options:", hours: "8")
            + Self.comment("Option 1:") + Self.course("PSYC 210", "Measurement") + Self.course("PSYC 211", "Methods")
            + Self.comment("Option 2:") + Self.course("PSYC 212", "Design I") + Self.course("PSYC 213", "Design II")
            + Self.comment("Subtotal", hours: "8")
        ).first)
        let options = try #require(methodology.options)
        #expect(options.map(\.label) == ["Option 1", "Option 2"])
        #expect(options.map { $0.parts.count } == [1, 1])
        #expect(options.allSatisfy { $0.parts[0].selection == .allRequired })
        #expect(options[0].parts[0].courseOptions == [["PSYC210"], ["PSYC211"]])
        #expect(options[1].parts[0].courseOptions == [["PSYC212"], ["PSYC213"]])
        #expect(methodology.id == "choose-one-of-the-following-options")
        #expect(methodology.name == "Methodology Core")
        #expect(methodology.requiredCredits == 8)
        #expect(methodology.catalogDescription == "Choose one of the following options:")
        // Older readers see the first option.
        #expect(methodology.courseOptions == [["PSYC210"], ["PSYC211"]])
    }

    @Test func aHeaderThatIsTheInstructionGivesTheRule() throws {
        // Biology: "Choose at least one organismal diversity course from the following list: 3-4"
        let diversity = try #require(parseSnippet(
            Self.header("Choose at least one organismal diversity course from the following list:", hours: "3-4")
            + Self.course("BIO 310", "Vertebrates") + Self.course("BIO 320", "Plants") + Self.course("BIO 330", "Fungi")
        ).first)
        #expect(diversity.selection == .chooseCourses(1))
        #expect(diversity.courseOptions.count == 1)
    }

    @Test func titlesKeepTrailingYears() {
        #expect(JMUHTMLCatalogParser.cleanCourseTitle("China to 1600").title == "China to 1600")
        #expect(JMUHTMLCatalogParser.cleanCourseTitle("Europe Since 1914").title == "Europe Since 1914")
        #expect(JMUHTMLCatalogParser.cleanCourseTitle("Topics in Psychology 1,2").title == "Topics in Psychology")
    }

    @Test func creditRangesAndCourseLevelsInRules() {
        func rule(_ text: String) -> RequirementSelection? {
            JMUHTMLCatalogParser.selectionRule(text: text, hasMultiCourseGroups: false)
        }
        #expect(rule("Select 9-12 credit hours of the following:") == .chooseCredits(9))
        #expect(rule("Select 0-3 credit hours of the following:") == .chooseCredits(3))
        #expect(rule("Choose any 300- or 400-level SPAN course") == nil)
        #expect(rule("Choose one 300-level course") == .chooseCourses(1))
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

    @Test func shortLabCodeInAPairRowIsItsOwnCourse() throws {
        // Biology B.S. "Core Requirements": "BIO 150 & 150L", 4 credits.
        let row = #"<tr><td class="codecol"><a href="/search/?P=BIO%20150" title="BIO 150" class="bubblelink code">BIO 150</a><br/><span style="margin-left:20px;" class="blockindent">&amp; <a href="/search/?P=BIO%20150L" title="BIO 150L" class="bubblelink code">150L</a></span></td><td>Foundations of Biology II<br/><span style="margin-left:20px;" class="blockindent">and Foundations of Biology II Laboratory</span></td><td class="hourscol">4</td></tr>"#
        let html = """
        <h1>Example, B.S.</h1><h2>Major Requirements</h2>
        <table class="sc_courselist"><tbody>\(Self.header("Core Requirements"))\(row)</tbody></table>
        """
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(
            html, kind: .major, sourceURL: URL(string: "https://catalog.jmu.edu/programs/x/")!
        )
        let courses = Dictionary(parsed.courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // The lab takes 1 of the row's credits, the lecture the rest.
        #expect(courses["BIO150"]?.credits == 3)
        #expect(courses["BIO150L"]?.credits == 1)
        #expect(courses["BIO150L"]?.title == "Foundations of Biology II Laboratory")
        let core = try #require(parsed.requirements.first)
        #expect(core.courseOptions.flatMap { $0 }.contains("BIO150L"))
    }

    @Test func subjectElectiveProseBecomesAPoolWithTheUpToOneList() throws {
        // Finance B.B.A. "Electives or Concentration": 12 credits of any
        // 300- or 400-level FIN course, up to one of them from a short list.
        let categories = parseSnippet(
            Self.header("Finance Major Core Courses")
            + Self.course("FIN 360", "Analytical Methods in Finance")
            + Self.comment("Subtotal", hours: "12")
            + Self.header("Electives or Concentration")
            + Self.comment("In addition to these core courses, the student majoring in finance must successfully complete 12 credit hours of finance elective courses. Finance electives include any 300- level or 400-level finance course.", hours: "12")
            + Self.comment("A student may choose up to one of the following courses to satisfy the finance elective credit hours: ")
            + Self.course("ACTG 313", "Accounting Information Systems") + Self.course("BLAW 360", "Legal Analysis")
        )
        #expect(!categories.contains { $0.name.lowercased().contains("up to one") })
        let electives = try #require(categories.first { $0.electivePoolSlots != nil })
        #expect(electives.requiredCredits == 12)
        #expect(electives.courseOptions.count == 4)
        #expect(electives.courseOptions.allSatisfy { $0 == [ElectivePool.token(subject: "FIN", minimumNumber: 300), "ACTG313", "BLAW360"] })

        let resolved = Catalog.fixture(
            courses: ["FIN360", "FIN420", "FIN500", "ACTG313", "BLAW360"].map {
                Course(id: $0, code: "\($0.prefix(while: \.isLetter)) \($0.drop(while: \.isLetter))", title: $0, credits: 3, availability: nil, prerequisites: [])
            },
            program: .fixture(id: "fin", title: "Finance", requirements: categories)
        ).resolvingElectivePools()
        let slot = try #require(resolved.programs[0].requirements.first { $0.id == electives.id }?.courseOptions.first)
        #expect(slot == ["FIN420", "ACTG313", "BLAW360"])
    }

    @Test func aSentenceAboutTheOtherOptionIsNotTheRule() throws {
        // Inclusive Early Childhood Education B.S. "Licensure Requirements or Electives"
        let licensure = try #require(parseSnippet(
            Self.header("Licensure Requirements or Electives", hours: "24")
            + Self.comment("Students who do not choose the licensure option will choose 24 credits of electives.")
            + Self.course("IECE 480", "Student Teaching") + Self.course("IECE 481", "Seminar")
        ).first)
        #expect(licensure.selection != .chooseCredits(24))
        #expect(licensure.courseOptions == [["IECE480"], ["IECE481"]])
    }

    @Test func creditsThatMayIncludeTheCoursesBelowAreAChoice() throws {
        // Engineering B.S. "ENGR Technical Electives": the 19 courses listed are
        // a menu for 12 credits, not all required.
        let categories = parseSnippet(
            Self.header("ENGR Technical Electives")
            + Self.comment("12 credits of ENGR Technical Electives may include (but are not limited to):", hours: "12")
            + Self.course("ENGR 345", "Foundations of Computer Engineering") + Self.course("ENGR 360", "Structural Analysis")
            + Self.course("ENGR 387", "Brewery Engineering") + Self.course("ENGR 426", "Product Development")
            + Self.course("ENGR 440", "Mechatronics")
        )
        #expect(categories.count == 1)
        let electives = try #require(categories.first)
        #expect(electives.requiredCredits == 12)
        #expect(electives.selection == .chooseCredits(12))
        #expect(electives.courseOptions.count == 4)
        #expect(electives.courseOptions.allSatisfy { Set($0) == ["ENGR345", "ENGR360", "ENGR387", "ENGR426", "ENGR440"] })
    }

    @Test func suggestedListsAreTheMenuOfTheChoiceBeforeThem() throws {
        // Physics B.S., Applied Physics: "Additional Courses" takes 9 credits;
        // the lists under "Suggested Areas of Interest" are where they come from.
        let html = """
        <h1>Example, B.S.</h1><h2>Major Requirements</h2>
        <table class="sc_courselist"><tbody>\(Self.header("Additional Courses"))\(Self.comment("Complete 9 credits approved by the head of the Department of Physics and Astronomy.", hours: "9"))</tbody></table>
        <h3>Suggested Areas of Interest to Complete the 9 Credit Hours Required (Minimum)</h3>
        <p>Students are strongly encouraged to select their courses from the areas below.</p>
        <table class="sc_courselist"><tbody>\(Self.header("Biophysics Courses"))\(Self.course("PHYS 326", "Biophysics"))\(Self.course("PHYS 364", "Modeling"))\(Self.header("Geophysics Courses"))\(Self.course("PHYS 337", "Geophysics"))</tbody></table>
        """
        let categories = JMUHTMLCatalogParser().parseProgramRequirements(
            html, kind: .major, sourceURL: URL(string: "https://catalog.jmu.edu/programs/x/")!
        ).requirements
        #expect(categories.map(\.name) == ["Additional Courses"])
        let additional = try #require(categories.first)
        #expect(additional.requiredCredits == 9)
        #expect(additional.selection == .chooseCredits(9))
        #expect(!additional.courseOptions.isEmpty)
        #expect(additional.courseOptions.allSatisfy { Set($0) == ["PHYS326", "PHYS364", "PHYS337"] })
    }

    @Test func choiceLinesAndOverlaysBecomeConstrainedSlots() throws {
        // English B.A. "Restricted Electives": three text-only choice lines
        // (7 courses, 21 credits) and three overlay lines that some of those
        // courses must meet, with the named lists printed below.
        func list(_ heading: String, _ codes: [String]) -> String {
            "<h3>\(heading)</h3><table class=\"sc_courselist\"><tbody>" + codes.map { Self.course($0, $0) }.joined() + "</tbody></table>"
        }
        let html = """
        <h1>Example, B.A.</h1><h2>Major Requirements</h2>
        <table class="sc_courselist"><tbody>
        \(Self.header("Core Courses"))\(Self.course("ENG 221", "Literature and Ideas"))\(Self.comment("Subtotal", hours: "3"))
        \(Self.header("Restricted Electives"))
        \(Self.comment("In addition to the core courses above, students must:"))
        \(Self.comment("Choose one course at the 200 or 300 level", hours: "3"))
        \(Self.comment("Choose four courses from the 300 level", hours: "12"))
        \(Self.comment("Choose two approved 400-level courses from the &quot;Advanced Studies in...&quot; courses", hours: "6"))
        \(Self.comment("See list of courses below to meet intermediate and advanced studies overlay requirements:"))
        \(Self.comment("One course at the 300 or 400 level, pre-1700"))
        \(Self.comment("One course at the 300 or 400 level, pre-1900"))
        \(Self.comment("One course from the Identity, Diversity and Power selections"))
        \(Self.comment("Subtotal", hours: "21"))
        </tbody></table>
        \(list("300 or 400 Level, Pre-1700", ["ENG 301", "ENG 401"]))
        \(list("300 or 400 Level, Pre-1900", ["ENG 301", "ENG 325", "ENG 401"]))
        \(list("Identity, Diversity and Power", ["ENG 359", "ENG 408"]))
        \(list("400 Level", ["ENG 401", "ENG 403", "ENG 408"]))
        """
        let categories = JMUHTMLCatalogParser().parseProgramRequirements(
            html, kind: .major, sourceURL: URL(string: "https://catalog.jmu.edu/programs/x/")!
        ).requirements
        #expect(categories.map(\.name) == ["Core Courses", "Restricted Electives"])
        let electives = try #require(categories.last)
        #expect(electives.requiredCredits == 21)
        let slots = electives.courseOptions
        #expect(slots.count == 7)
        #expect(slots.contains([ElectivePool.token(subject: "ENG", minimumNumber: 200, maximumNumber: 399)]))
        #expect(slots.filter { $0 == [ElectivePool.token(subject: "ENG", minimumNumber: 300, maximumNumber: 399)] }.count == 1)
        // Each overlay holds one of the four 300-level slots.
        #expect(slots.contains(["ENG301"]))
        #expect(slots.contains(["ENG301", "ENG325"]))
        #expect(slots.contains(["ENG359"]))
        #expect(slots.filter { $0 == ["ENG401", "ENG403", "ENG408"] }.count == 2)
        #expect(Set(electives.electivePoolSlots ?? []).count == 2)
    }

    private func parseConcentrations(intro: String, lists: [(String, [String])]) -> HTMLProgramRequirements {
        let concentrations = lists.map { heading, codes in
            "<h3>\(heading)</h3><table class=\"sc_courselist\"><tbody>" + codes.map { Self.course($0, $0) }.joined() + "</tbody></table>"
        }.joined()
        let html = """
        <h1>Example, B.A.</h1><h2>Major Requirements</h2>
        <table class="sc_courselist"><tbody>\(Self.header("Core Courses"))\(Self.course("ENG 221", "Literature and Ideas"))</tbody></table>
        <h2>Concentrations</h2><p>\(intro)</p>\(concentrations)
        """
        return JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: URL(string: "https://catalog.jmu.edu/programs/x/")!)
    }

    @Test func optionalConcentrationListsAreChoices() throws {
        // English B.A.: a concentration is nine credits from its list, if chosen.
        let english = parseConcentrations(
            intro: "In consultation with their advisors, students may choose nine credits of courses at the 300- or 400-level that acquaint them with the scope of one of the fields below.",
            lists: [("World Literature", ["ENG 305", "ENG 306", "ENG 358", "ENG 360"]), ("Print Culture", ["ENG 313", "ENG 358", "ENG 415"])]
        )
        #expect(!english.concentrationSelectionRequired)
        let world = try #require(english.concentrations.first { $0.name == "World Literature" }?.requirements)
        #expect(world.count == 1)
        #expect(world.first?.selection == .chooseCredits(9))
        #expect(world.first?.requiredCredits == 9)
        #expect(world.first?.courseOptions.allSatisfy { Set($0) == ["ENG305", "ENG306", "ENG358", "ENG360"] } == true)

        // Sociology B.A.: "four or more courses from the following concentration groupings".
        let sociology = parseConcentrations(
            intro: "The sociology program encourages majors to select electives that create a coherent program of study suited to their special needs and interests. Such a focus would involve four or more courses from the following concentration groupings:",
            lists: [("Markets and Cultures Concentration", ["SOCI 306", "SOCI 386", "SOCI 310", "SOCI 320", "SOCI 330"])]
        )
        #expect(!sociology.concentrationSelectionRequired)
        let markets = try #require(sociology.concentrations.first?.requirements)
        #expect(markets.count == 1)
        #expect(markets.first?.selection == .chooseCourses(4))
        #expect(markets.first?.requiredCredits == 12)
    }

    @Test func sectionsRepeatingATemplateAreTracks() throws {
        // Modern Foreign Languages B.A.: a generic table, then one table per
        // language with the same sections.
        func language(_ name: String, _ subject: String) -> String {
            """
            <h2>\(name)</h2><table class="sc_courselist"><tbody>
            \(Self.header("Language Foundations"))\(Self.course("\(subject) 300", "Language for Living"))\(Self.course("\(subject) 301", "Pop Culture"))
            \(Self.header("Electives"))\(Self.comment("Choose three additional courses from the following list:", hours: "9"))
            \(Self.course("\(subject) 330", "A"))\(Self.course("\(subject) 340", "B"))\(Self.course("\(subject) 350", "C"))\(Self.course("\(subject) 360", "D"))
            </tbody></table>
            """
        }
        let html = """
        <h1>Modern Foreign Languages, B.A.</h1><h2>Major Requirements</h2>
        <table class="sc_courselist"><tbody>
        \(Self.header("Language Foundations"))\(Self.comment("300: Language for Living", hours: "3"))\(Self.comment("Subtotal", hours: "15"))
        \(Self.header("Electives"))\(Self.comment("Choose 9 credits from the following:", hours: "9"))\(Self.comment("Subtotal", hours: "9"))
        </tbody></table>
        \(language("French", "FR"))\(language("Spanish", "SPAN"))
        """
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: URL(string: "https://catalog.jmu.edu/programs/x/")!)
        #expect(parsed.concentrationSelectionRequired)
        #expect(parsed.concentrations.map(\.name) == ["French", "Spanish"])
        #expect(parsed.requirements.isEmpty)
        let french = try #require(parsed.concentrations.first?.requirements)
        #expect(french.map(\.name) == ["Language Foundations", "Electives"])
        #expect(french.first?.courseOptions == [["FR300"], ["FR301"]])
        #expect(french.last?.selection == .chooseCourses(3))
    }

    @Test func nestedParenthesesBecomeOneRemark() {
        // Sport Communication minor: "SMAD 295 Practicum in Media Arts and Design ((taken for 3 credits))"
        let cleaned = JMUHTMLCatalogParser.cleanCourseTitle("Practicum in Media Arts and Design ((taken for 3 credits))")
        #expect(cleaned.title == "Practicum in Media Arts and Design")
        #expect(cleaned.remarks == ["Taken for 3 credits"])
    }
}

