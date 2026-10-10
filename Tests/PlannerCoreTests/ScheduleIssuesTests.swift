import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Schedule issues and warning tags")
struct ScheduleIssuesTests {
    static let fall26 = SemesterIdentity(year: 2026, term: .fall)
    static let spring27 = SemesterIdentity(year: 2027, term: .spring)

    static let catalog = Catalog.fixture(
        courses: [
            Course(id: "B", code: "BIO 100", title: "B", credits: 3, availability: [.fall, .spring], prerequisites: []),
            Course(id: "A", code: "ART 100", title: "A", credits: 3, availability: [.fall, .spring], prerequisites: [])
        ],
        program: Program.fixture(id: "p", title: "P", requirements: [])
    )

    static func w(_ course: String, _ semester: SemesterIdentity, _ kind: ConflictKind, kept: Bool = false, summary: String = "") -> ConflictWarning {
        ConflictWarning(courseID: course, semester: semester, kind: kind, summary: summary.isEmpty ? kind.title : summary, detail: "", isOverridden: kept)
    }

    static let load = w(ConflictWarning.semesterSubjectID, spring27, .heavyLoad)
    static let bPrereq = w("B", fall26, .missingPrerequisite, summary: "Needs CHEM 131")
    static let bCoreq = w("B", fall26, .missingCorequisite)
    static let aUnavailable = w("A", spring27, .unavailableSemester)
    static let aKept = w("A", fall26, .missingCorequisite, kept: true)
    static let hidden = w("A", fall26, .unknownAvailability)

    static let issues = ScheduleIssues([aUnavailable, bCoreq, load, hidden, aKept, bPrereq], catalog: catalog)

    @Test("a pending prerequisite choice is a worth-a-look issue on its placeholder")
    func pendingChoiceOnItsSlot() {
        let slot = PathwayPlaceholder.id(categoryID: "choice", optionIndex: 0)
        let notice = Self.w(slot, Self.fall26, .pendingPrerequisiteChoice)
        let issues = ScheduleIssues([notice, Self.bPrereq], catalog: Self.catalog)
        #expect(issues.worthALook == [notice])
        #expect(issues.mustFix == [Self.bPrereq])
        #expect(issues.warnings(for: slot, in: Self.fall26) == [notice])
    }

    @Test("groups by severity, drops hidden, orders by semester then course code")
    func grouping() {
        #expect(Self.issues.mustFix == [Self.bPrereq, Self.aUnavailable])
        #expect(Self.issues.worthALook == [Self.bCoreq, Self.load])
        #expect(Self.issues.kept == [Self.aKept])
        #expect(Self.issues.activeCount == 4)
        #expect(Self.issues.worstActive == .mustFix)
    }

    @Test("semester-level warnings sort before courses in the same semester")
    func semesterFirst() {
        let issues = ScheduleIssues([Self.aUnavailable, Self.w(ConflictWarning.semesterSubjectID, Self.spring27, .lightLoad)], catalog: Self.catalog)
        #expect(issues.worthALook.first?.isSemesterLevel == true)
        #expect(issues.mustFix == [Self.aUnavailable])
    }

    @Test("per-semester worst severity ignores kept warnings")
    func worstPerSemester() {
        #expect(Self.issues.worstActive(in: Self.fall26) == .mustFix)
        #expect(Self.issues.worstActive(in: Self.spring27) == .mustFix)
        let keptOnly = ScheduleIssues([Self.aKept], catalog: Self.catalog)
        #expect(keptOnly.worstActive(in: Self.fall26) == nil)
        #expect(keptOnly.worstActive == nil)
    }

    @Test("button title counts active issues")
    func buttonTitle() {
        #expect(Self.issues.buttonTitle == "4 issues")
        #expect(ScheduleIssues([Self.bCoreq], catalog: Self.catalog).buttonTitle == "1 issue")
        #expect(ScheduleIssues([Self.aKept], catalog: Self.catalog).buttonTitle == "No issues")
        #expect(ScheduleIssues.empty.buttonTitle == "No issues")
    }

    @Test("lookups return a chip's or semester's warnings, active and kept")
    func lookups() {
        #expect(Self.issues.warnings(for: "B", in: Self.fall26) == [Self.bPrereq, Self.bCoreq])
        #expect(Self.issues.warnings(for: "A", in: Self.fall26) == [Self.aKept])
        #expect(Self.issues.semesterWarnings(in: Self.spring27) == [Self.load])
    }

    @Test("tag shows the worst active warning plus a count")
    func tagWorstFirst() throws {
        let model = try #require(WarningTagModel(warnings: [Self.bCoreq, Self.bPrereq]))
        #expect(model.primary == Self.bPrereq)
        #expect(model.tone == .mustFix)
        #expect(model.label == "Needs CHEM 131 +1")
    }

    @Test("a chip whose warnings are all kept shows Kept")
    func tagKept() throws {
        let model = try #require(WarningTagModel(warnings: [Self.aKept]))
        #expect(model.tone == .kept)
        #expect(model.label == "Kept")
    }

    @Test("active warnings outrank kept ones on the tag")
    func tagActiveBeforeKept() throws {
        let kept = Self.w("B", Self.fall26, .missingPrerequisite, kept: true)
        let model = try #require(WarningTagModel(warnings: [kept, Self.bCoreq]))
        #expect(model.primary == Self.bCoreq)
        #expect(model.tone == .worthALook)
    }

    @Test("long summaries stay on one line")
    func longSummaryIsOneLine() throws {
        let long = Self.w("B", Self.fall26, .missingPrerequisite, summary: "Needs (MATH 231 or MATH 235) and (PHYS 140 or PHYS 240)")
        let model = try #require(WarningTagModel(warnings: [long]))
        #expect(!model.label.contains("\n"))
    }

    @Test("no warnings, no tag")
    func noTag() {
        #expect(WarningTagModel(warnings: []) == nil)
    }

    @Test("the list opens the popover of the tag that shows the warning")
    func tagID() {
        #expect(Self.issues.tagID(for: Self.bCoreq) == WarningTagModel(warnings: [Self.bPrereq, Self.bCoreq])?.key)
        #expect(Self.issues.tagID(for: Self.load) == WarningTagModel(warnings: [Self.load])?.key)
    }

    @Test("a tag keeps its popover identity when its top warning is kept")
    func tagKeyIsStable() throws {
        let active = try #require(WarningTagModel(warnings: [Self.bPrereq, Self.bCoreq]))
        let keptPrereq = Self.w("B", Self.fall26, .missingPrerequisite, kept: true)
        let afterKeep = try #require(WarningTagModel(warnings: [keptPrereq, Self.bCoreq]))
        #expect(afterKeep.primary == Self.bCoreq)
        #expect(afterKeep.key == active.key)
        #expect(Self.issues.tagID(for: Self.bCoreq) == active.key)
        #expect(Self.issues.tagID(for: Self.load) != active.key)
    }

    @Test("issues know which tags exist")
    func containsTag() throws {
        let key = try #require(WarningTagModel(warnings: [Self.bPrereq])).key
        #expect(Self.issues.containsTag(key))
        #expect(!ScheduleIssues.empty.containsTag(key))
    }
}
