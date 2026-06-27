import Foundation
import PlannerCore

/// Builds the "Contributing courses" rows surfaced on each requirement
/// category card in My Plan. Lives outside MyPlanView so the planner-core
/// tests can exercise the matching logic without spinning up SwiftUI.
struct ProgressContributionBuilder {
    static func contributions(
        for requirement: RequirementCategory,
        transferCredits: [TransferCredit],
        scheduled: [String: String],
        coursesByID: [String: Course]
    ) -> [CourseContribution] {
        let transferIDs = Set(transferCredits.flatMap(\.courseIDs))
        let rows = requirement.courseOptions.compactMap { option in
            if let transferID = option.first(where: transferIDs.contains),
               let course = coursesByID[transferID] {
                return CourseContribution(code: course.code, source: "Transfer", isTransfer: true)
            }
            if let scheduledID = option.first(where: { scheduled[$0] != nil }),
               let course = coursesByID[scheduledID],
               let semester = scheduled[scheduledID] {
                return CourseContribution(code: course.code, source: semester, isTransfer: false)
            }
            return nil
        }
        if !rows.isEmpty { return rows }
        guard let apLit = apLiteratureContribution(for: requirement, transferCredits: transferCredits) else {
            return []
        }
        return [apLit]
    }

    private static func apLiteratureContribution(
        for requirement: RequirementCategory,
        transferCredits: [TransferCredit]
    ) -> CourseContribution? {
        guard requirement.name.contains("[C2L]") else { return nil }
        let apLitGNEDIDs: Set<String> = ["GNED123", "GNED124", "GNED129"]
        guard transferCredits.contains(where: { credit in
            !apLitGNEDIDs.isDisjoint(with: credit.courseIDs)
                && credit.sourceDescription.localizedCaseInsensitiveContains("English Literature")
        }) else {
            return nil
        }
        return CourseContribution(code: "AP English Literature & Composition", source: "Transfer", isTransfer: true)
    }
}

struct CourseContribution: Identifiable, Equatable {
    var id: String { "\(code)-\(source)" }
    var code: String
    var source: String
    var isTransfer: Bool
}
