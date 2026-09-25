import Foundation

public enum FixSuggestion: Equatable, Sendable {
    /// Move the warned course to this semester.
    case move(courseID: String, to: SemesterIdentity)
    /// A prerequisite is scheduled too late; move it earlier.
    case moveEarlier(courseID: String)
}

/// One-click fixes for a course warning, read from the drop verdicts the
/// board already computes for that course.
public struct FixSuggester: Sendable {
    public var catalog: Catalog

    public init(catalog: Catalog) {
        self.catalog = catalog
    }

    public func suggestions(
        for warning: ConflictWarning,
        verdicts: [SemesterIdentity: DropVerdict],
        in pathway: Pathway
    ) -> [FixSuggestion] {
        guard !warning.isSemesterLevel, warning.kind.severity != .hidden else { return [] }
        let key = WarningKey(warning)
        let ordered = pathway.semesters.map(\.id).sorted()
        guard let currentIndex = ordered.firstIndex(of: warning.semester) else { return [] }

        let candidates = ordered.enumerated()
            .compactMap { index, semester -> (distance: Int, index: Int, semester: SemesterIdentity)? in
                guard semester != warning.semester, let verdict = verdicts[semester] else { return nil }
                guard verdict.resolvedKeys.contains(key),
                      !verdict.newWarnings.contains(where: { $0.kind.severity == .mustFix })
                else { return nil }
                return (abs(index - currentIndex), index, semester)
            }
            .sorted { ($0.distance, $0.index) < ($1.distance, $1.index) }
        if !candidates.isEmpty {
            return candidates.prefix(2).map { FixSuggestion.move(courseID: warning.courseID, to: $0.semester) }
        }

        guard warning.kind == .missingPrerequisite else { return [] }
        let semesterOf = Dictionary(
            pathway.semesters.flatMap { plan in plan.courseIDs.map { ($0, plan.id) } },
            uniquingKeysWith: { first, _ in first }
        )
        let late = warning.missingCourseIDs
            .compactMap { id -> (semester: SemesterIdentity, code: String, id: String)? in
                guard let semester = semesterOf[id], semester >= warning.semester else { return nil }
                return (semester, catalog.coursesByID[id]?.code ?? id, id)
            }
            .sorted { ($0.semester, $0.code) < ($1.semester, $1.code) }
        guard let first = late.first else { return [] }
        return [FixSuggestion.moveEarlier(courseID: first.id)]
    }
}
