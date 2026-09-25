import PlannerCore
import SwiftUI

/// "Move to" submenu for a schedule item. Each semester is labeled with the
/// verdict a drop there would get, matching the drag feedback. Verdicts are
/// read from the store's cache (filled when the chip is hovered) because
/// context-menu content may be built eagerly, before any `.task` could run.
struct MoveToMenu: View {
    @EnvironmentObject private var store: PlanStore
    var itemID: String
    var currentSemester: SemesterIdentity

    var body: some View {
        let verdicts = store.cachedDropVerdicts(for: itemID) ?? [:]
        Menu("Move to") {
            ForEach(store.activePathway?.semesters ?? []) { target in
                let isCurrent = target.id == currentSemester
                Button {
                    store.moveCourse(itemID, to: target.id)
                } label: {
                    Label(
                        Self.title(for: target.id, verdict: verdicts[target.id], isCurrent: isCurrent),
                        systemImage: Self.icon(for: verdicts[target.id])
                    )
                }
                .disabled(isCurrent)
            }
        }
    }

    static func title(for semester: SemesterIdentity, verdict: DropVerdict?, isCurrent: Bool) -> String {
        if isCurrent { return "\(semester.displayName) (current)" }
        guard let verdict else { return "\(semester.displayName): Checking…" }
        guard let headline = verdict.headline else { return semester.displayName }
        return "\(semester.displayName): \(headline)"
    }

    static func icon(for verdict: DropVerdict?) -> String {
        switch verdict?.level {
        case .blocking: "xmark.octagon"
        case .caution: "exclamationmark.triangle"
        case .clear: "checkmark.circle"
        case nil: "ellipsis.circle"
        }
    }
}
