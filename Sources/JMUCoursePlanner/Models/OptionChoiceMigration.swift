import Foundation
import PlannerCore

extension Program {
    /// False for the bundled seed's placeholder entries, which list a
    /// program without its requirements or concentrations. A saved plan's
    /// concentration and option are left alone until real data arrives.
    var hasRequirementData: Bool {
        requirementDataComplete && !(requirements.isEmpty && concentrations.isEmpty)
    }
}

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
    /// placeholders: old categoryID == option.id, each old slot → the slot
    /// of the chosen option's materialized parts whose menu matches its own
    /// (`slotMapping`), in semesters,
    /// `placeholders` (spec categoryID too) and `resolvedPlaceholders` keys.
    /// Also fills a default choice (`RequirementOption.defaultOptionID`) for
    /// every option requirement without one. Idempotent.
    static func migrate(_ plan: SavedStudentPlan, catalog: Catalog, completed: Set<String>) -> SavedStudentPlan {
        var plan = plan
        if let programID = plan.programID, let program = catalog.programsByID[programID], program.hasRequirementData,
           let found = formerOption(plan.concentrationID, in: program) {
            plan.concentrationID = found.concentrationID
            carryOver(found, programID: programID, program: program, into: &plan)
        }
        for index in plan.minors.indices {
            let selection = plan.minors[index]
            guard let program = catalog.programsByID[selection.programID], program.hasRequirementData,
                  let found = formerOption(selection.concentrationID, in: program) else { continue }
            plan.minors[index].concentrationID = found.concentrationID
            carryOver(found, programID: selection.programID, program: program, into: &plan)
        }
        // A plan saved before options existed may already schedule one
        // option's courses; they break a tie in completed courses.
        let scheduled = Set(plan.pathways.flatMap { $0.semesters.flatMap(\.courseIDs) + $0.resolvedPlaceholders.values })
        for ref in optionRequirements(of: plan, catalog: catalog) {
            let options = ref.requirement.options ?? []
            if let chosen = plan.optionChoices[ref.choiceKey], options.contains(where: { $0.id == chosen }) { continue }
            plan.optionChoices[ref.choiceKey] = RequirementOption.defaultOptionID(
                options, completed: completed, scheduled: scheduled, coursesByID: catalog.coursesByID
            )
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

        for pathwayIndex in plan.pathways.indices {
            var pathway = plan.pathways[pathwayIndex]
            let oldIDs = Set(pathway.placeholders.keys).union(pathway.resolvedPlaceholders.keys)
                .union(pathway.semesters.flatMap(\.courseIDs))
                .filter { $0.hasPrefix(oldPrefix) && Int($0.dropFirst(oldPrefix.count)) != nil }
            let mapping = slotMapping(oldIDs, in: pathway, to: slots.map { $0.part.courseOptions[$0.index] })
            func target(_ oldID: String) -> (id: String, part: RequirementCategory)? {
                guard let slot = mapping[oldID].map({ slots[$0] }) else { return nil }
                return (PathwayPlaceholder.id(categoryID: slot.part.id, optionIndex: slot.index), slot.part)
            }
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

    /// Sends each old slot to the new slot whose menu matches its own best
    /// (by shared courses over all courses), so a reordered option keeps its
    /// slots: the old Option 1 put "one of MATH 411/431/434/435" before its
    /// electives, the new one after them. Slots matching nothing (an
    /// unresolved elective pool, a slot without a spec) take the remaining
    /// new slots in order.
    private static func slotMapping(_ oldIDs: Set<String>, in pathway: Pathway, to newSlots: [[String]]) -> [String: Int] {
        func order(_ id: String) -> Int { Int(id.components(separatedBy: "::").last ?? "") ?? 0 }
        let old = oldIDs.sorted { order($0) < order($1) }
        let menus = old.map { id in
            Set(pathway.placeholders[id]?.alternates ?? []).union(pathway.resolvedPlaceholders[id].map { [$0] } ?? [])
        }
        var pairs: [(score: Double, old: Int, new: Int)] = []
        for (oldIndex, menu) in menus.enumerated() where !menu.isEmpty {
            for (newIndex, slot) in newSlots.enumerated() {
                let shared = menu.intersection(slot).count
                guard shared > 0 else { continue }
                pairs.append((Double(shared) / Double(menu.union(slot).count), oldIndex, newIndex))
            }
        }
        pairs.sort { ($0.score, -$0.old, -$0.new) > ($1.score, -$1.old, -$1.new) }
        var mapping: [String: Int] = [:]
        var used: Set<Int> = []
        for pair in pairs where mapping[old[pair.old]] == nil && !used.contains(pair.new) {
            mapping[old[pair.old]] = pair.new
            used.insert(pair.new)
        }
        var free = newSlots.indices.filter { !used.contains($0) }.makeIterator()
        for id in old where mapping[id] == nil {
            guard let next = free.next() else { break }
            mapping[id] = next
        }
        return mapping
    }
}
