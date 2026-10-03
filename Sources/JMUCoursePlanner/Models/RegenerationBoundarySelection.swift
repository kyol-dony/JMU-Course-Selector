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
}
