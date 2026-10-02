import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite struct AcademicHistoryTests {
    @Test func legacyAndRoundTrip() throws {
        let old = SavedStudentPlan(transferCredits: [TransferCredit(sourceDescription: "AP Test", courseIDs: ["CS149"], credits: 3)])
        let data = try JSONEncoder().encode(old)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["studentYear", "academicRecords", "currentSemester", "setupCompleted", "planningStart"] { json.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(SavedStudentPlan.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.academicRecords.isEmpty)
        #expect(legacy.currentSemester == nil)
        #expect(legacy.transferCredits.first?.credits == 3)
        var plan = old
        plan.studentYear = .junior
        plan.currentSemester = SemesterPlan(id: .init(year: 2026, term: .fall), courseIDs: ["UNKNOWN"], creditOverrides: ["UNKNOWN": 1.5], courseTitles: ["UNKNOWN": "Special study"])
        #expect(try JSONDecoder().decode(SavedStudentPlan.self, from: JSONEncoder().encode(plan)) == plan)
        #expect(CreditHoursFormatter.string(1.5) == "1.5")
        #expect(CreditHoursFormatter.string(3) == "3")
    }
    @Test func legacyCreditSourceDefaults() throws {
        let json = "{\"id\":\"00000000-0000-0000-0000-000000000001\",\"sourceDescription\":\"Dual enrollment\",\"courseIDs\":[\"CS149\"],\"credits\":3}"
        let credit = try JSONDecoder().decode(TransferCredit.self, from: Data(json.utf8))
        #expect(credit.source == .legacy)
    }
}
