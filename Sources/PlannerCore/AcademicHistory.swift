import Foundation

public enum AcademicCourseStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case earned, inProgress, excluded, needsReview
}
public enum AcademicCreditSource: String, Codable, Hashable, Sendable {
    case transcriptResident, transcriptTest, transcriptTransfer, manual, apMapped, legacy
    public var isTranscript: Bool { [.transcriptResident, .transcriptTest, .transcriptTransfer].contains(self) }
    public var label: String {
        switch self {
        case .transcriptResident: "JMU coursework"
        case .transcriptTest: "Test credit"
        case .transcriptTransfer: "Transfer credit"
        case .manual: "Manual credit"
        case .apMapped: "AP credit"
        case .legacy: "Prior credit"
        }
    }
}
public struct AcademicCourseRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var code: String
    public var title: String
    public var courseIDs: [String]
    public var attemptedCredits: Double
    public var earnedCredits: Double
    public var grade: String?
    public var printedTerm: String?
    public var status: AcademicCourseStatus
    public var source: AcademicCreditSource
    public var matchConfirmed: Bool
    public init(id: UUID = UUID(), code: String, title: String, courseIDs: [String] = [], attemptedCredits: Double = 0, earnedCredits: Double = 0, grade: String? = nil, printedTerm: String? = nil, status: AcademicCourseStatus, source: AcademicCreditSource, matchConfirmed: Bool = false) {
        self.id = id; self.code = code; self.title = title; self.courseIDs = courseIDs
        self.attemptedCredits = attemptedCredits; self.earnedCredits = earnedCredits
        self.grade = grade; self.printedTerm = printedTerm; self.status = status; self.source = source
        self.matchConfirmed = matchConfirmed
    }
}
public struct AcademicHistory: Hashable, Sendable {
    public var records: [AcademicCourseRecord]
    public var currentSemester: SemesterPlan?
    public var effectiveCredits: [TransferCredit]
    public var earnedHours: Double
    public var completedCourseIDs: Set<String> { Set(effectiveCredits.flatMap(\.courseIDs)) }
    public init(records: [AcademicCourseRecord], currentSemester: SemesterPlan?, effectiveCredits: [TransferCredit] = [], earnedHours: Double = 0) {
        self.records = records; self.currentSemester = currentSemester
        self.effectiveCredits = effectiveCredits; self.earnedHours = earnedHours
    }
}
public enum CreditHoursFormatter {
    public static func string(_ hours: Double) -> String {
        hours.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}
