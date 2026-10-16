import Foundation

/// What a student has to do to satisfy a requirement, as the catalog states it.
public enum RequirementSelection: Codable, Hashable, Sendable {
    /// Every course group is required.
    case allRequired
    /// Pick this many courses from the list.
    case chooseCourses(Int)
    /// Pick courses totaling this many credits.
    case chooseCredits(Int)
    /// Pick this many whole course groups (a group can be a pair taken together).
    case chooseGroups(Int)
    /// The parser could not tell; callers keep their legacy behavior.
    case unknown

    /// The `courseOptions` slot view of a requirement: each inner list is one
    /// slot of interchangeable courses. Returns nil for `.unknown` so the
    /// parser keeps its legacy options.
    public static func slots(
        choices: [[String]],
        selection: RequirementSelection,
        credits: (String) -> Int
    ) -> [[String]]? {
        if case .unknown = selection { return nil }
        guard !choices.isEmpty else { return [] }
        let alternatives = unique(choices.flatMap { $0 })
        switch selection {
        case .allRequired:
            return alternatives.map { [$0] }
        case .chooseCourses(let count):
            return Array(repeating: alternatives, count: max(count, 1))
        case .chooseCredits(let total):
            let largest = max(alternatives.map(credits).max() ?? 1, 1)
            let count = max(Int(ceil(Double(total) / Double(largest))), 1)
            return Array(repeating: alternatives, count: count)
        case .chooseGroups(let count):
            // Groups of different sizes ("PSYC 492, 495, 497 or 499A-C") have
            // no member every option shares, so each of the N slots accepts
            // any member; equal-size groups (pairs) get one slot per position.
            guard Set(choices.map(\.count)).count == 1 else {
                return Array(repeating: alternatives, count: max(count, 1))
            }
            let width = choices.map(\.count).max() ?? 0
            let positions = (0..<width).map { position in
                unique(choices.compactMap { position < $0.count ? $0[position] : nil })
            }
            return Array(repeating: positions, count: max(count, 1)).flatMap { $0 }
        case .unknown:
            return nil
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
