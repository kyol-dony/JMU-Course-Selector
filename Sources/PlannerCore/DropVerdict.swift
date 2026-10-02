import Foundation

/// Position-independent identity for a warning: the same course tripping the
/// same rule is the same problem no matter which semester it sits in.
public struct WarningKey: Hashable, Sendable {
    public var courseID: String
    public var kind: ConflictKind
    public var semester: SemesterIdentity?

    public init(_ warning: ConflictWarning) {
        courseID = warning.courseID
        kind = warning.kind
        semester = warning.isSemesterLevel ? warning.semester : nil
    }
}

/// Compares two warning lists the way the schedule board reports changes.
public enum WarningDiff {
    public static func relevant(_ warnings: [ConflictWarning]) -> [ConflictWarning] {
        warnings.filter { !$0.isOverridden && $0.kind.severity != .hidden }
    }

    public static func added(before: [ConflictWarning], after: [ConflictWarning]) -> [ConflictWarning] {
        let beforeKeys = Set(relevant(before).map(WarningKey.init))
        return relevant(after).filter { !beforeKeys.contains(WarningKey($0)) }
    }

    public static func removedCount(before: [ConflictWarning], after: [ConflictWarning]) -> Int {
        removed(before: before, after: after).count
    }

    public static func removed(before: [ConflictWarning], after: [ConflictWarning]) -> Set<WarningKey> {
        let afterKeys = Set(relevant(after).map(WarningKey.init))
        return Set(relevant(before).map(WarningKey.init)).subtracting(afterKeys)
    }
}

/// What dropping a schedule item into one semester would do to the pathway.
public struct DropVerdict: Equatable, Sendable {
    public enum Level: Int, Comparable, Sendable {
        case clear
        case caution
        case blocking

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public var level: Level
    public var headline: String?
    public var reason: String?
    public var newWarnings: [ConflictWarning]
    public var fixedCount: Int
    public var affectedCourseIDs: Set<String>
    public var resolvedKeys: Set<WarningKey>

    public init(
        level: Level,
        headline: String?,
        reason: String?,
        newWarnings: [ConflictWarning],
        fixedCount: Int,
        affectedCourseIDs: Set<String>,
        resolvedKeys: Set<WarningKey> = []
    ) {
        self.level = level
        self.headline = headline
        self.reason = reason
        self.newWarnings = newWarnings
        self.fixedCount = fixedCount
        self.affectedCourseIDs = affectedCourseIDs
        self.resolvedKeys = resolvedKeys
    }

    public static let neutral = DropVerdict(
        level: .clear,
        headline: nil,
        reason: nil,
        newWarnings: [],
        fixedCount: 0,
        affectedCourseIDs: []
    )
}

/// Simulates moving one item into each semester of a pathway and reports the
/// warnings that move would add or clear. Pure; safe to call off the main actor.
public struct DropVerdictCalculator: Sendable {
    public var catalog: Catalog

    public init(catalog: Catalog) {
        self.catalog = catalog
    }

    public func verdicts(
        moving itemID: String,
        in pathway: Pathway,
        overrides: [ConflictOverride],
        activeProgramTitle: String? = nil,
        completedAtStart: Set<String> = [],
        workload: WorkloadPreference? = nil,
        earnedHoursAtStart: Double? = nil
    ) -> [SemesterIdentity: DropVerdict] {
        let semesterIDs = pathway.semesters.map(\.id)
        guard !PathwayPlaceholder.isPlaceholder(itemID) else {
            return Dictionary(uniqueKeysWithValues: semesterIDs.map { ($0, DropVerdict.neutral) })
        }

        let detector = ConflictDetector(catalog: catalog)
        func detect(_ candidate: Pathway) -> [ConflictWarning] {
            detector.warnings(
                for: candidate,
                overrides: overrides,
                activeProgramTitle: activeProgramTitle,
                completedAtStart: completedAtStart,
                workload: workload,
                earnedHoursAtStart: earnedHoursAtStart
            )
        }

        let origin = pathway.semesters.first { $0.courseIDs.contains(itemID) }?.id
        let baseline = detect(pathway)
        var result: [SemesterIdentity: DropVerdict] = [:]
        for semesterID in semesterIDs {
            if semesterID == origin {
                result[semesterID] = .neutral
                continue
            }
            var candidate = pathway
            for index in candidate.semesters.indices {
                candidate.semesters[index].courseIDs.removeAll { $0 == itemID }
                if candidate.semesters[index].id == semesterID {
                    candidate.semesters[index].courseIDs.append(itemID)
                }
            }
            let simulated = detect(candidate)
            let resolved = WarningDiff.removed(before: baseline, after: simulated)
            result[semesterID] = verdict(
                moving: itemID,
                target: semesterID,
                added: WarningDiff.added(before: baseline, after: simulated),
                fixedCount: resolved.count,
                resolved: resolved
            )
        }
        return result
    }

    private func verdict(moving itemID: String, target: SemesterIdentity, added: [ConflictWarning], fixedCount: Int, resolved: Set<WarningKey>) -> DropVerdict {
        let level = added.map { Self.level(for: $0.kind) }.max() ?? .clear
        let courseLevel = added.filter { !$0.isSemesterLevel }
        let others = courseLevel
            .filter { $0.courseID != itemID }
            .sorted { ($0.semester, $0.courseID) < ($1.semester, $1.courseID) }
        let own = courseLevel
            .filter { $0.courseID == itemID }
            .sorted { Self.level(for: $0.kind) > Self.level(for: $1.kind) }
        let affected = Set(others.map(\.courseID))

        let headline: String?
        let reason: String?
        if let first = others.first {
            let count = affected.count
            headline = "Breaks \(count) course\(count == 1 ? "" : "s")"
            reason = count == 1
                ? "\(code(first.courseID)) \(Self.lossPhrase(for: first.kind))"
                : "\(code(first.courseID)) and \(count - 1) more affected"
        } else if let first = own.first {
            headline = Self.ownHeadline(for: first)
            reason = Self.ownReason(for: first)
        } else if let load = Self.loadText(added.filter(\.isSemesterLevel), target: target) {
            headline = load.headline
            reason = load.reason
        } else if fixedCount > 0 {
            headline = "Fixes \(fixedCount)"
            reason = nil
        } else {
            headline = nil
            reason = nil
        }

        return DropVerdict(
            level: level,
            headline: headline,
            reason: reason,
            newWarnings: added,
            fixedCount: fixedCount,
            affectedCourseIDs: affected,
            resolvedKeys: resolved
        )
    }

    private static func loadText(_ load: [ConflictWarning], target: SemesterIdentity) -> (headline: String, reason: String)? {
        if let heavy = load.first(where: { $0.kind == .heavyLoad && $0.semester == target }) {
            return ("Heavy load", heavy.detail)
        }
        if let light = load.first(where: { $0.kind == .lightLoad && $0.semester != target }) {
            return ("Leaves \(light.semester.displayName) light", light.detail)
        }
        return nil
    }

    static func level(for kind: ConflictKind) -> DropVerdict.Level {
        switch kind.severity {
        case .mustFix: .blocking
        case .worthALook: .caution
        case .hidden: .clear
        }
    }

    private static func lossPhrase(for kind: ConflictKind) -> String {
        switch kind {
        case .missingPrerequisite: "loses its prereq"
        case .missingCorequisite: "loses its coreq"
        case .unavailableSemester: "is not offered that term"
        case .unknownAvailability: "has unknown availability"
        case .heavyLoad: "is overloaded"
        case .lightLoad: "is underloaded"
        }
    }

    private static func ownHeadline(for warning: ConflictWarning) -> String {
        switch warning.kind {
        case .missingPrerequisite: "Missing prereq"
        case .missingCorequisite: "Coreq not in place"
        case .unavailableSemester: "Not offered in \(warning.semester.term.rawValue)"
        case .unknownAvailability: "Availability unknown"
        case .heavyLoad: "Heavy load"
        case .lightLoad: "Light load"
        }
    }

    private static func ownReason(for warning: ConflictWarning) -> String? {
        switch warning.kind {
        case .missingPrerequisite:
            return firstSentence(of: warning.detail)
        case .missingCorequisite:
            return warning.summary
        case .unavailableSemester, .unknownAvailability, .heavyLoad, .lightLoad:
            return nil
        }
    }

    static func firstSentence(of message: String) -> String {
        guard let range = message.range(of: ". ") else { return message }
        return String(message[..<range.lowerBound]) + "."
    }

    private func code(_ courseID: String) -> String {
        catalog.coursesByID[courseID]?.code ?? courseID
    }
}
