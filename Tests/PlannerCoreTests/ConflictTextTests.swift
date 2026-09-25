import Foundation
import Testing
@testable import PlannerCore

@Suite("Conflict severity and text")
struct ConflictTextTests {
    static let fall26 = SemesterIdentity(year: 2026, term: .fall)
    static let spring27 = SemesterIdentity(year: 2027, term: .spring)

    static let catalog = Catalog.fixture(
        courses: [
            Course(id: "MATH231", code: "MATH 231", title: "Calculus I", credits: 4, availability: [.fall, .spring], prerequisites: []),
            Course(id: "MATH232", code: "MATH 232", title: "Calculus II", credits: 4, availability: [.fall, .spring], prerequisites: ["MATH231"]),
            Course(id: "CS261", code: "CS 261", title: "Computer Systems I", credits: 3, availability: [.fall], prerequisites: []),
            Course(id: "CHEM131", code: "CHEM 131", title: "General Chemistry", credits: 3, availability: [.fall, .spring], prerequisites: []),
            Course(id: "CHEM131L", code: "CHEM 131L", title: "General Chemistry Lab", credits: 1, availability: [.fall, .spring], prerequisites: [], corequisiteExpr: .course("CHEM131"))
        ],
        program: Program.fixture(id: "p", title: "Program", requirements: [])
    )

    static func warnings() -> [ConflictWarning] {
        let pathway = Pathway(id: "text", name: "Text", semesters: [
            SemesterPlan(id: fall26, courseIDs: ["MATH232"]),
            SemesterPlan(id: spring27, courseIDs: ["CS261", "CHEM131L"])
        ])
        return ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: [])
    }

    private func warning(_ kind: ConflictKind) throws -> ConflictWarning {
        try #require(Self.warnings().first { $0.kind == kind })
    }

    @Test("each kind maps to one severity")
    func severityTable() {
        #expect(ConflictKind.missingPrerequisite.severity == .mustFix)
        #expect(ConflictKind.unavailableSemester.severity == .mustFix)
        #expect(ConflictKind.missingCorequisite.severity == .worthALook)
        #expect(ConflictKind.heavyLoad.severity == .worthALook)
        #expect(ConflictKind.lightLoad.severity == .worthALook)
        #expect(ConflictKind.unknownAvailability.severity == .hidden)
        #expect(ConflictSeverity.hidden < .worthALook && ConflictSeverity.worthALook < .mustFix)
    }

    @Test("popover titles read as plain phrases")
    func titles() {
        #expect(ConflictKind.missingPrerequisite.title == "Missing prerequisite")
        #expect(ConflictKind.missingCorequisite.title == "Missing corequisite")
        #expect(ConflictKind.unavailableSemester.title == "Not offered this term")
        #expect(ConflictKind.heavyLoad.title == "Heavy load")
        #expect(ConflictKind.lightLoad.title == "Light load")
        #expect(ConflictKind.unknownAvailability.title == "Availability unknown")
    }

    @Test("prerequisite warnings split summary, detail, and caveats")
    func prerequisiteText() throws {
        let warning = try warning(.missingPrerequisite)
        #expect(warning.summary == "Needs MATH 231")
        #expect(warning.detail == "Needs MATH 231. still missing MATH 231.")
        #expect(warning.notes == ["Parsed from catalog text; verify before registering."])
        #expect(warning.message == "Needs MATH 231. still missing MATH 231. Parsed from catalog text; verify before registering.")
        #expect(warning.missingCourseIDs == ["MATH231"])
    }

    @Test("corequisite warnings name the course to take alongside")
    func corequisiteText() throws {
        let warning = try warning(.missingCorequisite)
        #expect(warning.summary == "Take with CHEM 131")
        #expect(warning.detail == "Take alongside or before this course: CHEM 131.")
        #expect(warning.notes.isEmpty)
        #expect(warning.message == warning.detail)
        #expect(warning.missingCourseIDs == ["CHEM131"])
    }

    @Test("availability warnings name the term")
    func availabilityText() throws {
        let warning = try warning(.unavailableSemester)
        #expect(warning.summary == "Not offered in Spring")
        #expect(warning.detail == "CS 261 is not marked as typically offered in Spring.")
    }

    @Test("semester-level warnings use the reserved subject")
    func semesterSubject() throws {
        let load = ConflictWarning(
            courseID: ConflictWarning.semesterSubjectID, semester: Self.fall26, kind: .heavyLoad,
            summary: "Heavy load (19 cr)", detail: "19 credits", isOverridden: false
        )
        #expect(load.isSemesterLevel)
        #expect(!(try warning(.missingPrerequisite)).isSemesterLevel)
    }

    @Test("warnings saved before this change still decode")
    func legacyDecoding() throws {
        let json = """
        {"id":"X-2026-Fall-missingPrerequisite","courseID":"X","semester":{"year":2026,"term":"Fall"},\
        "kind":"missingPrerequisite","message":"Needs Y.","isOverridden":false}
        """
        let decoded = try JSONDecoder().decode(ConflictWarning.self, from: Data(json.utf8))
        #expect(decoded.summary == "Needs Y.")
        #expect(decoded.detail == "Needs Y.")
        #expect(decoded.notes.isEmpty)
        #expect(decoded.missingCourseIDs.isEmpty)
        #expect(decoded.message == "Needs Y.")
    }

    @Test("new fields survive an encode/decode round trip")
    func roundTrip() throws {
        let original = try warning(.missingPrerequisite)
        let decoded = try JSONDecoder().decode(ConflictWarning.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
