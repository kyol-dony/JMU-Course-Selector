import Foundation

public enum PrereqRuleConfidence: String, Codable, Hashable, Sendable {
    case curated
    case parsed
    case none

    public var displayName: String {
        switch self {
        case .curated: "Curated"
        case .parsed: "Parsed from catalog"
        case .none: "No known rule"
        }
    }
}

public enum PrereqRuleBasis: String, Codable, Hashable, Sendable {
    case explicit
    case inferred

    public var displayName: String {
        switch self {
        case .explicit: "Explicit catalog rule"
        case .inferred: "Source-backed inference"
        }
    }
}

public struct PrereqRuleOverlay: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var rules: [PrereqRule]

    public static let empty = PrereqRuleOverlay(schemaVersion: 1, rules: [])

    public init(schemaVersion: Int, rules: [PrereqRule]) {
        self.schemaVersion = schemaVersion
        self.rules = rules
    }

    public func rule(for courseID: String) -> PrereqRule? {
        rules.first { $0.courseID == courseID }
    }
}

public struct PrereqRule: Codable, Hashable, Sendable {
    public var courseID: String
    public var prerequisiteExpr: PrereqExpr
    public var corequisiteExpr: PrereqExpr
    public var confidence: PrereqRuleConfidence
    public var basis: PrereqRuleBasis
    public var sourceURL: URL
    public var sourceText: String
    public var notes: String?

    public init(
        courseID: String,
        prerequisiteExpr: PrereqExpr,
        corequisiteExpr: PrereqExpr,
        confidence: PrereqRuleConfidence,
        basis: PrereqRuleBasis,
        sourceURL: URL,
        sourceText: String,
        notes: String? = nil
    ) {
        self.courseID = courseID
        self.prerequisiteExpr = prerequisiteExpr
        self.corequisiteExpr = corequisiteExpr
        self.confidence = confidence
        self.basis = basis
        self.sourceURL = sourceURL
        self.sourceText = sourceText
        self.notes = notes
    }
}

public struct ResolvedPrereqRule: Hashable, Sendable {
    public var courseID: String
    public var prerequisiteExpr: PrereqExpr
    public var corequisiteExpr: PrereqExpr
    public var confidence: PrereqRuleConfidence
    public var basis: PrereqRuleBasis?
    public var sourceText: String?
    public var sourceURL: URL?
    public var notes: String?
    public var hasUnknownTokens: Bool

    public init(
        courseID: String,
        prerequisiteExpr: PrereqExpr,
        corequisiteExpr: PrereqExpr,
        confidence: PrereqRuleConfidence,
        basis: PrereqRuleBasis? = nil,
        sourceText: String? = nil,
        sourceURL: URL? = nil,
        notes: String? = nil,
        hasUnknownTokens: Bool = false
    ) {
        self.courseID = courseID
        self.prerequisiteExpr = prerequisiteExpr
        self.corequisiteExpr = corequisiteExpr
        self.confidence = confidence
        self.basis = basis
        self.sourceText = sourceText
        self.sourceURL = sourceURL
        self.notes = notes
        self.hasUnknownTokens = hasUnknownTokens
    }
}

/// Pure rule resolver. Looks up curated overlay first, then parses raw
/// catalog prereq text, then falls back to the legacy flat
/// `Course.prerequisites` list, then reports `.none`.
public struct PrereqRuleResolver: Sendable {
    public var catalog: Catalog
    public var overlay: PrereqRuleOverlay
    private let parserIndex: PrereqParser.CourseIndex

    public init(catalog: Catalog, overlay: PrereqRuleOverlay? = nil) {
        self.catalog = catalog
        self.overlay = overlay ?? catalog.prereqRuleOverlay
        self.parserIndex = PrereqParser.CourseIndex(coursesByID: catalog.coursesByID)
    }

    public func rule(for course: Course, activeProgramTitle: String?) -> ResolvedPrereqRule {
        if let curated = overlay.rule(for: course.id) {
            return ResolvedPrereqRule(
                courseID: course.id,
                prerequisiteExpr: curated.prerequisiteExpr.enforcedCourseOnly,
                corequisiteExpr: curated.corequisiteExpr.enforcedCourseOnly,
                confidence: .curated,
                basis: curated.basis,
                sourceText: curated.sourceText,
                sourceURL: curated.sourceURL,
                notes: curated.notes,
                hasUnknownTokens: curated.prerequisiteExpr.containsUnknown || curated.corequisiteExpr.containsUnknown
            )
        }

        let trimmedRaw = course.rawPrerequisiteText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedRaw.isEmpty {
            let parser = PrereqParser(index: parserIndex, activeProgramTitle: activeProgramTitle)
            let parsed = parser.parse(trimmedRaw)
            return ResolvedPrereqRule(
                courseID: course.id,
                prerequisiteExpr: parsed.prerequisiteExpr.enforcedCourseOnly,
                corequisiteExpr: parsed.corequisiteExpr.enforcedCourseOnly,
                confidence: .parsed,
                sourceText: trimmedRaw,
                sourceURL: course.descriptionSourceURL ?? course.registrarURL,
                notes: parsed.hasUnknownTokens ? "Some catalog text could not be converted to course-only prereq/coreq rules." : nil,
                hasUnknownTokens: parsed.hasUnknownTokens
            )
        }

        if course.prerequisiteExpr != .empty || course.corequisiteExpr != .empty {
            return ResolvedPrereqRule(
                courseID: course.id,
                prerequisiteExpr: course.prerequisiteExpr.enforcedCourseOnly,
                corequisiteExpr: course.corequisiteExpr.enforcedCourseOnly,
                confidence: .parsed,
                sourceText: nil,
                sourceURL: course.descriptionSourceURL ?? course.registrarURL,
                notes: course.hasUnknownPrereqTokens ? "Some catalog text could not be converted to course-only prereq/coreq rules." : nil,
                hasUnknownTokens: course.hasUnknownPrereqTokens
            )
        }

        if !course.prerequisites.isEmpty {
            return ResolvedPrereqRule(
                courseID: course.id,
                prerequisiteExpr: Self.legacyPrerequisiteExpr(course.prerequisites),
                corequisiteExpr: .empty,
                confidence: .parsed,
                sourceText: nil,
                sourceURL: course.descriptionSourceURL ?? course.registrarURL,
                notes: nil,
                hasUnknownTokens: false
            )
        }

        return ResolvedPrereqRule(
            courseID: course.id,
            prerequisiteExpr: .empty,
            corequisiteExpr: .empty,
            confidence: .none
        )
    }

    private static func legacyPrerequisiteExpr(_ prerequisites: [String]) -> PrereqExpr {
        switch prerequisites.count {
        case 0: return .empty
        case 1: return .course(prerequisites[0])
        default: return .all(prerequisites.map(PrereqExpr.course))
        }
    }
}

public extension PrereqExpr {
    var containsUnknown: Bool {
        switch self {
        case .unknown:
            return true
        case .all(let children), .any(let children):
            return children.contains { $0.containsUnknown }
        default:
            return false
        }
    }

    var courseLeaves: [String] {
        switch self {
        case .course(let id):
            return [id]
        case .all(let children), .any(let children):
            return children.flatMap(\.courseLeaves)
        default:
            return []
        }
    }
}
