import Foundation

public struct EffectiveCreditResult: Sendable {
    public var credits: [TransferCredit]
    public var earnedHours: Double { credits.reduce(0) { $0 + $1.credits } }
    public var completedCourseIDs: Set<String> { Set(credits.flatMap(\.courseIDs)) }
    public var issues: [TranscriptIssue]
}
public enum EffectiveCreditBuilder {
    public static func migrateLegacySource(_ row: AcademicCourseRecord) -> AcademicCourseRecord {
        var result = row
        if row.source == .legacy, row.title.range(of: #"^AP .+ score [1-5]$"#, options: .regularExpression) != nil { result.source = .apMapped }
        return result
    }
    public static func record(from credit: TransferCredit) -> AcademicCourseRecord {
        migrateLegacySource(.init(id: credit.id, code: credit.courseIDs.joined(separator: "/"), title: credit.sourceDescription, courseIDs: credit.courseIDs, earnedCredits: credit.credits, status: .earned, source: credit.source, matchConfirmed: true))
    }
    public static func build(records: [AcademicCourseRecord], legacyCredits: [TransferCredit]) -> EffectiveCreditResult {
        var result = EffectiveCreditResult(credits: [], issues: [])
        let ids = Set(records.map(\.id))
        let all = records + legacyCredits.filter { !ids.contains($0.id) }.map(record(from:))
        let sorted = all.sorted { ($0.source.isTranscript ? 0 : 1) < ($1.source.isTranscript ? 0 : 1) }
        var accepted: [AcademicCourseRecord] = []
        for row in sorted where row.status != .excluded {
            guard row.earnedCredits.isFinite, row.attemptedCredits.isFinite, row.earnedCredits >= 0, row.attemptedCredits >= 0 else {
                result.issues.append(.init(recordID: row.id, kind: .conflictingCredit, message: "Credit amounts must be finite and nonnegative.")); continue
            }
            if row.status == .needsReview { result.issues.append(.init(recordID: row.id, kind: .unknownGrade, message: "Choose earned, in progress, or excluded for this course.")); continue }
            let overlaps = accepted.filter { other in
                !Set(row.courseIDs).isDisjoint(with: other.courseIDs) || (row.courseIDs.isEmpty && other.courseIDs.isEmpty && row.code == other.code)
            }
            if let first = overlaps.first {
                let sameIDs = Set(first.courseIDs) == Set(row.courseIDs)
                let sameCredits = first.earnedCredits == row.earnedCredits
                if !sameIDs {
                    result.issues.append(.init(recordID: row.id, kind: .overlappingAward, message: "This bundled award overlaps another course. Exclude it or correct its course IDs and total credit; its credit cannot be split automatically."))
                } else if row.status == .inProgress || first.status != row.status || first.source == row.source || !sameCredits {
                    result.issues.append(.init(recordID: row.id, kind: .repeatedCourse, message: "This course appears more than once. Keep one award, or review a repeatable course's aggregate credit."))
                }
                continue
            }
            accepted.append(row)
            if row.status == .earned {
                result.credits.append(.init(id: row.id, sourceDescription: row.title, courseIDs: row.courseIDs, credits: row.earnedCredits, source: row.source))
            }
        }
        return result
    }
}
public struct TranscriptReviewDraft: Sendable {
    public var records: [AcademicCourseRecord]
    public var currentSemester: SemesterIdentity
    public var semesterConfirmed: Bool
    public var extractionIssues: [TranscriptIssue]
    public var dismissedIssueIDs: Set<UUID> = []
    public var issues: [TranscriptIssue] { extractionIssues.filter { !dismissedIssueIDs.contains($0.id) } }
    public mutating func replace(recordID: UUID, with course: Course) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].code = course.id; records[index].title = course.title
        records[index].courseIDs = [course.id]; records[index].matchConfirmed = true
    }
    public mutating func addAPScore(examName: String, score: Int, catalog: Catalog, program: Program?) {
        let prior = EffectiveCreditBuilder.build(records: records, legacyCredits: [])
        let credits = TransferCreditMapper(catalog: catalog).credits(forAPScores: [.init(examName: examName, score: score)], program: program, completedCourseIDs: prior.completedCourseIDs)
        for credit in credits {
            var row = EffectiveCreditBuilder.record(from: credit)
            // Reviewed manual awards are fixed equivalents, like transcript test credit.
            row.source = .manual
            records.append(row)
        }
    }
    public mutating func remove(recordID: UUID) { records.removeAll { $0.id == recordID } }
    public mutating func update(record: AcademicCourseRecord) { if let i = records.firstIndex(where: { $0.id == record.id }) { records[i] = record } }
    public mutating func add(course: Course, status: AcademicCourseStatus) {
        records.append(.init(code: course.id, title: course.title, courseIDs: [course.id], attemptedCredits: status == .inProgress ? Double(course.credits) : 0, earnedCredits: status == .earned ? Double(course.credits) : 0, status: status, source: .manual, matchConfirmed: true))
    }
    public mutating func retainAsGeneralCredit(recordID: UUID) {
        guard let i = records.firstIndex(where: { $0.id == recordID }), records[i].status == .earned else { return }
        records[i].courseIDs = []; records[i].matchConfirmed = true
    }
    public mutating func retainUnmatchedEnrollment(recordID: UUID) {
        guard let i = records.firstIndex(where: { $0.id == recordID }), records[i].status == .inProgress else { return }
        records[i].matchConfirmed = true
    }
    public mutating func setCurrentSemester(_ semester: SemesterIdentity) { currentSemester = semester; semesterConfirmed = true }
}
public enum TranscriptReviewError: Error, LocalizedError {
    case unresolved([TranscriptIssue])
    public var errorDescription: String? { "Resolve the highlighted course and semester issues before continuing." }
}
public enum TranscriptReconciler {
    public static func makeDraft(parsed: ParsedTranscript?, catalog: Catalog, existingRecords: [AcademicCourseRecord], existingCredits: [TransferCredit], defaultSemester: SemesterIdentity) -> TranscriptReviewDraft {
        var rows = parsed == nil ? existingRecords : existingRecords.filter { !$0.source.isTranscript }
        let existingIDs = Set(existingRecords.map(\.id))
        rows += existingCredits.filter { !existingIDs.contains($0.id) && (parsed == nil || !$0.source.isTranscript) }.map(EffectiveCreditBuilder.record(from:))
        rows += parsed?.records ?? []
        rows = rows.map(EffectiveCreditBuilder.migrateLegacySource)
        for i in rows.indices where !rows[i].matchConfirmed {
            let code = JMUTranscriptParser.normalizedCode(rows[i].code)
            rows[i].code = code
            if catalog.coursesByID[code] != nil || TransferCreditMapper.genEdCreditClusterTag(for: code) != nil {
                rows[i].courseIDs = [code]; rows[i].matchConfirmed = true
            }
        }
        let term = parsed?.latestPrintedTerm.flatMap(JMUTranscriptParser.supportedTerm)
        let hasTermMismatch = (parsed?.issues.contains { $0.kind == .termMismatch } ?? false) || rows.contains { $0.status == .inProgress && $0.printedTerm != nil && JMUTranscriptParser.supportedTerm($0.printedTerm!) != term }
        return .init(records: rows, currentSemester: term ?? defaultSemester, semesterConfirmed: parsed == nil || (term != nil && !hasTermMismatch), extractionIssues: parsed?.issues.filter { $0.recordID == nil } ?? [])
    }
    public static func validate(_ draft: TranscriptReviewDraft, catalog: Catalog) -> [TranscriptIssue] {
        var issues = draft.issues + EffectiveCreditBuilder.build(records: draft.records, legacyCredits: []).issues
        if !draft.semesterConfirmed { issues.append(.init(kind: .termMismatch, message: "Confirm a Fall or Spring semester for current enrollment.")) }
        for row in draft.records where row.status != .excluded {
            if !row.matchConfirmed { issues.append(.init(recordID: row.id, kind: .unknownCourse, message: "Match this course, retain it without a specific equivalence, or exclude it.")) }
        }
        return issues
    }
    public static func confirm(_ draft: TranscriptReviewDraft, catalog: Catalog) throws -> AcademicHistory {
        let blocking = validate(draft, catalog: catalog).filter(\.isBlocking)
        guard blocking.isEmpty else { throw TranscriptReviewError.unresolved(blocking) }
        let effective = EffectiveCreditBuilder.build(records: draft.records, legacyCredits: [])
        let current = draft.records.filter { $0.status == .inProgress }
        var semester = SemesterPlan(id: draft.currentSemester, courseIDs: [])
        for row in current {
            let code = row.courseIDs.first ?? row.code
            semester.courseIDs.append(code)
            semester.creditOverrides[code] = row.attemptedCredits
            semester.courseTitles[code] = row.title
        }
        return .init(records: draft.records, currentSemester: semester, effectiveCredits: effective.credits, earnedHours: effective.earnedHours)
    }
}
