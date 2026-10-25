import Foundation
import PlannerCore

/// The catalog tab's section index for one program: the requirements every
/// student shares, the chosen concentration's, then General Education as a
/// single entry.
struct CatalogOutline: Equatable {
    struct Entry: Identifiable, Equatable {
        enum Content: Equatable {
            case requirement(RequirementCategory)
            case generalEducation([RequirementCategory])
            case degree(DegreeRequirement)
        }

        let id: String
        let name: String
        let creditsText: String
        let hasCourseList: Bool
        let content: Content
    }

    struct Section: Identifiable, Equatable {
        let id: String
        let title: String
        let entries: [Entry]
    }

    let sections: [Section]

    var firstEntryID: String? { sections.first?.entries.first?.id }

    init(program: Program, concentrationID: String?) {
        let isGenEd = { (category: RequirementCategory) in
            ScheduleGenerator.isGenEdCategory(id: category.id, name: category.name)
        }
        var sections: [Section] = []
        let shared = program.requirements.filter { !isGenEd($0) }
        if !shared.isEmpty {
            sections.append(Section(id: "shared", title: "Shared", entries: shared.map { Self.entry($0, id: $0.id) }))
        }
        if let concentration = program.concentrations.first(where: { $0.id == concentrationID }),
           !concentration.requirements.isEmpty {
            sections.append(Section(
                id: "concentration-\(concentration.id)",
                title: "\(concentration.name) concentration",
                entries: concentration.requirements.map { Self.entry($0, id: "\(concentration.id)/\($0.id)") }
            ))
        }
        let genEd = program.requirements.filter(isGenEd)
        if !genEd.isEmpty {
            sections.append(Section(id: "every-major", title: "Every major", entries: [Entry(
                id: "general-education",
                name: "General Education",
                creditsText: "\(genEd.count) areas",
                hasCourseList: true,
                content: .generalEducation(genEd)
            )]))
        }
        if !program.degreeRequirements.isEmpty {
            sections.append(Section(id: "degree", title: "Degree", entries: program.degreeRequirements.map { requirement in
                Entry(
                    id: requirement.kind.categoryID,
                    name: DegreeRequirementText.name(requirement.kind),
                    creditsText: requirement.kind == .foreignLanguage ? "Through 232" : "\(requirement.creditsText) cr",
                    hasCourseList: false,
                    content: .degree(requirement)
                )
            }))
        }
        self.sections = sections
    }

    /// The concentration the dropdown starts on: the first one when the
    /// program requires a choice, otherwise none.
    static func defaultConcentrationID(for program: Program) -> String? {
        program.concentrationSelectionRequired ? program.concentrations.first?.id : nil
    }

    private static func entry(_ category: RequirementCategory, id: String) -> Entry {
        let hasCourseList = !category.courseOptions.isEmpty
        return Entry(
            id: id,
            name: category.name,
            creditsText: hasCourseList ? "\(category.requiredCredits) cr" : "No list",
            hasCourseList: hasCourseList,
            content: .requirement(category)
        )
    }
}

/// A requirement's selection rule in plain words, as shown on the catalog tab.
enum RequirementRuleText {
    static func label(for category: RequirementCategory) -> String {
        switch category.selection {
        case .allRequired: "All required"
        case .chooseCourses(let count):
            category.choices.isEmpty
                ? "Choose \(count) course\(count == 1 ? "" : "s")"
                : "Choose \(count) of \(category.choices.count)"
        case .chooseCredits(let credits): "Choose \(credits) credits"
        case .chooseGroups(let count): count == 1 ? "Choose 1 option" : "Choose \(count) options"
        case .unknown: "See catalog"
        }
    }
}

/// A B.A./B.S. degree requirement in plain words, as the catalog tab shows it.
enum DegreeRequirementText {
    static func name(_ kind: DegreeRequirementKind) -> String {
        switch kind {
        case .philosophy: "Philosophy"
        case .foreignLanguage: "Foreign Language"
        case .scientificLiteracy: "Scientific Literacy"
        case .quantitative: "Quantitative"
        }
    }

    static func rule(for requirement: DegreeRequirement) -> String {
        requirement.kind == .foreignLanguage ? "Through 232" : "Choose 3 credits"
    }

    /// Which courses count, from the Registrar's B.A./B.S. degree course list.
    static func eligibility(for kind: DegreeRequirementKind) -> String {
        switch kind {
        case .philosophy:
            "Any PHIL course except PHIL 120 and PHIL 150, not also used for General Education."
        case .foreignLanguage:
            "Any foreign language, including American Sign Language, through the 232 level. Where you start depends on placement."
        case .scientificLiteracy:
            "Any ANTH, BIO, CHEM, ECON, GEOG, GEOL, ISAT, ISCI, PHYS, POSC or SOCI course, or selected ASTR, CS, IA and KIN courses, not also used for General Education."
        case .quantitative:
            "Any MATH course, or selected BIO, CS, HSA, HTH, IA, ISAT and KIN courses, not also used for General Education."
        }
    }
}
