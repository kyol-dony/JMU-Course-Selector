import Foundation
import PlannerCore

/// An option requirement of one declared program (the major, a second
/// major, or a minor), as the plan sees it after concentration selection.
struct OptionRequirementRef: Hashable {
    var programID: String
    var requirement: RequirementCategory

    var choiceKey: String {
        RequirementOption.choiceKey(programID: programID, requirementID: requirement.id)
    }
}

/// Brings a saved plan in line with option requirements. Plans saved before
/// options existed picked "Option N" as a concentration, and their slots
/// were `__pl::option-N::<k>`; those become the option choice and the
/// chosen option's part slots, so the student's edits survive.
enum OptionChoiceMigration {
    /// For the major and each minor whose concentrationID no longer exists in
    /// its program: find an option requirement (in the program or in the
    /// concentration whose id is the old id's longest prefix) with an option
    /// whose id is the old id's suffix; set optionChoices[key], set
    /// concentrationID to that concentration (or nil), and rewrite pathway
    /// placeholders: old categoryID == option.id, slot k → the k-th slot
    /// across the chosen option's materialized parts, in semesters,
    /// `placeholders` (spec categoryID too) and `resolvedPlaceholders` keys.
    /// Also fills a default choice (`RequirementOption.defaultOptionID`) for
    /// every option requirement without one. Idempotent.
    static func migrate(_ plan: SavedStudentPlan, catalog: Catalog, completed: Set<String>) -> SavedStudentPlan {
        var plan = plan
        if let programID = plan.programID, let program = catalog.programsByID[programID],
           let found = formerOption(plan.concentrationID, in: program) {
            plan.concentrationID = found.concentrationID
            carryOver(found, programID: programID, program: program, into: &plan)
        }
        for index in plan.minors.indices {
            let selection = plan.minors[index]
            guard let program = catalog.programsByID[selection.programID],
                  let found = formerOption(selection.concentrationID, in: program) else { continue }
            plan.minors[index].concentrationID = found.concentrationID
            carryOver(found, programID: selection.programID, program: program, into: &plan)
        }
        for ref in optionRequirements(of: plan, catalog: catalog) {
            let options = ref.requirement.options ?? []
            if let chosen = plan.optionChoices[ref.choiceKey], options.contains(where: { $0.id == chosen }) { continue }
            plan.optionChoices[ref.choiceKey] = RequirementOption.defaultOptionID(options, completed: completed)
        }
        return plan
    }

    /// Option requirements of the declared major and minors, each with the
    /// id the scheduler gives it (after its concentration's requirements
    /// are merged in).
    static func optionRequirements(of plan: SavedStudentPlan, catalog: Catalog) -> [OptionRequirementRef] {
        let declared = [plan.programID.map { ($0, plan.concentrationID) }].compactMap { $0 }
            + plan.minors.map { ($0.programID, $0.concentrationID) }
        return declared.flatMap { programID, concentrationID -> [OptionRequirementRef] in
            guard let program = catalog.programsByID[programID],
                  let effective = try? program.effectiveProgram(concentrationID: concentrationID) else { return [] }
            return effective.requirements
                .filter { !($0.options ?? []).isEmpty }
                .map { OptionRequirementRef(programID: programID, requirement: $0) }
        }
    }

    private struct FormerOption {
        var concentrationID: String?
        var requirement: RequirementCategory
        var option: RequirementOption
    }

    /// The option a no-longer-existing concentration id named:
    /// "<track>-option-2" is option-2 under the track, "option-2" is option-2
    /// of a program-level requirement.
    private static func formerOption(_ oldID: String?, in program: Program) -> FormerOption? {
        guard let oldID, !program.concentrations.contains(where: { $0.id == oldID }) else { return nil }
        let tracks: [(Concentration?, String)] = program.concentrations
            .filter { oldID.hasPrefix($0.id + "-") }
            .sorted { $0.id.count > $1.id.count }
            .map { ($0, String(oldID.dropFirst($0.id.count + 1))) }
        for (track, suffix) in tracks + [(nil, oldID)] {
            let requirements = track.map { (try? program.effectiveProgram(concentrationID: $0.id).requirements) ?? [] }
                ?? program.requirements
            for requirement in requirements {
                if let option = requirement.options?.first(where: { $0.id == suffix }) {
                    return FormerOption(concentrationID: track?.id, requirement: requirement, option: option)
                }
            }
        }
        return nil
    }

    private static func carryOver(_ found: FormerOption, programID: String, program: Program, into plan: inout SavedStudentPlan) {
        let key = RequirementOption.choiceKey(programID: programID, requirementID: found.requirement.id)
        plan.optionChoices[key] = found.option.id
        // The parts exactly as scheduling materializes them.
        var single = program
        single.requirements = [found.requirement]
        single.concentrations = []
        let parts = single.choosingOptions([key: found.option.id], programID: programID).requirements
        let slots = parts.flatMap { part in part.courseOptions.indices.map { (part: part, index: $0) } }
        let oldPrefix = PathwayPlaceholder.prefix + found.option.id + "::"

        func target(_ oldID: String) -> (id: String, part: RequirementCategory)? {
            guard oldID.hasPrefix(oldPrefix), let k = Int(oldID.dropFirst(oldPrefix.count)), slots.indices.contains(k) else { return nil }
            let slot = slots[k]
            return (PathwayPlaceholder.id(categoryID: slot.part.id, optionIndex: slot.index), slot.part)
        }

        for pathwayIndex in plan.pathways.indices {
            var pathway = plan.pathways[pathwayIndex]
            for semesterIndex in pathway.semesters.indices {
                pathway.semesters[semesterIndex].courseIDs = pathway.semesters[semesterIndex].courseIDs.map { target($0)?.id ?? $0 }
            }
            var placeholders: [String: PlaceholderSpec] = [:]
            for (id, spec) in pathway.placeholders {
                guard let new = target(id) else {
                    placeholders[id] = spec
                    continue
                }
                var spec = spec
                spec.categoryID = new.part.id
                spec.categoryName = new.part.name
                // The "or take both" pair is offered in the slot, as generation does.
                spec.alternates += (new.part.alternativeGroup ?? []).filter { !spec.alternates.contains($0) }
                placeholders[new.id] = spec
            }
            pathway.placeholders = placeholders
            pathway.resolvedPlaceholders = Dictionary(
                pathway.resolvedPlaceholders.map { (target($0.key)?.id ?? $0.key, $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
            plan.pathways[pathwayIndex] = pathway
        }
    }
}
