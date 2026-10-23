import Foundation

/// A requirement the bachelor's degree adds on top of the major and General
/// Education: Philosophy and a foreign language for a B.A., Scientific
/// Literacy and Quantitative for a B.S.
public enum DegreeRequirementKind: String, Codable, Hashable, Sendable, CaseIterable, CodingKeyRepresentable {
    case philosophy, foreignLanguage, scientificLiteracy, quantitative

    /// Category ID of the requirement's placeholders ("degree-philosophy").
    public var categoryID: String { "degree-\(rawValue)" }

    /// Name of the requirement's pick-a-course placeholder.
    public var placeholderName: String {
        switch self {
        case .philosophy: "Philosophy (B.A.)"
        case .foreignLanguage: "Foreign Language (B.A.)"
        case .scientificLiteracy: "Scientific Literacy (B.S.)"
        case .quantitative: "Quantitative (B.S.)"
        }
    }
}

/// One row of a program's "Degree Requirements" table.
public struct DegreeRequirement: Codable, Hashable, Sendable {
    public var kind: DegreeRequirementKind
    /// The table's credits column, as written ("3", "3-4", "0-12").
    public var creditsText: String
    /// The table's footnote for the row, if any.
    public var note: String?

    public init(kind: DegreeRequirementKind, creditsText: String, note: String? = nil) {
        self.kind = kind
        self.creditsText = creditsText
        self.note = note
    }
}

/// Which courses satisfy each degree requirement, from the Registrar's
/// "Courses that may be used to satisfy B.A./B.S. Degree Requirements"
/// list. Bundled with the app; the catalog pages don't carry it.
public struct DegreeEligibility: Codable, Hashable, Sendable {
    public struct Rule: Codable, Hashable, Sendable {
        /// Subjects where any course counts ("BIO").
        public var anySubjects: [String]
        /// Subjects where only these course numbers count ("CS": [227, 327]).
        public var courses: [String: [Int]]
        /// Course IDs that never count ("PHIL120").
        public var excluded: [String]
        public var minimumCredits: Int

        public init(anySubjects: [String], courses: [String: [Int]] = [:], excluded: [String] = [], minimumCredits: Int = 3) {
            self.anySubjects = anySubjects
            self.courses = courses
            self.excluded = excluded
            self.minimumCredits = minimumCredits
        }
    }

    public var rules: [DegreeRequirementKind: Rule]
    /// Foreign-language subjects a B.A. language requirement can use.
    public var languageSubjects: [String]

    public init(rules: [DegreeRequirementKind: Rule], languageSubjects: [String]) {
        self.rules = rules
        self.languageSubjects = languageSubjects
    }

    public static let empty = DegreeEligibility(rules: [:], languageSubjects: [])

    /// Course numbers of the language sequence the planner reads: 101 → 102
    /// → 231 → 232, plus the intensive 111 (= 101 + 102) and 212 (= 231 + 232).
    public static let languageSequenceNumbers: Set<Int> = [101, 102, 111, 212, 231, 232]

    /// Whether `courseID` ("MATH231") counts toward `kind`. The foreign
    /// language is a sequence, not a list, so it is never eligible here.
    public func isEligible(_ courseID: String, for kind: DegreeRequirementKind) -> Bool {
        guard kind != .foreignLanguage, let rule = rules[kind],
              !rule.excluded.contains(courseID),
              let (subject, number) = Self.subjectAndNumber(courseID)
        else { return false }
        return rule.anySubjects.contains(subject) || rule.courses[subject]?.contains(number) == true
    }

    public static func load(from url: URL) throws -> DegreeEligibility {
        try JSONDecoder().decode(DegreeEligibility.self, from: Data(contentsOf: url))
    }

    /// "PHIL101" → ("PHIL", 101); "BIO140L" → ("BIO", 140).
    public static func subjectAndNumber(_ courseID: String) -> (String, Int)? {
        let subject = courseID.prefix { $0.isLetter }
        let digits = courseID.dropFirst(subject.count).prefix { $0.isNumber }
        guard !subject.isEmpty, let number = Int(digits) else { return nil }
        return (String(subject), number)
    }
}

/// Where a B.A. student starts the foreign-language sequence, from the
/// placement question in setup.
public enum LanguagePlacement: String, Codable, Hashable, Sendable, CaseIterable {
    case level101, level102, level231, level232, placedOut, notSure

    /// The first course number the plan schedules; nil when placed out.
    /// "Not sure yet" plans the full sequence from 101.
    public var startingNumber: Int? {
        switch self {
        case .level101, .notSure: 101
        case .level102: 102
        case .level231: 231
        case .level232: 232
        case .placedOut: nil
        }
    }
}

/// A B.A. student's language and placement.
public struct ForeignLanguagePlan: Codable, Hashable, Sendable {
    /// Course subject ("SPAN").
    public var subject: String
    public var placement: LanguagePlacement

    public init(subject: String, placement: LanguagePlacement) {
        self.subject = subject
        self.placement = placement
    }

    /// Whether any declared major's degree table lists the foreign-language
    /// requirement. Minors never carry degree requirements.
    public static func isRequired(by programs: [Program]) -> Bool {
        programs.contains { $0.kind == .major && $0.degreeRequirements.contains { $0.kind == .foreignLanguage } }
    }
}

/// Which planned courses the plan uses for General Education. A course used
/// for Gen Ed cannot also meet a degree requirement, and today a course
/// matched to a Gen Ed slot is not recorded per slot, so this re-derives it
/// the same way for scheduling and progress.
public enum GenEdAssignment {
    /// Each slot of each Gen Ed category (`ScheduleGenerator.isGenEdCategory`)
    /// takes one course from `courseIDs` among its alternates, in category
    /// order, preferring a course no degree kind in `degreeKinds` accepts. A
    /// resolved Gen Ed placeholder in `fixed` (placeholder ID → course) keeps
    /// the course the student chose.
    public static func courses(
        categories: [RequirementCategory],
        courseIDs: [String],
        fixed: [String: String],
        degreeKinds: Set<DegreeRequirementKind>,
        eligibility: DegreeEligibility
    ) -> Set<String> {
        var used: Set<String> = []
        func degreeUsable(_ id: String) -> Bool { degreeKinds.contains { eligibility.isEligible(id, for: $0) } }
        for category in categories where ScheduleGenerator.isGenEdCategory(id: category.id, name: category.name) {
            for (index, slot) in category.courseOptions.enumerated() {
                if let chosen = fixed[PathwayPlaceholder.id(categoryID: category.id, optionIndex: index)] {
                    used.insert(chosen)
                    continue
                }
                let candidates = courseIDs.filter { slot.contains($0) && !used.contains($0) }
                if let pick = candidates.first(where: { !degreeUsable($0) }) ?? candidates.first {
                    used.insert(pick)
                }
            }
        }
        return used
    }
}

/// What a plan still needs for its degree requirements.
public struct DegreeResolution: Equatable, Sendable {
    /// The course meeting each of Philosophy, Scientific Literacy and Quantitative.
    public var satisfiedBy: [DegreeRequirementKind: String] = [:]
    /// Language courses to schedule, in sequence order.
    public var languageCoursesToAdd: [String] = []
    public var languageComplete = false
    /// One entry per pick-a-course slot to add; `.foreignLanguage` once per
    /// sequence level missing from the catalog.
    public var placeholdersNeeded: [DegreeRequirementKind] = []
    /// Sequence levels with no catalog course.
    public var missingLanguageLevels: [Int] = []
}

/// Resolves a plan's courses against its degree requirements (spec §6.3).
public struct DegreeRequirementResolver: Sendable {
    private static let sequence = [101, 102, 231, 232]

    private let coursesByID: [String: Course]
    private let eligibility: DegreeEligibility

    public init(catalog: Catalog) {
        self.coursesByID = catalog.coursesByID
        self.eligibility = catalog.degreeEligibility
    }

    /// The degree requirements of every declared major, each once, in
    /// `DegreeRequirementKind` order. Minors carry none.
    public static func kinds(for programs: [Program]) -> [DegreeRequirementKind] {
        let declared = Set(programs.filter { $0.kind == .major }.flatMap { $0.degreeRequirements.map(\.kind) })
        return DegreeRequirementKind.allCases.filter(declared.contains)
    }

    public func resolve(
        kinds: [DegreeRequirementKind],
        plannedCourseIDs: [String],
        completedCourseIDs: Set<String>,
        genEdCourseIDs: Set<String>,
        languagePlan: ForeignLanguagePlan?
    ) -> DegreeResolution {
        var result = DegreeResolution()
        let available = completedCourseIDs.sorted() + plannedCourseIDs.filter { !completedCourseIDs.contains($0) }
        var used: Set<String> = []
        for kind in DegreeRequirementKind.allCases where kinds.contains(kind) {
            if kind == .foreignLanguage {
                resolveLanguage(languagePlan, planned: Set(plannedCourseIDs), completed: completedCourseIDs, into: &result)
                continue
            }
            if let course = available.first(where: {
                eligibility.isEligible($0, for: kind) && !genEdCourseIDs.contains($0) && !used.contains($0)
            }) {
                used.insert(course)
                result.satisfiedBy[kind] = course
            } else {
                result.placeholdersNeeded.append(kind)
            }
        }
        return result
    }

    /// From the placement's starting level, or the level after the highest
    /// course in the subject already planned or earned (111 counts as 102,
    /// 212 as 232), through 232.
    private func resolveLanguage(_ plan: ForeignLanguagePlan?, planned: Set<String>, completed: Set<String>, into result: inout DegreeResolution) {
        guard let plan else { return }
        let taken = planned.union(completed)
        let levels = taken.compactMap { id -> Int? in
            guard let (subject, number) = DegreeEligibility.subjectAndNumber(id), subject == plan.subject else { return nil }
            switch number {
            case 111: return 102
            case 212: return 232
            default: return Self.sequence.contains(number) ? number : nil
            }
        }
        let earned = completed.compactMap { id -> Int? in
            guard let (subject, number) = DegreeEligibility.subjectAndNumber(id), subject == plan.subject else { return nil }
            return number == 212 ? 232 : number == 111 ? 102 : number
        }
        guard let placementStart = plan.placement.startingNumber, !levels.contains(232) else {
            result.languageComplete = plan.placement == .placedOut || earned.contains(232)
            return
        }
        let highest = levels.max().flatMap { Self.sequence.firstIndex(of: $0) }
        let start = max(Self.sequence.firstIndex(of: placementStart) ?? 0, highest.map { $0 + 1 } ?? 0)
        for number in Self.sequence[start...] {
            let id = "\(plan.subject)\(number)"
            if taken.contains(id) { continue }
            if coursesByID[id] != nil {
                result.languageCoursesToAdd.append(id)
            } else {
                result.missingLanguageLevels.append(number)
                result.placeholdersNeeded.append(.foreignLanguage)
            }
        }
    }
}
