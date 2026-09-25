import Foundation

/// Position-independent identity for a warning: the same course tripping the
/// same rule is the same problem no matter which semester it sits in.
public struct WarningKey: Hashable, Sendable {
    public var courseID: String
    public var kind: ConflictKind

    public init(_ warning: ConflictWarning) {
        courseID = warning.courseID
        kind = warning.kind
    }
}

/// Compares two warning lists the way the schedule board reports changes.
public enum WarningDiff {
    public static func relevant(_ warnings: [ConflictWarning]) -> [ConflictWarning] {
        warnings.filter { !$0.isOverridden && $0.kind != .unknownAvailability }
    }

    public static func added(before: [ConflictWarning], after: [ConflictWarning]) -> [ConflictWarning] {
        let beforeKeys = Set(relevant(before).map(WarningKey.init))
        return relevant(after).filter { !beforeKeys.contains(WarningKey($0)) }
    }

    public static func removedCount(before: [ConflictWarning], after: [ConflictWarning]) -> Int {
        let afterKeys = Set(relevant(after).map(WarningKey.init))
        return Set(relevant(before).map(WarningKey.init)).subtracting(afterKeys).count
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

    public init(
        level: Level,
        headline: String?,
        reason: String?,
        newWarnings: [ConflictWarning],
        fixedCount: Int,
        affectedCourseIDs: Set<String>
    ) {
        self.level = level
        self.headline = headline
        self.reason = reason
        self.newWarnings = newWarnings
        self.fixedCount = fixedCount
        self.affectedCourseIDs = affectedCourseIDs
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
        completedAtStart: Set<String> = []
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
                completedAtStart: completedAtStart
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
            result[semesterID] = verdict(
                moving: itemID,
                added: WarningDiff.added(before: baseline, after: simulated),
                fixedCount: WarningDiff.removedCount(before: baseline, after: simulated)
            )
        }
        return result
    }

    private func verdict(moving itemID: String, added: [ConflictWarning], fixedCount: Int) -> DropVerdict {
        let level = added.map { Self.level(for: $0.kind) }.max() ?? .clear
        let others = added
            .filter { $0.courseID != itemID }
            .sorted { ($0.semester, $0.courseID) < ($1.semester, $1.courseID) }
        let own = added
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
            affectedCourseIDs: affected
        )
    }

    static func level(for kind: ConflictKind) -> DropVerdict.Level {
        switch kind {
        case .missingPrerequisite, .unavailableSemester: .blocking
        case .missingCorequisite: .caution
        case .unknownAvailability: .clear
        }
    }

    private static func lossPhrase(for kind: ConflictKind) -> String {
        switch kind {
        case .missingPrerequisite: "loses its prereq"
        case .missingCorequisite: "loses its coreq"
        case .unavailableSemester: "is not offered that term"
        case .unknownAvailability: "has unknown availability"
        }
    }

    private static func ownHeadline(for warning: ConflictWarning) -> String {
        switch warning.kind {
        case .missingPrerequisite: "Missing prereq"
        case .missingCorequisite: "Coreq not in place"
        case .unavailableSemester: "Not offered in \(warning.semester.term.rawValue)"
        case .unknownAvailability: "Availability unknown"
        }
    }

    private static func ownReason(for warning: ConflictWarning) -> String? {
        switch warning.kind {
        case .missingPrerequisite:
            return firstSentence(of: warning.message)
        case .missingCorequisite:
            guard let range = warning.message.range(of: ": ") else { return warning.message }
            return "Take with \(warning.message[range.upperBound...])"
        case .unavailableSemester, .unknownAvailability:
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
