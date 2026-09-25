import PlannerCore

/// What a warning tag shows for one chip or semester: the most important
/// warning's summary, how many more there are, and the tone.
struct WarningTagModel: Equatable {
    enum Tone: Equatable {
        case mustFix
        case worthALook
        case kept
    }

    /// The warning the tag is named after.
    let primary: ConflictWarning
    /// Popover identity: the tag's subject (course or semester) in its
    /// semester, so keeping the top warning does not close or re-key it.
    let key: String
    /// All warnings behind the tag, most important first.
    let warnings: [ConflictWarning]
    let tone: Tone
    let label: String

    init?(warnings: [ConflictWarning]) {
        let ordered = Self.ordered(warnings)
        guard let first = ordered.first else { return nil }
        primary = first
        key = Self.key(for: first)
        self.warnings = ordered
        if first.isOverridden {
            tone = .kept
        } else {
            tone = first.kind.severity == .mustFix ? .mustFix : .worthALook
        }
        let text = first.isOverridden ? "Kept" : first.summary
        let extra = ordered.count - 1
        label = extra > 0 ? "\(text) +\(extra)" : text
    }

    static func key(for warning: ConflictWarning) -> String {
        "\(warning.courseID)|\(warning.semester.year)-\(warning.semester.term.rawValue)"
    }

    /// Active before kept, then most severe first; stable otherwise.
    static func ordered(_ warnings: [ConflictWarning]) -> [ConflictWarning] {
        warnings.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isOverridden != rhs.element.isOverridden { return !lhs.element.isOverridden }
                if lhs.element.kind.severity != rhs.element.kind.severity {
                    return lhs.element.kind.severity > rhs.element.kind.severity
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
