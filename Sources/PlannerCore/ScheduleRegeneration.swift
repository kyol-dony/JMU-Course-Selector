import Foundation

public enum ScheduleGenerationStrategy: String, CaseIterable, Sendable {
    case balanced, majorFirst, genEdFirst

    public static func resolve(pathwayID: String, index: Int) -> Self {
        switch pathwayID {
        case "path-1": return .balanced
        case "path-2": return .majorFirst
        case "path-3": return .genEdFirst
        default: return allCases.indices.contains(index) ? allCases[index] : .balanced
        }
    }
}

public enum AnchoredRegenerationError: Error, LocalizedError {
    case invalidCutoff
    public var errorDescription: String? { "Choose an existing semester in the displayed pathway." }
}

/// An immutable prefix. Planned concrete courses are eligibility input only;
/// unresolved slots reserve requirements and hours without granting equivalences.
public struct AnchoredScheduleContext: Sendable {
    public let semesters: [SemesterPlan]
    public let placeholders: [String: PlaceholderSpec]
    public let resolvedPlaceholders: [String: String]
    public let completedCourseIDs: Set<String>
    public let reservedPlaceholderIDs: Set<String>
    public let standingSemesterOffset: Int
    public let preferenceSemesterOffset: Int
    public let startingSemester: SemesterIdentity

    public init(source: Pathway, through cutoff: SemesterIdentity) throws {
        guard source.semesters.contains(where: { $0.id == cutoff }) else {
            throw AnchoredRegenerationError.invalidCutoff
        }
        semesters = source.semesters.filter { $0.id <= cutoff }.sorted { $0.id < $1.id }
        let ids = Set(semesters.flatMap(\.courseIDs))
        let concrete = ids.filter { !PathwayPlaceholder.isPlaceholder($0) }
        completedCourseIDs = concrete
        resolvedPlaceholders = source.resolvedPlaceholders.filter { concrete.contains($0.value) }
        let reserved = ids.filter(PathwayPlaceholder.isPlaceholder).union(source.resolvedPlaceholders.filter { concrete.contains($0.value) }.keys)
        reservedPlaceholderIDs = reserved
        placeholders = source.placeholders.filter { reserved.contains($0.key) }
        standingSemesterOffset = semesters.count
        startingSemester = cutoff.next
        func position(_ semester: SemesterIdentity) -> Int {
            semester.year * 2 + (semester.term == .spring ? 0 : 1)
        }
        preferenceSemesterOffset = position(startingSemester) - position(semesters[0].id)
    }
}
