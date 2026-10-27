import Foundation

/// One branch of a "choose one of the following options" requirement: an
/// ordered list of parts, each an ordinary requirement of its own.
public struct RequirementOption: Codable, Hashable, Sendable {
    /// Slug of the label: "option-2".
    public var id: String
    /// "Option 2".
    public var label: String
    /// Each part is an ordinary requirement; its id is local to the option.
    public var parts: [RequirementCategory]

    public init(id: String, label: String, parts: [RequirementCategory]) {
        self.id = id
        self.label = label
        self.parts = parts
    }

    /// Where a student's pick is stored. The program is part of the key
    /// because a major and a minor can both have a requirement with this id.
    public static func choiceKey(programID: String, requirementID: String) -> String {
        "\(programID)/\(requirementID)"
    }

    /// The option whose distinguishing courses in `completed` carry the
    /// most credits. A tie goes to the option with the most in `completed`
    /// and `scheduled` (a saved plan's courses) together, then to the first
    /// option. A course counts for one slot of an option, and only when it
    /// tells the options apart: elective-pool slots and courses every option
    /// lists are left out, since Math's pools list every MATH 3xx/4xx
    /// course in both options. Unknown courses count one credit.
    public static func defaultOptionID(
        _ options: [RequirementOption], completed: Set<String>, scheduled: Set<String> = [], coursesByID: [String: Course] = [:]
    ) -> String? {
        let slots = options.map(\.distinguishingSlots)
        let common = options.count > 1
            ? slots.dropFirst().reduce(Set(slots[0].joined())) { $0.intersection($1.joined()) }
            : []
        func credits(_ slots: [[String]], _ taken: Set<String>) -> Int {
            var consumed: Set<String> = []
            return slots.sorted { $0.count < $1.count }.reduce(0) { total, slot in
                guard let course = slot.first(where: { taken.contains($0) && !common.contains($0) && !consumed.contains($0) })
                else { return total }
                consumed.insert(course)
                return total + (coursesByID[course]?.credits ?? 1)
            }
        }
        var best: (id: String, score: (Int, Int))?
        for (option, optionSlots) in zip(options, slots) {
            let score = (credits(optionSlots, completed), credits(optionSlots, completed.union(scheduled)))
            if best == nil || score > best!.score {
                best = (option.id, score)
            }
        }
        return best?.id
    }

    /// The option's slots other than elective-pool slots, each offering the
    /// part's "or take both" group too.
    var distinguishingSlots: [[String]] {
        parts.flatMap { part in
            let pools = Set(part.electivePoolSlots ?? [])
            return part.courseOptions.enumerated()
                .filter { !pools.contains($0.offset) }
                .map { $0.element + (part.alternativeGroup ?? []) }
        }
    }
}

public enum OptionPartID {
    private static let separator = "--"
    private static let programSeparator: Character = "/"

    /// "r--o--i", or "p/r--o--i" for a part of a second major or minor `p`.
    static func make(programID: String? = nil, requirementID: String, optionID: String, partIndex: Int) -> String {
        let id = [requirementID, optionID, String(partIndex)].joined(separator: separator)
        return programID.map { "\($0)\(programSeparator)\(id)" } ?? id
    }

    /// (nil, "choose-one-of-the-following-options", "option-2", 1) for
    /// "choose-one-of-the-following-options--option-2--1", and the program
    /// first for a second major's or minor's part ("posc-minor/…--option-1--0");
    /// nil otherwise.
    public static func parse(_ categoryID: String) -> (programID: String?, requirementID: String, optionID: String, partIndex: Int)? {
        let pieces = categoryID.components(separatedBy: separator)
        guard pieces.count >= 3, let index = Int(pieces[pieces.count - 1]), index >= 0 else { return nil }
        let optionID = pieces[pieces.count - 2]
        var requirementID = pieces.dropLast(2).joined(separator: separator)
        var programID: String?
        if let slash = requirementID.firstIndex(of: programSeparator) {
            programID = String(requirementID[..<slash])
            requirementID = String(requirementID[requirementID.index(after: slash)...])
            guard programID?.isEmpty == false else { return nil }
        }
        guard !requirementID.isEmpty, !optionID.isEmpty else { return nil }
        return (programID, requirementID, optionID, index)
    }
}

public extension Program {
    /// Replaces each option requirement (in requirements and concentrations)
    /// with the chosen option's parts: the choice comes from
    /// `choices[choiceKey]`, else the first option. Part i of option o of
    /// requirement r gets id "r--o--i" and name "Option label: part name"; a
    /// part with an `alternativeGroup` has the group's courses appended to
    /// every slot, without duplicates. `asAdditionalProgram` (a second major
    /// or minor) puts the program in the part ids ("p/r--o--i"): real
    /// programs share requirement and option ids, and their slots must not.
    func choosingOptions(_ choices: [String: String], programID: String, asAdditionalProgram: Bool = false) -> Program {
        func expand(_ requirements: [RequirementCategory]) -> [RequirementCategory] {
            requirements.flatMap { category -> [RequirementCategory] in
                guard let options = category.options, !options.isEmpty else { return [category] }
                let chosenID = choices[RequirementOption.choiceKey(programID: programID, requirementID: category.id)]
                let option = options.first { $0.id == chosenID } ?? options[0]
                return option.parts.enumerated().map { index, part in
                    var part = part
                    part.id = OptionPartID.make(programID: asAdditionalProgram ? programID : nil,
                                                requirementID: category.id, optionID: option.id, partIndex: index)
                    part.name = "\(option.label): \(part.name)"
                    if let group = part.alternativeGroup {
                        part.courseOptions = part.courseOptions.map { slot in
                            slot + group.filter { !slot.contains($0) }
                        }
                    }
                    return part
                }
            }
        }

        var program = self
        program.requirements = expand(requirements)
        program.concentrations = concentrations.map { concentration in
            var concentration = concentration
            concentration.requirements = expand(concentration.requirements)
            return concentration
        }
        return program
    }
}
