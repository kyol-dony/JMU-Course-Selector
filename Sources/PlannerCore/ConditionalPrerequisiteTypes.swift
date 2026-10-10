import Foundation

// Transient inputs and results of conditional placeholder analysis. None of
// these are Codable or stored on a Pathway: they are derived from the
// current schedule each time, so no assumed course selection is ever saved.

/// Which rule a dependency comes from; decides when a provider must be
/// scheduled relative to the dependent course.
public enum ConditionalDependencyKind: Hashable, Sendable {
    /// Provider in an earlier semester.
    case prerequisite
    /// Provider in the same or an earlier semester.
    case corequisite
    /// Lab or lecture partner in the same semester.
    case labPairing
}

/// One requirement of one scheduled course.
public struct ConditionalDependencyKey: Hashable, Sendable {
    public let courseID: String
    public let semester: SemesterIdentity
    public let kind: ConditionalDependencyKind

    public init(courseID: String, semester: SemesterIdentity, kind: ConditionalDependencyKind) {
        self.courseID = courseID
        self.semester = semester
        self.kind = kind
    }
}

/// A dependency to satisfy: the complete expression, which real courses may
/// already partly cover.
public struct ConditionalPrerequisiteRequest: Sendable {
    public let key: ConditionalDependencyKey
    public let expression: PrereqExpr

    public init(key: ConditionalDependencyKey, expression: PrereqExpr) {
        self.key = key
        self.expression = expression
    }
}

/// The schedule and context the analysis reads.
public struct ConditionalPrerequisiteInput: Sendable {
    public let pathway: Pathway
    /// Courses earned before the first semester (transfer, AP, history).
    public let completedAtStart: Set<String>
    /// Each semester's class standing; a semester missing here doesn't
    /// enforce standing.
    public let standingBySemester: [SemesterIdentity: ClassStanding]
    /// Caps hypothetical choices at the workload's credit limit; nil skips
    /// the check.
    public let workload: WorkloadPreference?
    public let activeProgramTitle: String?
    /// Real courses planned but not yet placed (during generation). A slot
    /// never stands in for one, which would invent a duplicate enrollment.
    public let unscheduledCourseIDs: Set<String>

    public init(
        pathway: Pathway,
        completedAtStart: Set<String>,
        standingBySemester: [SemesterIdentity: ClassStanding],
        workload: WorkloadPreference?,
        activeProgramTitle: String?,
        unscheduledCourseIDs: Set<String> = []
    ) {
        self.pathway = pathway
        self.completedAtStart = completedAtStart
        self.standingBySemester = standingBySemester
        self.workload = workload
        self.activeProgramTitle = activeProgramTitle
        self.unscheduledCourseIDs = unscheduledCourseIDs
    }
}

/// A slot whose hypothetical course supports a scheduled course, directly
/// or through a chain of providers.
public struct ConditionalProviderUse: Hashable, Sendable {
    public let placeholderID: String
    public let supportingCourseID: String
    /// The scheduled course the chain ultimately supports.
    public let dependent: ConditionalDependencyKey

    public init(placeholderID: String, supportingCourseID: String, dependent: ConditionalDependencyKey) {
        self.placeholderID = placeholderID
        self.supportingCourseID = supportingCourseID
        self.dependent = dependent
    }
}

/// Outcome of a feasibility search.
public enum ConditionalFeasibility: Equatable, Sendable {
    /// A compatible slot → course assignment satisfies every request. The
    /// assignment is a witness only, never a student's selection.
    case feasible(assignments: [String: String], uses: Set<ConditionalProviderUse>)
    /// No compatible assignment exists.
    case impossible
    /// The search ran out of budget before deciding.
    case unconfirmed
}

/// A scheduled course's dependency status in a plan.
public enum ConditionalPrerequisiteStatus: Equatable, Sendable {
    /// Real courses satisfy it.
    case satisfied
    /// Compatible unresolved slot choices can satisfy it.
    case conditional
    /// Nothing in the plan can satisfy it.
    case unmet
    /// The search couldn't decide within its budget.
    case unconfirmed
}

/// Derived conditional dependencies of a plan.
public struct PlaceholderPrerequisiteAnalysis: Equatable, Sendable {
    public let statusByDependency: [ConditionalDependencyKey: ConditionalPrerequisiteStatus]
    /// Slot → eligible supporting option → requirements it supports.
    public let supportsByPlaceholder: [String: [String: Set<ConditionalDependencyKey>]]

    public init(
        statusByDependency: [ConditionalDependencyKey: ConditionalPrerequisiteStatus],
        supportsByPlaceholder: [String: [String: Set<ConditionalDependencyKey>]]
    ) {
        self.statusByDependency = statusByDependency
        self.supportsByPlaceholder = supportsByPlaceholder
    }

    public static let empty = PlaceholderPrerequisiteAnalysis(statusByDependency: [:], supportsByPlaceholder: [:])
}

/// Explored-state allowance, counted separately for each connected group
/// of slots and dependencies. Baseline proofs and forced-option probes in
/// one analysis pass share it.
public struct ConditionalSearchBudget: Sendable {
    public let limitPerGroup: Int
    private var used: [String: Int] = [:]

    public init(limitPerGroup: Int = 10_000) {
        self.limitPerGroup = limitPerGroup
    }

    /// Records one explored state for `group`; false once it's exhausted.
    mutating func spend(_ group: String) -> Bool {
        let count = used[group, default: 0]
        guard count < limitPerGroup else { return false }
        used[group] = count + 1
        return true
    }

    func isExhausted(_ group: String) -> Bool {
        used[group, default: 0] >= limitPerGroup
    }
}

/// Wording shared by the board's pending-choice notice and the placeholder
/// picker, so both explain a slot the same way.
public enum PlaceholderDependencyText {
    /// "MATH 410 in Spring 2027", once per course and semester, in schedule
    /// then course-code order.
    public static func dependentPhrases(_ keys: Set<ConditionalDependencyKey>, code: (String) -> String) -> [String] {
        var seen: Set<String> = []
        return keys
            .sorted { ($0.semester, code($0.courseID)) < ($1.semester, code($1.courseID)) }
            .map { "\(code($0.courseID)) in \($0.semester.displayName)" }
            .filter { seen.insert($0).inserted }
    }

    /// "A", "A and B", "A, B, and C".
    public static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
        }
    }

    /// "Choose MATH 300 here to support MATH 410 in Spring 2027." Choices
    /// supporting the same courses share one sentence.
    public static func choiceSentences(_ supports: [String: Set<ConditionalDependencyKey>], code: (String) -> String) -> [String] {
        var choicesByDependents: [[String]: [String]] = [:]
        for (option, keys) in supports {
            choicesByDependents[dependentPhrases(keys, code: code), default: []].append(option)
        }
        return choicesByDependents
            .map { dependents, options in (options.map(code).sorted(), dependents) }
            .sorted { $0.0.lexicographicallyPrecedes($1.0) }
            .map { options, dependents in
                "Choose \(options.joined(separator: " or ")) here to support \(list(dependents))."
            }
    }

    /// "Supports MATH 410 in Spring 2027", for one choice's picker row.
    public static func supportLabel(_ keys: Set<ConditionalDependencyKey>, code: (String) -> String) -> String {
        "Supports \(list(dependentPhrases(keys, code: code)))"
    }
}
