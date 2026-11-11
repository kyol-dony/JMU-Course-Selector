import Foundation

/// Repairs Art requirements whose relationships live in catalog prose.
public enum ArtConcentrationPolicy {
    private static let studioNames = [
        "Ceramics", "Fibers", "Metals", "Painting", "Photography", "Printmaking", "Sculpture"
    ]
    private static let artEducationName = "Art Education"

    public static func selectionRequired(programID: String, parsedValue: Bool) -> Bool {
        ["art-ba", "art-bs"].contains(programID) ? false : parsedValue
    }

    public static func applying(to catalog: Catalog) -> Catalog {
        var catalog = catalog
        let sourceBFA = catalog.programsByID["art-bfa"]
        let studioConcentrations = sourceBFA?.concentrations.filter { studioNames.contains($0.name) } ?? []
        let education = sourceBFA?.concentrations.first { $0.name == artEducationName }

        catalog.programs = catalog.programs.map { program in
            var program = program
            program.concentrationSelectionRequired = selectionRequired(
                programID: program.id, parsedValue: program.concentrationSelectionRequired)

            if program.id == "art-bfa" {
                program.requirements = program.requirements.map(Self.artRelatedElectives)
                if let education {
                    let studios = program.concentrations.filter { studioNames.contains($0.name) }
                    let combined = studios.map { studio in
                        Concentration(
                            id: "\(studio.id)-art-education",
                            name: "\(studio.name) + Art Education",
                            requirements: studio.requirements + education.requirements,
                            verificationStatus: studio.verificationStatus == .verified && education.verificationStatus == .verified
                                ? .verified : .partial,
                            totalCredits: 143
                        )
                    }
                    // B.F.A. Art Education is additive to one studio area;
                    // never expose it as a standalone concentration.
                    program.concentrations = studios + combined
                    program.concentrationSelectionRequired = true
                }
            }

            if ["art-ba", "art-bs"].contains(program.id), !studioConcentrations.isEmpty {
                program.requirements = program.requirements.map { category in
                    Self.studioEmphasis(category, studios: studioConcentrations, coursesByID: catalog.coursesByID)
                }
            }
            return program
        }
        return catalog
    }

    /// Catalog names five subject areas but prints no course links. Subject
    /// tokens resolve against current catalog course inventory.
    private static func artRelatedElectives(_ category: RequirementCategory) -> RequirementCategory {
        guard category.name == "Art and Art-Related Electives" else { return category }
        var category = category
        let pool = ["ART", "GRPH", "ARCD", "ARED", "INDU"].map {
            ElectivePool.token(subject: $0, minimumNumber: 100)
        }
        category.requiredCredits = 15
        category.selection = .chooseCredits(15)
        category.courseOptions = Array(repeating: pool, count: 5)
        category.electivePoolSlots = Array(0..<5)
        category.note = "Choose 15 credits from Art, Graphic Design, Architectural Design, Art Education, or Industrial Design coursework, including eligible independent study, internship, and study-abroad studio work. Courses used for the studio concentration cannot count again here."
        category.verificationStatus = .partial
        category.allocationReview = "Allocation review required: studio-concentration courses cannot also satisfy these electives. For Art Education, only 15 credits may overlap. Course suggestions do not confirm fulfillment."
        return category
    }

    /// B.A./B.S. students choose six upper-level credits in one studio area.
    /// B.F.A. concentration lists supply current area membership.
    private static func studioEmphasis(
        _ category: RequirementCategory,
        studios: [Concentration],
        coursesByID: [String: Course]
    ) -> RequirementCategory {
        guard category.name == "Studio Art Emphasis" else { return category }
        var category = category
        let options = studios.compactMap { studio -> RequirementOption? in
            var seen: Set<String> = []
            let courses = studio.requirements
                .flatMap { $0.courseOptions.flatMap { $0 } }
                .filter { id in
                    guard seen.insert(id).inserted,
                          let course = coursesByID[id],
                          let parsed = ElectivePool.subjectAndNumber(of: course.code)
                    else { return false }
                    return parsed.subject == "ART" && (300...499).contains(parsed.number)
                }
            guard !courses.isEmpty else { return nil }
            var part = RequirementCategory(
                id: "studio-area",
                name: "Upper-level \(studio.name)",
                requiredCredits: 6,
                courseOptions: Array(repeating: courses, count: 2),
                verificationStatus: studio.verificationStatus,
                selection: .chooseCredits(6),
                choices: courses.map { [$0] }
            )
            part.allocationReview = "Allocation review required: these 6 credits must be additional to the 18 credits of Studio Art Electives."
            return RequirementOption(id: studio.id, label: studio.name, parts: [part])
        }
        guard !options.isEmpty else { return category }
        category.requiredCredits = 6
        category.courseOptions = []
        category.electivePoolSlots = nil
        category.selection = .chooseGroups(1)
        category.choices = []
        category.options = options
        category.allocationReview = "Allocation review required: these 6 credits must be additional to the 18 credits of Studio Art Electives."
        category.note = "Choose 6 credits of 300- or 400-level ART coursework in one studio area. Courses from different studio areas cannot be mixed."
        return category
    }
}
