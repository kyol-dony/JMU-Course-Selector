import Foundation

/// Terms missing from a pathway between one semester and the next one it has.
public struct SemesterGap: Equatable, Sendable {
    /// The existing semester the gap follows.
    public var after: SemesterIdentity
    /// The missing terms, in calendar order.
    public var missing: [SemesterIdentity]

    public init(after: SemesterIdentity, missing: [SemesterIdentity]) {
        self.after = after
        self.missing = missing
    }
}

extension Pathway {
    /// Where generated pathways begin; also the first term of an empty pathway.
    public static let defaultStartSemester = SemesterIdentity(year: 2026, term: .fall)

    /// The term after the pathway's last semester.
    public var nextSemester: SemesterIdentity {
        semesters.map(\.id).max()?.next ?? Self.defaultStartSemester
    }

    /// Terms the pathway skips between its first and last semesters.
    public var semesterGaps: [SemesterGap] {
        let ordered = semesters.map(\.id).sorted()
        return zip(ordered, ordered.dropFirst()).compactMap { current, following in
            var missing: [SemesterIdentity] = []
            var term = current.next
            while term < following {
                missing.append(term)
                term = term.next
            }
            return missing.isEmpty ? nil : SemesterGap(after: current, missing: missing)
        }
    }
}
