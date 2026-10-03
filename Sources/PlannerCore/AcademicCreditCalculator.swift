import Foundation

public struct AcademicCreditTotals: Sendable {
    public var earnedHours: Double
    public var projectedHours: Double
}
public enum AcademicCreditCalculator {
    public static func generalHours(credits: [TransferCredit], current: SemesterPlan?, programs: [Program], catalog: Catalog) -> Double {
        let requirements = programs.flatMap(\.requirements)
        let requiredIDs = Set(requirements.flatMap { $0.courseOptions.flatMap { $0 } })
        var allocatedIDs: Set<String> = []
        let knownRequired = credits.reduce(0.0) { sum, credit in
            let required = Set(credit.courseIDs).intersection(requiredIDs).subtracting(allocatedIDs)
            allocatedIDs.formUnion(required)
            let nominal = required.reduce(0.0) { $0 + Double(catalog.coursesByID[$1]?.credits ?? 0) }
            // Allocate actual hours up to the catalog requirement; excess is general credit.
            let allocated = min(credit.credits, nominal)
            return sum + allocated
        } + (current.map { semester in
            Set(semester.courseIDs).intersection(requiredIDs).subtracting(allocatedIDs).reduce(0.0) {
                $0 + min(semester.creditOverrides[$1] ?? Double(catalog.coursesByID[$1]?.credits ?? 0), Double(catalog.coursesByID[$1]?.credits ?? 0))
            }
        } ?? 0)
        let aliasHours = credits.filter { credit in
            Set(credit.courseIDs).isDisjoint(with: requiredIDs) && credit.courseIDs.contains { code in
                guard let tag = TransferCreditMapper.genEdCreditClusterTag(for: code) else { return false }
                return requirements.contains { $0.name.contains(tag) }
            }
        }.reduce(0.0) { $0 + $1.credits }
        let total = credits.reduce(0.0) { $0 + $1.credits } + (current.map { hours(in: $0, catalog: catalog) } ?? 0)
        return max(0, total - knownRequired - aliasHours)
    }
    /// Corrections below a catalog course's nominal hours still leave graduation hours to earn.
    public static func requirementCreditShortfall(credits: [TransferCredit], current: SemesterPlan?, programs: [Program], catalog: Catalog) -> Double {
        let requiredIDs = Set(programs.flatMap(\.requirements).flatMap { $0.courseOptions.flatMap { $0 } })
        var seen: Set<String> = []
        var shortfall = 0.0
        for credit in credits {
            let ids = Set(credit.courseIDs).intersection(requiredIDs).subtracting(seen)
            seen.formUnion(ids)
            let nominal = ids.reduce(0.0) { $0 + Double(catalog.coursesByID[$1]?.credits ?? 0) }
            shortfall += max(0, nominal - credit.credits)
        }
        if let current {
            for code in Set(current.courseIDs).intersection(requiredIDs).subtracting(seen) {
                let nominal = Double(catalog.coursesByID[code]?.credits ?? 0)
                shortfall += max(0, nominal - (current.creditOverrides[code] ?? nominal))
            }
        }
        return shortfall
    }
    public static func hours(in semester: SemesterPlan, catalog: Catalog) -> Double {
        Set(semester.courseIDs).reduce(0) { $0 + (semester.creditOverrides[$1] ?? Double(catalog.coursesByID[$1]?.credits ?? 0)) }
    }
    /// Prior awards and planned rows contribute once. Placeholder hours reserve
    /// graduation/standing capacity, never concrete-course equivalence.
    public static func projectedHours(in semesters: [SemesterPlan], placeholders: [String: PlaceholderSpec],
                                      transferCredits: [TransferCredit], catalog: Catalog) -> Double {
        var accumulator = PlannedCreditAccumulator(
            hours: transferCredits.reduce(0.0) { $0 + $1.credits },
            completedCourseIDs: Set(transferCredits.flatMap(\.courseIDs)))
        for semester in semesters {
            accumulator.include(semester, placeholders: placeholders, catalog: catalog)
        }
        return accumulator.hours
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

/// Shared chronological accounting for future standing. Concrete IDs already
/// earned or planned contribute once; unresolved slots contribute hours only.
struct PlannedCreditAccumulator {
    private(set) var hours: Double
    private var seen: Set<String>

    init(hours: Double, completedCourseIDs: Set<String>) {
        self.hours = hours
        self.seen = completedCourseIDs
    }

    mutating func include(_ semester: SemesterPlan, placeholders: [String: PlaceholderSpec], catalog: Catalog) {
        for id in semester.courseIDs where seen.insert(id).inserted {
            hours += semester.creditOverrides[id] ?? placeholders[id]?.credits ?? Double(catalog.coursesByID[id]?.credits ?? 0)
        }
    }
}
