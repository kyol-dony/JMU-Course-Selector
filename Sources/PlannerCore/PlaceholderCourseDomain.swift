import Foundation

/// The courses a placeholder slot can become. Shared by conditional
/// prerequisite analysis and the placeholder picker so their menus can't
/// diverge.
public enum PlaceholderCourseDomain {
    /// The slot's catalog alternates in their listed order, without
    /// duplicates or unknown IDs; the whole catalog when it lists none (Open
    /// Electives).
    public static func eligibleCourseIDs(for spec: PlaceholderSpec, catalog: Catalog) -> [String] {
        guard !spec.alternates.isEmpty else { return catalog.courses.map(\.id) }
        let coursesByID = catalog.coursesByID
        var seen: Set<String> = []
        return spec.alternates.filter { coursesByID[$0] != nil && seen.insert($0).inserted }
    }
}
