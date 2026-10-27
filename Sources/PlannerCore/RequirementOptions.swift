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

    /// The option with the most courses in `completed` (any part,
    /// alternatives included). Ties and zero go to the first option.
    public static func defaultOptionID(_ options: [RequirementOption], completed: Set<String>) -> String? {
        var best: (id: String, count: Int)?
        for option in options {
            let count = option.courseIDs.intersection(completed).count
            if best == nil || count > best!.count {
                best = (option.id, count)
            }
        }
        return best?.id
    }

    /// Every course any part of the option can use, alternatives included.
    var courseIDs: Set<String> {
        Set(parts.flatMap { part in part.courseOptions.flatMap { $0 } + (part.alternativeGroup ?? []) })
    }
}

public enum OptionPartID {
    private static let separator = "--"

    static func make(requirementID: String, optionID: String, partIndex: Int) -> String {
        [requirementID, optionID, String(partIndex)].joined(separator: separator)
    }

    /// ("choose-one-of-the-following-options", "option-2", 1) for
    /// "choose-one-of-the-following-options--option-2--1"; nil otherwise.
    public static func parse(_ categoryID: String) -> (requirementID: String, optionID: String, partIndex: Int)? {
        let pieces = categoryID.components(separatedBy: separator)
        guard pieces.count >= 3, let index = Int(pieces[pieces.count - 1]), index >= 0 else { return nil }
        let optionID = pieces[pieces.count - 2]
        let requirementID = pieces.dropLast(2).joined(separator: separator)
        guard !requirementID.isEmpty, !optionID.isEmpty else { return nil }
        return (requirementID, optionID, index)
    }
}

public extension Program {
    /// Replaces each option requirement (in requirements and concentrations)
    /// with the chosen option's parts: the choice comes from
    /// `choices[choiceKey]`, else the first option. Part i of option o of
    /// requirement r gets id "r--o--i" and name "Option label: part name"; a
    /// part with an `alternativeGroup` has the group's courses appended to
    /// every slot, without duplicates.
    func choosingOptions(_ choices: [String: String], programID: String) -> Program {
        func expand(_ requirements: [RequirementCategory]) -> [RequirementCategory] {
            requirements.flatMap { category -> [RequirementCategory] in
                guard let options = category.options, !options.isEmpty else { return [category] }
                let chosenID = choices[RequirementOption.choiceKey(programID: programID, requirementID: category.id)]
                let option = options.first { $0.id == chosenID } ?? options[0]
                return option.parts.enumerated().map { index, part in
                    var part = part
                    part.id = OptionPartID.make(requirementID: category.id, optionID: option.id, partIndex: index)
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
