import Foundation

/// An enforceable credit obligation whose eligibility needs evidence beyond a
/// catalog course code. Examples explain the rule; they are not a course pool.
public struct CourseworkApproval: Codable, Hashable, Sendable {
    public var guidance: String
    public var examples: [String]
    public var sourceURL: URL

    public static let honors = CourseworkApproval(
        guidance: "Complete Honors-approved coursework in General Education, the Honors College, or an academic unit. Confirm the Honors section or approved Honors option with Honors advising. An ordinary course code alone does not establish Honors credit. These credits may also meet major or General Education requirements; reserved hours are provisional until overlap is confirmed.",
        examples: [
            "HON 200 or HON 300 interdisciplinary seminars",
            "Honors-designated General Education sections",
            "Honors-designated departmental sections or approved Honors options"
        ],
        sourceURL: URL(string: "https://www.jmu.edu/honors/faculty/teaching-for-honors.shtml")!
    )

    public static let psychologyElective = CourseworkApproval(
        guidance: "Choose 3 credit hours of psychology electives. The catalog does not state an eligible prefix, course level, or fixed course list, so confirm the course with Psychology advising before treating it as satisfying this requirement.",
        examples: [],
        sourceURL: URL(string: "https://catalog.jmu.edu/programs/psychology-bs/")!
    )
}

public enum HonorsCoursework {
    public static let programID = "honors-interdisciplinary-studies-minor"

    public static func applying(to category: RequirementCategory) -> RequirementCategory {
        guard category.name == "Honors Courses" else { return category }
        var category = category
        category.requiredCredits = 12
        category.selection = .chooseCredits(12)
        category.courseOptions = []
        category.choices = []
        category.verificationStatus = .partial
        category.approval = .honors
        return category
    }

    /// Repair existing snapshots too, without requiring a network refresh.
    public static func applying(to catalog: Catalog) -> Catalog {
        var catalog = catalog
        catalog.programs = catalog.programs.map { program in
            guard program.id == programID else { return program }
            var program = program
            program.requirements = program.requirements.map { applying(to: $0) }
            return program
        }
        return catalog
    }
}
