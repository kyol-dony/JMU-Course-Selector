import Foundation
import Testing
@testable import PlannerCore

@Suite("JMU catalog HTML parser")
struct CatalogHTMLParserTests {
    @Test("2026 program search extracts and deduplicates undergraduate majors and minors")
    func parsesModernProgramIndex() throws {
        let cards = """
        <div class="filter-items filter-items--grid"><ul class="isotope">
          <li class="item filter_1"><a href="/programs/computer-science-bs/"><div class="item-container"><span class="title">Computer Science, B.S.</span><span class="keyword">Undergraduate</span><span class="keyword">Bachelor's Degrees</span></div></a></li>
          <li class="item filter_1"><a href="/programs/computer-science-minor/"><div class="item-container"><span class="title">Computer Science Minor</span><span class="keyword">Undergraduate</span><span class="keyword">Minors</span></div></a></li>
          <li class="item filter_2"><a href="/programs/computer-science-ms/"><div class="item-container"><span class="title">Computer Science, M.S.</span><span class="keyword">Graduate</span><span class="keyword">Master's Degrees</span></div></a></li>
        </ul></div>
        """
        let html = cards + cards

        let entries = JMUHTMLCatalogParser().parseProgramsOfStudy(html)

        #expect(entries.count == 2)
        #expect(entries.map(\.kind) == [.major, .minor])
        #expect(entries[0].sourceURL.absoluteString == "https://catalog.jmu.edu/programs/computer-science-bs/")
        #expect(entries[0].printURL == entries[0].sourceURL)
    }

    @Test("2026 requirement tables preserve required rows, choices, and search URLs")
    func parsesModernProgramRequirements() throws {
        let html = """
        <h1 class="page-title">Computer Science, B.S.</h1>
        <div id="requirementstextcontainer">
          <table class="sc_sctable"><tr><td><strong>Total</strong></td><td><strong>120</strong></td></tr></table>
          <h2>Major Requirements</h2>
          <table class="sc_courselist"><tbody>
            <tr><td class="codecol"><a href="/search/?P=CS%20149">CS 149</a></td><td>Introduction to Programming</td><td class="hourscol">3</td></tr>
            <tr><td class="codecol"><a href="/search/?P=CS%20159">CS 159</a></td><td>Advanced Programming</td><td class="hourscol">3</td></tr>
            <tr><td colspan="2"><span class="courselistcomment">Choose one statistics course:</span></td><td class="hourscol">3-4</td></tr>
            <tr><td class="codecol"><a href="/search/?P=MATH%20220">MATH 220</a></td><td>Elementary Statistics [C3QR]</td><td class="hourscol"></td></tr>
            <tr><td class="codecol"><a href="/search/?P=MATH%20229">MATH 229</a></td><td>Introduction to Applied Statistics Using R [C3QR]</td><td class="hourscol"></td></tr>
            <tr class="listsum"><td>Total Credits</td><td></td><td>9-10</td></tr>
          </tbody></table>
        </div>
        <div id="recommendedscheduletextcontainer"></div>
        """
        let sourceURL = try #require(URL(string: "https://catalog.jmu.edu/programs/computer-science-bs/"))

        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: sourceURL)

        #expect(parsed.title == "Computer Science, B.S.")
        #expect(parsed.totalCredits == 120)
        #expect(parsed.requirements.count == 2)
        #expect(parsed.requirements[0].courseOptions == [["CS149"], ["CS159"]])
        #expect(parsed.requirements[1].courseOptions == [["MATH220", "MATH229"]])
        #expect(parsed.courses.first(where: { $0.id == "CS149" })?.registrarURL?.absoluteString == "https://catalog.jmu.edu/search/?P=CS%20149")
    }

    @Test("2026 course search extracts description and prerequisite text")
    func parsesModernCourseDetail() {
        let html = """
        <article class="searchresult search-courseresult"><div class="courseblock" data-coursecode="CS 149">
          <div class="courseblockdesc noindent">Fundamental problem-solving techniques using a modern programming language.</div>
          <div class="courseblockextra noindent">Prerequisites: <a href="/search/?P=MATH%20155">MATH 155</a> or sufficient placement score.</div>
        </div></article>
        """

        let detail = JMUHTMLCatalogParser().parseCourseDetail(html)

        #expect(detail.description == "Fundamental problem-solving techniques using a modern programming language.")
        #expect(detail.prerequisiteText == "Prerequisites: MATH 155 or sufficient placement score.")
    }

    @Test("2026 Gen Ed tables retain a parent cluster tag below explanatory subheadings")
    func parsesModernNestedGenEdHeading() throws {
        let html = """
        <h1 class="page-title">Arts and Humanities</h1>
        <h3>Literature [C2L]</h3>
        <p>Literature requirement overview.</p>
        <h4>Literature and Writing Infusion</h4>
        <table class="sc_courselist"><tbody>
          <tr><td class="codecol"><a href="/search/?P=ENG%20221">ENG 221</a></td><td>Literature and Ideas [C2L]</td><td class="hourscol">3</td></tr>
        </tbody></table>
        """
        let sourceURL = try #require(URL(string: "https://catalog.jmu.edu/general-education/arts-humanities/"))

        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: sourceURL)

        #expect(parsed.requirements.contains { $0.name == "Literature [C2L]" && $0.courseOptions == [["ENG221"]] })
    }

    @Test("2026 nested concentration tracks become selectable leaf pathways with inherited requirements")
    func parsesModernNestedConcentrationTracks() throws {
        let html = """
        <h1 class="page-title">Music, B.M.</h1>
        <div id="requirementstextcontainer">
          <h2>Major Requirements</h2>
          <table class="sc_courselist"><tbody>
            <tr><td class="codecol"><a href="/search/?P=MUS%20143">MUS 143</a></td><td>Aural Skills I</td><td class="hourscol">1</td></tr>
            <tr class="areaheader"><td colspan="2"><span class="courselistcomment areaheader">Concentrations</span></td><td class="hourscol"></td></tr>
            <tr><td colspan="2"><span class="courselistcomment">Choose one of the following concentrations:</span></td><td class="hourscol">43-59</td></tr>
          </tbody></table>
          <h2>Concentrations</h2>
          <h3>Jazz Studies Concentration</h3>
          <table class="sc_courselist"><tbody>
            <tr><td class="codecol"><a href="/search/?P=MUS%20340">MUS 340</a></td><td>Jazz Studies</td><td class="hourscol">3</td></tr>
          </tbody></table>
          <h3>Music Education Concentration</h3>
          <h4>Professional Education Sequence Requirements</h4>
          <table class="sc_courselist"><tbody>
            <tr><td class="codecol"><a href="/search/?P=EDUC%20310">EDUC 310</a></td><td>Teaching and Learning</td><td class="hourscol">3</td></tr>
          </tbody></table>
          <h4>Music Education, Instrumental Track</h4>
          <h5>Subtrack in Winds Requirements</h5>
          <table class="sc_courselist"><tbody>
            <tr><td class="codecol"><a href="/search/?P=MUS%20350">MUS 350</a></td><td>Wind Methods</td><td class="hourscol">3</td></tr>
          </tbody></table>
          <h5>Subtrack in Strings Requirements</h5>
          <table class="sc_courselist"><tbody>
            <tr><td class="codecol"><a href="/search/?P=MUS%20351">MUS 351</a></td><td>String Methods</td><td class="hourscol">3</td></tr>
          </tbody></table>
          <h4>Music Education, Vocal Track</h4>
          <table class="sc_courselist"><tbody>
            <tr><td class="codecol"><a href="/search/?P=MUS%20404">MUS 404</a></td><td>Vocal Pedagogy</td><td class="hourscol">3</td></tr>
          </tbody></table>
        </div>
        <div id="recommendedscheduletextcontainer"></div>
        """
        let sourceURL = try #require(URL(string: "https://catalog.jmu.edu/programs/music-bm/"))

        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: sourceURL)
        let byName = Dictionary(uniqueKeysWithValues: parsed.concentrations.map { ($0.name, $0) })

        #expect(parsed.concentrationSelectionRequired)
        #expect(Set(byName.keys) == [
            "Jazz Studies",
            "Music Education, Instrumental Track - Winds",
            "Music Education, Instrumental Track - Strings",
            "Music Education, Vocal"
        ])
        let winds = try #require(byName["Music Education, Instrumental Track - Winds"])
        let windCourses = Set(winds.requirements.flatMap(\.courseOptions).flatMap { $0 })
        #expect(windCourses.contains("EDUC310"))
        #expect(windCourses.contains("MUS350"))
        #expect(!windCourses.contains("MUS351"))
        #expect(!windCourses.contains("MUS404"))
        let vocal = try #require(byName["Music Education, Vocal"])
        let vocalCourses = Set(vocal.requirements.flatMap(\.courseOptions).flatMap { $0 })
        #expect(vocalCourses.contains("EDUC310"))
        #expect(vocalCourses.contains("MUS404"))
        #expect(!vocalCourses.contains("MUS350"))
        #expect(parsed.requirements.flatMap(\.courseOptions).flatMap { $0 } == ["MUS143"])
    }

    @Test("program index extracts majors and minors from JMU program lists")
    func parsesProgramIndex() throws {
        let html = """
        <p style="padding-left: 30px"><strong>Major</strong></p>
        <ul class="program-list">
        <li><a href="preview_program.php?catoid=62&poid=27091&returnto=3541">Computer Science, B.S.</a></li>
        </ul>
        <p style="padding-left: 30px"><strong>Cross Disciplinary Minor</strong></p>
        <ul class="program-list">
        <li><a href="preview_program.php?catoid=62&amp;poid=27015&amp;returnto=3541">Robotics Minor</a></li>
        </ul>
        """

        let entries = JMUHTMLCatalogParser().parseProgramsOfStudy(html)

        #expect(entries.count == 2)
        #expect(entries[0].title == "Computer Science, B.S.")
        #expect(entries[0].kind == .major)
        #expect(entries[0].degreeType == "B.S.")
        #expect(entries[0].printURL.absoluteString.contains("poid=27091"))
        #expect(entries[1].title == "Robotics Minor")
        #expect(entries[1].kind == .minor)
    }

    @Test("program requirements preserve required courses and choice groups")
    func parsesProgramRequirements() throws {
        let html = """
        <h1 id="acalog-content">Computer Science Minor</h1>
        <div class="acalog-core"><h2><a name="MinorRequirements"></a>Minor Requirements</h2><hr></div>
        <div class="custom_leftpad_20">
          <div class="acalog-core"><h3><a name="IntroductoryCourses6CreditHours"></a>Introductory Courses: 6 Credit Hours</h3><hr>
            <ul>
              <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '368727',this, 'x'); return false;">CS 149. Introduction to Programming</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
              <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '368728',this, 'x'); return false;">CS 159. Advanced Programming</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            </ul>
          </div>
          <div class="acalog-core"><h3><a name="CoreCourse3CreditHours"></a>Core Course: 3 Credit Hours</h3><hr>
            <p>Choose one of the following:</p>
            <ul>
              <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '368704',this, 'x'); return false;">CS 240. Algorithms and Data Structures</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
              <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '368734',this, 'x'); return false;">CS 261. Computer Systems I</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            </ul>
          </div>
          <div class="acalog-core"><h2><a name="Total18CreditHours"></a>Total: 18 Credit Hours</h2><hr></div>
        </div>
        """

        let sourceURL = try #require(URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=27051&returnto=3541"))
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .minor, sourceURL: sourceURL)

        #expect(parsed.title == "Computer Science Minor")
        #expect(parsed.requirements.count == 2)
        #expect(parsed.requirements[0].requiredCredits == 6)
        #expect(parsed.requirements[0].courseOptions == [["CS149"], ["CS159"]])
        #expect(parsed.requirements[1].courseOptions == [["CS240", "CS261"]])
        #expect(parsed.courses.map(\.id).sorted() == ["CS149", "CS159", "CS240", "CS261"])
        #expect(parsed.courses.first(where: { $0.id == "CS149" })?.registrarURL?.absoluteString.contains("coid=368727") == true)
    }

    @Test("or markers create alternate course options")
    func parsesOrAlternates() throws {
        let html = """
        <h1 id="acalog-content">Accounting, B.B.A.</h1>
        <div class="acalog-core"><h2><a name="DegreeAndMajorRequirements"></a>Degree and Major Requirements</h2><hr></div>
        <div class="acalog-core"><h3><a name="MathChoice34CreditHours"></a>Math Choice: 3-4 Credit Hours</h3><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '370246',this, 'x'); return false;">MATH 205. Applied Calculus [C3QR]</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-adhoc acalog-adhoc-after" style="list-style: none;"><p>or</p></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '370231',this, 'x'); return false;">MATH 235. Calculus I [C3QR]</a> <em><strong>Credits:</strong></em> <em>4.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h2><a name="RecommendedScheduleForMajors"></a>Recommended Schedule for Majors</h2><hr></div>
        """

        let sourceURL = try #require(URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=27172&returnto=3541"))
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: sourceURL)

        let math = try #require(parsed.requirements.first)
        #expect(math.courseOptions == [["MATH205", "MATH235"]])
        #expect(math.requiredCredits == 3)
    }

    @Test("nested acalog wrappers do not hide the first child requirement")
    func parsesNestedRequirementWrappers() throws {
        let html = """
        <h1 id="acalog-content">Accounting, B.B.A.</h1>
        <div class="acalog-core"><h2><a name="DegreeAndMajorRequirements"></a>Degree and Major Requirements</h2><hr></div>
        <div class="acalog-core"><h2><a name="BBACoreComponent"></a>B.B.A. Core Component</h2><hr>
          <div class="custom_leftpad_20">
            <div class="acalog-core"><h3><a name="LowerCore"></a>Lower Core: 6 Credit Hours</h3><hr>
              <ul>
                <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '368535',this, 'x'); return false;">COB 191. Business Analytics I</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
                <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '368544',this, 'x'); return false;">COB 202. Interpersonal Skills</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
              </ul>
            </div>
            <div class="acalog-core"><h3><a name="UpperCore"></a>Upper Core: 3 Credit Hours</h3><hr>
              <ul>
                <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '368543',this, 'x'); return false;">COB 487. Strategic Management</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
              </ul>
            </div>
          </div>
        </div>
        <div class="acalog-core"><h2><a name="RecommendedScheduleForMajors"></a>Recommended Schedule for Majors</h2><hr></div>
        """

        let sourceURL = try #require(URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=27172&returnto=3541"))
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: sourceURL)

        #expect(parsed.requirements.map(\.name) == ["Lower Core: 6 Credit Hours", "Upper Core: 3 Credit Hours"])
        #expect(parsed.requirements[0].courseOptions == [["COB191"], ["COB202"]])
        #expect(parsed.requirements[1].courseOptions == [["COB487"]])
    }

    @Test("choose multiple requirements use concrete default choices")
    func parsesChooseMultipleDefaults() throws {
        let html = """
        <h1 id="acalog-content">Example, B.S.</h1>
        <div class="acalog-core"><h2><a name="MajorRequirements"></a>Major Requirements</h2><hr></div>
        <div class="acalog-core"><h3><a name="Electives9CreditHours"></a>Electives: 9 Credit Hours</h3><hr>
          <p>Choose three of the following:</p>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '1',this, 'x'); return false;">CS 343. Application Development</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '2',this, 'x'); return false;">CS 374. Database Systems</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '3',this, 'x'); return false;">CS 444. Artificial Intelligence</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '4',this, 'x'); return false;">CS 450. Operating Systems</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h2><a name="AdditionalInformation"></a>Additional Information</h2><hr></div>
        """

        let sourceURL = try #require(URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=1&returnto=3541"))
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: sourceURL)

        let electives = try #require(parsed.requirements.first)
        // "Choose three of the following" now emits three parallel options,
        // each exposing the full alternate pool, so the schedule produces
        // three picker placeholders rather than hard-coding the first three
        // entries as required.
        let fullPool = ["CS343", "CS374", "CS444", "CS450"]
        #expect(electives.courseOptions == [fullPool, fullPool, fullPool])
        #expect(electives.note?.contains("choice requirement") == true)
    }

    @Test("credit-hour choice headings cap credits and placeholder slots")
    func creditHourChoiceCapsPlaceholders() throws {
        let html = """
        <h1 id="acalog-content">Statistics, B.S.</h1>
        <div class="acalog-core"><h2><a name="MajorRequirements"></a>Major Requirements</h2><hr></div>
        <div class="acalog-core"><h3><a name="StatisticsElectives"></a>Please choose six credit hours from the following:</h3><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '1',this, 'x'); return false;">MATH 324. Applied Regression Analysis</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '2',this, 'x'); return false;">MATH 325. Applied Linear Regression</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '3',this, 'x'); return false;">MATH 326. Design and Analysis of Experiments</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '4',this, 'x'); return false;">MATH 354. Modern College Geometry</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '5',this, 'x'); return false;">MATH 368. Mathematical Models</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '6',this, 'x'); return false;">MATH 410. Introduction to Real Analysis I</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        """

        let sourceURL = try #require(URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=1&returnto=3541"))
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: sourceURL)
        let requirement = try #require(parsed.requirements.first)
        let fullPool = ["MATH324", "MATH325", "MATH326", "MATH354", "MATH368", "MATH410"]

        #expect(requirement.requiredCredits == 6)
        #expect(requirement.courseOptions == [fullPool, fullPool])

        let catalog = Catalog.fixture(
            courses: parsed.courses,
            program: Program.fixture(
                id: "statistics-bs",
                title: "Statistics, B.S.",
                requirements: parsed.requirements
            )
        )
        let pathway = try #require(try ScheduleGenerator(catalog: catalog).generatePathways(
            for: "statistics-bs",
            workload: .standard,
            transferCredits: []
        ).first)
        let choicePlaceholders = pathway.placeholders.values.filter { $0.categoryID == requirement.id }
        #expect(choicePlaceholders.count == 2)
        #expect(choicePlaceholders.reduce(0) { $0 + $1.credits } == 6)
    }

    @Test("major concentrations are split out of parent requirements")
    func parsesConcentrationsSeparatelyFromParentRequirements() throws {
        let html = """
        <h1 id="acalog-content">Physics, B.S.</h1>
        <div class="acalog-core"><h2><a name="DegreeAndMajorRequirements"></a>Degree and Major Requirements</h2><hr></div>
        <div class="acalog-core"><h3><a name="PhysicsCore"></a>Physics Core: 4 Credit Hours</h3><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '1',this, 'x'); return false;">PHYS 240. University Physics I</a> <em><strong>Credits:</strong></em> <em>4.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h2><a name="Concentrations"></a>Concentrations</h2><hr></div>
        <div class="acalog-core"><h3><a name="AppliedPhysicsConcentration"></a>Applied Physics Concentration</h3><hr></div>
        <div class="acalog-core"><h4><a name="AppliedPhysicsRequiredCourses"></a>Applied Physics Required Courses: 3 Credit Hours</h4><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '2',this, 'x'); return false;">PHYS 360. Modern Physics</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h3><a name="FundamentalStudiesConcentration"></a>Fundamental Studies Concentration</h3><hr></div>
        <div class="acalog-core"><h4><a name="FundamentalStudiesRequiredCourses"></a>Fundamental Studies Required Courses: 3 Credit Hours</h4><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '3',this, 'x'); return false;">PHYS 390. Advanced Seminar</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h2><a name="RecommendedScheduleForMajors"></a>Recommended Schedule for Majors</h2><hr></div>
        """

        let sourceURL = try #require(URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=27000&returnto=3541"))
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: sourceURL)

        #expect(parsed.requirements.map(\.name) == ["Physics Core: 4 Credit Hours"])
        #expect(parsed.requirements.flatMap(\.courseOptions).flatMap { $0 } == ["PHYS240"])
        #expect(parsed.concentrationSelectionRequired)
        #expect(parsed.concentrations.map(\.name) == ["Applied Physics", "Fundamental Studies"])
        #expect(parsed.concentrations[0].requirements.map(\.name) == ["Applied Physics Required Courses: 3 Credit Hours"])
        #expect(parsed.concentrations[0].requirements.flatMap(\.courseOptions).flatMap { $0 } == ["PHYS360"])
        #expect(parsed.concentrations[1].requirements.flatMap(\.courseOptions).flatMap { $0 } == ["PHYS390"])
        #expect(parsed.courses.map(\.id).sorted() == ["PHYS240", "PHYS360", "PHYS390"])
    }

    @Test("umbrella concentrations with plain-named children are split out (Music B.M. shape)")
    func parsesPlainNamedConcentrationsUnderUmbrella() throws {
        let html = """
        <h1 id="acalog-content">Music, B.M.</h1>
        <div class="acalog-core"><h2><a name="MajorRequirements"></a>Major Requirements</h2><hr></div>
        <div class="acalog-core"><h3><a name="MusicCore"></a>Music Core: 3 Credit Hours</h3><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '1',this, 'x'); return false;">MUS 141. Music Theory I</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h2><a name="Concentrations"></a>Concentrations</h2><hr></div>
        <div class="acalog-core"><h3><a name="Composition"></a>Composition</h3><hr></div>
        <div class="acalog-core"><h4><a name="CompositionRequiredCourses"></a>Required Courses: 3 Credit Hours</h4><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '2',this, 'x'); return false;">MUS 300. Composition Seminar</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h3><a name="JazzStudies"></a>Jazz Studies</h3><hr></div>
        <div class="acalog-core"><h4><a name="JazzRequiredCourses"></a>Required Courses: 3 Credit Hours</h4><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '3',this, 'x'); return false;">MUS 310. Jazz Improvisation</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h3><a name="MusicIndustry"></a>Music Industry</h3><hr></div>
        <div class="acalog-core"><h4><a name="IndustryRequiredCourses"></a>Required Courses: 3 Credit Hours</h4><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '4',this, 'x'); return false;">MUS 320. Music Business</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h2><a name="RecommendedScheduleForMajors"></a>Recommended Schedule for Majors</h2><hr></div>
        """

        let sourceURL = try #require(URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=27191&returnto=3541"))
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: sourceURL)

        #expect(parsed.requirements.map(\.name) == ["Music Core: 3 Credit Hours"])
        #expect(parsed.concentrations.map(\.name) == ["Composition", "Jazz Studies", "Music Industry"])
        #expect(parsed.concentrationSelectionRequired)
        #expect(parsed.concentrations[0].requirements.flatMap(\.courseOptions).flatMap { $0 } == ["MUS300"])
        #expect(parsed.concentrations[1].requirements.flatMap(\.courseOptions).flatMap { $0 } == ["MUS310"])
        #expect(parsed.concentrations[2].requirements.flatMap(\.courseOptions).flatMap { $0 } == ["MUS320"])
    }

    @Test("optional concentration sections keep base major selectable")
    func parsesOptionalConcentrationSections() throws {
        let html = """
        <h1 id="acalog-content">Statistics, B.S.</h1>
        <div class="acalog-core"><h2><a name="MajorRequirements"></a>Major Requirements</h2><hr>
          <p>Students may choose either a standard statistics major or a statistics major with a data science concentration.</p>
        </div>
        <div class="acalog-core"><h3><a name="CoreCourses"></a>Core Courses: 3 Credit Hours</h3><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '1',this, 'x'); return false;">MATH 329. Introduction to Probability and Theoretical Statistics</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h3><a name="AdditionalRequirements"></a>Additional Requirements: 3 Credit Hours</h3><hr>
          <p>Students who do not elect to complete a concentration in data science must take the following credit hours.</p>
        </div>
        <div class="acalog-core"><h4><a name="AdditionalRequiredCourses"></a>Additional Required Courses: 3 Credit Hours</h4><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '2',this, 'x'); return false;">MATH 428. Statistical Consulting</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h3><a name="DataScienceConcentration"></a>Data Science Concentration: 3 Credit Hours</h3><hr>
          <p>Students who declare the concentration in data science must take the following credit hours in addition to the core courses.</p>
        </div>
        <div class="acalog-core"><h4><a name="DataScienceRequiredCourses"></a>Data Science Required Courses: 3 Credit Hours</h4><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '3',this, 'x'); return false;">DATA 200. Introduction to Data</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h2><a name="RecommendedScheduleForMajors"></a>Recommended Schedule for Majors</h2><hr></div>
        """

        let sourceURL = try #require(URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=27125&returnto=3541"))
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: sourceURL)

        #expect(!parsed.concentrationSelectionRequired)
        #expect(parsed.requirements.map(\.name) == [
            "Core Courses: 3 Credit Hours",
            "Additional Requirements: 3 Credit Hours",
            "Additional Required Courses: 3 Credit Hours"
        ])
        #expect(parsed.requirements.flatMap(\.courseOptions).flatMap { $0 } == ["MATH329", "MATH428"])
        #expect(parsed.concentrations.map(\.name) == ["Data Science"])
        #expect(parsed.concentrations.first?.requirements.flatMap(\.courseOptions).flatMap { $0 } == ["DATA200"])
    }

    @Test("required concentration sections create selectable concentration tracks")
    func parsesRequiredConcentrationSections() throws {
        let html = """
        <h1 id="acalog-content">Computer Information Systems, B.B.A.</h1>
        <div class="acalog-core"><h2><a name="DegreeAndMajorRequirements"></a>Degree and Major Requirements</h2><hr></div>
        <div class="acalog-core"><h3><a name="MajorRequirements"></a>Major Requirements</h3><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '1',this, 'x'); return false;">CIS 221. Principles of Programming</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h2><a name="RequiredConcentration"></a>Required Concentration</h2><hr></div>
        <div class="acalog-core"><h3><a name="InformationAndCybersecurityManagementConcentration"></a>Information and Cybersecurity Management Concentration</h3><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '2',this, 'x'); return false;">CIS 301. Cloud Server Management</a> <em><strong>Credits:</strong></em> <em>1.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '3',this, 'x'); return false;">CIS 424. Computer Security Management</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '4',this, 'x'); return false;">CIS 425. Defensive Cybersecurity</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h4><a name="InformationAndCybersecurityManagementConcentrationElectives"></a>Information and Cybersecurity Management Concentration Electives</h4><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '5',this, 'x'); return false;">CIS 420. Advanced Topics in Computing Networks</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h2><a name="CooperativeEducationConcentration"></a>Cooperative Education Concentration</h2><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '6',this, 'x'); return false;">CIS 498. Special Topics in Computer Information Systems</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h2><a name="RecommendedScheduleForMajors"></a>Recommended Schedule for Majors</h2><hr></div>
        """

        let sourceURL = try #require(URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=27090&returnto=3541"))
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: sourceURL)

        #expect(parsed.requirements.map(\.name) == ["Major Requirements"])
        #expect(parsed.requirements.flatMap(\.courseOptions).flatMap { $0 } == ["CIS221"])
        #expect(parsed.concentrationSelectionRequired)
        #expect(parsed.concentrations.map(\.name) == ["Information and Cybersecurity Management"])
        let cybersecurity = try #require(parsed.concentrations.first)
        #expect(cybersecurity.requirements.map(\.name) == [
            "Information and Cybersecurity Management Concentration",
            "Information and Cybersecurity Management Concentration Electives"
        ])
        #expect(cybersecurity.requirements.flatMap(\.courseOptions).flatMap { $0 } == ["CIS301", "CIS424", "CIS425", "CIS420"])
    }

    @Test("concentration total caps inferred elective credits")
    func concentrationTotalCapsInferredElectiveCredits() throws {
        let html = """
        <h1 id="acalog-content">Computer Information Systems, B.B.A.</h1>
        <div class="acalog-core"><h2><a name="DegreeAndMajorRequirements"></a>Degree and Major Requirements</h2><hr></div>
        <div class="acalog-core"><h2><a name="RequiredConcentration"></a>Required Concentration</h2><hr></div>
        <div class="acalog-core"><h3><a name="InformationSystemsConcentration"></a>Information Systems Concentration</h3><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '1',this, 'x'); return false;">CIS 330. Database Design and Application</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '2',this, 'x'); return false;">CIS 454. Systems Analysis and Design</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '3',this, 'x'); return false;">CIS 484. Information Systems Development and Implementation</a> <em><strong>Credits:</strong></em> <em>1.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h4><a name="InformationSystemsConcentrationElectives"></a>Information Systems Concentration Electives</h4><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '4',this, 'x'); return false;">CIS 354. Advanced Visual Basic Programming</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '5',this, 'x'); return false;">CIS 366. Web Design and Development</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '6',this, 'x'); return false;">CIS 420. Advanced Topics in Computing Networks</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '7',this, 'x'); return false;">CIS 424. Computer Security Management</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '8',this, 'x'); return false;">CIS 490. Special Studies</a> <em><strong>Credits:</strong></em> <em>1.00 - 3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h4><a name="InformationSystemsConcentrationTotal13CreditHours"></a>Information Systems Concentration Total: 13 Credit Hours</h4><hr></div>
        <div class="acalog-core"><h2><a name="RecommendedScheduleForMajors"></a>Recommended Schedule for Majors</h2><hr></div>
        """

        let sourceURL = try #require(URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=27090&returnto=3541"))
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .major, sourceURL: sourceURL)

        let concentration = try #require(parsed.concentrations.first)
        let electives = try #require(concentration.requirements.first { $0.name.contains("Electives") })
        #expect(electives.requiredCredits == 6)
        #expect(electives.courseOptions.count == 5)
    }

    @Test("minor page without a Requirements heading still produces requirements")
    func parsesMinorWithoutRequirementsHeading() throws {
        // Many JMU minor pages drop the "Minor Requirements" H2 entirely and
        // list "Required Courses", "Electives" blocks as siblings under the
        // top H1. Parser must fall back to the first acalog-core block.
        let html = """
        <h1 id="acalog-content">African, African American and Diaspora Studies Minor</h1>
        <div class="acalog-core"><h2><a name="RequiredCourses4CreditHours"></a>Required Courses: 4 Credit Hours</h2><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '1',this, 'x'); return false;">AAAD 200. Introduction to AAAD</a> <em><strong>Credits:</strong></em> <em>4.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h2><a name="Electives15CreditHours"></a>Electives: 15 Credit Hours</h2><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '2',this, 'x'); return false;">AAAD 300. African Diaspora Studies</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '3',this, 'x'); return false;">AAAD 310. Black Feminist Thought</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        """

        let url = try #require(URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=26992"))
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .minor, sourceURL: url)

        #expect(parsed.requirements.count == 2)
        #expect(parsed.requirements.first?.name.contains("Required Courses") == true)
        #expect(parsed.requirements.flatMap(\.courseOptions).flatMap { $0 }.contains("AAAD200"))
    }

    @Test("minor pathway labeled \"Option 1\" / \"Option 2\" becomes selectable concentrations")
    func parsesNumberedOptionsAsConcentrations() throws {
        let html = """
        <h1 id="acalog-content">Robotics Minor</h1>
        <div class="acalog-core"><h2><a name="Core"></a>Core: 3 Credit Hours</h2><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '1',this, 'x'); return false;">ROB 200. Intro Robotics</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h2><a name="Option1"></a>Option 1: Aerial Robotics</h2><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '2',this, 'x'); return false;">ROB 310. UAV Systems</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        <div class="acalog-core"><h2><a name="Option2"></a>Option 2: Ground Robotics</h2><hr>
          <ul>
            <li class="acalog-course"><span><a href="#" onClick="showCourse('62', '3',this, 'x'); return false;">ROB 320. Mobile Robots</a> <em><strong>Credits:</strong></em> <em>3.00</em></span></li>
          </ul>
        </div>
        """

        let url = try #require(URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=1"))
        let parsed = JMUHTMLCatalogParser().parseProgramRequirements(html, kind: .minor, sourceURL: url)

        #expect(parsed.concentrations.count == 2, "Option 1 and Option 2 must each become a concentration entry")
        let names = parsed.concentrations.map(\.name)
        #expect(names.contains(where: { $0.contains("Aerial Robotics") }))
        #expect(names.contains(where: { $0.contains("Ground Robotics") }))
        // The shared "Core" must remain on the parent requirements, not folded into a concentration.
        #expect(parsed.requirements.contains { $0.name.contains("Core") })
    }
}
