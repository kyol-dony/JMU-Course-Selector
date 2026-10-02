import Foundation
import Testing
@testable import PlannerCore

@Suite struct TranscriptReconcilerTests {
    static func record(_ code: String = "CS149", credits: Double = 3, status: AcademicCourseStatus = .earned, source: AcademicCreditSource = .transcriptResident) -> AcademicCourseRecord {
        .init(code: code, title: "Course", courseIDs: [code], attemptedCredits: credits, earnedCredits: status == .earned ? credits : 0, status: status, source: source, matchConfirmed: true)
    }
    @Test func sampleAndReimport() throws {
        let catalog = TranscriptTestFixtures.sampleCatalog()
        let parsed = try JMUTranscriptParser.parse(pages: [TranscriptTestFixtures.sampleText()])
        var draft = TranscriptReconciler.makeDraft(parsed: parsed, catalog: catalog, existingRecords: [], existingCredits: [], defaultSemester: .init(year: 2026, term: .fall))
        for r in draft.records { if r.status == .earned { draft.retainAsGeneralCredit(recordID: r.id) } else { draft.retainUnmatchedEnrollment(recordID: r.id) } }
        draft.setCurrentSemester(.init(year: 2026, term: .fall))
        let confirmed = try TranscriptReconciler.confirm(draft, catalog: catalog)
        #expect(confirmed.earnedHours == 49)
        #expect(!confirmed.completedCourseIDs.contains("CS149"))
        #expect(confirmed.currentSemester?.courseIDs.count == 5)
        let again = TranscriptReconciler.makeDraft(parsed: parsed, catalog: catalog, existingRecords: confirmed.records, existingCredits: confirmed.effectiveCredits, defaultSemester: .init(year: 2026, term: .fall))
        #expect(again.records.count == 24)
    }
    @Test func duplicateAndInvalidAmounts() {
        let duplicate = EffectiveCreditBuilder.build(records: [Self.record(), Self.record()], legacyCredits: [])
        #expect(duplicate.earnedHours == 3)
        #expect(duplicate.issues.contains { $0.kind == .repeatedCourse })
        for amount in [-1.0, Double.infinity, Double.nan] {
            let result = EffectiveCreditBuilder.build(records: [Self.record(credits: amount)], legacyCredits: [])
            #expect(!result.issues.isEmpty)
        }
    }
    @Test func partialBundledAPOverlapRequiresReview() {
        let ap = TransferCredit(sourceDescription: "AP", courseIDs: ["CS149", "CS000"], credits: 6, source: .apMapped)
        let r = EffectiveCreditBuilder.build(records: [Self.record()], legacyCredits: [ap])
        #expect(r.issues.contains { $0.kind == .overlappingAward })
        #expect(!r.credits.contains { $0.courseIDs == ["CS000"] && $0.credits == 3 })
    }
    @Test func earnedCurrentConflict() {
        let result = EffectiveCreditBuilder.build(records: [Self.record(), Self.record(status: .inProgress)], legacyCredits: [])
        #expect(result.issues.contains { $0.kind == .repeatedCourse })
    }
    @Test func repeatableCourseExplicitAggregate() {
        let result = EffectiveCreditBuilder.build(records: [Self.record(credits: 7.5)], legacyCredits: [])
        #expect(result.earnedHours == 7.5)
        #expect(result.completedCourseIDs == ["CS149"])
        #expect(result.issues.isEmpty)
    }
    @Test func termAndUnknownMustBeConfirmed() throws {
        let parsed = try JMUTranscriptParser.parse(pages: ["James Madison University\nUnofficial Transcript\nSummer Semester 2026\nZZZ 123 Unknown 1.50 0.00 0.000"])
        var draft = TranscriptReconciler.makeDraft(parsed: parsed, catalog: TranscriptTestFixtures.sampleCatalog(), existingRecords: [], existingCredits: [], defaultSemester: .init(year: 2026, term: .fall))
        #expect(throws: TranscriptReviewError.self) { try TranscriptReconciler.confirm(draft, catalog: TranscriptTestFixtures.sampleCatalog()) }
        draft.retainUnmatchedEnrollment(recordID: draft.records[0].id)
        draft.setCurrentSemester(.init(year: 2026, term: .fall))
        let result = try TranscriptReconciler.confirm(draft, catalog: TranscriptTestFixtures.sampleCatalog())
        #expect(result.currentSemester?.creditOverrides["ZZZ123"] == 1.5)
    }
}
