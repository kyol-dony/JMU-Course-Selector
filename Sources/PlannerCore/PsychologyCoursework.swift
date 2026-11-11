import Foundation

/// Psychology's catalog leaves its three-credit elective unrestricted in
/// prose. Keep its credit budget visible without inventing a course domain.
public enum PsychologyCoursework {
    public static let programID = "psychology-bs"

    public static func applying(to category: RequirementCategory) -> RequirementCategory {
        guard category.name == "Psychology Electives" else { return category }
        var category = category
        category.requiredCredits = 3
        category.selection = .chooseCredits(3)
        category.courseOptions = []
        category.choices = []
        category.verificationStatus = .partial
        category.approval = .psychologyElective
        return category
    }

    /// Repair cached snapshots without a network refresh.
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
