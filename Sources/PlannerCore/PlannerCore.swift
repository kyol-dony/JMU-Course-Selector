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
    /// Indexes of `courseOptions` that are elective-pool slots ("9 credits
    /// of MATH electives at MATH 310 or above"), filled in by
    /// `Catalog.resolvingElectivePools()`. A second major or minor's course
    /// from the pool can stand in for one of these slots.
    public var electivePoolSlots: [Int]?
    /// What the catalog asks for. `.unknown` keeps legacy, name-based behavior.
    public var selection: RequirementSelection
    /// The catalog's course groups, in order; one inner list is courses taken
    /// together ("PSYC 210 & PSYC 211"). Empty for legacy categories.
    public var choices: [[String]]
    /// The catalog's instruction line, prose, and requirement-level footnotes.
    public var catalogDescription: String?
    /// Catalog remarks and footnotes per course ID, within this requirement.
    public var courseRemarks: [String: [String]]

    public init(
        id: String,
        name: String,
        requiredCredits: Int,
        courseOptions: [[String]],
        verificationStatus: VerificationStatus = .verified,
        note: String? = nil,
        electivePoolSlots: [Int]? = nil,
        selection: RequirementSelection = .unknown,
        choices: [[String]] = [],
        catalogDescription: String? = nil,
        courseRemarks: [String: [String]] = [:]
    ) {
        self.id = id
        self.name = name
        self.requiredCredits = requiredCredits
        self.courseOptions = courseOptions
        self.verificationStatus = verificationStatus
        self.note = note
        self.electivePoolSlots = electivePoolSlots
        self.selection = selection
        self.choices = choices
        self.catalogDescription = catalogDescription
        self.courseRemarks = courseRemarks
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, requiredCredits, courseOptions, verificationStatus, note, electivePoolSlots
        case selection, choices, catalogDescription, courseRemarks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        requiredCredits = try c.decode(Int.self, forKey: .requiredCredits)
        courseOptions = try c.decode([[String]].self, forKey: .courseOptions)
        verificationStatus = try c.decodeIfPresent(VerificationStatus.self, forKey: .verificationStatus) ?? .verified
        note = try c.decodeIfPresent(String.self, forKey: .note)
        electivePoolSlots = try c.decodeIfPresent([Int].self, forKey: .electivePoolSlots)
        selection = try c.decodeIfPresent(RequirementSelection.self, forKey: .selection) ?? .unknown
        choices = try c.decodeIfPresent([[String]].self, forKey: .choices) ?? []
        catalogDescription = try c.decodeIfPresent(String.self, forKey: .catalogDescription)
        courseRemarks = try c.decodeIfPresent([String: [String]].self, forKey: .courseRemarks) ?? [:]
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
    public var programs: [Program] {
        didSet { programsByIDStorage = Self.index(programs) }
    }
    public var courses: [Course] {
        didSet { coursesByIDStorage = Self.index(courses) }
    }
    public var apCreditRules: [TransferCreditRule]
    public var prereqRuleOverlay: PrereqRuleOverlay
    private var coursesByIDStorage: [String: Course]
    private var programsByIDStorage: [String: Program]

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
        self.coursesByIDStorage = Self.index(courses)
        self.programsByIDStorage = Self.index(programs)
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
        self.coursesByIDStorage = Self.index(courses)
        self.programsByIDStorage = Self.index(programs)
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
        coursesByIDStorage
    }

    public var programsByID: [String: Program] {
        programsByIDStorage
    }

    private static func index<Value: Identifiable>(_ values: [Value]) -> [Value.ID: Value] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
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
    public var creditOverrides: [String: Double]
    public var courseTitles: [String: String]
    public init(id: SemesterIdentity, courseIDs: [String], creditOverrides: [String: Double] = [:], courseTitles: [String: String] = [:]) {
        self.id = id; self.courseIDs = courseIDs; self.creditOverrides = creditOverrides; self.courseTitles = courseTitles
    }
    public var term: SemesterTerm { id.term }
    private enum CodingKeys: String, CodingKey { case id, courseIDs, creditOverrides, courseTitles }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(SemesterIdentity.self, forKey: .id)
        courseIDs = try c.decode([String].self, forKey: .courseIDs)
        creditOverrides = try c.decodeIfPresent([String: Double].self, forKey: .creditOverrides) ?? [:]
        courseTitles = try c.decodeIfPresent([String: String].self, forKey: .courseTitles) ?? [:]
    }
}

/// A single un-filled requirement slot in a generated schedule. The user
/// taps a placeholder course chip in the Schedule tab and picks one of the
/// alternates; the planner then swaps the placeholder ID for the chosen
/// course ID in the pathway.
public struct PlaceholderSpec: Codable, Hashable, Sendable {
    public var categoryID: String
    public var categoryName: String
    public var alternates: [String]
    public var credits: Double

    public init(categoryID: String, categoryName: String, alternates: [String], credits: Double) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.alternates = alternates
        self.credits = credits
    }
}

extension PlaceholderSpec {
    public init(categoryID: String, categoryName: String, alternates: [String], credits: Int) {
        self.init(categoryID: categoryID, categoryName: categoryName, alternates: alternates, credits: Double(credits))
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
    public var credits: Double
    public var source: AcademicCreditSource
    public init(id: UUID = UUID(), sourceDescription: String, courseIDs: [String], credits: Double, source: AcademicCreditSource = .legacy) {
        self.id = id; self.sourceDescription = sourceDescription; self.courseIDs = courseIDs
        self.credits = credits; self.source = source
    }
    private enum CodingKeys: String, CodingKey { case id, sourceDescription, courseIDs, credits, source }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sourceDescription = try c.decode(String.self, forKey: .sourceDescription)
        courseIDs = try c.decode([String].self, forKey: .courseIDs)
        credits = try c.decode(Double.self, forKey: .credits)
        source = try c.decodeIfPresent(AcademicCreditSource.self, forKey: .source) ?? .legacy
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
                credits: Double(rule.credits), source: .apMapped
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
        var credits: Double
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
        additionalPrograms: [Program] = [],
        preservedSemester: SemesterPlan? = nil,
        earnedHoursAtStart: Double? = nil,
        progress: (@Sendable (Int, Int, String) -> Void)? = nil
    ) throws -> [Pathway] {
        let context = try preservedSemester.map {
            try AnchoredScheduleContext(source: Pathway(id: "", name: "", semesters: [$0]), through: $0.id)
        }
        return try generate(for: programID, concentrationID: concentrationID, workload: workload,
                            transferCredits: transferCredits, starting: start, additionalPrograms: additionalPrograms,
                            context: context, source: nil, strategy: nil, earnedHoursAtStart: earnedHoursAtStart, progress: progress)
    }

    public func regeneratePathway(
        from source: Pathway,
        through cutoff: SemesterIdentity,
        for programID: String,
        concentrationID: String? = nil,
        strategy: ScheduleGenerationStrategy,
        workload: WorkloadPreference,
        transferCredits: [TransferCredit],
        additionalPrograms: [Program] = [],
        earnedHoursAtStart: Double? = nil,
        progress: (@Sendable (Int, Int, String) -> Void)? = nil
    ) throws -> Pathway {
        let context = try AnchoredScheduleContext(source: source, through: cutoff)
        return try generate(for: programID, concentrationID: concentrationID, workload: workload,
                            transferCredits: transferCredits, starting: context.startingSemester,
                            additionalPrograms: additionalPrograms, context: context, source: source,
                            strategy: strategy, earnedHoursAtStart: earnedHoursAtStart, progress: progress)[0]
    }

    private func generate(
        for programID: String, concentrationID: String?, workload: WorkloadPreference,
        transferCredits: [TransferCredit], starting start: SemesterIdentity, additionalPrograms: [Program],
        context: AnchoredScheduleContext?, source: Pathway?, strategy: ScheduleGenerationStrategy?,
        earnedHoursAtStart: Double?, progress: (@Sendable (Int, Int, String) -> Void)?
    ) throws -> [Pathway] {
        try Task.checkCancellation()
        let prefix = context?.semesters ?? []
        let preservedSemester = prefix.first
        let reservations = source == nil ? nil : context
        let program = try programForScheduling(programID, concentrationID: concentrationID)
        let completed = Set(transferCredits.flatMap(\.courseIDs)).union(context?.completedCourseIDs ?? [])
        var placeholders = context?.placeholders ?? [:]
        // Build one course list per program so the merge step below can
        // interleave them. Appending all extras after the primary made the
        // scheduler greedy-pack primary courses in early semesters and shove
        // second-major / minor courses into the final terms. The merge step
        // gives every program a proportional share of each semester instead.
        var perProgramLists: [[String]] = []
        // A course may legitimately fulfill requirements in more than one
        // program. Keep its planned ID while walking every selected program so
        // an overlap is scheduled only once, while each program's requirement
        // still treats it as fulfilled.
        // Mandatory concrete work from any declared program can also fulfill
        // a selective pool. Reserve that work before selecting elective slots.
        let anticipatedCourses: Set<String> = source == nil ? [] : Set(([program] + additionalPrograms).flatMap { p in
            p.requirements.filter { category in
                switch behavior(for: category) {
                case .required: return true
                case .selective, .groups: return false
                case .legacy:
                    let name = legacyKeywordText(category)
                    return name.contains("required") || !(name.contains("elective") || name.contains("choose") || name.contains("select"))
                }
            }.flatMap { $0.courseOptions.filter { $0.count == 1 }.flatMap { $0 } }
        })
        let lists = plannedProgramLists(
            for: program,
            additionalPrograms: additionalPrograms,
            completed: completed,
            placeholders: &placeholders,
            anchors: reservations,
            anticipatedCourses: anticipatedCourses
        )
        var primaryList = lists.primary
        let extraLists = lists.extras
        // JMU degrees require 120 CRH total. If the primary major's declared
        // requirements fall short, top up with Open Elective placeholders so
        // the schedule reaches 120 (before AP/transfer credits whittle it
        // down). Credits a minor / second major adds beyond the primary major
        // fill that same gap, so they shrink the top-up instead of stacking
        // on top of it. Secondary programs are never topped up themselves.
        try Task.checkCancellation()
        // Both entry points share selection, lab expansion, variant ordering and
        // semester construction. Full generation retains its legacy gap allocation.
        if source == nil {
            let originalGap = openElectiveGap(for: program, additionalPrograms: additionalPrograms)
            let general = AcademicCreditCalculator.generalHours(credits: transferCredits, current: preservedSemester, programs: [program] + additionalPrograms, catalog: catalog)
            let shortfall = AcademicCreditCalculator.requirementCreditShortfall(credits: transferCredits, current: preservedSemester, programs: [program] + additionalPrograms, catalog: catalog)
            primaryList.append(contentsOf: openElectivePlaceholders(gap: max(0, Double(originalGap) - general + shortfall), placeholders: &placeholders))
        }
        perProgramLists.append(primaryList)
        perProgramLists.append(contentsOf: extraLists)
        var required = withLabs(
            Self.interleaveByProportion(perProgramLists), completed: completed,
            placeholders: &placeholders,
            labPairing: LabPairing(catalog: catalog, activeProgramTitle: program.title),
            reservedIDs: context?.reservedPlaceholderIDs ?? []
        )
        if source != nil, program.kind == .major,
           program.requirements.reduce(0, { $0 + $1.requiredCredits }) >= 60 {
            let prefixHours = AcademicCreditCalculator.projectedHours(in: prefix, placeholders: placeholders, transferCredits: transferCredits, catalog: catalog)
            let suffixHours = Set(required).reduce(0.0) { $0 + credits(for: $1, placeholders: placeholders) }
            required += openElectivePlaceholders(gap: max(0, 120 - prefixHours - suffixHours), placeholders: &placeholders, reservedIDs: context?.reservedPlaceholderIDs ?? [])
        }
        try Task.checkCancellation()

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

        let selectedIndices = strategy.map { [ScheduleGenerationStrategy.allCases.firstIndex(of: $0)!] } ?? Array(variants.indices)
        for (progressIndex, index) in selectedIndices.enumerated() {
            let variant = variants[index]
            try Task.checkCancellation()
            progress?(progressIndex + 1, selectedIndices.count, source?.name ?? pathwayName(index + 1))
            try Task.checkCancellation()
            let semesters = try buildSemesters(
                courseIDs: variant,
                completedAtStart: completed,
                workload: workload,
                starting: context?.startingSemester ?? start,
                placeholders: placeholders,
                activeProgramTitle: program.title,
                earnedHoursAtStart: earnedHoursAtStart.map { initial in
                    initial + AcademicCreditCalculator.projectedHours(in: prefix, placeholders: placeholders, transferCredits: transferCredits, catalog: catalog) - transferCredits.reduce(0.0) { $0 + $1.credits }
                },
                standingSemesterOffset: source == nil ? 0 : context?.standingSemesterOffset ?? 0,
                preferenceSemesterOffset: source == nil ? 0 : context?.preferenceSemesterOffset ?? 0,
                preservedSemesters: prefix
            )
            pathways.append(Pathway(
                id: source?.id ?? "path-\(index + 1)",
                name: source?.name ?? pathwayName(index + 1),
                semesters: prefix + semesters,
                placeholders: placeholders,
                resolvedPlaceholders: context?.resolvedPlaceholders ?? [:]
            ))
        }

        return pathways
    }

    /// Helper used by the variant sorter so placeholder IDs surface a sensible
    /// credit weight without polluting the catalog's coursesByID dict.
    private func credits(for courseID: String, placeholders: [String: PlaceholderSpec]) -> Double {
        if let spec = placeholders[courseID] { return spec.credits }
        return Double(catalog.coursesByID[courseID]?.credits ?? 0)
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
    /// scheduled once and counts toward both options. `reusedCredits` grows
    /// by the credits such options declare, capped at each category's
    /// requirement, so the Open Elective gap can count that course once.
    ///
    /// `completed` may also contain JMU GNED placeholder course IDs (e.g.,
    /// `GNED123` awarded by AP Lit). Those satisfy any option in a Gen Ed
    /// category whose name carries the matching cluster tag (`[C2L]`), even
    /// though the GNED ID is not in the alternate list of any specific option.
    private func requiredCourseIDs(
        for program: Program,
        completed: Set<String>,
        plannedCourseIDs: inout Set<String>,
        reusedCredits: inout Int,
        placeholders: inout [String: PlaceholderSpec],
        anchors: AnchoredScheduleContext? = nil,
        anticipatedCourses: Set<String> = []
    ) -> [String] {
        let completedClusterTags = Set(completed.compactMap { TransferCreditMapper.genEdCreditClusterTag(for: $0) })
        // Seed the local de-duplication set with courses chosen for earlier
        // programs. This allows, for example, a Mathematics core course to
        // satisfy a Statistics elective without scheduling it twice.
        var seen = plannedCourseIDs
        var result: [String] = []
        for category in program.requirements {
            if Task.isCancelled { break }
            let lowerName = legacyKeywordText(category)
            let rule = behavior(for: category)
            // Required categories are mandatory in full — every option must
            // reach the schedule. Bypass the Gen Ed cluster shortcut and the
            // selective-elective placeholder path so nothing trims the option
            // list before iteration. Without a parsed rule, a heading that
            // carries "required" marks the category.
            let categoryIsRequired: Bool
            switch rule {
            case .required: categoryIsRequired = true
            case .selective, .groups: categoryIsRequired = false
            case .legacy: categoryIsRequired = lowerName.contains("required")
            }

            let categorySatisfiedByCluster = completedClusterTags.contains(where: category.name.contains)
            if !categoryIsRequired && categorySatisfiedByCluster { continue }

            // Credits of this category met by a course already scheduled for
            // an earlier one.
            var categoryReusedCredits = 0
            defer { reusedCredits += min(categoryReusedCredits, category.requiredCredits) }

            if case .groups(let count) = rule,
               appendCourseGroups(
                count,
                for: category,
                completed: completed,
                anticipatedCourses: anticipatedCourses,
                seen: &seen,
                reusedCredits: &categoryReusedCredits,
                result: &result,
                anchors: anchors
            ) {
                continue
            }

            let optionCount = max(category.courseOptions.count, 1)
            let fallbackOptionCredits = max(category.requiredCredits / optionCount, 1)
            if !categoryIsRequired,
               appendSelectableElectivePlaceholders(
                for: category,
                completed: completed,
                plannedCourseIDs: plannedCourseIDs.union(anticipatedCourses),
                seen: &seen,
                result: &result,
                placeholders: &placeholders,
                fallbackOptionCredits: fallbackOptionCredits,
                anchors: anchors
            ) {
                continue
            }

            // Only selective categories use an allowance. Reserve its entire
            // anchored amount before choosing earlier options; a retained later
            // slot must not be overlooked when the cap stops iteration.
            let categoryIsSelective: Bool
            switch rule {
            case .required: categoryIsSelective = false
            case .selective, .groups: categoryIsSelective = true
            case .legacy:
                categoryIsSelective = !categoryIsRequired && (
                    lowerName.contains("choose")
                    || lowerName.contains("elective")
                    || lowerName.contains("select")
                )
            }
            // A choose-N-courses rule is already limited by its N slots; its
            // credits can read low ("two lab courses: 2-8"), so no cap.
            let isCountedRule: Bool
            if case .chooseCourses = category.selection { isCountedRule = true } else { isCountedRule = false }
            let hasCreditLimit = categoryIsSelective && !isCountedRule && category.requiredCredits > 0
            let poolSlots = Set(category.electivePoolSlots ?? [])
            var reservedIDs = Set((anchors?.placeholders ?? [:]).filter { $0.value.categoryID == category.id }.keys)
            for (index, _) in category.courseOptions.enumerated() {
                let id = PathwayPlaceholder.id(categoryID: category.id, optionIndex: index)
                if anchors?.reservedPlaceholderIDs.contains(id) == true { reservedIDs.insert(id) }
            }
            let reservedHours = reservedIDs.reduce(0.0) { hours, id in
                if let spec = anchors?.placeholders[id] { return hours + spec.credits }
                guard let entry = category.courseOptions.enumerated().first(where: {
                    PathwayPlaceholder.id(categoryID: category.id, optionIndex: $0.offset) == id
                }) else { return hours }
                let slotCredits = poolSlots.contains(entry.offset)
                    ? Self.electivePoolSlotCredits
                    : credits(for: entry.element, fallback: fallbackOptionCredits)
                return hours + Double(slotCredits)
            }
            var plannedCredits = hasCreditLimit ? reservedHours : 0
            // Resolved anchor choices belong to their exact slots in this
            // category. Other programs/categories can still use their concrete
            // equivalence, but another row here needs a distinct choice.
            var consumed = Set((anchors?.resolvedPlaceholders ?? [:]).filter { reservedIDs.contains($0.key) }.values)
            for (idx, option) in category.courseOptions.enumerated() {
                if hasCreditLimit && plannedCredits >= Double(category.requiredCredits) { break }
                // Pool slots reserve their share of the allowance rather than
                // the largest course on the menu.
                let optionCredits = poolSlots.contains(idx)
                    ? Self.electivePoolSlotCredits
                    : credits(for: option, fallback: fallbackOptionCredits)
                let slotID = PathwayPlaceholder.id(categoryID: category.id, optionIndex: idx)
                if reservedIDs.contains(slotID) { continue }
                let available = completed.union(seen).union(option.count > 1 ? anticipatedCourses : [])
                if let match = option.first(where: {
                    available.contains($0) && !consumed.contains($0)
                }) {
                    consumed.insert(match)
                    if seen.contains(match) && !completed.contains(match) {
                        categoryReusedCredits += optionCredits
                    }
                    plannedCredits += Double(optionCredits)
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
                    consumed.insert(pick)
                }
                plannedCredits += Double(optionCredits)
            }
        }
        plannedCourseIDs.formUnion(result.filter { !PathwayPlaceholder.isPlaceholder($0) })
        return result
    }

    private func appendSelectableElectivePlaceholders(
        for category: RequirementCategory,
        completed: Set<String>,
        plannedCourseIDs: Set<String>,
        seen: inout Set<String>,
        result: inout [String],
        placeholders: inout [String: PlaceholderSpec],
        fallbackOptionCredits: Int,
        anchors: AnchoredScheduleContext? = nil
    ) -> Bool {
        let usesElectivePool: Bool
        switch category.selection {
        case .chooseCredits: usesElectivePool = true
        case .unknown: usesElectivePool = legacyKeywordText(category).contains("elective")
        case .allRequired, .chooseCourses, .chooseGroups: usesElectivePool = false
        }
        guard usesElectivePool,
              category.requiredCredits > 0,
              category.courseOptions.count > 1
        else {
            return false
        }

        let optionCredits = category.courseOptions.map { credits(for: $0, fallback: fallbackOptionCredits) }
        let totalEligibleCredits = optionCredits.reduce(0, +)
        guard totalEligibleCredits > category.requiredCredits else { return false }

        let satisfiedCourseIDs = completed.union(plannedCourseIDs)
        let fulfilledCredits = uniqueCourseIDs(category.courseOptions.flatMap { $0 })
            .filter(satisfiedCourseIDs.contains)
            .reduce(0) { $0 + (catalog.coursesByID[$1]?.credits ?? fallbackOptionCredits) }
        let reservedHours = anchors?.placeholders.filter {
            $0.value.categoryID == category.id && anchors?.resolvedPlaceholders[$0.key] == nil
        }.values.reduce(0.0) { $0 + $1.credits } ?? 0
        let remainingCredits = max(Double(category.requiredCredits - fulfilledCredits) - reservedHours, 0)
        guard remainingCredits > 0 else { return true }

        let alternates = uniqueCourseIDs(category.courseOptions.flatMap { $0 })
            .filter { !satisfiedCourseIDs.contains($0) }
        guard !alternates.isEmpty else { return true }

        let slotCredits = max(optionCredits.max() ?? fallbackOptionCredits, 1)
        let slotCount = max(Int(ceil(Double(remainingCredits) / Double(slotCredits))), 1)
        for slot in 0..<slotCount {
            let id = unusedPlaceholderID(categoryID: category.id, startingAt: slot, placeholders: placeholders, reservedIDs: anchors?.reservedPlaceholderIDs ?? [])
            guard seen.insert(id).inserted else { continue }
            result.append(id)
            placeholders[id] = PlaceholderSpec(
                categoryID: category.id,
                categoryName: category.name,
                alternates: alternates,
                credits: min(Double(slotCredits), remainingCredits - Double(slot * slotCredits))
            )
        }
        return true
    }

    /// How the generator fills a requirement: from its parsed selection rule,
    /// or from keywords in its name when the parser could not tell.
    private enum RequirementBehavior: Equatable {
        case required, selective, groups(Int), legacy
    }

    /// The text the keyword fallback reads: the name plus the ID. A
    /// requirement renamed after its catalog section keeps its old
    /// instruction ("choose-two-of-the-following") in its ID.
    private func legacyKeywordText(_ category: RequirementCategory) -> String {
        "\(category.name) \(category.id.replacingOccurrences(of: "-", with: " "))".lowercased()
    }

    private func behavior(for category: RequirementCategory) -> RequirementBehavior {
        switch category.selection {
        case .allRequired: return .required
        case .chooseCourses, .chooseCredits: return .selective
        case .chooseGroups(let count): return .groups(count)
        case .unknown: return .legacy
        }
    }

    /// Schedules `count` whole groups from `category.choices` (a group can be
    /// a pair taken together), every member as a concrete course. Groups with
    /// a member already completed or planned come first, then catalog order.
    /// Returns false when the slot loop should handle the category instead:
    /// no groups were parsed, or an anchored regeneration already holds
    /// placeholders for its slots.
    private func appendCourseGroups(
        _ count: Int,
        for category: RequirementCategory,
        completed: Set<String>,
        anticipatedCourses: Set<String>,
        seen: inout Set<String>,
        reusedCredits: inout Int,
        result: inout [String],
        anchors: AnchoredScheduleContext?
    ) -> Bool {
        guard !category.choices.isEmpty else { return false }
        let slotPrefix = "\(PathwayPlaceholder.prefix)\(category.id)::"
        let anchoredSlots = (anchors?.placeholders ?? [:]).values.contains { $0.categoryID == category.id }
            || (anchors?.reservedPlaceholderIDs ?? []).contains { $0.hasPrefix(slotPrefix) }
        guard !anchoredSlots else { return false }
        let started = completed.union(seen).union(anticipatedCourses)
        let ordered = category.choices.filter { $0.contains(where: started.contains) }
            + category.choices.filter { !$0.contains(where: started.contains) }
        for group in ordered.prefix(max(count, 1)) {
            for courseID in group where !completed.contains(courseID) {
                if seen.insert(courseID).inserted {
                    result.append(courseID)
                } else {
                    reusedCredits += catalog.coursesByID[courseID]?.credits ?? 0
                }
            }
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

    /// `courseIDs` with lectures and labs completed into pairs: each lecture
    /// that needs a lab followed by one (the lab when only one fits, else a
    /// "Lab for ..." placeholder), and each lone lab preceded by its lecture.
    /// Skipped when the partner is already listed or completed.
    private func withLabs(
        _ courseIDs: [String],
        completed: Set<String>,
        placeholders: inout [String: PlaceholderSpec],
        labPairing: LabPairing,
        reservedIDs: Set<String> = []
    ) -> [String] {
        var listed = Set(courseIDs).union(reservedIDs)
        var result: [String] = []
        for courseID in courseIDs {
            // A lab listed on its own ("choose two laboratory courses") is
            // taken with its lecture, so the lecture comes along.
            let lectures = labPairing.lectures(forLab: courseID)
            if let lecture = lectures.first,
               !lectures.contains(where: { listed.contains($0) || completed.contains($0) }),
               listed.insert(lecture).inserted {
                result.append(lecture)
            }
            result.append(courseID)
            let labs = labPairing.labOptions(forLecture: courseID)
            guard !labs.isEmpty,
                  !labs.contains(where: { listed.contains($0) || completed.contains($0) })
            else { continue }
            let lab = labs.count == 1 ? labs[0] : LabPairing.labPlaceholderID(forLecture: courseID)
            guard listed.insert(lab).inserted else { continue }
            if labs.count > 1 {
                placeholders[lab] = labPairing.labPlaceholderSpec(forLecture: courseID)
            }
            result.append(lab)
        }
        return result
    }

    /// Lecture → lab pairs among `courseIDs` that must be placed together.
    private func labUnits(in courseIDs: [String], labPairing: LabPairing) -> [String: String] {
        let pool = Pathway(id: "", name: "", semesters: [SemesterPlan(id: SemesterIdentity(year: 0, term: .fall), courseIDs: courseIDs)])
        var labFor: [String: String] = [:]
        var paired: Set<String> = []
        for item in courseIDs where LabPairing.isLab(item) || LabPairing.lecture(forLabPlaceholder: item) != nil {
            guard let lecture = labPairing.partners(of: item, in: pool).first,
                  !paired.contains(lecture), !paired.contains(item)
            else { continue }
            labFor[lecture] = item
            paired.formUnion([lecture, item])
        }
        return labFor
    }

    private func buildSemesters(
        courseIDs: [String],
        completedAtStart: Set<String>,
        workload: WorkloadPreference,
        starting start: SemesterIdentity,
        placeholders: [String: PlaceholderSpec] = [:],
        activeProgramTitle: String? = nil,
        earnedHoursAtStart: Double? = nil,
        standingSemesterOffset: Int = 0,
        preferenceSemesterOffset: Int = 0,
        preservedSemesters: [SemesterPlan] = []
    ) throws -> [SemesterPlan] {
        var remaining = courseIDs
        var completed = completedAtStart
        var earnedHours = earnedHoursAtStart
        var semester = start
        var semesterOffset = 0
        var result: [SemesterPlan] = []
        var emptySemesterCount = 0
        let resolver = PrereqRuleResolver(catalog: catalog)
        let labPairing = LabPairing(catalog: catalog, activeProgramTitle: activeProgramTitle)
        // Unresolved slots already placed (here or in the preserved prefix)
        // can conditionally supply a later course's prerequisite. Courses
        // admitted that way stay constraints for the rest of the build, but
        // no slot is ever resolved: the witnesses are only proofs.
        let analyzer = PlaceholderPrerequisiteAnalyzer(catalog: catalog)
        var admitted: [ConditionalPrerequisiteRequest] = []
        var budget = ConditionalSearchBudget()
        var placedStanding = Dictionary(
            preservedSemesters.enumerated().map { ($1.id, ClassStanding.forSemester(position: $0 + 1, totalSemesters: nil)) },
            uniquingKeysWith: { first, _ in first }
        )
        func probeInput(_ items: [String], at semester: SemesterIdentity, standing: ClassStanding) -> ConditionalPrerequisiteInput {
            var standings = placedStanding
            standings[semester] = standing
            return ConditionalPrerequisiteInput(
                pathway: Pathway(id: "", name: "", semesters: preservedSemesters + result + [SemesterPlan(id: semester, courseIDs: items)], placeholders: placeholders),
                completedAtStart: completedAtStart,
                standingBySemester: standings,
                workload: workload,
                activeProgramTitle: activeProgramTitle,
                unscheduledCourseIDs: Set(remaining.filter { !PathwayPlaceholder.isPlaceholder($0) }).subtracting(items)
            )
        }

        while !remaining.isEmpty {
            try Task.checkCancellation()
            var selected: [String] = []
            var credits = 0.0
            let maxCredits = Double(workload.creditRange.upperBound)
            let target = targetLevel(for: semesterOffset + preferenceSemesterOffset)
            let labFor = labUnits(in: remaining, labPairing: labPairing)
            let pairedLabs = Set(labFor.values)
            // Plan length isn't known while building, so standing uses the
            // four-year position rule alone; the conflict detector, which
            // also credits shorter plans, has the final say. Terms skipped
            // because nothing fit still advance the offset so a lone
            // standing-gated course can't stall generation.
            let termStanding = earnedHours.map(ClassStanding.forEarnedCredits) ?? ClassStanding.forSemester(position: semesterOffset + standingSemesterOffset + 1, totalSemesters: nil)
            // A slot that can supply a pending course's prerequisite isn't
            // held back by preferences like its menu's median level.
            let urgency = Dictionary(remaining.map { item in
                (item, analyzer.providerPriority(itemID: item, pendingCourseIDs: remaining, completedCourseIDs: completed, placeholders: placeholders, activeProgramTitle: activeProgramTitle))
            }, uniquingKeysWith: { first, _ in first })
            var conditional: [String: ConditionalPrerequisiteRequest] = [:]

            let ready = try remaining.enumerated().compactMap { order, courseID -> ScheduleCandidate? in
                let courseCredits: Double
                let courseAvailability: Set<SemesterTerm>?
                let prerequisiteExpr: PrereqExpr
                if let spec = placeholders[courseID] {
                    // A needed slot holds off while its needed choices still
                    // lack prerequisites another pending slot would supply.
                    if urgency[courseID] == 0, try analyzer.slotShouldWait(
                        courseID, in: semester, input: probeInput([courseID], at: semester, standing: termStanding),
                        admitted: admitted, pendingCourseIDs: remaining, completedCourseIDs: completed,
                        placeholders: placeholders, budget: &budget
                    ) {
                        return nil
                    }
                    courseCredits = spec.credits
                    courseAvailability = nil
                    prerequisiteExpr = .empty
                } else if let course = catalog.coursesByID[courseID] {
                    courseCredits = Double(course.credits)
                    courseAvailability = course.availability
                    // A lecture and its lab go in together, so neither waits
                    // on the other as a prerequisite.
                    prerequisiteExpr = resolver.rule(for: course, activeProgramTitle: activeProgramTitle).prerequisiteExpr
                        .treatingAsSatisfied(labPairing.pairedCourses(of: courseID))
                } else {
                    return nil
                }
                if let availability = courseAvailability, !availability.contains(semester.term) { return nil }
                if case .unmet = PrereqEvaluator(completedBefore: completed, scheduledThisTerm: [], standing: termStanding)
                    .evaluate(prerequisiteExpr, mode: .prereq) {
                    // Not ready on real work; an earlier unresolved slot may
                    // still supply what's missing.
                    guard let request = try analyzer.conditionalPrerequisite(
                        for: courseID, in: semester, input: probeInput([courseID], at: semester, standing: termStanding),
                        admitted: admitted, budget: &budget
                    ) else { return nil }
                    conditional[courseID] = request
                }
                return ScheduleCandidate(courseID: courseID, credits: courseCredits, variantOrder: order)
            }
            .sorted { lhs, rhs in
                compare(lhs, rhs, targetLevel: target, semesterOffset: semesterOffset + preferenceSemesterOffset, placeholders: placeholders, urgency: urgency)
            }

            let readyByID = Dictionary(ready.map { ($0.courseID, $0) }, uniquingKeysWith: { first, _ in first })
            for candidate in ready where !pairedLabs.contains(candidate.courseID) {
                var unit = [candidate]
                if let lab = labFor[candidate.courseID] {
                    // A lecture waits until its lab can share the semester.
                    guard let labCandidate = readyByID[lab] else { continue }
                    unit.append(labCandidate)
                }
                let unitCredits = unit.reduce(0) { $0 + $1.credits }
                guard credits + unitCredits <= maxCredits else { continue }
                // Re-check conditional members together with everything
                // admitted so far, including this term's earlier picks: one
                // slot can't supply incompatible choices to two courses.
                var unitRequests: [ConditionalPrerequisiteRequest] = []
                var compatible = true
                for member in unit where conditional[member.courseID] != nil {
                    guard let request = try analyzer.conditionalPrerequisite(
                        for: member.courseID, in: semester,
                        input: probeInput(selected + unit.map(\.courseID), at: semester, standing: termStanding),
                        admitted: admitted + unitRequests, budget: &budget
                    ) else {
                        compatible = false
                        break
                    }
                    unitRequests.append(request)
                }
                guard compatible else { continue }
                admitted += unitRequests
                selected.append(contentsOf: unit.map(\.courseID))
                credits += unitCredits
            }

            if selected.isEmpty {
                emptySemesterCount += 1
                guard emptySemesterCount <= 8 else {
                    if !strictPrereqs {
                        let fallbackStart = result.last?.id.next ?? semester
                        result.append(contentsOf: try buildBestEffortSemesters(
                            courseIDs: remaining,
                            workload: workload,
                            starting: fallbackStart,
                            placeholders: placeholders,
                            baseSemesterOffset: standingSemesterOffset == 0 && preferenceSemesterOffset == 0 ? result.count : semesterOffset + preferenceSemesterOffset
                        ))
                        return result
                    }
                    throw PlannerError.impossibleSchedule("Could not place the remaining courses while respecting prerequisites and semester availability.")
                }
                semester = semester.next
                semesterOffset += 1
                continue
            }

            placedStanding[semester] = termStanding
            result.append(SemesterPlan(id: semester, courseIDs: selected))
            remaining.removeAll { selected.contains($0) }
            completed.formUnion(selected)
            earnedHours = earnedHours.map { $0 + credits }
            semester = semester.next
            semesterOffset += 1
        }

        // Every conditionally admitted course must still have a compatible
        // route in the finished schedule.
        if strictPrereqs, !admitted.isEmpty {
            let finished = ConditionalPrerequisiteInput(
                pathway: Pathway(id: "", name: "", semesters: preservedSemesters + result, placeholders: placeholders),
                completedAtStart: completedAtStart,
                standingBySemester: placedStanding,
                workload: workload,
                activeProgramTitle: activeProgramTitle
            )
            var check = ConditionalSearchBudget()
            guard case .feasible = try ConditionalPrerequisiteSolver(catalog: catalog).solve(admitted, in: finished, budget: &check) else {
                throw PlannerError.impossibleSchedule("Could not confirm the placeholder choices this schedule relies on for prerequisites.")
            }
        }
        return result
    }

    private func buildBestEffortSemesters(
        courseIDs: [String],
        workload: WorkloadPreference,
        starting start: SemesterIdentity,
        placeholders: [String: PlaceholderSpec],
        baseSemesterOffset: Int
    ) throws -> [SemesterPlan] {
        var remaining = courseIDs
        var semester = start
        var semesterOffset = baseSemesterOffset
        var result: [SemesterPlan] = []
        let maxCredits = Double(workload.creditRange.upperBound)
        let labPairing = LabPairing(catalog: catalog)

        while !remaining.isEmpty {
            try Task.checkCancellation()
            var selected: [String] = []
            var selectedCredits = 0.0
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

            // Lectures keep their labs beside them here too.
            let labFor = labUnits(in: remaining, labPairing: labPairing)
            let pairedLabs = Set(labFor.values)
            for candidate in candidates where !pairedLabs.contains(candidate.courseID) {
                let unit = [candidate.courseID] + (labFor[candidate.courseID].map { [$0] } ?? [])
                let unitCredits = unit.reduce(0) { $0 + credits(for: $1, placeholders: placeholders) }
                if unitCredits > maxCredits, selected.isEmpty {
                    selected.append(contentsOf: unit)
                    break
                }
                guard selectedCredits + unitCredits <= maxCredits else { continue }
                selected.append(contentsOf: unit)
                selectedCredits += unitCredits
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
        placeholders: [String: PlaceholderSpec],
        urgency: [String: Int] = [:]
    ) -> Bool {
        let lhsTimingPriority = genEdTimingPriority(for: lhs.courseID, semesterOffset: semesterOffset, placeholders: placeholders)
        let rhsTimingPriority = genEdTimingPriority(for: rhs.courseID, semesterOffset: semesterOffset, placeholders: placeholders)
        if lhsTimingPriority != rhsTimingPriority {
            return lhsTimingPriority < rhsTimingPriority
        }

        // A slot designated to supply a pending course's prerequisite isn't
        // held back by its menu's median level: it ranks as on-level work,
        // alongside (not ahead of) real courses at this semester's level.
        let lhsLevel = urgency[lhs.courseID] == 0 ? targetLevel : courseLevel(for: lhs.courseID, placeholders: placeholders)
        let rhsLevel = urgency[rhs.courseID] == 0 ? targetLevel : courseLevel(for: rhs.courseID, placeholders: placeholders)
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

    public static func isGenEdCategory(id: String, name: String) -> Bool {
        id.contains("gened") || name.lowercased().contains("general education")
    }

    /// Credits one elective-pool slot stands for: the parser makes N / 3
    /// slots for "N credits of ... electives".
    public static let electivePoolSlotCredits = 3

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
    ///
    /// `additionalCredits` are degree credits contributed outside the
    /// primary major's requirements (minor / second-major courses) and
    /// reduce the gap one-for-one. `reusedCredits` are declared credits met
    /// by a course already counted for another requirement (MATH 220 for
    /// both a major requirement and the [C3QR] cluster); that course is
    /// scheduled once, so they widen the gap one-for-one.
    ///
    /// `scheduledCredits` are the hours the generator schedules for these
    /// requirements. When they exceed the declared tally (4-credit courses in
    /// 3-credit slots, labs) the gap shrinks to what still reaches 120, as
    /// regeneration tops up. Declared credits that no scheduled course stands
    /// for still count, so the gap never grows past the declared view.
    public static func openElectiveGap(
        for program: Program,
        additionalCredits: Int = 0,
        reusedCredits: Int = 0,
        scheduledCredits: Int = 0
    ) -> Int {
        guard program.kind == .major else { return 0 }
        let declared = program.requirements
            .filter { !$0.courseOptions.isEmpty }
            .reduce(0) { $0 + $1.requiredCredits }
        // Threshold gate keeps thin test fixtures (under 60 credits) from
        // generating dozens of placeholders. Real JMU majors easily clear
        // 60 once Gen Ed clusters and concentration requirements are
        // merged into the effective program. Requirements without a course
        // list count toward the gate; their credits are left to the gap.
        guard program.requirements.reduce(0, { $0 + $1.requiredCredits }) >= 60 else { return 0 }
        let counted = max(declared - reusedCredits + additionalCredits, scheduledCredits)
        return max(0, 120 - counted)
    }

    /// Open Elective gap for `program` once `additionalPrograms` (minors,
    /// second majors) claim their share of the 120 CRH. Only credits unique
    /// to the additional programs count: a course that already fulfills a
    /// primary-major requirement is scheduled once and adds nothing new.
    /// Likewise a course filling two of the primary major's own requirements
    /// counts once toward 120.
    ///
    /// Deliberately ignores transfer credit so the schedule generator and
    /// progress calculator always agree on the same gap — a minor course
    /// satisfied by AP/transfer still counts toward the degree total.
    public func openElectiveGap(for program: Program, additionalPrograms: [Program]) -> Int {
        guard program.kind == .major else { return 0 }
        var placeholders: [String: PlaceholderSpec] = [:]
        let lists = plannedProgramLists(for: program, additionalPrograms: additionalPrograms, completed: [], placeholders: &placeholders)
        // Courses that also fill one of the primary major's elective-pool
        // slots count once toward 120, so they don't shrink the gap.
        let additionalCredits = lists.extras.joined()
            .filter { !lists.sharedCourseIDs.contains($0) }
            .reduce(0) { $0 + Int(credits(for: $1, placeholders: placeholders)) }
        // What the generator schedules for these programs, labs included.
        // A course that fills two requirements appears here once.
        let scheduled = withLabs(
            Self.interleaveByProportion([lists.primary] + lists.extras), completed: [],
            placeholders: &placeholders,
            labPairing: LabPairing(catalog: catalog, activeProgramTitle: program.title)
        )
        let scheduledCredits = Set(scheduled).reduce(0.0) { $0 + credits(for: $1, placeholders: placeholders) }
        return Self.openElectiveGap(
            for: program,
            additionalCredits: additionalCredits,
            reusedCredits: lists.reusedCredits,
            scheduledCredits: Int(scheduledCredits)
        )
    }

    /// Each program's still-needed courses, in program order. A course
    /// already planned for an earlier program fulfills a later program's
    /// matching requirement without being scheduled twice. And a second
    /// major's or minor's course that fits one of the primary major's
    /// elective-pool slots ("MATH electives at MATH 310 or above") fills
    /// that slot instead of the slot staying open; `sharedCourseIDs` lists
    /// those courses, one per slot. `reusedCredits` are the primary major's
    /// requirement credits met by a course it already schedules for another
    /// requirement.
    private func plannedProgramLists(
        for program: Program,
        additionalPrograms: [Program],
        completed: Set<String>,
        placeholders: inout [String: PlaceholderSpec],
        anchors: AnchoredScheduleContext? = nil,
        anticipatedCourses: Set<String> = []
    ) -> (primary: [String], extras: [[String]], sharedCourseIDs: Set<String>, reusedCredits: Int) {
        var plannedCourseIDs: Set<String> = []
        var reusedCredits = 0
        var primary = requiredCourseIDs(
            for: program,
            completed: completed,
            plannedCourseIDs: &plannedCourseIDs,
            reusedCredits: &reusedCredits,
            placeholders: &placeholders,
            anchors: anchors,
            anticipatedCourses: anticipatedCourses
        )
        var extras: [[String]] = []
        for extra in additionalPrograms {
            if Task.isCancelled { break }
            // Extras are counted by the courses they add, which already
            // leaves out overlaps; their reuse needs no correction.
            var extraReusedCredits = 0
            extras.append(requiredCourseIDs(
                for: extra,
                completed: completed,
                plannedCourseIDs: &plannedCourseIDs,
                reusedCredits: &extraReusedCredits,
                placeholders: &placeholders,
                anchors: anchors,
                anticipatedCourses: anticipatedCourses
            ))
        }

        let poolSlotIDs = Set(program.requirements.flatMap { category in
            (category.electivePoolSlots ?? []).map { PathwayPlaceholder.id(categoryID: category.id, optionIndex: $0) }
        })
        // Anticipated courses have already claimed a slot during requirement
        // selection; do not use that same course to remove a second slot.
        var available = uniqueCourseIDs(extras.joined().filter {
            !PathwayPlaceholder.isPlaceholder($0) && !anticipatedCourses.contains($0)
        })
        var shared: Set<String> = []
        primary.removeAll { id in
            guard poolSlotIDs.contains(id),
                  let spec = placeholders[id],
                  let course = available.first(where: spec.alternates.contains)
            else { return false }
            available.removeAll { $0 == course }
            shared.insert(course)
            placeholders[id] = nil
            return true
        }
        return (primary, extras, shared, reusedCredits)
    }

    /// Build Open Elective placeholders to cover `gap` CRH — the shortfall
    /// between the plan's requirement credits and JMU's degree credit
    /// minimum. Each slot defaults to 3 credits with the last slot trimmed
    /// to whatever remains. Returns an empty array when `gap` is zero.
    private func openElectivePlaceholders(
        gap: Double,
        placeholders: inout [String: PlaceholderSpec],
        reservedIDs: Set<String> = []
    ) -> [String] {
        guard gap > 0 else { return [] }
        let slotCredits = 3.0
        let slotCount = Int(ceil(Double(gap) / Double(slotCredits)))
        // Leave `alternates` empty. Storing every catalog course id per slot
        // would balloon the persisted pathway JSON and make the sorter call
        // `medianAlternateLevel` over 1000+ ids every comparison, freezing
        // pathway generation. The UI special-cases open electives to render
        // the full catalog picker on demand.
        var ids: [String] = []
        for slot in 0..<slotCount {
            let id = unusedPlaceholderID(categoryID: Self.openElectiveCategoryID, startingAt: slot, placeholders: placeholders, reservedIDs: reservedIDs)
            let remaining = gap - Double(slot) * slotCredits
            let credits = min(slotCredits, remaining)
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

    private func unusedPlaceholderID(categoryID: String, startingAt index: Int, placeholders: [String: PlaceholderSpec], reservedIDs: Set<String> = []) -> String {
        var next = index
        while placeholders[PathwayPlaceholder.id(categoryID: categoryID, optionIndex: next)] != nil || reservedIDs.contains(PathwayPlaceholder.id(categoryID: categoryID, optionIndex: next)) {
            next += 1
        }
        return PathwayPlaceholder.id(categoryID: categoryID, optionIndex: next)
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

public enum ConflictSeverity: Int, Comparable, Sendable {
    case hidden
    case worthALook
    case mustFix

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum ConflictKind: String, Codable, Hashable, Sendable {
    case missingPrerequisite
    case missingCorequisite
    case unavailableSemester
    case unknownAvailability
    case heavyLoad
    case lightLoad
    case labNotPaired
    /// An unresolved placeholder whose choice a later course is counting on
    /// for a prerequisite. A derived explanation, never kept or fixed.
    case pendingPrerequisiteChoice

    public var displayName: String {
        switch self {
        case .pendingPrerequisiteChoice: "Prerequisite choice needed"
        case .missingPrerequisite: "Prerequisite warning"
        case .missingCorequisite: "Corequisite warning"
        case .labNotPaired: "Lab pairing warning"
        case .unavailableSemester: "Semester availability warning"
        case .unknownAvailability: "Availability unknown"
        case .heavyLoad: "Heavy load warning"
        case .lightLoad: "Light load warning"
        }
    }

    public var severity: ConflictSeverity {
        switch self {
        case .missingPrerequisite, .unavailableSemester, .labNotPaired: .mustFix
        case .missingCorequisite, .heavyLoad, .lightLoad, .pendingPrerequisiteChoice: .worthALook
        case .unknownAvailability: .hidden
        }
    }

    public var title: String {
        switch self {
        case .missingPrerequisite: "Missing prerequisite"
        case .missingCorequisite: "Missing corequisite"
        case .labNotPaired: "Lab not paired"
        case .pendingPrerequisiteChoice: "Prerequisite choice needed"
        case .unavailableSemester: "Not offered this term"
        case .unknownAvailability: "Availability unknown"
        case .heavyLoad: "Heavy load"
        case .lightLoad: "Light load"
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
    public static let semesterSubjectID = "__semester__"
    public var id: String
    public var courseID: String
    public var semester: SemesterIdentity
    public var kind: ConflictKind
    public var message: String
    public var isOverridden: Bool
    public var summary: String
    public var detail: String
    public var notes: [String]
    public var missingCourseIDs: [String]

    public var isSemesterLevel: Bool { courseID == Self.semesterSubjectID }

    public init(courseID: String, semester: SemesterIdentity, kind: ConflictKind, summary: String, detail: String, notes: [String] = [], missingCourseIDs: [String] = [], isOverridden: Bool) {
        self.id = "\(courseID)-\(semester.year)-\(semester.term.rawValue)-\(kind.rawValue)"
        self.courseID = courseID
        self.semester = semester
        self.kind = kind
        self.summary = summary
        self.detail = detail
        self.notes = notes
        self.missingCourseIDs = missingCourseIDs
        self.message = ([detail] + notes).joined(separator: " ")
        self.isOverridden = isOverridden
    }

    public init(courseID: String, semester: SemesterIdentity, kind: ConflictKind, message: String, isOverridden: Bool) {
        self.init(courseID: courseID, semester: semester, kind: kind, summary: message, detail: message, isOverridden: isOverridden)
    }

    private enum CodingKeys: String, CodingKey {
        case id, courseID, semester, kind, message, isOverridden, summary, detail, notes, missingCourseIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        courseID = try c.decode(String.self, forKey: .courseID)
        semester = try c.decode(SemesterIdentity.self, forKey: .semester)
        kind = try c.decode(ConflictKind.self, forKey: .kind)
        message = try c.decode(String.self, forKey: .message)
        isOverridden = try c.decode(Bool.self, forKey: .isOverridden)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? message
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? message
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
        missingCourseIDs = try c.decodeIfPresent([String].self, forKey: .missingCourseIDs) ?? []
    }
}

/// Evaluates whether a `PrereqExpr` is satisfied given the set of courses
/// the student has completed before this term (`completedBefore`) and the
/// set scheduled in the same term (`scheduledThisTerm`). Prereq mode only
/// honors `completedBefore`; coreq mode honors their union. `standing` is the
/// term's class standing; when nil, standing requirements are not enforced.
public struct PrereqEvaluator: Sendable {
    public enum Mode: Sendable { case prereq, coreq }
    public enum Outcome: Sendable, Equatable {
        case satisfied
        case unmet(missing: PrereqExpr, original: PrereqExpr)
    }

    public let completedBefore: Set<String>
    public let scheduledThisTerm: Set<String>
    public let standing: ClassStanding?

    public init(completedBefore: Set<String>, scheduledThisTerm: Set<String>, standing: ClassStanding? = nil) {
        self.completedBefore = completedBefore
        self.scheduledThisTerm = scheduledThisTerm
        self.standing = standing
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
        case .standing(let requirement):
            guard let standing else { return .empty }
            return requirement.isSatisfied(by: standing) ? .empty : expr
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
        activeProgramTitle: String? = nil,
        completedAtStart: Set<String> = [],
        workload: WorkloadPreference? = nil,
        earnedHoursAtStart: Double? = nil,
        prerequisiteAnalysis: PlaceholderPrerequisiteAnalysis? = nil
    ) -> [ConflictWarning] {
        let coursesByID = catalog.coursesByID
        // Seed with courses already banked before the first semester — AP and
        // dual-enrollment transfer credits. Without this the detector raises
        // false prereq warnings for chains the student already started in
        // high school (e.g., AP Calculus awarding MATH 231/232).
        var completedBefore = completedAtStart
        var warnings: [ConflictWarning] = []
        let resolver = PrereqRuleResolver(catalog: catalog)
        let labPairing = LabPairing(catalog: catalog, activeProgramTitle: activeProgramTitle)

        let orderedSemesters = pathway.semesters.sorted(by: { $0.id < $1.id })
        // Class standing counts semesters by their place in the plan, so a
        // deleted semester is one the student doesn't attend. Trailing empty
        // semesters aren't part of the plan yet and don't lengthen it.
        let planLength = (orderedSemesters.lastIndex { !$0.courseIDs.isEmpty } ?? -1) + 1
        let standings = Self.standings(
            for: pathway, catalog: catalog, completedAtStart: completedAtStart, earnedHoursAtStart: earnedHoursAtStart
        )
        // Which unresolved slots can supply what courses still need. A
        // dependency only stops being a conflict when its route is proven.
        let analysis = prerequisiteAnalysis ?? placeholderPrerequisiteAnalysis(
            for: pathway, activeProgramTitle: activeProgramTitle, completedAtStart: completedAtStart,
            workload: workload, earnedHoursAtStart: earnedHoursAtStart
        ) ?? .empty
        func status(_ courseID: String, _ semester: SemesterIdentity, _ kind: ConditionalDependencyKind) -> ConditionalPrerequisiteStatus? {
            analysis.statusByDependency[ConditionalDependencyKey(courseID: courseID, semester: semester, kind: kind)]
        }
        let unconfirmedNote = "A placeholder choice might supply this, but the planner couldn't confirm it. Choose a course for an earlier placeholder or regenerate the schedule."
        for (index, semester) in orderedSemesters.enumerated() {
            let realInThisTerm = Set(semester.courseIDs.filter { !PathwayPlaceholder.isPlaceholder($0) })
            let standing = standings[semester.id] ?? ClassStanding.forSemester(position: index + 1, totalSemesters: planLength)
            let evaluator = PrereqEvaluator(completedBefore: completedBefore, scheduledThisTerm: realInThisTerm, standing: standing)

            for courseID in semester.courseIDs where !PathwayPlaceholder.isPlaceholder(courseID) {
                guard let course = coursesByID[courseID] else { continue }

                if course.availability == nil {
                    warnings.append(warning(
                        courseID: courseID,
                        semester: semester.id,
                        kind: .unknownAvailability,
                        summary: "Availability unknown",
                        detail: "\(course.code) does not have verified semester availability in the local catalog cache.",
                        overrides: overrides
                    ))
                } else if let availability = course.availability, !availability.contains(semester.term) {
                    warnings.append(warning(
                        courseID: courseID,
                        semester: semester.id,
                        kind: .unavailableSemester,
                        summary: "Not offered in \(semester.term.rawValue)",
                        detail: "\(course.code) is not marked as typically offered in \(semester.term.rawValue).",
                        overrides: overrides
                    ))
                }

                let resolvedRule = resolver.rule(for: course, activeProgramTitle: activeProgramTitle)
                let labs = labPairing.labOptions(forLecture: courseID)
                let lectures = labPairing.lectures(forLab: courseID)
                // A lecture and its lab are taken together, so neither is the
                // other's prerequisite; the lab-pairing check covers them.
                let pairedCourses = Set(labs + lectures)
                if case .unmet(let missing, let original) = evaluator.evaluate(resolvedRule.prerequisiteExpr.treatingAsSatisfied(pairedCourses), mode: .prereq),
                   status(courseID, semester.id, .prerequisite) != .conditional {
                    var text = Self.prereqText(
                        original: original,
                        missing: missing,
                        hasUnknown: resolvedRule.hasUnknownTokens,
                        confidence: resolvedRule.confidence,
                        catalogNotes: resolvedRule.notes,
                        coursesByID: coursesByID,
                        satisfied: completedBefore,
                        standingNote: "\(semester.id.displayName) counts as \(standing.displayName) standing (semester \(index + 1) of \(planLength))."
                    )
                    if status(courseID, semester.id, .prerequisite) == .unconfirmed {
                        text.notes.append(unconfirmedNote)
                    }
                    warnings.append(warning(
                        courseID: courseID,
                        semester: semester.id,
                        kind: .missingPrerequisite,
                        summary: text.summary,
                        detail: text.detail,
                        notes: text.notes,
                        missingCourseIDs: Self.collectCourseLeaves(missing),
                        overrides: overrides
                    ))
                }

                // A lecture and its lab must share the semester, which the
                // "alongside or before" coreq check would let slide; the
                // lab-pairing check below covers them instead.
                let itemsThisTerm = Set(semester.courseIDs)
                let labStatus = status(courseID, semester.id, .labPairing)
                let labNotes = labStatus == .unconfirmed ? [unconfirmedNote] : []
                if !labs.isEmpty,
                   !labs.contains(where: itemsThisTerm.contains),
                   !itemsThisTerm.contains(LabPairing.labPlaceholderID(forLecture: courseID)),
                   labStatus != .conditional {
                    let names = labs.map { coursesByID[$0]?.code ?? $0 }.joined(separator: " or ")
                    warnings.append(warning(
                        courseID: courseID,
                        semester: semester.id,
                        kind: .labNotPaired,
                        summary: "Needs \(names) this term",
                        detail: "Take \(names) in \(semester.id.displayName), the same semester as \(course.code).",
                        notes: labNotes,
                        missingCourseIDs: labs,
                        overrides: overrides
                    ))
                }
                if !lectures.isEmpty, !lectures.contains(where: itemsThisTerm.contains), labStatus != .conditional {
                    let names = lectures.map { coursesByID[$0]?.code ?? $0 }.joined(separator: " or ")
                    warnings.append(warning(
                        courseID: courseID,
                        semester: semester.id,
                        kind: .labNotPaired,
                        summary: "Take with \(names)",
                        detail: "Take \(course.code) in the same semester as \(names).",
                        notes: labNotes,
                        missingCourseIDs: lectures,
                        overrides: overrides
                    ))
                }
                let corequisites = resolvedRule.corequisiteExpr.treatingAsSatisfied(pairedCourses)

                if case .unmet(let missing, _) = evaluator.evaluate(corequisites, mode: .coreq),
                   status(courseID, semester.id, .corequisite) != .conditional {
                    let rendered = missing.displayString(coursesByID: coursesByID)
                    warnings.append(warning(
                        courseID: courseID,
                        semester: semester.id,
                        kind: .missingCorequisite,
                        summary: "Take with \(rendered)",
                        detail: "Take alongside or before this course: \(rendered).",
                        notes: status(courseID, semester.id, .corequisite) == .unconfirmed ? [unconfirmedNote] : [],
                        missingCourseIDs: Self.collectCourseLeaves(missing),
                        overrides: overrides
                    ))
                }
            }
            completedBefore.formUnion(realInThisTerm)
        }
        warnings += pendingChoiceNotices(for: pathway, analysis: analysis, orderedSemesters: orderedSemesters)

        if let workload {
            warnings += loadWarnings(for: pathway, workload: workload, overrides: overrides)
        }
        return warnings
    }

    public static let fullTimeCredits = 12

    /// The conditional placeholder analysis these warnings use, with the
    /// same standing and history context. Nil when it can't finish (for
    /// example, when cancelled); callers then keep ordinary conflicts.
    public func placeholderPrerequisiteAnalysis(
        for pathway: Pathway,
        activeProgramTitle: String? = nil,
        completedAtStart: Set<String> = [],
        workload: WorkloadPreference? = nil,
        earnedHoursAtStart: Double? = nil
    ) -> PlaceholderPrerequisiteAnalysis? {
        let hasOpenSlot = pathway.semesters.contains { semester in
            semester.courseIDs.contains { PathwayPlaceholder.isPlaceholder($0) && pathway.placeholders[$0] != nil }
        }
        guard hasOpenSlot else { return .empty }
        let input = ConditionalPrerequisiteInput(
            pathway: pathway,
            completedAtStart: completedAtStart,
            standingBySemester: Self.standings(for: pathway, catalog: catalog, completedAtStart: completedAtStart, earnedHoursAtStart: earnedHoursAtStart),
            workload: workload,
            activeProgramTitle: activeProgramTitle
        )
        return try? PlaceholderPrerequisiteAnalyzer(catalog: catalog).analyze(input)
    }

    /// Each semester's class standing: from earned hours when known,
    /// otherwise from its place in the plan.
    static func standings(
        for pathway: Pathway,
        catalog: Catalog,
        completedAtStart: Set<String>,
        earnedHoursAtStart: Double?
    ) -> [SemesterIdentity: ClassStanding] {
        let ordered = pathway.semesters.sorted { $0.id < $1.id }
        let planLength = (ordered.lastIndex { !$0.courseIDs.isEmpty } ?? -1) + 1
        var credits = earnedHoursAtStart.map { PlannedCreditAccumulator(hours: $0, completedCourseIDs: completedAtStart) }
        var result: [SemesterIdentity: ClassStanding] = [:]
        for (index, semester) in ordered.enumerated() {
            result[semester.id] = credits.map { ClassStanding.forEarnedCredits($0.hours) }
                ?? ClassStanding.forSemester(position: index + 1, totalSemesters: planLength)
            credits?.include(semester, placeholders: pathway.placeholders, catalog: catalog)
        }
        return result
    }

    /// One notice per unresolved slot later courses count on, naming the
    /// choices that would support them. Never kept: it explains, it isn't a
    /// conflict.
    private func pendingChoiceNotices(
        for pathway: Pathway,
        analysis: PlaceholderPrerequisiteAnalysis,
        orderedSemesters: [SemesterPlan]
    ) -> [ConflictWarning] {
        let coursesByID = catalog.coursesByID
        func code(_ courseID: String) -> String { coursesByID[courseID]?.code ?? courseID }
        var notices: [ConflictWarning] = []
        for semester in orderedSemesters {
            for slot in semester.courseIDs where PathwayPlaceholder.isPlaceholder(slot) {
                guard let supports = analysis.supportsByPlaceholder[slot], !supports.isEmpty else { continue }
                let sentences = PlaceholderDependencyText.choiceSentences(supports, code: code)
                notices.append(ConflictWarning(
                    courseID: slot,
                    semester: semester.id,
                    kind: .pendingPrerequisiteChoice,
                    summary: ConflictKind.pendingPrerequisiteChoice.title,
                    detail: sentences.joined(separator: " "),
                    isOverridden: false
                ))
            }
        }
        return notices
    }

    private func loadWarnings(for pathway: Pathway, workload: WorkloadPreference, overrides: [ConflictOverride]) -> [ConflictWarning] {
        let semesters = pathway.semesters.sorted { $0.id < $1.id }
        guard let lastFilled = semesters.lastIndex(where: { !$0.courseIDs.isEmpty }) else { return [] }
        let coursesByID = catalog.coursesByID
        let range = workload.creditRange
        var result: [ConflictWarning] = []
        for (index, semester) in semesters.enumerated() {
            let credits = semester.courseIDs.reduce(0.0) { total, id in
                if PathwayPlaceholder.isPlaceholder(id) {
                    return total + (pathway.placeholders[id]?.credits ?? 0)
                }
                return total + (semester.creditOverrides[id] ?? Double(coursesByID[id]?.credits ?? 0))
            }
            if credits > Double(range.upperBound + 2) {
                result.append(warning(
                    courseID: ConflictWarning.semesterSubjectID,
                    semester: semester.id,
                    kind: .heavyLoad,
                    summary: "Heavy load (\(CreditHoursFormatter.string(credits)) cr)",
                    detail: "\(CreditHoursFormatter.string(credits)) credits is above your \(workload.rawValue) load (\(range.lowerBound)–\(range.upperBound)).",
                    overrides: overrides
                ))
            } else if credits < Double(Self.fullTimeCredits), index < lastFilled {
                result.append(warning(
                    courseID: ConflictWarning.semesterSubjectID,
                    semester: semester.id,
                    kind: .lightLoad,
                    summary: "Light load (\(CreditHoursFormatter.string(credits)) cr)",
                    detail: "\(CreditHoursFormatter.string(credits)) credits is below full-time (\(Self.fullTimeCredits)).",
                    overrides: overrides
                ))
            }
        }
        return result
    }

    private static func prereqText(
        original: PrereqExpr,
        missing: PrereqExpr,
        hasUnknown: Bool,
        confidence: PrereqRuleConfidence,
        catalogNotes: String?,
        coursesByID: [String: Course],
        satisfied: Set<String>,
        standingNote: String
    ) -> (summary: String, detail: String, notes: [String]) {
        let originalText = original.displayString(coursesByID: coursesByID)
        let missingText = missing.displayString(coursesByID: coursesByID)
        let satisfiedLeaves = collectCourseLeaves(original).filter { satisfied.contains($0) }
        let satisfiedText = satisfiedLeaves.compactMap { coursesByID[$0]?.code ?? $0 }.joined(separator: ", ")
        var detail = "Needs \(originalText)."
        if !satisfiedText.isEmpty {
            detail += " You have \(satisfiedText);"
        }
        detail += " still missing \(missingText)."
        var notes: [String] = []
        if missing.containsStanding {
            notes.append(standingNote)
        }
        if hasUnknown {
            notes.append("Some prereqs couldn't be parsed; verify with the catalog.")
        }
        if confidence == .parsed {
            notes.append("Parsed from catalog text; verify before registering.")
        }
        if let note = catalogNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            notes.append("Catalog note: \(note)")
        }
        return ("Needs \(missingText)", detail, notes)
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

    private func warning(courseID: String, semester: SemesterIdentity, kind: ConflictKind, summary: String, detail: String, notes: [String] = [], missingCourseIDs: [String] = [], overrides: [ConflictOverride]) -> ConflictWarning {
        let isOverridden = overrides.contains { $0.courseID == courseID && $0.semester == semester && $0.kind == kind }
        return ConflictWarning(courseID: courseID, semester: semester, kind: kind, summary: summary, detail: detail, notes: notes, missingCourseIDs: missingCourseIDs, isOverridden: isOverridden)
    }
}

public struct CategoryProgress: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var completedCredits: Double
    public var requiredCredits: Int
    public var verificationStatus: VerificationStatus

    public var remainingCredits: Double {
        max(Double(requiredCredits) - completedCredits, 0)
    }

    public var fraction: Double {
        guard requiredCredits > 0 else { return 1 }
        return min(Double(completedCredits) / Double(requiredCredits), 1)
    }
}

public struct GraduationProgress: Codable, Hashable, Sendable {
    public var categories: [CategoryProgress]
    public var projectedGraduation: SemesterIdentity?
    public var earnedHours: Double = 0
    public var projectedHours: Double = 0
    public init(categories: [CategoryProgress], projectedGraduation: SemesterIdentity?, earnedHours: Double = 0, projectedHours: Double = 0) {
        self.categories = categories; self.projectedGraduation = projectedGraduation
        self.earnedHours = earnedHours; self.projectedHours = projectedHours
    }
    private enum CodingKeys: String, CodingKey { case categories, projectedGraduation, earnedHours, projectedHours }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = try c.decode([CategoryProgress].self, forKey: .categories)
        projectedGraduation = try c.decodeIfPresent(SemesterIdentity.self, forKey: .projectedGraduation)
        earnedHours = try c.decodeIfPresent(Double.self, forKey: .earnedHours) ?? 0
        projectedHours = try c.decodeIfPresent(Double.self, forKey: .projectedHours) ?? 0
    }

    public var overallCompletedCredits: Double {
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
            // Each course fills at most one option, so slots sharing a menu
            // ("choose two", elective pools) need different courses. Options
            // with the shortest menus claim their course first.
            var consumed: Set<String> = []
            let completedCredits = category.courseOptions
                .sorted { $0.count < $1.count }
                .reduce(0.0) { total, options in
                    if TransferCreditMapper.genEdCreditSatisfies(category: category, completedCourseIDs: completedCourseIDs) {
                        return total + Double(max(category.requiredCredits / max(category.courseOptions.count, 1), 1))
                    }
                    guard let completed = options.first(where: { completedCourseIDs.contains($0) && !consumed.contains($0) }),
                          let course = coursesByID[completed] else {
                        return total
                    }
                    consumed.insert(completed)
                    let earned = transferCredits.first { $0.courseIDs == [completed] }?.credits
                    let enrolled = pathway.semesters.first { $0.courseIDs.contains(completed) }?.creditOverrides[completed]
                    return total + (earned ?? enrolled ?? Double(course.credits))
                }
            let id = idPrefix.isEmpty ? category.id : "\(idPrefix)::\(category.id)"
            let name = namePrefix.isEmpty ? category.name : "\(namePrefix): \(category.name)"
            return CategoryProgress(
                id: id,
                name: name,
                completedCredits: min(completedCredits, Double(category.requiredCredits)),
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
        // primary major's declared requirements (plus any minor / second-major
        // credits) and the JMU degree minimum.
        // Completion ticks up as the user resolves each Open Elective
        // placeholder slot (the resolved credits stop appearing in
        // pathway.placeholders).
        let openElectiveGap = ScheduleGenerator(catalog: catalog)
            .openElectiveGap(for: effectiveProgram, additionalPrograms: additionalPrograms)
        if openElectiveGap > 0 {
            let resolvedIDs = Set(pathway.resolvedPlaceholders.keys)
            let unresolvedOpenElectiveCredits = pathway.placeholders
                .filter { id, spec in
                    spec.categoryID == ScheduleGenerator.openElectiveCategoryID
                        && !resolvedIDs.contains(id)
                }
                .reduce(0) { $0 + $1.value.credits }
            let completedOpenElectiveCredits = max(0, Double(openElectiveGap) - unresolvedOpenElectiveCredits)
            categories.append(CategoryProgress(
                id: ScheduleGenerator.openElectiveCategoryID,
                name: "Open Electives",
                completedCredits: min(completedOpenElectiveCredits, Double(openElectiveGap)),
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

        let history = AcademicHistory(records: [], currentSemester: nil, effectiveCredits: transferCredits, earnedHours: transferCredits.reduce(0) { $0 + $1.credits })
        let totals = AcademicCreditCalculator.totals(history: history, pathway: pathway, catalog: catalog)
        return GraduationProgress(categories: categories, projectedGraduation: pathway.projectedGraduation, earnedHours: totals.earnedHours, projectedHours: totals.projectedHours)
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
        // A concentration row can share a major row's ID (both named after
        // "Choose one of the following:"). Its placeholders would reuse the
        // major's slot IDs and drop out of the schedule, so it takes the
        // concentration's name as a prefix. Major IDs never change.
        var takenIDs = Set(requirements.map(\.id))
        let concentrationRequirements = concentration.requirements.map { category in
            var category = category
            if takenIDs.contains(category.id) {
                let base = "\(concentration.id)-\(category.id)"
                var candidate = base
                var suffix = 2
                while takenIDs.contains(candidate) || concentration.requirements.contains(where: { $0.id == candidate }) {
                    candidate = "\(base)-\(suffix)"
                    suffix += 1
                }
                category.id = candidate
            }
            takenIDs.insert(category.id)
            return category
        }
        effective.requirements = requirements + concentrationRequirements
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
