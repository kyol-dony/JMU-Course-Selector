import PlannerCore

/// How a placeholder explains the prerequisite choices later courses count
/// on: the notice's summary and detail, and a label for each supporting
/// choice in its picker. Pure formatting of the current analysis.
struct PlaceholderDependencyPresentation: Equatable {
    let summary: String
    let detail: String
    /// "Supports MATH 410 in Spring 2027", keyed by supporting course.
    let labelsByCourseID: [String: String]

    init(supports: [String: Set<ConditionalDependencyKey>], coursesByID: [String: Course]) {
        func code(_ courseID: String) -> String { coursesByID[courseID]?.code ?? courseID }
        summary = ConflictKind.pendingPrerequisiteChoice.title
        detail = PlaceholderDependencyText.choiceSentences(supports, code: code).joined(separator: " ")
        labelsByCourseID = supports.compactMapValues { keys in
            keys.isEmpty ? nil : PlaceholderDependencyText.supportLabel(keys, code: code)
        }
    }
}
