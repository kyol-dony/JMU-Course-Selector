import Foundation

public enum SemesterTerm: String, Codable, Hashable, CaseIterable, Comparable, Sendable {
    case fall = "Fall"
    case spring = "Spring"

    public static func < (lhs: SemesterTerm, rhs: SemesterTerm) -> Bool {
        switch (lhs, rhs) {
        case (.spring, .fall): true
        default: false
        }
    }
}

public struct SemesterIdentity: Codable, Hashable, Comparable, Sendable {
    public var year: Int
    public var term: SemesterTerm

    public init(year: Int, term: SemesterTerm) {
        self.year = year
        self.term = term
    }

    public var displayName: String {
        "\(term.rawValue) \(year)"
    }

    public var next: SemesterIdentity {
        switch term {
        case .fall:
            SemesterIdentity(year: year + 1, term: .spring)
        case .spring:
            SemesterIdentity(year: year, term: .fall)
        }
    }

    public static func < (lhs: SemesterIdentity, rhs: SemesterIdentity) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        return lhs.term < rhs.term
    }
}

public enum VerificationStatus: String, Codable, Hashable, Sendable {
    case verified
    case unverified
    case partial
}

public enum ProgramKind: String, Codable, Hashable, Sendable {
    case major
    case minor
    case certificate
}

public struct CatalogSource: Codable, Hashable, Sendable {
    public var catalogYear: String
    public var issueDate: Date
    public var retrievedDate: Date
    public var sourceURLs: [URL]
    public var retrievalNotes: [String]

    public init(catalogYear: String, issueDate: Date, retrievedDate: Date, sourceURLs: [URL], retrievalNotes: [String]) {
        self.catalogYear = catalogYear
        self.issueDate = issueDate
        self.retrievedDate = retrievedDate
        self.sourceURLs = sourceURLs
        self.retrievalNotes = retrievalNotes
    }

    public func isOlderThanSixMonths(referenceDate: Date = Date()) -> Bool {
        Calendar.current.dateComponents([.month], from: retrievedDate, to: referenceDate).month ?? 0 >= 6
    }
}

public struct Course: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var code: String
    public var title: String
    public var credits: Int
    public var availability: Set<SemesterTerm>?
    public var prerequisites: [String]
    public var verificationStatus: VerificationStatus
    public var registrarURL: URL?
    public var description: String?
    public var descriptionSourceURL: URL?
    public var detailRetrievedAt: Date?
    public var prerequisiteExpr: PrereqExpr
    public var corequisiteExpr: PrereqExpr
    public var hasUnknownPrereqTokens: Bool
    /// Raw prereq sentence scraped from the catalog detail page, retained until
    /// Pass 2 of catalog parsing structures it into `prerequisiteExpr`. Not user
    /// facing; absent when the course's detail page hasn't been fetched yet.
    public var rawPrerequisiteText: String?

    public init(
        id: String,
        code: String,
        title: String,
        credits: Int,
        availability: Set<SemesterTerm>?,
        prerequisites: [String],
        verificationStatus: VerificationStatus = .verified,
        registrarURL: URL? = nil,
        description: String? = nil,
        descriptionSourceURL: URL? = nil,
        detailRetrievedAt: Date? = nil,
        prerequisiteExpr: PrereqExpr = .empty,
        corequisiteExpr: PrereqExpr = .empty,
        hasUnknownPrereqTokens: Bool = false,
        rawPrerequisiteText: String? = nil
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.credits = credits
        self.availability = availability
        self.prerequisites = prerequisites
        self.verificationStatus = verificationStatus
        self.registrarURL = registrarURL
        self.description = description
        self.descriptionSourceURL = descriptionSourceURL
        self.detailRetrievedAt = detailRetrievedAt
        self.prerequisiteExpr = prerequisiteExpr
        self.corequisiteExpr = corequisiteExpr
        self.hasUnknownPrereqTokens = hasUnknownPrereqTokens
        self.rawPrerequisiteText = rawPrerequisiteText
    }

    private enum CourseCodingKeys: String, CodingKey {
        case id, code, title, credits, availability, prerequisites, verificationStatus,
             registrarURL, description, descriptionSourceURL, detailRetrievedAt,
             prerequisiteExpr, corequisiteExpr, hasUnknownPrereqTokens, rawPrerequisiteText
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CourseCodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.code = try c.decode(String.self, forKey: .code)
        self.title = try c.decode(String.self, forKey: .title)
        self.credits = try c.decode(Int.self, forKey: .credits)
        self.availability = try c.decodeIfPresent(Set<SemesterTerm>.self, forKey: .availability)
        self.prerequisites = try c.decode([String].self, forKey: .prerequisites)
        self.verificationStatus = try c.decodeIfPresent(VerificationStatus.self, forKey: .verificationStatus) ?? .verified
        self.registrarURL = try c.decodeIfPresent(URL.self, forKey: .registrarURL)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.descriptionSourceURL = try c.decodeIfPresent(URL.self, forKey: .descriptionSourceURL)
        self.detailRetrievedAt = try c.decodeIfPresent(Date.self, forKey: .detailRetrievedAt)
        self.prerequisiteExpr = try c.decodeIfPresent(PrereqExpr.self, forKey: .prerequisiteExpr) ?? .empty
        self.corequisiteExpr = try c.decodeIfPresent(PrereqExpr.self, forKey: .corequisiteExpr) ?? .empty
        self.hasUnknownPrereqTokens = try c.decodeIfPresent(Bool.self, forKey: .hasUnknownPrereqTokens) ?? false
        self.rawPrerequisiteText = try c.decodeIfPresent(String.self, forKey: .rawPrerequisiteText)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CourseCodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(code, forKey: .code)
        try c.encode(title, forKey: .title)
        try c.encode(credits, forKey: .credits)
        try c.encodeIfPresent(availability, forKey: .availability)
        try c.encode(prerequisites, forKey: .prerequisites)
        try c.encode(verificationStatus, forKey: .verificationStatus)
        try c.encodeIfPresent(registrarURL, forKey: .registrarURL)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(descriptionSourceURL, forKey: .descriptionSourceURL)
        try c.encodeIfPresent(detailRetrievedAt, forKey: .detailRetrievedAt)
        try c.encode(prerequisiteExpr, forKey: .prerequisiteExpr)
        try c.encode(corequisiteExpr, forKey: .corequisiteExpr)
        try c.encode(hasUnknownPrereqTokens, forKey: .hasUnknownPrereqTokens)
        try c.encodeIfPresent(rawPrerequisiteText, forKey: .rawPrerequisiteText)
    }
}

public struct RequirementCategory: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var requiredCredits: Int
    public var courseOptions: [[String]]
    public var verificationStatus: VerificationStatus
    public var note: String?

    public init(
        id: String,
        name: String,
        requiredCredits: Int,
        courseOptions: [[String]],
        verificationStatus: VerificationStatus = .verified,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.requiredCredits = requiredCredits
        self.courseOptions = courseOptions
        self.verificationStatus = verificationStatus
        self.note = note
    }
}

public struct Concentration: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var requirements: [RequirementCategory]
    public var verificationStatus: VerificationStatus

    public init(id: String, name: String, requirements: [RequirementCategory], verificationStatus: VerificationStatus = .unverified) {
        self.id = id
        self.name = name
        self.requirements = requirements
        self.verificationStatus = verificationStatus
    }
}

public struct Program: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var degreeType: String?
    public var kind: ProgramKind
    public var college: String
    public var department: String
    public var catalogPage: Int?
    public var totalCredits: Int?
    public var requirements: [RequirementCategory]
    public var concentrations: [Concentration]
    public var concentrationSelectionRequired: Bool
    public var verificationStatus: VerificationStatus
    public var requirementDataComplete: Bool
    public var sourceNote: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case degreeType
        case kind
        case college
        case department
        case catalogPage
        case totalCredits
        case requirements
        case concentrations
        case concentrationSelectionRequired
        case verificationStatus
        case requirementDataComplete
        case sourceNote
    }

    public init(
        id: String,
        title: String,
        degreeType: String?,
        kind: ProgramKind,
        college: String,
        department: String,
        catalogPage: Int?,
        totalCredits: Int?,
        requirements: [RequirementCategory],
        concentrations: [Concentration] = [],
        concentrationSelectionRequired: Bool? = nil,
        verificationStatus: VerificationStatus,
        requirementDataComplete: Bool,
        sourceNote: String
    ) {
        self.id = id
        self.title = title
        self.degreeType = degreeType
        self.kind = kind
        self.college = college
        self.department = department
        self.catalogPage = catalogPage
        self.totalCredits = totalCredits
        self.requirements = requirements
        self.concentrations = concentrations
        self.concentrationSelectionRequired = concentrationSelectionRequired ?? !concentrations.isEmpty
        self.verificationStatus = verificationStatus
        self.requirementDataComplete = requirementDataComplete
        self.sourceNote = sourceNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        degreeType = try container.decodeIfPresent(String.self, forKey: .degreeType)
        kind = try container.decode(ProgramKind.self, forKey: .kind)
        college = try container.decode(String.self, forKey: .college)
        department = try container.decode(String.self, forKey: .department)
        catalogPage = try container.decodeIfPresent(Int.self, forKey: .catalogPage)
        totalCredits = try container.decodeIfPresent(Int.self, forKey: .totalCredits)
        requirements = try container.decode([RequirementCategory].self, forKey: .requirements)
        concentrations = try container.decodeIfPresent([Concentration].self, forKey: .concentrations) ?? []
        concentrationSelectionRequired = try container.decodeIfPresent(Bool.self, forKey: .concentrationSelectionRequired) ?? !concentrations.isEmpty
        verificationStatus = try container.decode(VerificationStatus.self, forKey: .verificationStatus)
        requirementDataComplete = try container.decode(Bool.self, forKey: .requirementDataComplete)
        sourceNote = try container.decode(String.self, forKey: .sourceNote)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(degreeType, forKey: .degreeType)
        try container.encode(kind, forKey: .kind)
        try container.encode(college, forKey: .college)
        try container.encode(department, forKey: .department)
        try container.encodeIfPresent(catalogPage, forKey: .catalogPage)
        try container.encodeIfPresent(totalCredits, forKey: .totalCredits)
        try container.encode(requirements, forKey: .requirements)
        try container.encode(concentrations, forKey: .concentrations)
        try container.encode(concentrationSelectionRequired, forKey: .concentrationSelectionRequired)
        try container.encode(verificationStatus, forKey: .verificationStatus)
        try container.encode(requirementDataComplete, forKey: .requirementDataComplete)
        try container.encode(sourceNote, forKey: .sourceNote)
    }
}

public struct Catalog: Codable, Sendable {
    public var source: CatalogSource
    public var programs: [Program]
    public var courses: [Course]
    public var apCreditRules: [TransferCreditRule]
    public var prereqRuleOverlay: PrereqRuleOverlay

    public init(
        source: CatalogSource,
        programs: [Program],
        courses: [Course],
        apCreditRules: [TransferCreditRule],
        prereqRuleOverlay: PrereqRuleOverlay = .empty
    ) {
        self.source = source
        self.programs = programs
        self.courses = courses
        self.apCreditRules = apCreditRules
        self.prereqRuleOverlay = prereqRuleOverlay
    }

    private enum CodingKeys: String, CodingKey {
        case source, programs, courses, apCreditRules, prereqRuleOverlay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.source = try c.decode(CatalogSource.self, forKey: .source)
        self.programs = try c.decode([Program].self, forKey: .programs)
        self.courses = try c.decode([Course].self, forKey: .courses)
        self.apCreditRules = try c.decode([TransferCreditRule].self, forKey: .apCreditRules)
        self.prereqRuleOverlay = try c.decodeIfPresent(PrereqRuleOverlay.self, forKey: .prereqRuleOverlay) ?? .empty
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(source, forKey: .source)
        try c.encode(programs, forKey: .programs)
        try c.encode(courses, forKey: .courses)
        try c.encode(apCreditRules, forKey: .apCreditRules)
        try c.encode(prereqRuleOverlay, forKey: .prereqRuleOverlay)
    }

    public var coursesByID: [String: Course] {
        Dictionary(uniqueKeysWithValues: courses.map { ($0.id, $0) })
    }

    public var programsByID: [String: Program] {
        Dictionary(uniqueKeysWithValues: programs.map { ($0.id, $0) })
    }
}

public enum WorkloadPreference: String, Codable, CaseIterable, Hashable, Sendable {
    case light = "Light"
    case standard = "Standard"
    case heavy = "Heavy"

    public var creditRange: ClosedRange<Int> {
        switch self {
        case .light: 12...13
        case .standard: 14...16
        case .heavy: 17...19
        }
    }

    public var displayName: String {
        switch self {
        case .light: "Light (12-13 credits)"
        case .standard: "Standard (14-16 credits)"
        case .heavy: "Heavy (17-19 credits)"
        }
    }
}

public struct SemesterPlan: Codable, Hashable, Identifiable, Sendable {
    public var id: SemesterIdentity
    public var courseIDs: [String]

    public init(id: SemesterIdentity, courseIDs: [String]) {
        self.id = id
        self.courseIDs = courseIDs
    }

    public var term: SemesterTerm { id.term }
}

/// A single un-filled requirement slot in a generated schedule. The user
/// taps a placeholder course chip in the Schedule tab and picks one of the
/// alternates; the planner then swaps the placeholder ID for the chosen
/// course ID in the pathway.
public struct PlaceholderSpec: Codable, Hashable, Sendable {
    public var categoryID: String
    public var categoryName: String
    public var alternates: [String]
    public var credits: Int

    public init(categoryID: String, categoryName: String, alternates: [String], credits: Int) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.alternates = alternates
        self.credits = credits
    }
}

public struct Pathway: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var semesters: [SemesterPlan]
    /// Map from placeholder course ID (`__pl::<categoryID>::<optionIndex>`) to
    /// the spec the UI uses to render the picker menu. Empty for pathways
    /// without any unfilled multi-alternate option slots.
    public var placeholders: [String: PlaceholderSpec]
    /// Map from a resolved placeholder ID to the real course ID the student
    /// picked. Lets the UI surface contributing courses for synthetic
    /// categories (Open Electives) that have no `RequirementCategory`
    /// backing them in the catalog.
    public var resolvedPlaceholders: [String: String]

    public init(
        id: String,
        name: String,
        semesters: [SemesterPlan],
        placeholders: [String: PlaceholderSpec] = [:],
        resolvedPlaceholders: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.semesters = semesters
        self.placeholders = placeholders
        self.resolvedPlaceholders = resolvedPlaceholders
    }

    public var projectedGraduation: SemesterIdentity? {
        semesters.last?.id
    }

    private enum CodingKeys: String, CodingKey { case id, name, semesters, placeholders, resolvedPlaceholders }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.semesters = try c.decode([SemesterPlan].self, forKey: .semesters)
        self.placeholders = try c.decodeIfPresent([String: PlaceholderSpec].self, forKey: .placeholders) ?? [:]
        self.resolvedPlaceholders = try c.decodeIfPresent([String: String].self, forKey: .resolvedPlaceholders) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(semesters, forKey: .semesters)
        try c.encode(placeholders, forKey: .placeholders)
        try c.encode(resolvedPlaceholders, forKey: .resolvedPlaceholders)
    }
}

public enum PathwayPlaceholder {
    public static let prefix = "__pl::"

    public static func id(categoryID: String, optionIndex: Int) -> String {
        "\(prefix)\(categoryID)::\(optionIndex)"
    }

    public static func isPlaceholder(_ courseID: String) -> Bool {
        courseID.hasPrefix(prefix)
    }
}

public enum PlannerError: Error, LocalizedError, Equatable {
    case programNotFound(String)
    case programRequirementsUnavailable(String)
    case concentrationRequired(String)
    case concentrationNotFound(programTitle: String, concentrationID: String)
    case impossibleSchedule(String)

    public var errorDescription: String? {
        switch self {
        case .programNotFound(let id):
            "Program not found: \(id)"
        case .programRequirementsUnavailable(let title):
            "\(title) is in the catalog list, but its detailed requirements have not been verified yet."
        case .concentrationRequired(let title):
            "\(title) requires a concentration before generating a plan."
        case .concentrationNotFound(let title, let concentrationID):
            "\(title) does not include concentration \(concentrationID). Choose a current concentration."
        case .impossibleSchedule(let message):
            message
        }
    }
}

public struct APScore: Codable, Hashable, Sendable {
    public var examName: String
    public var score: Int

    public init(examName: String, score: Int) {
        self.examName = examName
        self.score = score
    }
}

public enum TransferSourceRule: Codable, Hashable, Sendable {
    case apExam(name: String, minimumScore: Int)
    case dualEnrollment(label: String)

    public var displayName: String {
        switch self {
        case .apExam(let name, let minimumScore):
            "\(name), score \(minimumScore)+"
        case .dualEnrollment(let label):
            label
        }
    }
}

public struct TransferCreditRule: Codable, Hashable, Sendable {
    public var source: TransferSourceRule
    public var awardedCourseIDs: [String]
    public var credits: Int
    public var meetsGeneralEducation: Bool
    public var sourceNote: String

    public init(source: TransferSourceRule, awardedCourseIDs: [String], credits: Int, meetsGeneralEducation: Bool, sourceNote: String) {
        self.source = source
        self.awardedCourseIDs = awardedCourseIDs
        self.credits = credits
        self.meetsGeneralEducation = meetsGeneralEducation
        self.sourceNote = sourceNote
    }
}

public struct TransferCredit: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var sourceDescription: String
    public var courseIDs: [String]
    public var credits: Int

    public init(id: UUID = UUID(), sourceDescription: String, courseIDs: [String], credits: Int) {
        self.id = id
        self.sourceDescription = sourceDescription
        self.courseIDs = courseIDs
        self.credits = credits
    }
}

public struct TransferCreditMapper: Sendable {
    public var catalog: Catalog

    public init(catalog: Catalog) {
        self.catalog = catalog
    }

    /// Legacy entry point retained for tests and callers that do not have a
    /// declared major yet. Picks the highest qualifying tier per exam; among
    /// tiers, prefers the rule that awards the most credits.
    public func credits(forAPScores scores: [APScore]) -> [TransferCredit] {
        credits(forAPScores: scores, program: nil, completedCourseIDs: [])
    }

    /// Maps a list of AP scores to concrete `TransferCredit` awards.
    ///
    /// JMU's AP chart frequently fans an exam name out into multiple variants:
    /// score tiers (3 / 4 / 5), major vs non-major tracks, and `or` alternatives
    /// inside a single cell. The student should never have to pick the variant
    /// manually. This mapper picks the variant that gets the student closest to
    /// graduation:
    ///
    /// 1. Filter candidates to rules whose canonical exam name matches and
    ///    whose `minimumScore` the student met.
    /// 2. Keep only the highest qualifying `minimumScore` (no tier stacking).
    /// 3. Among the surviving tier's variants, pick the one that satisfies the
    ///    most of the active program's required courses (using the supplied
    ///    `program` and `completedCourseIDs` so we don't double-credit a
    ///    course the student has already accounted for elsewhere).
    /// 4. Tiebreaker 1: most `credits`. Tiebreaker 2: meets General Education.
    public func credits(
        forAPScores scores: [APScore],
        program: Program?,
        completedCourseIDs: Set<String>
    ) -> [TransferCredit] {
        // Per-score candidate sets (top tier only).
        let perScore: [(score: APScore, candidates: [TransferCreditRule])] = scores.map { score in
            let qualifying = catalog.apCreditRules.filter { rule in
                guard case .apExam(let name, let minScore) = rule.source else { return false }
                return name.caseInsensitiveCompare(score.examName) == .orderedSame
                    && score.score >= minScore
            }
            guard !qualifying.isEmpty else { return (score, []) }
            let highestTier = qualifying.compactMap { rule -> Int? in
                if case .apExam(_, let minScore) = rule.source { return minScore }
                return nil
            }.max() ?? 0
            let topTier = qualifying.filter { rule in
                if case .apExam(_, let minScore) = rule.source { return minScore == highestTier }
                return false
            }
            return (score, topTier)
        }

        // Pre-mark options already covered by non-AP transfer credits (dual
        // enrollment). Option-key = (categoryID, optionIndex). Treated as
        // claimed so AP variants don't pile onto the same option.
        var claimedOptions: Set<OptionKey> = []
        if let program {
            for category in program.requirements {
                for (idx, option) in category.courseOptions.enumerated() {
                    if option.contains(where: completedCourseIDs.contains) {
                        claimedOptions.insert(OptionKey(categoryID: category.id, index: idx))
                    }
                }
            }
        }

        // Process scores in order of fewest variant choices first. Exams with a
        // single forced placement (e.g., AP Lit -> GNED 123) get their option
        // locked in before flexible exams that could go elsewhere. Stable
        // alphabetical tiebreaker for determinism.
        let processingOrder = perScore.enumerated().sorted { lhs, rhs in
            if lhs.element.candidates.count != rhs.element.candidates.count {
                return lhs.element.candidates.count < rhs.element.candidates.count
            }
            return lhs.element.score.examName < rhs.element.score.examName
        }

        var picksByOriginalIndex: [Int: TransferCreditRule] = [:]
        for (originalIndex, entry) in processingOrder {
            guard !entry.candidates.isEmpty else { continue }
            let scored = entry.candidates.map { rule -> (rule: TransferCreditRule, key: (Int, Int, Int, Int)) in
                let rescued = creditsRescued(by: rule, program: program, claimed: claimedOptions)
                let optionsHit = optionsSatisfied(by: rule, program: program, claimed: claimedOptions)
                let genEd = rule.meetsGeneralEducation ? 1 : 0
                return (rule, (rescued, optionsHit, rule.credits, genEd))
            }
            guard let best = scored.max(by: { $0.key < $1.key }) else { continue }
            picksByOriginalIndex[originalIndex] = best.rule

            // Reserve every option this rule satisfies so subsequent scores
            // route their credit somewhere else.
            for key in optionKeys(satisfiedBy: best.rule, program: program, claimed: claimedOptions) {
                claimedOptions.insert(key)
            }
        }

        // Emit results in the student's original score order.
        return scores.enumerated().compactMap { index, score in
            guard let rule = picksByOriginalIndex[index] else { return nil }
            guard case .apExam(let name, _) = rule.source else { return nil }
            return TransferCredit(
                sourceDescription: "AP \(name) score \(score.score)",
                courseIDs: rule.awardedCourseIDs,
                credits: rule.credits
            )
        }
    }

    private struct OptionKey: Hashable {
        var categoryID: String
        var index: Int
    }

    /// JMU awards "GNED ###" placeholder courses for several AP exams to denote
    /// "credit toward a specific Gen Ed cluster" without naming a specific
    /// catalog course. Map each GNED ID to the cluster tag that lives inside
    /// the Gen Ed category's display name (e.g., "General Education —
    /// Literature [C2L]"). When scoring coverage we treat the GNED award as
    /// satisfying any option in a category whose name contains the tag.
    /// Public lookup used by `ScheduleGenerator` so it can recognize the same
    /// GNED → cluster aliases the mapper uses when crediting options.
    public static func genEdCreditClusterTag(for courseID: String) -> String? {
        genEdCreditClusterTagTable[courseID]
    }

    public static func genEdCreditSatisfies(category: RequirementCategory, completedCourseIDs: Set<String>) -> Bool {
        let completedClusterTags = Set(completedCourseIDs.compactMap { genEdCreditClusterTag(for: $0) })
        return completedClusterTags.contains { category.name.contains($0) }
    }

    private static let genEdCreditClusterTagTable: [String: String] = [
        // Cluster Two
        "GNED123": "[C2L]",   // Literature
        "GNED124": "[C2L]",
        "GNED129": "[C2L]",
        "GNED130": "[C2HQC]", // Human Questions and Contexts
        "GNED131": "[C2HQC]",
        "GNED132": "[C2VPA]", // Visual and Performing Arts
        // Cluster Four
        "GNED140": "[C4AE]",  // American Experience
        "GNED141": "[C4AE]",
        "GNED142": "[C4GE]",  // Global Experience
        "GNED143": "[C4GE]",
        "GNED144": "[C4GE]",
        // Cluster Five
        "GNED150": "[C5SD]",  // Sociocultural Domain
        "GNED151": "[C5SD]",
        "GNED155": "[C5W]"    // Wellness Domain
    ]

    /// Returns the set of option-keys that this rule's awards would satisfy in
    /// the given program, excluding options that are already in `claimed`.
    /// Honors both exact-course-ID matches and GNED cluster aliases.
    private func optionKeys(
        satisfiedBy rule: TransferCreditRule,
        program: Program?,
        claimed: Set<OptionKey>
    ) -> [OptionKey] {
        guard let program else { return [] }
        let awarded = Set(rule.awardedCourseIDs)
        let awardedClusterTags = Set(rule.awardedCourseIDs.compactMap { Self.genEdCreditClusterTag(for: $0) })
        var keys: [OptionKey] = []
        for category in program.requirements {
            let categoryClusterMatch = awardedClusterTags.contains(where: category.name.contains)
            for (idx, option) in category.courseOptions.enumerated() {
                let key = OptionKey(categoryID: category.id, index: idx)
                if claimed.contains(key) { continue }
                if option.contains(where: awarded.contains) || categoryClusterMatch {
                    keys.append(key)
                }
            }
        }
        return keys
    }

    /// Count of distinct (unclaimed) requirement options this rule would
    /// satisfy. Each option counts at most once.
    private func optionsSatisfied(
        by rule: TransferCreditRule,
        program: Program?,
        claimed: Set<OptionKey>
    ) -> Int {
        optionKeys(satisfiedBy: rule, program: program, claimed: claimed).count
    }

    /// Catalog credits "rescued" by routing this rule's award through the
    /// given program. Each satisfied option contributes its share of the
    /// category's `requiredCredits` (split evenly across the category's
    /// options). Options already in `claimed` are skipped so two different AP
    /// scores cannot stack-claim the same option.
    private func creditsRescued(
        by rule: TransferCreditRule,
        program: Program?,
        claimed: Set<OptionKey>
    ) -> Int {
        guard let program else { return 0 }
        let awarded = Set(rule.awardedCourseIDs)
        let awardedClusterTags = Set(rule.awardedCourseIDs.compactMap { Self.genEdCreditClusterTag(for: $0) })
        var rescued = 0
        for category in program.requirements {
            let optionCount = max(category.courseOptions.count, 1)
            let perOption = max(category.requiredCredits / optionCount, 1)
            let categoryClusterMatch = awardedClusterTags.contains(where: category.name.contains)
            for (idx, option) in category.courseOptions.enumerated() {
                let key = OptionKey(categoryID: category.id, index: idx)
                if claimed.contains(key) { continue }
                if option.contains(where: awarded.contains) || categoryClusterMatch {
                    rescued += perOption
                }
            }
        }
        return rescued
    }
}

public struct ScheduleGenerator: Sendable {
    public var catalog: Catalog
    public var strictPrereqs: Bool

    public init(catalog: Catalog, strictPrereqs: Bool = false) {
        self.catalog = catalog
        self.strictPrereqs = strictPrereqs
    }

    private struct ScheduleCandidate: Sendable {
        var courseID: String
        var credits: Int
        var variantOrder: Int
    }

    private enum GenEdTimingWindow: Sendable {
        case firstYear
        case sophomoreYear
    }

    public func generatePathways(
        for programID: String,
        concentrationID: String? = nil,
        workload: WorkloadPreference,
        transferCredits: [TransferCredit],
        starting start: SemesterIdentity = SemesterIdentity(year: Calendar.current.component(.year, from: Date()), term: .fall),
        additionalPrograms: [Program] = []
    ) throws -> [Pathway] {
        let program = try programForScheduling(programID, concentrationID: concentrationID)
        let completed = Set(transferCredits.flatMap(\.courseIDs))
        var placeholders: [String: PlaceholderSpec] = [:]
        // Build one course list per program so the merge step below can
        // interleave them. Appending all extras after the primary made the
        // scheduler greedy-pack primary courses in early semesters and shove
        // second-major / minor courses into the final terms. The merge step
        // gives every program a proportional share of each semester instead.
        var perProgramLists: [[String]] = []
        var primaryList = requiredCourseIDs(for: program, completed: completed, placeholders: &placeholders)
        // JMU degrees require 120 CRH total. If the primary major's declared
        // requirements fall short, top up with Open Elective placeholders so
        // the schedule reaches 120 on the major alone (before AP/transfer
        // credits whittle it down). Secondary majors / minors are NOT topped
        // up — those only contribute their own program-specific requirements.
        primaryList.append(contentsOf: openElectivePlaceholders(for: program, placeholders: &placeholders))
        perProgramLists.append(primaryList)
        for extra in additionalPrograms {
            perProgramLists.append(requiredCourseIDs(for: extra, completed: completed, placeholders: &placeholders))
        }
        let required = Self.interleaveByProportion(perProgramLists)
        guard !required.isEmpty else {
            return (1...3).map { index in
                Pathway(id: "path-\(index)", name: pathwayName(index), semesters: [])
            }
        }

        let genEdCourseIDs: Set<String> = Set(
            program.requirements
                .filter { Self.isGenEdCategory(id: $0.id, name: $0.name) }
                .flatMap { $0.courseOptions.flatMap { $0 } }
        )
        func isGenEd(_ courseID: String) -> Bool {
            if PathwayPlaceholder.isPlaceholder(courseID) {
                guard let spec = placeholders[courseID] else { return false }
                return Self.isGenEdCategory(id: spec.categoryID, name: spec.categoryName)
            }
            return genEdCourseIDs.contains(courseID)
        }

        // Stable partition: non-Gen-Ed first for Major-First, Gen-Ed first for
        // Gen-Ed-First. Preserves the catalog order inside each bucket so the
        // downstream scheduler's prereq-aware placement still has a coherent
        // starting list. The scheduler itself enforces workload caps, prereqs,
        // coreqs, and semester availability, so these orderings only bias which
        // courses get earliest legal slots.
        let majorFirst = required.enumerated().sorted { lhs, rhs in
            let lhsGen = isGenEd(lhs.element)
            let rhsGen = isGenEd(rhs.element)
            if lhsGen != rhsGen { return !lhsGen }
            return lhs.offset < rhs.offset
        }.map(\.element)
        let genEdFirst = required.enumerated().sorted { lhs, rhs in
            let lhsGen = isGenEd(lhs.element)
            let rhsGen = isGenEd(rhs.element)
            if lhsGen != rhsGen { return lhsGen }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var pathways: [Pathway] = []
        let variants = [required, majorFirst, genEdFirst]

        for (index, variant) in variants.enumerated() {
            let semesters = try buildSemesters(
                courseIDs: variant,
                completedAtStart: completed,
                workload: workload,
                starting: start,
                placeholders: placeholders,
                activeProgramTitle: program.title
            )
            pathways.append(Pathway(
                id: "path-\(index + 1)",
                name: pathwayName(index + 1),
                semesters: semesters,
                placeholders: placeholders
            ))
        }

        return pathways
    }

    /// Helper used by the variant sorter so placeholder IDs surface a sensible
    /// credit weight without polluting the catalog's coursesByID dict.
    private func credits(for courseID: String, placeholders: [String: PlaceholderSpec]) -> Int {
        if let spec = placeholders[courseID] { return spec.credits }
        return catalog.coursesByID[courseID]?.credits ?? 0
    }

    private func programForScheduling(_ programID: String, concentrationID: String?) throws -> Program {
        guard let rawProgram = catalog.programsByID[programID] else {
            throw PlannerError.programNotFound(programID)
        }
        let program = try rawProgram.effectiveProgram(concentrationID: concentrationID)
        // Only block when there is literally nothing schedulable. If any requirement
        // exposes course options, build a schedule from what we have — the UI surfaces
        // partial/unverified statuses so the student can see the gaps.
        let hasAnyCourse = program.requirements.contains { !$0.courseOptions.isEmpty }
        guard hasAnyCourse else {
            throw PlannerError.programRequirementsUnavailable(program.title)
        }
        return program
    }

    /// Returns the list of courses the student still needs to schedule.
    ///
    /// Each `courseOptions` entry is an OR group: completing ANY of its
    /// alternates satisfies the option. If a student has transfer credit (or
    /// any other "completed" mark) on `BIO 103` and `BIO 103` is one of twelve
    /// alternates in the Natural Systems option, that option is done; we do
    /// not also schedule `ANTH 196` just because it's first in the list. When
    /// the option is not yet satisfied, we still default to the first
    /// alternate, which lets the catalog drive a consistent default pick.
    /// The returned list is deduplicated: if the same course is the default
    /// pick for more than one option (e.g., MATH 220 appearing as both the
    /// QR cluster default and a major's stats requirement default), it is
    /// scheduled once and counts toward both options.
    ///
    /// `completed` may also contain JMU GNED placeholder course IDs (e.g.,
    /// `GNED123` awarded by AP Lit). Those satisfy any option in a Gen Ed
    /// category whose name carries the matching cluster tag (`[C2L]`), even
    /// though the GNED ID is not in the alternate list of any specific option.
    private func requiredCourseIDs(
        for program: Program,
        completed: Set<String>,
        placeholders: inout [String: PlaceholderSpec]
    ) -> [String] {
        let completedClusterTags = Set(completed.compactMap { TransferCreditMapper.genEdCreditClusterTag(for: $0) })
        var seen: Set<String> = []
        var result: [String] = []
        for category in program.requirements {
            let lowerName = category.name.lowercased()
            // Categories whose heading carries "required" are mandatory in
            // full — every option must reach the schedule. Bypass the Gen Ed
            // cluster shortcut and the selective-elective placeholder path
            // so nothing trims the option list before iteration.
            let categoryIsRequired = lowerName.contains("required")

            let categorySatisfiedByCluster = completedClusterTags.contains(where: category.name.contains)
            if !categoryIsRequired && categorySatisfiedByCluster { continue }

            let optionCount = max(category.courseOptions.count, 1)
            let fallbackOptionCredits = max(category.requiredCredits / optionCount, 1)
            if !categoryIsRequired,
               appendSelectableElectivePlaceholders(
                for: category,
                completed: completed,
                seen: &seen,
                result: &result,
                placeholders: &placeholders,
                fallbackOptionCredits: fallbackOptionCredits
            ) {
                continue
            }

            var plannedCredits = 0
            // Only honor `requiredCredits` as a hard cap on iteration when the
            // category's name signals selective semantics ("Choose N",
            // "Elective"). Required blocks ignore the cap so every option
            // lands in the schedule.
            let categoryIsSelective = !categoryIsRequired && (
                lowerName.contains("choose")
                || lowerName.contains("elective")
                || lowerName.contains("select")
            )
            let hasCreditLimit = categoryIsSelective && category.requiredCredits > 0
            for (idx, option) in category.courseOptions.enumerated() {
                if hasCreditLimit && plannedCredits >= category.requiredCredits { break }

                let optionCredits = credits(for: option, fallback: fallbackOptionCredits)
                if option.contains(where: completed.contains) || option.contains(where: seen.contains) {
                    plannedCredits += optionCredits
                    continue
                }

                if option.count > 1 {
                    // Multi-alternate option → schedule a placeholder. UI lets
                    // the student pick the actual course in the Schedule tab.
                    let id = PathwayPlaceholder.id(categoryID: category.id, optionIndex: idx)
                    if seen.insert(id).inserted {
                        result.append(id)
                        placeholders[id] = PlaceholderSpec(
                            categoryID: category.id,
                            categoryName: category.name,
                            alternates: option,
                            credits: optionCredits
                        )
                    }
                } else {
                    guard let pick = option.first else { continue }
                    if seen.insert(pick).inserted {
                        result.append(pick)
                    }
                }
                plannedCredits += optionCredits
            }
        }
        return result
    }

    private func appendSelectableElectivePlaceholders(
        for category: RequirementCategory,
        completed: Set<String>,
        seen: inout Set<String>,
        result: inout [String],
        placeholders: inout [String: PlaceholderSpec],
        fallbackOptionCredits: Int
    ) -> Bool {
        guard category.name.lowercased().contains("elective"),
              category.requiredCredits > 0,
              category.courseOptions.count > 1
        else {
            return false
        }

        let optionCredits = category.courseOptions.map { credits(for: $0, fallback: fallbackOptionCredits) }
        let totalEligibleCredits = optionCredits.reduce(0, +)
        guard totalEligibleCredits > category.requiredCredits else { return false }

        let alternates = uniqueCourseIDs(category.courseOptions.flatMap { $0 })
            .filter { !completed.contains($0) }
        guard !alternates.isEmpty else { return true }

        let slotCredits = max(optionCredits.max() ?? fallbackOptionCredits, 1)
        let slotCount = max(Int(ceil(Double(category.requiredCredits) / Double(slotCredits))), 1)
        for slot in 0..<slotCount {
            let id = PathwayPlaceholder.id(categoryID: category.id, optionIndex: slot)
            guard seen.insert(id).inserted else { continue }
            result.append(id)
            placeholders[id] = PlaceholderSpec(
                categoryID: category.id,
                categoryName: category.name,
                alternates: alternates,
                credits: min(slotCredits, max(category.requiredCredits - (slot * slotCredits), 1))
            )
        }
        return true
    }

    private func uniqueCourseIDs(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private func credits(for option: [String], fallback: Int) -> Int {
        let knownCredits = option.compactMap { catalog.coursesByID[$0]?.credits }
        return knownCredits.max() ?? fallback
    }

    private func buildSemesters(
        courseIDs: [String],
        completedAtStart: Set<String>,
        workload: WorkloadPreference,
        starting start: SemesterIdentity,
        placeholders: [String: PlaceholderSpec] = [:],
        activeProgramTitle: String? = nil
    ) throws -> [SemesterPlan] {
        var remaining = courseIDs
        var completed = completedAtStart
        var semester = start
        var semesterOffset = 0
        var result: [SemesterPlan] = []
        var emptySemesterCount = 0
        let resolver = PrereqRuleResolver(catalog: catalog)

        while !remaining.isEmpty {
            var selected: [String] = []
            var credits = 0
            let maxCredits = workload.creditRange.upperBound
            let target = targetLevel(for: semesterOffset)

            let ready = remaining.enumerated().compactMap { order, courseID -> ScheduleCandidate? in
                let courseCredits: Int
                let courseAvailability: Set<SemesterTerm>?
                let prerequisiteExpr: PrereqExpr
                if let spec = placeholders[courseID] {
                    courseCredits = spec.credits
                    courseAvailability = nil
                    prerequisiteExpr = .empty
                } else if let course = catalog.coursesByID[courseID] {
                    courseCredits = course.credits
                    courseAvailability = course.availability
                    prerequisiteExpr = resolver.rule(for: course, activeProgramTitle: activeProgramTitle).prerequisiteExpr
                } else {
                    return nil
                }
                guard case .satisfied = PrereqEvaluator(
                    completedBefore: completed,
                    scheduledThisTerm: []
                ).evaluate(prerequisiteExpr, mode: .prereq) else { return nil }
                if let availability = courseAvailability, !availability.contains(semester.term) { return nil }
                return ScheduleCandidate(courseID: courseID, credits: courseCredits, variantOrder: order)
            }
            .sorted { lhs, rhs in
                compare(lhs, rhs, targetLevel: target, semesterOffset: semesterOffset, placeholders: placeholders)
            }

            for candidate in ready {
                let courseCredits = candidate.credits
                guard credits + courseCredits <= maxCredits else { continue }
                selected.append(candidate.courseID)
                credits += courseCredits
            }

            if selected.isEmpty {
                emptySemesterCount += 1
                guard emptySemesterCount <= 8 else {
                    if !strictPrereqs {
                        let fallbackStart = result.last?.id.next ?? semester
                        result.append(contentsOf: buildBestEffortSemesters(
                            courseIDs: remaining,
                            workload: workload,
                            starting: fallbackStart,
                            placeholders: placeholders,
                            baseSemesterOffset: result.count
                        ))
                        return result
                    }
                    throw PlannerError.impossibleSchedule("Could not place the remaining courses while respecting prerequisites and semester availability.")
                }
                semester = semester.next
                semesterOffset += 1
                continue
            }

            result.append(SemesterPlan(id: semester, courseIDs: selected))
            remaining.removeAll { selected.contains($0) }
            completed.formUnion(selected)
            semester = semester.next
            semesterOffset += 1
        }

        return result
    }

    private func buildBestEffortSemesters(
        courseIDs: [String],
        workload: WorkloadPreference,
        starting start: SemesterIdentity,
        placeholders: [String: PlaceholderSpec],
        baseSemesterOffset: Int
    ) -> [SemesterPlan] {
        var remaining = courseIDs
        var semester = start
        var semesterOffset = baseSemesterOffset
        var result: [SemesterPlan] = []
        let maxCredits = workload.creditRange.upperBound

        while !remaining.isEmpty {
            var selected: [String] = []
            var selectedCredits = 0
            let target = targetLevel(for: semesterOffset)
            let candidates = remaining.enumerated()
                .map { order, courseID in
                    ScheduleCandidate(
                        courseID: courseID,
                        credits: credits(for: courseID, placeholders: placeholders),
                        variantOrder: order
                    )
                }
                .sorted { lhs, rhs in
                    compare(lhs, rhs, targetLevel: target, semesterOffset: semesterOffset, placeholders: placeholders)
                }

            for candidate in candidates {
                if candidate.credits > maxCredits, selected.isEmpty {
                    selected.append(candidate.courseID)
                    break
                }
                guard selectedCredits + candidate.credits <= maxCredits else { continue }
                selected.append(candidate.courseID)
                selectedCredits += candidate.credits
            }

            if selected.isEmpty, let first = candidates.first {
                selected.append(first.courseID)
            }

            result.append(SemesterPlan(id: semester, courseIDs: selected))
            let selectedSet = Set(selected)
            remaining.removeAll { selectedSet.contains($0) }
            semester = semester.next
            semesterOffset += 1
        }

        return result
    }

    private func compare(
        _ lhs: ScheduleCandidate,
        _ rhs: ScheduleCandidate,
        targetLevel: Int,
        semesterOffset: Int,
        placeholders: [String: PlaceholderSpec]
    ) -> Bool {
        let lhsTimingPriority = genEdTimingPriority(for: lhs.courseID, semesterOffset: semesterOffset, placeholders: placeholders)
        let rhsTimingPriority = genEdTimingPriority(for: rhs.courseID, semesterOffset: semesterOffset, placeholders: placeholders)
        if lhsTimingPriority != rhsTimingPriority {
            return lhsTimingPriority < rhsTimingPriority
        }

        let lhsLevel = courseLevel(for: lhs.courseID, placeholders: placeholders)
        let rhsLevel = courseLevel(for: rhs.courseID, placeholders: placeholders)
        let lhsDistance = abs(lhsLevel - targetLevel)
        let rhsDistance = abs(rhsLevel - targetLevel)
        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }
        if lhsLevel != rhsLevel {
            return lhsLevel < rhsLevel
        }
        if lhs.variantOrder != rhs.variantOrder {
            return lhs.variantOrder < rhs.variantOrder
        }
        return lhs.courseID < rhs.courseID
    }

    private func genEdTimingPriority(
        for courseID: String,
        semesterOffset: Int,
        placeholders: [String: PlaceholderSpec]
    ) -> Int {
        guard let timingWindow = genEdTimingWindow(for: courseID, placeholders: placeholders) else {
            return 1
        }

        switch timingWindow {
        case .firstYear:
            return 0
        case .sophomoreYear:
            return semesterOffset >= 2 ? 0 : 1
        }
    }

    private func genEdTimingWindow(for courseID: String, placeholders: [String: PlaceholderSpec]) -> GenEdTimingWindow? {
        guard let categoryName = placeholders[courseID]?.categoryName else { return nil }
        let normalized = categoryName.lowercased()

        if normalized.contains("[c1") ||
            normalized.contains("madison foundations") ||
            normalized.contains("critical thinking") ||
            normalized.contains("human communication") ||
            normalized.contains("writing") {
            return .firstYear
        }

        if normalized.contains("[c3") ||
            normalized.contains("[c5") ||
            normalized.contains("sociocultural") ||
            normalized.contains("wellness") ||
            normalized.contains("quantitative reasoning") ||
            normalized.contains("physical principles") ||
            normalized.contains("natural systems") ||
            normalized.contains("lab experience") ||
            normalized.contains("natural world") {
            return .sophomoreYear
        }

        return nil
    }

    private func courseLevel(for courseID: String, placeholders: [String: PlaceholderSpec]) -> Int {
        if let spec = placeholders[courseID] {
            // Open electives accept any course; defaulting to the mid level
            // keeps them neutral in the level-ramp sorter without scanning
            // the entire catalog every comparison.
            if spec.categoryID == Self.openElectiveCategoryID { return 200 }
            return medianAlternateLevel(for: spec.alternates)
        }
        guard let course = catalog.coursesByID[courseID],
              let level = Self.courseLevel(fromCode: course.code)
        else { return 200 }
        return level
    }

    private func medianAlternateLevel(for alternates: [String]) -> Int {
        let levels = alternates.compactMap { id -> Int? in
            guard let course = catalog.coursesByID[id] else { return nil }
            return Self.courseLevel(fromCode: course.code)
        }
        .sorted()

        guard !levels.isEmpty else { return 200 }
        let middle = levels.count / 2
        if levels.count % 2 == 1 {
            return levels[middle]
        }
        let median = Double(levels[middle - 1] + levels[middle]) / 2.0
        return Self.roundToNearestHundred(median)
    }

    private func targetLevel(for semesterOffset: Int) -> Int {
        let clampedOffset = min(max(semesterOffset, 0), 7)
        let raw = 100.0 + (Double(clampedOffset) / 7.0) * 300.0
        return Self.roundToNearestHundred(raw)
    }

    private static func courseLevel(fromCode code: String) -> Int? {
        guard let range = code.range(of: #"\d{3}"#, options: .regularExpression),
              let number = Int(code[range])
        else { return nil }
        let bucket = (number / 100) * 100
        return min(max(bucket, 100), 400)
    }

    private static func roundToNearestHundred(_ value: Double) -> Int {
        Int((value / 100.0).rounded()) * 100
    }

    private func pathwayName(_ index: Int) -> String {
        switch index {
        case 1: "Balanced Path"
        case 2: "Major-First Path"
        default: "Gen Ed-First Path"
        }
    }

    private static func isGenEdCategory(id: String, name: String) -> Bool {
        id.contains("gened") || name.lowercased().contains("general education")
    }

    /// Synthetic category id for Open Elective placeholders that pad the
    /// primary major's schedule out to the JMU degree credit minimum.
    public static let openElectiveCategoryID = "open-elective"

    /// Gap between the primary major's declared requirement credits and
    /// JMU's 120 CRH degree minimum. Only fires for `.major` programs whose
    /// declared credits clear a substance threshold — the catalog parser's
    /// `totalCredits` often reports a section subtotal ("Major Requirements
    /// Total: 49 CRH") rather than the full degree total, so we hardcode
    /// 120 for real majors and ignore `program.totalCredits` here.
    ///
    /// Umbrella section headers (categories with no parseable course
    /// options — e.g., "Additional Requirements: 22-24 CRH") are excluded
    /// from the declared-credit tally because their sub-rows already
    /// account for the same credits; counting both would zero the gap.
    public static func openElectiveGap(for program: Program) -> Int {
        guard program.kind == .major else { return 0 }
        let declared = program.requirements
            .filter { !$0.courseOptions.isEmpty }
            .reduce(0) { $0 + $1.requiredCredits }
        // Threshold gate keeps thin test fixtures (declared < 60) from
        // generating dozens of placeholders. Real JMU majors easily clear
        // 60 once Gen Ed clusters and concentration requirements are
        // merged into the effective program.
        guard declared >= 60 else { return 0 }
        return max(0, 120 - declared)
    }

    /// Build Open Elective placeholders to cover the gap between the primary
    /// major's declared requirement credits and JMU's degree credit minimum.
    /// Each slot defaults to 3 credits with the last slot trimmed to whatever
    /// remains. `alternates` lists every catalog course id so the schedule
    /// board can offer a course picker on tap. Returns an empty array when
    /// the program already declares ≥ target CRH of requirements.
    private func openElectivePlaceholders(
        for program: Program,
        placeholders: inout [String: PlaceholderSpec]
    ) -> [String] {
        let gap = Self.openElectiveGap(for: program)
        guard gap > 0 else { return [] }
        let slotCredits = 3
        let slotCount = Int(ceil(Double(gap) / Double(slotCredits)))
        // Leave `alternates` empty. Storing every catalog course id per slot
        // would balloon the persisted pathway JSON and make the sorter call
        // `medianAlternateLevel` over 1000+ ids every comparison, freezing
        // pathway generation. The UI special-cases open electives to render
        // the full catalog picker on demand.
        var ids: [String] = []
        for slot in 0..<slotCount {
            let id = PathwayPlaceholder.id(categoryID: Self.openElectiveCategoryID, optionIndex: slot)
            let remaining = gap - slot * slotCredits
            let credits = min(slotCredits, max(remaining, 1))
            placeholders[id] = PlaceholderSpec(
                categoryID: Self.openElectiveCategoryID,
                categoryName: "Open Elective",
                alternates: [],
                credits: credits
            )
            ids.append(id)
        }
        return ids
    }

    /// Merge per-program ordered course lists into one list that spreads each
    /// program's courses proportionally across the result. Each entry gets a
    /// normalized position `(idx + 0.5) / list.count`; the merged list is
    /// sorted by that fraction with a stable tiebreaker on the source program
    /// index. A primary major with 40 courses and a minor with 10 will
    /// interleave roughly 4-primary-then-1-minor instead of "all primary then
    /// all minor". Duplicates (same course id reached by multiple programs)
    /// are kept at their first occurrence.
    static func interleaveByProportion(_ lists: [[String]]) -> [String] {
        struct Slot { let id: String; let fraction: Double; let listIndex: Int }
        var slots: [Slot] = []
        for (listIndex, list) in lists.enumerated() {
            let denominator = max(Double(list.count), 1)
            for (idx, id) in list.enumerated() {
                slots.append(Slot(
                    id: id,
                    fraction: (Double(idx) + 0.5) / denominator,
                    listIndex: listIndex
                ))
            }
        }
        slots.sort { lhs, rhs in
            if lhs.fraction != rhs.fraction { return lhs.fraction < rhs.fraction }
            return lhs.listIndex < rhs.listIndex
        }
        var seen = Set<String>()
        var result: [String] = []
        for slot in slots where seen.insert(slot.id).inserted {
            result.append(slot.id)
        }
        return result
    }
}

public enum ConflictKind: String, Codable, Hashable, Sendable {
    case missingPrerequisite
    case missingCorequisite
    case unavailableSemester
    case unknownAvailability

    public var displayName: String {
        switch self {
        case .missingPrerequisite: "Prerequisite warning"
        case .missingCorequisite: "Corequisite warning"
        case .unavailableSemester: "Semester availability warning"
        case .unknownAvailability: "Availability unknown"
        }
    }
}

public struct ConflictOverride: Codable, Hashable, Sendable {
    public var courseID: String
    public var semester: SemesterIdentity
    public var kind: ConflictKind

    public init(courseID: String, semester: SemesterIdentity, kind: ConflictKind) {
        self.courseID = courseID
        self.semester = semester
        self.kind = kind
    }
}

public struct ConflictWarning: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var courseID: String
    public var semester: SemesterIdentity
    public var kind: ConflictKind
    public var message: String
    public var isOverridden: Bool

    public init(courseID: String, semester: SemesterIdentity, kind: ConflictKind, message: String, isOverridden: Bool) {
        self.id = "\(courseID)-\(semester.year)-\(semester.term.rawValue)-\(kind.rawValue)"
        self.courseID = courseID
        self.semester = semester
        self.kind = kind
        self.message = message
        self.isOverridden = isOverridden
    }
}

/// Evaluates whether a `PrereqExpr` is satisfied given the set of courses
/// the student has completed before this term (`completedBefore`) and the
/// set scheduled in the same term (`scheduledThisTerm`). Prereq mode only
/// honors `completedBefore`; coreq mode honors their union.
public struct PrereqEvaluator: Sendable {
    public enum Mode: Sendable { case prereq, coreq }
    public enum Outcome: Sendable, Equatable {
        case satisfied
        case unmet(missing: PrereqExpr, original: PrereqExpr)
    }

    public let completedBefore: Set<String>
    public let scheduledThisTerm: Set<String>

    public init(completedBefore: Set<String>, scheduledThisTerm: Set<String>) {
        self.completedBefore = completedBefore
        self.scheduledThisTerm = scheduledThisTerm
    }

    public func evaluate(_ expr: PrereqExpr, mode: Mode) -> Outcome {
        let pool = (mode == .prereq) ? completedBefore : completedBefore.union(scheduledThisTerm)
        let trimmed = prune(expr, pool: pool)
        if case .empty = trimmed { return .satisfied }
        return .unmet(missing: trimmed, original: expr)
    }

    /// Walk the tree returning the still-missing sub-expression. Empty
    /// means fully satisfied.
    private func prune(_ expr: PrereqExpr, pool: Set<String>) -> PrereqExpr {
        switch expr {
        case .empty:
            return .empty
        case .course(let id):
            return pool.contains(id) ? .empty : .course(id)
        case .unknown:
            return expr  // unknowns are never satisfied
        case .all(let xs):
            let trimmed = xs.compactMap { child -> PrereqExpr? in
                let pruned = prune(child, pool: pool)
                if case .empty = pruned { return nil }
                return pruned
            }
            if trimmed.isEmpty { return .empty }
            if trimmed.count == 1 { return trimmed[0] }
            return .all(trimmed)
        case .any(let xs):
            // If any branch is empty post-prune, the whole group is satisfied.
            for branch in xs {
                if case .empty = prune(branch, pool: pool) { return .empty }
            }
            // None satisfied: keep all branches so the warning lists every option.
            let trimmed = xs.map { prune($0, pool: pool) }
            if trimmed.count == 1 { return trimmed[0] }
            return .any(trimmed)
        }
    }
}

public struct ConflictDetector: Sendable {
    public var catalog: Catalog

    public init(catalog: Catalog) {
        self.catalog = catalog
    }

    public func warnings(
        for pathway: Pathway,
        overrides: [ConflictOverride],
        activeProgramTitle: String? = nil
    ) -> [ConflictWarning] {
        let coursesByID = catalog.coursesByID
        var completedBefore = Set<String>()
        var warnings: [ConflictWarning] = []
        let resolver = PrereqRuleResolver(catalog: catalog)

        for semester in pathway.semesters.sorted(by: { $0.id < $1.id }) {
            let realInThisTerm = Set(semester.courseIDs.filter { !PathwayPlaceholder.isPlaceholder($0) })
            let evaluator = PrereqEvaluator(completedBefore: completedBefore, scheduledThisTerm: realInThisTerm)

            for courseID in semester.courseIDs where !PathwayPlaceholder.isPlaceholder(courseID) {
                guard let course = coursesByID[courseID] else { continue }

                if course.availability == nil {
                    warnings.append(warning(
                        courseID: courseID,
                        semester: semester.id,
                        kind: .unknownAvailability,
                        message: "\(course.code) does not have verified semester availability in the local catalog cache.",
                        overrides: overrides
                    ))
                } else if let availability = course.availability, !availability.contains(semester.term) {
                    warnings.append(warning(
                        courseID: courseID,
                        semester: semester.id,
                        kind: .unavailableSemester,
                        message: "\(course.code) is not marked as typically offered in \(semester.term.rawValue).",
                        overrides: overrides
                    ))
                }

                let resolvedRule = resolver.rule(for: course, activeProgramTitle: activeProgramTitle)
                if case .unmet(let missing, let original) = evaluator.evaluate(resolvedRule.prerequisiteExpr, mode: .prereq) {
                    warnings.append(warning(
                        courseID: courseID,
                        semester: semester.id,
                        kind: .missingPrerequisite,
                        message: Self.prereqMessage(
                            original: original,
                            missing: missing,
                            hasUnknown: resolvedRule.hasUnknownTokens,
                            confidence: resolvedRule.confidence,
                            notes: resolvedRule.notes,
                            coursesByID: coursesByID,
                            satisfied: completedBefore
                        ),
                        overrides: overrides
                    ))
                }

                if case .unmet(let missing, _) = evaluator.evaluate(resolvedRule.corequisiteExpr, mode: .coreq) {
                    let rendered = missing.displayString(coursesByID: coursesByID)
                    warnings.append(warning(
                        courseID: courseID,
                        semester: semester.id,
                        kind: .missingCorequisite,
                        message: "Take alongside or before this course: \(rendered).",
                        overrides: overrides
                    ))
                }
            }
            completedBefore.formUnion(realInThisTerm)
        }

        return warnings
    }

    private static func prereqMessage(
        original: PrereqExpr,
        missing: PrereqExpr,
        hasUnknown: Bool,
        confidence: PrereqRuleConfidence,
        notes: String?,
        coursesByID: [String: Course],
        satisfied: Set<String>
    ) -> String {
        let originalText = original.displayString(coursesByID: coursesByID)
        let missingText = missing.displayString(coursesByID: coursesByID)
        let satisfiedLeaves = collectCourseLeaves(original).filter { satisfied.contains($0) }
        let satisfiedText = satisfiedLeaves.compactMap { coursesByID[$0]?.code ?? $0 }.joined(separator: ", ")
        var message = "Needs \(originalText)."
        if !satisfiedText.isEmpty {
            message += " You have \(satisfiedText);"
        }
        message += " still missing \(missingText)."
        if hasUnknown {
            message += " Some prereqs couldn't be parsed; verify with the catalog."
        }
        if confidence == .parsed {
            message += " Parsed from catalog text; verify before registering."
        }
        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            message += " Catalog note: \(notes)"
        }
        return message
    }

    private static func collectCourseLeaves(_ expr: PrereqExpr) -> [String] {
        switch expr {
        case .course(let id):
            return [id]
        case .all(let children), .any(let children):
            return children.flatMap(collectCourseLeaves)
        default:
            return []
        }
    }

    private func warning(courseID: String, semester: SemesterIdentity, kind: ConflictKind, message: String, overrides: [ConflictOverride]) -> ConflictWarning {
        let isOverridden = overrides.contains { $0.courseID == courseID && $0.semester == semester && $0.kind == kind }
        return ConflictWarning(courseID: courseID, semester: semester, kind: kind, message: message, isOverridden: isOverridden)
    }
}

public struct CategoryProgress: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var completedCredits: Int
    public var requiredCredits: Int
    public var verificationStatus: VerificationStatus

    public var remainingCredits: Int {
        max(requiredCredits - completedCredits, 0)
    }

    public var fraction: Double {
        guard requiredCredits > 0 else { return 1 }
        return min(Double(completedCredits) / Double(requiredCredits), 1)
    }
}

public struct GraduationProgress: Codable, Hashable, Sendable {
    public var categories: [CategoryProgress]
    public var projectedGraduation: SemesterIdentity?

    public var overallCompletedCredits: Int {
        categories.reduce(0) { $0 + $1.completedCredits }
    }

    public var overallRequiredCredits: Int {
        categories.reduce(0) { $0 + $1.requiredCredits }
    }

    public var overallFraction: Double {
        guard overallRequiredCredits > 0 else { return 0 }
        return min(Double(overallCompletedCredits) / Double(overallRequiredCredits), 1)
    }
}

public struct ProgressCalculator: Sendable {
    public var catalog: Catalog

    public init(catalog: Catalog) {
        self.catalog = catalog
    }

    public func progress(
        programID: String,
        concentrationID: String? = nil,
        pathway: Pathway,
        transferCredits: [TransferCredit],
        additionalPrograms: [Program] = []
    ) throws -> GraduationProgress {
        guard let program = catalog.programsByID[programID] else {
            throw PlannerError.programNotFound(programID)
        }
        let effectiveProgram = try program.effectiveProgram(concentrationID: concentrationID)

        // Placeholder course IDs in the pathway represent UNFILLED options.
        // They should not count toward completed credits. Strip them so the
        // category stays partial until the student picks a real course.
        let pathwayCourseIDs = pathway.semesters.flatMap(\.courseIDs).filter { !PathwayPlaceholder.isPlaceholder($0) }
        let completedCourseIDs = Set(pathwayCourseIDs).union(transferCredits.flatMap(\.courseIDs))
        let coursesByID = catalog.coursesByID

        func progressRow(category: RequirementCategory, idPrefix: String = "", namePrefix: String = "") -> CategoryProgress {
            let completedCredits = category.courseOptions.reduce(0) { total, options in
                if TransferCreditMapper.genEdCreditSatisfies(category: category, completedCourseIDs: completedCourseIDs) {
                    return total + max(category.requiredCredits / max(category.courseOptions.count, 1), 1)
                }
                guard let completed = options.first(where: completedCourseIDs.contains),
                      let course = coursesByID[completed] else {
                    return total
                }
                return total + course.credits
            }
            let id = idPrefix.isEmpty ? category.id : "\(idPrefix)::\(category.id)"
            let name = namePrefix.isEmpty ? category.name : "\(namePrefix): \(category.name)"
            return CategoryProgress(
                id: id,
                name: name,
                completedCredits: min(completedCredits, category.requiredCredits),
                requiredCredits: category.requiredCredits,
                verificationStatus: category.verificationStatus
            )
        }

        // Drop section-header categories that have no parseable course options.
        // JMU catalog pages often emit an umbrella row (e.g. "Additional
        // Requirements: 22-24 CRH") whose credits are fully covered by the
        // sub-rows that follow ("Additional Required Courses", "Restricted
        // Electives"). The umbrella has zero `courseOptions` because the
        // parser can't extract any course IDs from it, so surfacing it as a
        // requirement just inflates the denominator and confuses the user.
        var categories = effectiveProgram.requirements
            .filter { !$0.courseOptions.isEmpty }
            .map { progressRow(category: $0) }

        // Mirror ScheduleGenerator's 120-CRH top-up: surface an "Open
        // Electives" row whose required credits cover the gap between the
        // primary major's declared requirements and the JMU degree minimum.
        // Completion ticks up as the user resolves each Open Elective
        // placeholder slot (the resolved credits stop appearing in
        // pathway.placeholders).
        let openElectiveGap = ScheduleGenerator.openElectiveGap(for: effectiveProgram)
        if openElectiveGap > 0 {
            let resolvedIDs = Set(pathway.resolvedPlaceholders.keys)
            let unresolvedOpenElectiveCredits = pathway.placeholders
                .filter { id, spec in
                    spec.categoryID == ScheduleGenerator.openElectiveCategoryID
                        && !resolvedIDs.contains(id)
                }
                .reduce(0) { $0 + $1.value.credits }
            let completedOpenElectiveCredits = max(0, openElectiveGap - unresolvedOpenElectiveCredits)
            categories.append(CategoryProgress(
                id: ScheduleGenerator.openElectiveCategoryID,
                name: "Open Electives",
                completedCredits: min(completedOpenElectiveCredits, openElectiveGap),
                requiredCredits: openElectiveGap,
                // `.partial` makes ProgressRail paint the bar gold (the
                // catalog-unverified tone). Open electives are synthetic so
                // they're never catalog-verified.
                verificationStatus: .partial
            ))
        }

        // Add a category row per minor / second-major requirement, prefixed
        // so the UI can show "Minor: Robotics: Required Courses" and never
        // collides with a major-side category ID.
        for extra in additionalPrograms {
            let label = extra.kind == .major ? "Second Major" : "Minor"
            let prefix = "\(label) (\(extra.title))"
            for category in extra.requirements where !category.courseOptions.isEmpty {
                categories.append(progressRow(
                    category: category,
                    idPrefix: extra.id,
                    namePrefix: prefix
                ))
            }
        }

        return GraduationProgress(categories: categories, projectedGraduation: pathway.projectedGraduation)
    }
}

public extension Catalog {
    static func fixture(
        courses: [Course],
        program: Program,
        apRules: [TransferCreditRule] = [],
        prereqRuleOverlay: PrereqRuleOverlay = .empty
    ) -> Catalog {
        Catalog(
            source: CatalogSource(
                catalogYear: "Fixture",
                issueDate: Date(timeIntervalSince1970: 0),
                retrievedDate: Date(timeIntervalSince1970: 0),
                sourceURLs: [],
                retrievalNotes: []
            ),
            programs: [program],
            courses: courses,
            apCreditRules: apRules,
            prereqRuleOverlay: prereqRuleOverlay
        )
    }
}

public extension Program {
    func effectiveProgram(concentrationID: String?) throws -> Program {
        guard !concentrations.isEmpty else { return self }
        guard let concentrationID else {
            if !concentrationSelectionRequired { return self }
            throw PlannerError.concentrationRequired(title)
        }
        guard let concentration = concentrations.first(where: { $0.id == concentrationID }) else {
            throw PlannerError.concentrationNotFound(programTitle: title, concentrationID: concentrationID)
        }
        var effective = self
        effective.requirements = requirements + concentration.requirements
        effective.sourceNote = "\(sourceNote) Selected concentration: \(concentration.name)."
        return effective
    }

    static func fixture(
        id: String,
        title: String,
        requirements: [RequirementCategory],
        concentrations: [Concentration] = []
    ) -> Program {
        Program(
            id: id,
            title: title,
            degreeType: nil,
            kind: .major,
            college: "Fixture College",
            department: "Fixture Department",
            catalogPage: nil,
            totalCredits: requirements.reduce(0) { $0 + $1.requiredCredits },
            requirements: requirements,
            concentrations: concentrations,
            verificationStatus: .verified,
            requirementDataComplete: true,
            sourceNote: "Test fixture"
        )
    }
}
