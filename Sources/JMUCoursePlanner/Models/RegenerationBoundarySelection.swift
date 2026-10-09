import PlannerCore

struct RegenerationBoundarySelection: Equatable {
    let semesters: [SemesterIdentity]
    var selected: SemesterIdentity?

    init(pathway: Pathway) {
        semesters = Array(Set(pathway.semesters.map(\.id))).sorted()
        selected = semesters.first
    }
    var canConfirm: Bool { selected.map(semesters.contains) ?? false }
    var summary: String {
        guard let selected, canConfirm else { return "Choose a semester to preserve." }
        return "Keep everything through \(selected.displayName). Rebuild \(selected.next.displayName) onward."
    }

    /// How a semester reads on the board while picking the anchor.
    enum Role: Equatable {
        /// The last semester kept as-is.
        case anchor
        /// Earlier than the anchor: kept as-is.
        case kept
        /// After the anchor: replaced by the rebuild.
        case rebuilt
    }

    /// Nil until a valid anchor is picked, and for semesters not in the pathway.
    func role(of semester: SemesterIdentity) -> Role? {
        guard let selected, canConfirm, semesters.contains(semester) else { return nil }
        if semester == selected { return .anchor }
        return semester < selected ? .kept : .rebuilt
    }

    /// Text for the toolbar bar shown while picking.
    var prompt: String {
        guard let selected, canConfirm else { return "Click the last semester to keep" }
        return "Keep through \(selected.displayName) · rebuild \(selected.next.displayName) onward"
    }
}
