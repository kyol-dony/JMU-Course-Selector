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
        detailRetrievedAt: Date? = nil
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
    }
}

public struct RequirementCategory: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var requiredCredits: Int
    public var courseOptions: [[String]]
    public var verificationStatus: VerificationStatus
    public var note: String?

    public var selectionKey: String {
        "\(id)::\(name)"
    }

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
    public var verificationStatus: VerificationStatus
    public var requirementDataComplete: Bool
    public var sourceNote: String

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
        self.verificationStatus = verificationStatus
        self.requirementDataComplete = requirementDataComplete
        self.sourceNote = sourceNote
    }
}

public struct Catalog: Codable, Sendable {
    public var source: CatalogSource
    public var programs: [Program]
    public var courses: [Course]
    public var apCreditRules: [TransferCreditRule]

    public init(source: CatalogSource, programs: [Program], courses: [Course], apCreditRules: [TransferCreditRule]) {
        self.source = source
        self.programs = programs
        self.courses = courses
        self.apCreditRules = apCreditRules
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

public struct Pathway: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var semesters: [SemesterPlan]

    public init(id: String, name: String, semesters: [SemesterPlan]) {
        self.id = id
        self.name = name
        self.semesters = semesters
    }

    public var projectedGraduation: SemesterIdentity? {
        semesters.last?.id
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

    public init(catalog: Catalog) {
        self.catalog = catalog
    }

    public func generatePathways(
        for programID: String,
        concentrationID: String? = nil,
        workload: WorkloadPreference,
        transferCredits: [TransferCredit],
        starting start: SemesterIdentity = SemesterIdentity(year: Calendar.current.component(.year, from: Date()), term: .fall),
        requirementSelections: [String: [String]] = [:]
    ) throws -> [Pathway] {
        let program = try programForScheduling(programID, concentrationID: concentrationID)
        let completed = Set(transferCredits.flatMap(\.courseIDs))
        let required = requiredCourseIDs(for: program, completed: completed, requirementSelections: requirementSelections)
        guard !required.isEmpty else {
            return (1...3).map { index in
                Pathway(id: "path-\(index)", name: pathwayName(index), semesters: [])
            }
        }

        var pathways: [Pathway] = []
        let variants = [
            required,
            required.sorted { lhs, rhs in
                (catalog.coursesByID[lhs]?.credits ?? 0, lhs) > (catalog.coursesByID[rhs]?.credits ?? 0, rhs)
            },
            required.sorted()
        ]

        for (index, variant) in variants.enumerated() {
            let semesters = try buildSemesters(courseIDs: variant, completedAtStart: completed, workload: workload, starting: start)
            pathways.append(Pathway(id: "path-\(index + 1)", name: pathwayName(index + 1), semesters: semesters))
        }

        return pathways
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
        requirementSelections: [String: [String]]
    ) -> [String] {
        let completedClusterTags = Set(completed.compactMap { TransferCreditMapper.genEdCreditClusterTag(for: $0) })
        var seen: Set<String> = []
        var result: [String] = []
        for category in program.requirements {
            let categorySatisfiedByCluster = completedClusterTags.contains(where: category.name.contains)
            for option in courseOptions(for: category, requirementSelections: requirementSelections) {
                if categorySatisfiedByCluster { continue }
                if option.contains(where: completed.contains) { continue }
                guard let pick = option.first else { continue }
                if seen.insert(pick).inserted {
                    result.append(pick)
                }
            }
        }
        return result
    }

    private func courseOptions(
        for category: RequirementCategory,
        requirementSelections: [String: [String]]
    ) -> [[String]] {
        guard let selected = requirementSelections[category.selectionKey],
              !selected.isEmpty,
              category.courseOptions.contains(where: { Set($0).isSuperset(of: selected) })
        else {
            return category.courseOptions
        }
        return [selected]
    }

    private func buildSemesters(
        courseIDs: [String],
        completedAtStart: Set<String>,
        workload: WorkloadPreference,
        starting start: SemesterIdentity
    ) throws -> [SemesterPlan] {
        var remaining = courseIDs
        var completed = completedAtStart
        var semester = start
        var result: [SemesterPlan] = []
        var emptySemesterCount = 0

        while !remaining.isEmpty {
            var selected: [String] = []
            var credits = 0
            let maxCredits = workload.creditRange.upperBound

            for courseID in remaining {
                guard let course = catalog.coursesByID[courseID] else { continue }
                guard course.prerequisites.allSatisfy(completed.contains) else { continue }
                if let availability = course.availability, !availability.contains(semester.term) { continue }
                guard credits + course.credits <= maxCredits else { continue }
                selected.append(courseID)
                credits += course.credits
            }

            if selected.isEmpty {
                emptySemesterCount += 1
                guard emptySemesterCount <= 8 else {
                    throw PlannerError.impossibleSchedule("Could not place the remaining courses while respecting prerequisites and semester availability.")
                }
                semester = semester.next
                continue
            }

            result.append(SemesterPlan(id: semester, courseIDs: selected))
            remaining.removeAll { selected.contains($0) }
            completed.formUnion(selected)
            semester = semester.next
        }

        return result
    }

    private func pathwayName(_ index: Int) -> String {
        switch index {
        case 1: "Balanced Path"
        case 2: "Major-First Path"
        default: "Flexible Path"
        }
    }
}

public enum ConflictKind: String, Codable, Hashable, Sendable {
    case missingPrerequisite
    case unavailableSemester
    case unknownAvailability

    public var displayName: String {
        switch self {
        case .missingPrerequisite: "Prerequisite warning"
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

public struct ConflictDetector: Sendable {
    public var catalog: Catalog

    public init(catalog: Catalog) {
        self.catalog = catalog
    }

    public func warnings(for pathway: Pathway, overrides: [ConflictOverride]) -> [ConflictWarning] {
        let coursesByID = catalog.coursesByID
        var completed = Set<String>()
        var warnings: [ConflictWarning] = []

        for semester in pathway.semesters.sorted(by: { $0.id < $1.id }) {
            for courseID in semester.courseIDs {
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

                let missing = course.prerequisites.filter { !completed.contains($0) }
                if !missing.isEmpty {
                    warnings.append(warning(
                        courseID: courseID,
                        semester: semester.id,
                        kind: .missingPrerequisite,
                        message: "\(course.code) is scheduled before: \(missing.joined(separator: ", ")).",
                        overrides: overrides
                    ))
                }
            }
            completed.formUnion(semester.courseIDs)
        }

        return warnings
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
        requirementSelections: [String: [String]] = [:]
    ) throws -> GraduationProgress {
        guard let program = catalog.programsByID[programID] else {
            throw PlannerError.programNotFound(programID)
        }
        let effectiveProgram = try program.effectiveProgram(concentrationID: concentrationID)

        let completedCourseIDs = Set(pathway.semesters.flatMap(\.courseIDs)).union(transferCredits.flatMap(\.courseIDs))
        let coursesByID = catalog.coursesByID
        let categories = effectiveProgram.requirements.map { category in
            let completedCredits = courseOptions(for: category, requirementSelections: requirementSelections).reduce(0) { total, options in
                guard let completed = options.first(where: completedCourseIDs.contains),
                      let course = coursesByID[completed] else {
                    return total
                }
                return total + course.credits
            }
            return CategoryProgress(
                id: category.id,
                name: category.name,
                completedCredits: min(completedCredits, category.requiredCredits),
                requiredCredits: category.requiredCredits,
                verificationStatus: category.verificationStatus
            )
        }

        return GraduationProgress(categories: categories, projectedGraduation: pathway.projectedGraduation)
    }

    private func courseOptions(
        for category: RequirementCategory,
        requirementSelections: [String: [String]]
    ) -> [[String]] {
        guard let selected = requirementSelections[category.selectionKey],
              !selected.isEmpty,
              category.courseOptions.contains(where: { Set($0).isSuperset(of: selected) })
        else {
            return category.courseOptions
        }
        return [selected]
    }
}

public extension Catalog {
    static func fixture(courses: [Course], program: Program, apRules: [TransferCreditRule] = []) -> Catalog {
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
            apCreditRules: apRules
        )
    }
}

public extension Program {
    func effectiveProgram(concentrationID: String?) throws -> Program {
        guard !concentrations.isEmpty else { return self }
        guard let concentrationID else {
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
