import Foundation

public struct AcademicCreditTotals: Sendable {
    public var earnedHours: Double
    public var projectedHours: Double
}
public enum AcademicCreditCalculator {
    public static func hours(in semester: SemesterPlan, catalog: Catalog) -> Double {
        Set(semester.courseIDs).reduce(0) { $0 + (semester.creditOverrides[$1] ?? Double(catalog.coursesByID[$1]?.credits ?? 0)) }
    }
    public static func totals(history: AcademicHistory, pathway: Pathway, catalog: Catalog) -> AcademicCreditTotals {
        var seen = history.completedCourseIDs
        var projected = history.earnedHours
        for semester in pathway.semesters {
            for code in semester.courseIDs where !PathwayPlaceholder.isPlaceholder(code) && seen.insert(code).inserted {
                projected += semester.creditOverrides[code] ?? Double(catalog.coursesByID[code]?.credits ?? 0)
            }
        }
        return .init(earnedHours: history.earnedHours, projectedHours: projected)
    }
}
