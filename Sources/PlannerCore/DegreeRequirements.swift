import Foundation

/// A requirement the bachelor's degree adds on top of the major and General
/// Education: Philosophy and a foreign language for a B.A., Scientific
/// Literacy and Quantitative for a B.S.
public enum DegreeRequirementKind: String, Codable, Hashable, Sendable, CaseIterable, CodingKeyRepresentable {
    case philosophy, foreignLanguage, scientificLiteracy, quantitative
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
    static func subjectAndNumber(_ courseID: String) -> (String, Int)? {
        let subject = courseID.prefix { $0.isLetter }
        let digits = courseID.dropFirst(subject.count).prefix { $0.isNumber }
        guard !subject.isEmpty, let number = Int(digits) else { return nil }
        return (String(subject), number)
    }
}
