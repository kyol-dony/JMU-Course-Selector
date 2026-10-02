import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite struct TranscriptReviewTests {
    @Test func draftEditsAndCatalogAdditions() throws {
        let c = TranscriptTestFixtures.prerequisiteCatalog()
        let saved = SavedStudentPlan()
        var draft = TranscriptReconciler.makeDraft(parsed: nil, catalog: c, existingRecords: [], existingCredits: [], defaultSemester: .init(year: 2026, term: .fall))
        draft.add(course: c.courses[0], status: .earned)
        draft.add(course: c.courses[1], status: .inProgress)
        var current = draft.records[1]; current.attemptedCredits = 1.5; draft.update(record: current)
        let history = try TranscriptReconciler.confirm(draft, catalog: c)
        #expect(history.earnedHours == 3)
        #expect(history.currentSemester?.creditOverrides["CS159"] == 1.5)
        #expect(saved.academicRecords.isEmpty)
        draft.remove(recordID: draft.records[0].id)
        #expect(try TranscriptReconciler.confirm(draft, catalog: c).earnedHours == 0)
    }
    @Test func replaceFalseMatchAndExcludeUnknownGrade() throws {
        let c = TranscriptTestFixtures.prerequisiteCatalog()
        var draft = TranscriptReconciler.makeDraft(parsed: nil, catalog: c, existingRecords: [.init(code: "CSOOO", title: "General", earnedCredits: 3, status: .earned, source: .transcriptTest)], existingCredits: [], defaultSemester: .init(year: 2026, term: .fall))
        #expect(throws: TranscriptReviewError.self) { try TranscriptReconciler.confirm(draft, catalog: c) }
        draft.replace(recordID: draft.records[0].id, with: c.courses[0])
        #expect(try TranscriptReconciler.confirm(draft, catalog: c).completedCourseIDs == ["CS149"])
        draft.records[0].status = .excluded
        #expect(try TranscriptReconciler.confirm(draft, catalog: c).earnedHours == 0)
    }
    @Test func apEntryStaysInDraft() throws {
        var c = TranscriptTestFixtures.prerequisiteCatalog()
        c.apCreditRules = [.init(source: .apExam(name: "Computer Science A", minimumScore: 3), awardedCourseIDs: ["CS149"], credits: 3, meetsGeneralEducation: false, sourceNote: "Fixture")]
        var draft = TranscriptReconciler.makeDraft(parsed: nil, catalog: c, existingRecords: [], existingCredits: [], defaultSemester: .init(year: 2026, term: .fall))
        draft.addAPScore(examName: "Computer Science A", score: 5, catalog: c, program: c.programs.first)
        #expect(try TranscriptReconciler.confirm(draft, catalog: c).earnedHours == 3)
        #expect(draft.records[0].title.contains("AP Computer Science A"))
    }
}
