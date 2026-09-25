import PlannerCore

/// The board's warnings arranged for the issues list, tags, and outlines.
struct ScheduleIssues: Equatable {
    var mustFix: [ConflictWarning]
    var worthALook: [ConflictWarning]
    var kept: [ConflictWarning]

    static let empty = ScheduleIssues(mustFix: [], worthALook: [], kept: [])

    init(mustFix: [ConflictWarning], worthALook: [ConflictWarning], kept: [ConflictWarning]) {
        self.mustFix = mustFix
        self.worthALook = worthALook
        self.kept = kept
    }

    /// Hidden kinds are dropped. Each group reads in board order: semester,
    /// then semester-level warnings, then course code.
    init(_ warnings: [ConflictWarning], catalog: Catalog) {
        func code(_ warning: ConflictWarning) -> String {
            catalog.coursesByID[warning.courseID]?.code ?? warning.courseID
        }
        let visible = warnings
            .filter { $0.kind.severity != .hidden }
            .sorted { lhs, rhs in
                if lhs.semester != rhs.semester { return lhs.semester < rhs.semester }
                if lhs.isSemesterLevel != rhs.isSemesterLevel { return lhs.isSemesterLevel }
                if code(lhs) != code(rhs) { return code(lhs) < code(rhs) }
                return lhs.kind.severity > rhs.kind.severity
            }
        kept = visible.filter(\.isOverridden)
        let active = visible.filter { !$0.isOverridden }
        mustFix = active.filter { $0.kind.severity == .mustFix }
        worthALook = active.filter { $0.kind.severity == .worthALook }
    }

    private var all: [ConflictWarning] { mustFix + worthALook + kept }

    var activeCount: Int { mustFix.count + worthALook.count }

    var worstActive: ConflictSeverity? {
        if !mustFix.isEmpty { return .mustFix }
        if !worthALook.isEmpty { return .worthALook }
        return nil
    }

    var buttonTitle: String {
        switch activeCount {
        case 0: "No issues"
        case 1: "1 issue"
        default: "\(activeCount) issues"
        }
    }

    /// A chip's warnings, active and kept, most important first.
    func warnings(for courseID: String, in semester: SemesterIdentity) -> [ConflictWarning] {
        WarningTagModel.ordered(all.filter { $0.courseID == courseID && $0.semester == semester })
    }

    /// A semester header's load warnings, most important first.
    func semesterWarnings(in semester: SemesterIdentity) -> [ConflictWarning] {
        WarningTagModel.ordered(all.filter { $0.isSemesterLevel && $0.semester == semester })
    }

    /// Drives the resting outline. Kept warnings do not count.
    func worstActive(in semester: SemesterIdentity) -> ConflictSeverity? {
        (mustFix + worthALook)
            .filter { $0.semester == semester }
            .map(\.kind.severity)
            .max()
    }

    /// The popover identity of the tag that shows `warning`.
    func tagID(for warning: ConflictWarning) -> String {
        WarningTagModel.key(for: warning)
    }

    /// Whether any tag on the board has this popover identity.
    func containsTag(_ key: String) -> Bool {
        all.contains { WarningTagModel.key(for: $0) == key }
    }
}
