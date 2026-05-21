import Foundation

/// Pass 2 of catalog parsing. After every program has been parsed and the
/// full course map is assembled, this resolver walks each course's scraped
/// `rawPrerequisiteText` and structures it into typed
/// `prerequisiteExpr` / `corequisiteExpr` trees. Runs once, in place.
///
/// Why it lives outside `CatalogHTMLParser`: cross-program references
/// ("CS 240 requires MATH 235") only resolve once the entire catalog has
/// been collected. Pass 1 builds the lookup map; Pass 2 consumes it.
public enum CatalogPrereqResolver {
    public static func applyPassTwo(to courses: inout [Course]) {
        let byID = Dictionary(uniqueKeysWithValues: courses.map { ($0.id, $0) })
        let parser = PrereqParser(coursesByID: byID)
        for index in courses.indices {
            let result = parser.parse(courses[index].rawPrerequisiteText)
            courses[index].prerequisiteExpr = result.prerequisiteExpr
            courses[index].corequisiteExpr = result.corequisiteExpr
            courses[index].hasUnknownPrereqTokens = result.hasUnknownTokens
            courses[index].prerequisites = flattenCourseIDs(result.prerequisiteExpr)
            if result.hasUnknownTokens {
                courses[index].verificationStatus = .partial
            }
        }
    }

    private static func flattenCourseIDs(_ expr: PrereqExpr) -> [String] {
        switch expr {
        case .course(let id): return [id]
        case .all(let xs), .any(let xs): return xs.flatMap(flattenCourseIDs)
        default: return []
        }
    }
}
