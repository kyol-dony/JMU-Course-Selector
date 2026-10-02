import Foundation

/// A student's class standing in a planned semester.
public enum ClassStanding: Int, Codable, Hashable, Comparable, CaseIterable, Sendable {
    case firstYear
    case sophomore
    case junior
    case senior

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .firstYear: "first-year"
        case .sophomore: "sophomore"
        case .junior: "junior"
        case .senior: "senior"
        }
    }

    /// Standing for the semester at 1-based `position` in a plan of
    /// `totalSemesters`. A semester earns the higher of two standings:
    /// - by position on a four-year track (semesters 1–2 first-year, 3–4
    ///   sophomore, 5–6 junior, 7+ senior), and
    /// - by semesters remaining, counting this one, for students finishing
    ///   early (≤ 6 sophomore, ≤ 4 junior, ≤ 2 senior).
    /// Pass a nil total when the plan length isn't known yet (the schedule
    /// generator); only the position rule applies then.
    public static func forEarnedCredits(_ hours: Double) -> ClassStanding {
        if hours < 28 { return .firstYear }
        if hours < 60 { return .sophomore }
        if hours < 90 { return .junior }
        return .senior
    }

    public static func forSemester(position: Int, totalSemesters: Int?) -> ClassStanding {
        let byPosition = ClassStanding(rawValue: min(max(position - 1, 0) / 2, ClassStanding.senior.rawValue)) ?? .senior
        guard let totalSemesters else { return byPosition }
        let remaining = totalSemesters - position + 1
        let byRemaining: ClassStanding = switch remaining {
        case ...2: .senior
        case ...4: .junior
        case ...6: .sophomore
        default: .firstYear
        }
        return max(byPosition, byRemaining)
    }
}

/// A "sophomore standing"-style prerequisite: the standing a semester must
/// fall within for the course to be taken then.
public struct StandingRequirement: Codable, Hashable, Sendable {
    public var minimum: ClassStanding
    public var maximum: ClassStanding

    public init(minimum: ClassStanding, maximum: ClassStanding = .senior) {
        self.minimum = minimum
        self.maximum = max(minimum, maximum)
    }

    public func isSatisfied(by standing: ClassStanding) -> Bool {
        (minimum...maximum).contains(standing)
    }

    public var displayString: String {
        if maximum == .senior || minimum == maximum {
            return "\(minimum.displayName) standing"
        }
        let joiner = maximum.rawValue - minimum.rawValue == 1 ? "or" : "through"
        return "\(minimum.displayName) \(joiner) \(maximum.displayName) standing"
    }
}

public indirect enum PrereqExpr: Codable, Hashable, Sendable {
    case empty
    case course(String)
    case unknown(String)
    case standing(StandingRequirement)
    case all([PrereqExpr])
    case any([PrereqExpr])

    private enum CodingKeys: String, CodingKey { case kind, value, children, standing }
    private enum Kind: String, Codable { case empty, course, unknown, standing, all, any }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .empty: self = .empty
        case .course: self = .course(try c.decode(String.self, forKey: .value))
        case .unknown: self = .unknown(try c.decode(String.self, forKey: .value))
        case .standing: self = .standing(try c.decode(StandingRequirement.self, forKey: .standing))
        case .all: self = .all(try c.decode([PrereqExpr].self, forKey: .children))
        case .any: self = .any(try c.decode([PrereqExpr].self, forKey: .children))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .empty:
            try c.encode(Kind.empty, forKey: .kind)
        case .course(let id):
            try c.encode(Kind.course, forKey: .kind)
            try c.encode(id, forKey: .value)
        case .unknown(let text):
            try c.encode(Kind.unknown, forKey: .kind)
            try c.encode(text, forKey: .value)
        case .standing(let requirement):
            try c.encode(Kind.standing, forKey: .kind)
            try c.encode(requirement, forKey: .standing)
        case .all(let children):
            try c.encode(Kind.all, forKey: .kind)
            try c.encode(children, forKey: .children)
        case .any(let children):
            try c.encode(Kind.any, forKey: .kind)
            try c.encode(children, forKey: .children)
        }
    }
}

public extension PrereqExpr {
    var enforcedCourseOnly: PrereqExpr {
        switch self {
        case .empty:
            return .empty
        case .course, .standing:
            return self
        case .unknown:
            return .empty
        case .all(let children):
            let enforced = children
                .map(\.enforcedCourseOnly)
                .filter { $0 != .empty }
            switch enforced.count {
            case 0: return .empty
            case 1: return enforced[0]
            default: return .all(enforced)
            }
        case .any(let children):
            let enforced = children
                .map(\.enforcedCourseOnly)
                .filter { $0 != .empty }
            switch enforced.count {
            case 0: return .empty
            case 1: return enforced[0]
            default: return .any(enforced)
            }
        }
    }

    func displayString(coursesByID: [String: Course]) -> String {
        switch self {
        case .empty:
            return ""
        case .course(let id):
            return coursesByID[id]?.code ?? id
        case .unknown(let text):
            return text
        case .standing(let requirement):
            return requirement.displayString
        case .all(let children):
            return joinChildren(children, separator: " and ", coursesByID: coursesByID)
        case .any(let children):
            return joinChildren(children, separator: " or ", coursesByID: coursesByID)
        }
    }

    private func joinChildren(_ children: [PrereqExpr], separator: String, coursesByID: [String: Course]) -> String {
        children.map { child -> String in
            let rendered = child.displayString(coursesByID: coursesByID)
            switch child {
            case .all, .any:
                return "(\(rendered))"
            default:
                return rendered
            }
        }.joined(separator: separator)
    }
}
