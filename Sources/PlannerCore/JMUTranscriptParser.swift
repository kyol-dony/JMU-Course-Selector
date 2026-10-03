import Foundation

public enum TranscriptIssueKind: String, Hashable, Sendable {
    case malformedRow, unknownGrade, unknownCourse, conflictingCredit, repeatedCourse
    case unsupportedTerm, termMismatch, totalMismatch, overlappingAward
}
public struct TranscriptIssue: Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var recordID: UUID?
    public var kind: TranscriptIssueKind
    public var message: String
    public var isBlocking: Bool
    public init(recordID: UUID? = nil, kind: TranscriptIssueKind, message: String, isBlocking: Bool = true) {
        self.recordID = recordID; self.kind = kind; self.message = message; self.isBlocking = isBlocking
    }
}
public struct ParsedTranscript: Sendable {
    public var records: [AcademicCourseRecord]
    public var latestPrintedTerm: String?
    public var printedEarnedTotal: Double?
    public var issues: [TranscriptIssue]
}
public enum TranscriptParserError: Error, LocalizedError {
    case notJMUTranscript, noCourseRows
    public var errorDescription: String? {
        switch self {
        case .notJMUTranscript: "Choose a JMU unofficial transcript PDF, or enter your courses manually."
        case .noCourseRows: "No course rows could be read. Try another PDF or enter your courses manually."
        }
    }
}
public enum JMUTranscriptParser {
    public static func normalizedCode(_ code: String) -> String {
        code.uppercased().filter { !$0.isWhitespace }
    }
    /// Readable form of a normalized code: "CS149" becomes "CS 149". Codes
    /// without digits (transcript placeholders like "CSOOO") split before
    /// their last three characters, matching the printed "CS OOO".
    public static func displayCode(_ code: String) -> String {
        let compact = normalizedCode(code)
        if let digit = compact.firstIndex(where: \.isNumber), digit != compact.startIndex {
            return "\(compact[..<digit]) \(compact[digit...])"
        }
        guard compact.count > 3 else { return compact }
        let split = compact.index(compact.endIndex, offsetBy: -3)
        return "\(compact[..<split]) \(compact[split...])"
    }
    public static func supportedTerm(_ printed: String) -> SemesterIdentity? {
        let parts = printed.split(separator: " ")
        guard let last = parts.last, let year = Int(last) else { return nil }
        if printed.hasPrefix("Fall ") { return .init(year: year, term: .fall) }
        if printed.hasPrefix("Spring ") { return .init(year: year, term: .spring) }
        return nil
    }
    private static func groups(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
    public static func parse(pages: [String]) throws -> ParsedTranscript {
        let document = pages.joined(separator: "\n")
        guard document.localizedCaseInsensitiveContains("James Madison University"),
              document.localizedCaseInsensitiveContains("Unofficial Transcript") else { throw TranscriptParserError.notJMUTranscript }
        var result = ParsedTranscript(records: [], latestPrintedTerm: nil, printedEarnedTotal: nil, issues: [])
        var term: String?
        var source = AcademicCreditSource.transcriptResident
        var pendingHeading: String?
        var pending: String?
        let courseStart = #"^([A-Z]{2,8})\s*([0-9]{2,4}[A-Z]*|OOO|000)\s+(.+)$"#
        let row = #"^([A-Z]{2,8})\s*([0-9]{2,4}[A-Z]*|OOO|000)\s+(.+?)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s+(?:([A-Z][A-Z+\-]*)\s+)?(\d+(?:\.\d+)?)$"#
        func flushPending() {
            if pending != nil { result.issues.append(.init(kind: .malformedRow, message: "A course row was incomplete. Add the missing course or dismiss this issue after reviewing.")) }
            pending = nil
        }
        for raw in document.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            // A term heading may continue on the next page after repeated headers.
            if line.hasPrefix("Page ") || line.hasPrefix("Course ") || line.contains("Unofficial Transcript") || line.contains("James Madison University") || line.hasPrefix("Print Date:") { continue }
            if let heading = pendingHeading {
                pendingHeading = nil
                if groups(#"^\d{4}$"#, line) != nil { line = heading + " " + line }
                else {
                    term = nil
                    result.issues.append(.init(kind: .termMismatch, message: "A semester heading was incomplete. Confirm the current semester before continuing.", isBlocking: false))
                }
            }
            if groups(#"^(Fall|Spring|Summer|Winter) Semester$"#, line) != nil {
                flushPending(); pendingHeading = line; continue
            }
            if groups(#"^(Fall|Spring|Summer|Winter) Semester \d{4}$"#, line) != nil {
                flushPending(); term = line; source = .transcriptResident
                func termKey(_ text: String) -> Int {
                    let season = text.components(separatedBy: " ").first ?? ""
                    return (Int(text.suffix(4)) ?? 0) * 10 + (["Spring": 1, "Summer": 2, "Fall": 3, "Winter": 4][season] ?? 0)
                }
                if result.latestPrintedTerm == nil || termKey(line) > termKey(result.latestPrintedTerm!) { result.latestPrintedTerm = line }
                if supportedTerm(line) == nil { result.issues.append(.init(kind: .unsupportedTerm, message: "Select a Fall or Spring semester for current enrollment; the transcript includes an unsupported term.", isBlocking: false)) }
                continue
            }
            if line.contains("Test Credits Applied") { flushPending(); source = .transcriptTest; continue }
            if line.contains("Transfer Credits Applied") { flushPending(); source = .transcriptTransfer; continue }
            if let total = groups(#"Cum Totals\s+[\d.]+\s+([\d.]+)\s+[\d.]+"#, line) { result.printedEarnedTotal = Double(total[1]); continue }
            // Repeated page headers and footer lines do not interrupt a split course row.
            if line.hasPrefix("Page ") || line.hasPrefix("Course ") || line.contains("Unofficial Transcript") || line.contains("James Madison University") || line.hasPrefix("Print Date:") { continue }
            if groups(courseStart, line) != nil {
                flushPending(); pending = line
            } else if pending != nil, groups(#"^\d"#, line) != nil {
                pending! += " " + line
            } else { continue }
            guard let candidate = pending, let fields = groups(row, candidate),
                  let attempted = Double(fields[4]), let earned = Double(fields[5]) else { continue }
            let grade = fields[6]
            let passing = ["A", "A+", "A-", "B", "B+", "B-", "C", "C+", "C-", "D", "D+", "D-", "CR", "P"]
            let excluded = ["F", "W", "I", "NC", "NP", "WF", "WP", "AU"]
            let status: AcademicCourseStatus
            if excluded.contains(grade) { status = .excluded }
            else if earned > 0 && passing.contains(grade) { status = .earned }
            else if earned == 0 && attempted > 0 && grade.isEmpty && source == .transcriptResident { status = .inProgress }
            else { status = .needsReview }
            let record = AcademicCourseRecord(code: fields[1] + fields[2], title: fields[3], attemptedCredits: attempted, earnedCredits: earned, grade: grade.isEmpty ? nil : grade, printedTerm: source == .transcriptResident ? term : nil, status: status, source: source)
            result.records.append(record)
            if status == .needsReview { result.issues.append(.init(recordID: record.id, kind: .unknownGrade, message: "Confirm the status and credit of this course.")) }
            pending = nil
        }
        flushPending()
        if pendingHeading != nil { result.issues.append(.init(kind: .termMismatch, message: "A semester heading was incomplete. Confirm the current semester before continuing.", isBlocking: false)) }
        guard !result.records.isEmpty else { throw TranscriptParserError.noCourseRows }
        if let total = result.printedEarnedTotal {
            let sum = result.records.filter { $0.status == .earned }.reduce(0) { $0 + $1.earnedCredits }
            if abs(sum - total) > 0.001 { result.issues.append(.init(kind: .totalMismatch, message: "Detected earned credit differs from the printed total. Check for missed or repeated courses.", isBlocking: false)) }
        }
        return result
    }
}
