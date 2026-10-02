import Foundation

public struct AcademicCreditTotals: Sendable {
    public var earnedHours: Double
    public var projectedHours: Double
}
public enum AcademicCreditCalculator {
    public static func generalHours(credits: [TransferCredit], current: SemesterPlan?, programs: [Program], catalog: Catalog) -> Double {
        let requirements = programs.flatMap(\.requirements)
        let requiredIDs = Set(requirements.flatMap { $0.courseOptions.flatMap { $0 } })
        let allIDs = Set(credits.flatMap(\.courseIDs)).union(current?.courseIDs ?? [])
        let knownRequired = allIDs.intersection(requiredIDs).reduce(0.0) { $0 + (current?.creditOverrides[$1] ?? Double(catalog.coursesByID[$1]?.credits ?? 0)) }
        let aliasHours = credits.filter { credit in
            credit.courseIDs.contains { code in
                guard let tag = TransferCreditMapper.genEdCreditClusterTag(for: code) else { return false }
                return requirements.contains { $0.name.contains(tag) }
            }
        }.reduce(0.0) { $0 + $1.credits }
        let total = credits.reduce(0.0) { $0 + $1.credits } + (current.map { hours(in: $0, catalog: catalog) } ?? 0)
        return max(0, total - knownRequired - aliasHours)
    }
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
