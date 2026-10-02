import Foundation

enum PrereqToken: Equatable {
    case courseRef(String)
    case unknown(String)
    case and
    case or
    case lparen
    case rparen
    case comma
    case semicolon
}

enum PrereqLexer {
    private static let coursePattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"^[A-Z]{2,5}\s+\d{3}[A-Z]?"#)
    }()

    static func tokenize(_ input: String) -> [PrereqToken] {
        var tokens: [PrereqToken] = []
        var unknownBuffer = ""
        var i = input.startIndex

        func flushUnknown() {
            let trimmed = unknownBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
            if !trimmed.isEmpty {
                tokens.append(.unknown(trimmed))
            }
            unknownBuffer = ""
        }

        while i < input.endIndex {
            let ch = input[i]
            if ch.isWhitespace {
                if !unknownBuffer.isEmpty { unknownBuffer.append(" ") }
                i = input.index(after: i)
                continue
            }
            if ch == "(" {
                flushUnknown(); tokens.append(.lparen); i = input.index(after: i); continue
            }
            if ch == ")" {
                flushUnknown(); tokens.append(.rparen); i = input.index(after: i); continue
            }
            if ch == "," {
                flushUnknown(); tokens.append(.comma); i = input.index(after: i); continue
            }
            if ch == ";" {
                flushUnknown(); tokens.append(.semicolon); i = input.index(after: i); continue
            }
            if ch == "." {
                // sentence-ending or abbreviation: treat as a token separator
                flushUnknown()
                i = input.index(after: i)
                continue
            }

            // course-ref match anchored at i
            let remainder = String(input[i...])
            if let match = coursePattern.firstMatch(in: remainder, range: NSRange(remainder.startIndex..., in: remainder)) {
                let range = Range(match.range, in: remainder)!
                let raw = String(remainder[range])
                let code = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                flushUnknown()
                tokens.append(.courseRef(code))
                i = input.index(i, offsetBy: remainder.distance(from: remainder.startIndex, to: range.upperBound))
                continue
            }

            // keyword detection
            if ch.isLetter, let kw = readWord(from: input, at: i) {
                let lower = kw.word.lowercased()
                if lower == "and" {
                    flushUnknown(); tokens.append(.and)
                } else if lower == "or" {
                    flushUnknown(); tokens.append(.or)
                } else {
                    if !unknownBuffer.isEmpty, !unknownBuffer.hasSuffix(" ") {
                        unknownBuffer.append(" ")
                    }
                    unknownBuffer += kw.word
                }
                i = kw.end
                continue
            }

            unknownBuffer.append(ch)
            i = input.index(after: i)
        }
        flushUnknown()
        return tokens
    }

    private static func readWord(from s: String, at start: String.Index) -> (word: String, end: String.Index)? {
        var end = start
        while end < s.endIndex, s[end].isLetter { end = s.index(after: end) }
        guard end > start else { return nil }
        return (String(s[start..<end]), end)
    }
}

public struct ParseResult: Sendable, Equatable {
    public var prerequisiteExpr: PrereqExpr
    public var corequisiteExpr: PrereqExpr
    public var hasUnknownTokens: Bool

    public init(prerequisiteExpr: PrereqExpr = .empty,
                corequisiteExpr: PrereqExpr = .empty,
                hasUnknownTokens: Bool = false) {
        self.prerequisiteExpr = prerequisiteExpr
        self.corequisiteExpr = corequisiteExpr
        self.hasUnknownTokens = hasUnknownTokens
    }
}

public struct PrereqParser: Sendable {
    struct CourseIndex: Sendable {
        let codeToID: [String: String]

        init(coursesByID: [String: Course]) {
            var map: [String: String] = [:]
            for (id, course) in coursesByID {
                map[PrereqParser.normalizeCode(course.code)] = id
            }
            self.codeToID = map
        }
    }

    private let codeToID: [String: String]   // normalized "CS 159" → "cs-159"
    private let activeProgramTitle: String?

    public init(coursesByID: [String: Course], activeProgramTitle: String? = nil) {
        self.init(index: CourseIndex(coursesByID: coursesByID), activeProgramTitle: activeProgramTitle)
    }

    init(index: CourseIndex, activeProgramTitle: String? = nil) {
        self.codeToID = index.codeToID
        self.activeProgramTitle = activeProgramTitle
    }

    public func parse(_ text: String?) -> ParseResult {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ParseResult()
        }
        let (prereqText, coreqText) = Self.splitCoreq(text)
        var hasUnknown = false
        let prereq = parseSegment(prereqText, hasUnknown: &hasUnknown)
        let coreq = parseSegment(coreqText, hasUnknown: &hasUnknown)
        return ParseResult(prerequisiteExpr: prereq, corequisiteExpr: coreq, hasUnknownTokens: hasUnknown)
    }

    private func parseSegment(_ text: String, hasUnknown: inout Bool) -> PrereqExpr {
        guard !text.isEmpty else { return .empty }
        let prepared = Self.prepareSegment(text, activeProgramTitle: activeProgramTitle)
        guard !prepared.text.isEmpty else { return .empty }
        let rawTokens = PrereqLexer.tokenize(prepared.text)
        let resolved: [PrereqToken] = rawTokens.map { token in
            if case .courseRef(let raw) = token {
                let key = Self.normalizeCode(raw)
                if let id = codeToID[key] {
                    return .courseRef(id)
                }
                return .unknown(raw)
            }
            return token
        }
        let expr: PrereqExpr
        switch prepared.mode {
        case .normal:
            var index = 0
            expr = parseExpr(resolved, &index)
        case .choiceList:
            expr = parseChoiceList(resolved)
        }
        var standingResidue = false
        var normalized = Self.normalize(Self.extractStanding(from: expr, residue: &standingResidue))
        // The grammar stops at text it can't connect ("majors only. Junior
        // standing"), dropping what follows. A standing named anywhere in
        // the segment is still a requirement, so AND it on and flag the
        // segment as only partly understood.
        if !normalized.containsStanding,
           let requirement = Self.standingRequirement(in: prepared.clauseText) {
            normalized = Self.normalize(.all([normalized, .standing(requirement)]))
            standingResidue = true
        }
        if standingResidue || Self.containsUnknown(normalized) { hasUnknown = true }
        return normalized
    }

    private enum SegmentMode {
        case normal
        case choiceList
    }

    private struct PreparedSegment {
        var text: String
        var mode: SegmentMode
        /// The applicable clause before choice-list / grade trimming, which
        /// can cut away a standing phrase ("Senior standing and one of the
        /// following ...").
        var clauseText: String = ""
    }

    /// Semicolons separate clauses and bind loosest: "A or B; and C or D"
    /// is (A or B) and (C or D). A clause opening with "or" ("; or
    /// permission of the instructor") is an alternative to everything
    /// before it.
    private func parseExpr(_ tokens: [PrereqToken], _ i: inout Int) -> PrereqExpr {
        var result = parseOr(tokens, &i)
        while i < tokens.count, case .semicolon = tokens[i] {
            i += 1
            var isAlternative = false
            if i < tokens.count, case .and = tokens[i] {
                i += 1
            } else if i < tokens.count, case .or = tokens[i] {
                i += 1
                isAlternative = true
            }
            let next = parseOr(tokens, &i)
            result = isAlternative ? .any([result, next]) : .all([result, next])
        }
        return result
    }

    private func parseOr(_ tokens: [PrereqToken], _ i: inout Int) -> PrereqExpr {
        var children = [parseAnd(tokens, &i)]
        while i < tokens.count, case .or = tokens[i] {
            i += 1
            children.append(parseAnd(tokens, &i))
        }
        return children.count == 1 ? children[0] : .any(children)
    }

    private func parseAnd(_ tokens: [PrereqToken], _ i: inout Int) -> PrereqExpr {
        var children = [parseTerm(tokens, &i)]
        loop: while i < tokens.count {
            switch tokens[i] {
            case .and, .comma:
                i += 1
                // Oxford comma: ", and X" is one separator, not an empty term.
                if i < tokens.count, case .and = tokens[i] { i += 1 }
                children.append(parseTerm(tokens, &i))
            default:
                break loop
            }
        }
        return children.count == 1 ? children[0] : .all(children)
    }

    private func parseTerm(_ tokens: [PrereqToken], _ i: inout Int) -> PrereqExpr {
        guard i < tokens.count else { return .empty }
        switch tokens[i] {
        case .lparen:
            i += 1
            let inner = parseExpr(tokens, &i)
            if i < tokens.count, case .rparen = tokens[i] { i += 1 }
            return inner
        case .courseRef(let id):
            i += 1
            return .course(id)
        case .unknown(let text):
            i += 1
            return .unknown(text)
        default:
            i += 1
            return .empty
        }
    }

    private func parseChoiceList(_ tokens: [PrereqToken]) -> PrereqExpr {
        let children: [PrereqExpr] = tokens.compactMap { token in
            switch token {
            case .courseRef(let id):
                return .course(id)
            case .unknown(let text):
                return .unknown(text)
            default:
                return nil
            }
        }
        if children.isEmpty { return .empty }
        if children.count == 1 { return children[0] }
        return .any(children)
    }

    private static let coreqMarkers: [String] = [
        "corequisite(s):", "corequisites:", "corequisite:"
    ]

    private static func splitCoreq(_ text: String) -> (String, String) {
        let lower = text.lowercased()
        for marker in coreqMarkers {
            if let range = lower.range(of: marker) {
                let prefixDistance = lower.distance(from: lower.startIndex, to: range.lowerBound)
                let suffixDistance = lower.distance(from: lower.startIndex, to: range.upperBound)
                let prefix = text.prefix(prefixDistance)
                let suffix = text[text.index(text.startIndex, offsetBy: suffixDistance)...]
                return (
                    String(prefix).trimmingCharacters(in: .whitespacesAndNewlines),
                    String(suffix).trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    private static let leadingHeaders: [String] = [
        "prerequisite(s):", "prerequisites:", "prerequisite:"
    ]

    private static func stripLeadingHeader(_ text: String) -> String {
        let lower = text.lowercased()
        for header in leadingHeaders where lower.hasPrefix(header) {
            return String(text.dropFirst(header.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func prepareSegment(_ text: String, activeProgramTitle: String?) -> PreparedSegment {
        let withoutHeader = normalizeStandingPhrases(in: stripLeadingHeader(text))
        let conditional = selectApplicableMajorClause(in: withoutHeader, activeProgramTitle: activeProgramTitle)
        var gradeAdjusted = stripGradeQualifier(from: conditional)
        gradeAdjusted.clauseText = conditional
        return gradeAdjusted
    }

    private static let oneOfFollowingPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?i)\bone\s+of\s+the\s+following(?:\s+courses?)?\s*:?\s*"#)
    }()

    private static let gradeQualifierPatterns: [NSRegularExpression] = [
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?i)\b(?:with\s+)?(?:a\s+)?(?:minimum\s+)?grade\s+of\s+["“”']?[A-F][+-]?["“”']?\s+or\s+better\s+in\s+"#),
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?i)\b[A-F][+-]?\s+or\s+better\s+in\s+"#)
    ]

    private static let trailingEquivalentPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(?i)\s+or\s+(?:(?:an?|the)\s+)?equivalent(?:\s+course)?\s*\.?\s*$"#
        )
    }()

    private static func stripGradeQualifier(from text: String) -> PreparedSegment {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = firstRange(of: oneOfFollowingPattern, in: trimmed) {
            let suffix = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return PreparedSegment(text: String(suffix), mode: .choiceList)
        }

        var cleaned = trimmed
        for pattern in gradeQualifierPatterns {
            cleaned = pattern.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }
        if let choiceList = equivalentChoiceList(in: cleaned) {
            return PreparedSegment(text: choiceList, mode: .choiceList)
        }
        return PreparedSegment(text: cleaned.trimmingCharacters(in: .whitespacesAndNewlines), mode: .normal)
    }

    /// JMU uses comma-only lists followed by "or equivalent" to mean any one
    /// listed course is sufficient. Keep ordinary comma lists conjunctive and
    /// only opt into choice-list parsing when the prefix contains course refs
    /// separated solely by commas.
    private static func equivalentChoiceList(in text: String) -> String? {
        guard let match = trailingEquivalentPattern.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ), let range = Range(match.range, in: text) else {
            return nil
        }

        let prefix = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = PrereqLexer.tokenize(prefix)
        let courseCount = tokens.reduce(into: 0) { count, token in
            if case .courseRef = token { count += 1 }
        }
        guard courseCount >= 2, tokens.contains(.comma) else { return nil }
        guard tokens.allSatisfy({ token in
            if case .courseRef = token { return true }
            if case .comma = token { return true }
            return false
        }) else {
            return nil
        }
        return prefix
    }

    private struct MajorClause {
        var isNonMajor: Bool
        /// "For X minors:" clauses only bound the clause before them; the
        /// active program is always a major, so they are never selected.
        var isMinor: Bool
        var label: String
        var body: String
    }

    private static let majorClausePattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?i)\bfor\s+(non[-\s]+)?(.+?)\s+(majors?|minors?)\s*:"#)
    }()

    private static func selectApplicableMajorClause(in text: String, activeProgramTitle: String?) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = majorClausePattern.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        guard !matches.isEmpty else { return trimmed }

        let firstRange = Range(matches[0].range, in: trimmed)!
        let commonPrefix = String(trimmed[..<firstRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let clauses: [MajorClause] = matches.enumerated().compactMap { index, match in
            guard let markerRange = Range(match.range, in: trimmed),
                  let labelRange = Range(match.range(at: 2), in: trimmed) else { return nil }
            let nextStart = index + 1 < matches.count
                ? Range(matches[index + 1].range, in: trimmed)!.lowerBound
                : trimmed.endIndex
            let body = String(trimmed[markerRange.upperBound..<nextStart])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let isNonMajor = match.range(at: 1).location != NSNotFound
            let isMinor = Range(match.range(at: 3), in: trimmed)
                .map { trimmed[$0].lowercased().hasPrefix("minor") } ?? false
            return MajorClause(
                isNonMajor: isNonMajor,
                isMinor: isMinor,
                label: String(trimmed[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                body: body
            )
        }

        let active = activeProgramTitle.map(normalizeProgramMatchText)
        let selectable = clauses.filter { !$0.isMinor }
        let selected: MajorClause?
        if let active,
           let matchingMajor = selectable.first(where: { !$0.isNonMajor && program(active, matches: $0.label) }) {
            selected = matchingMajor
        } else if let active,
                  let nonMajor = selectable.first(where: { $0.isNonMajor && !program(active, matches: $0.label) }) {
            selected = nonMajor
        } else if active == nil,
                  let nonMajor = selectable.first(where: \.isNonMajor) {
            selected = nonMajor
        } else {
            selected = nil
        }

        let selectedBody = selected?.body ?? ""
        return [commonPrefix, selectedBody]
            .filter { !$0.isEmpty }
            .joined(separator: "; ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func program(_ normalizedProgram: String, matches label: String) -> Bool {
        let normalizedLabel = normalizeProgramMatchText(label)
        guard !normalizedProgram.isEmpty, !normalizedLabel.isEmpty else { return false }
        return normalizedProgram.contains(normalizedLabel) || normalizedLabel.contains(normalizedProgram)
    }

    private static func normalizeProgramMatchText(_ text: String) -> String {
        let beforeDegree = text.split(separator: ",", maxSplits: 1).first.map(String.init) ?? text
        let lowered = beforeDegree.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
        let stopWords: Set<String> = ["major", "majors", "student", "students", "non"]
        return lowered
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !stopWords.contains($0) }
            .joined(separator: " ")
    }

    // MARK: Class standing

    /// One class level as catalogs write it: "junior", "Juniors", "jr",
    /// "First-year" (which the lexer turns into "First- year"), "First year
    /// students", "freshmen". Non-capturing so callers can wrap it.
    private static let standingLevelPattern = #"(?:first[-\s]*year(?:\s+students?)?|freshm[ae]n|sophomores?|juniors?|seniors?|jr|sr)"#

    /// A level phrase only counts when it describes students: followed by
    /// "standing" / "status" / "only", or by a nearby majors / minors /
    /// students. Keeps "senior thesis" and "junior year" out.
    private static let standingContextLookahead = #"(?=\s+(?:standing|status|only)\b|\s+(?:[\w&'.-]+\s+){0,5}?(?:majors?|minors?|students?)\b)"#

    /// "Sophomore, junior and senior dance majors" / "junior or senior
    /// standing" / "jr/sr standing" → "Sophomore thru senior ...", so the
    /// lexer keeps the range in one unknown leaf instead of splitting it on
    /// commas, "and", and "or".
    private static let standingListPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?i)\b("# + standingLevelPattern + #")(?:\s*,\s*"# + standingLevelPattern + #")*\s*,?\s*(?:and|or|/|&)\s*("# + standingLevelPattern + #")\b"# + standingContextLookahead)
    }()

    /// "junior status" → "junior standing".
    private static let standingStatusPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?i)\b("# + standingLevelPattern + #")\s+status\b"#)
    }()

    /// "standing or higher/above" → "standing".
    private static let standingOrHigherPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?i)\bstanding\s+or\s+(?:higher|above)\b"#)
    }()

    /// A level, or a "thru" range of levels, inside an unknown leaf.
    private static let standingLevelRunPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?i)\b("# + standingLevelPattern + #")(?:\s+thru\s+("# + standingLevelPattern + #"))?\b"#)
    }()

    private static let standingFollowsPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?i)^\s+standing\b"#)
    }()

    private static let studentGroupFollowsPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?i)^\s+(?:[\w&'.-]+\s+){0,5}?(?:majors?|minors?|students?)\b"#)
    }()

    /// Words that can sit beside a standing phrase without adding a
    /// requirement of their own ("Students must have at least junior
    /// standing only").
    private static let standingFillerWords: Set<String> = [
        "students", "student", "must", "have", "at", "least", "only", "required", "a", "an", "the", "in", "with"
    ]

    private static func normalizeStandingPhrases(in text: String) -> String {
        var result = text
        for (pattern, template) in [
            (standingListPattern, "$1 thru $2"),
            (standingStatusPattern, "$1 standing"),
            (standingOrHigherPattern, "standing")
        ] {
            result = pattern.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: template
            )
        }
        return result
    }

    /// First standing requirement named in any sentence of `text`. Scanned
    /// sentence by sentence so an "only" in one sentence ("Non-business
    /// majors only. Junior standing") doesn't make another exact.
    private static func standingRequirement(in text: String) -> StandingRequirement? {
        for sentence in text.split(whereSeparator: { ".;".contains($0) }) {
            var ignored = false
            if case .standing(let requirement) = extractStanding(from: .unknown(String(sentence)), residue: &ignored) {
                return requirement
            }
        }
        return nil
    }

    private static func standingLevel(_ word: String) -> ClassStanding? {
        let lower = word.lowercased()
        if lower.hasPrefix("first") || lower.hasPrefix("freshm") { return .firstYear }
        if lower.hasPrefix("sophomore") { return .sophomore }
        if lower.hasPrefix("junior") || lower == "jr" { return .junior }
        if lower.hasPrefix("senior") || lower == "sr" { return .senior }
        return nil
    }

    /// "seniors", "first year students": the level word names the students
    /// themselves, so it needs no "standing" or "majors" after it.
    private static func namesStudents(_ word: String) -> Bool {
        let lower = word.lowercased()
        if lower.hasPrefix("first") { return lower.contains("student") }
        return lower.count > 2 && lower.hasSuffix("s") || lower == "freshmen"
    }

    /// The level phrase in `text` that states a standing requirement, with
    /// the range of text it covers.
    private static func standingMatch(in text: String) -> (requirement: StandingRequirement, range: Range<String.Index>)? {
        // "second-semester juniors may enroll with instructor permission"
        // grants an exception rather than stating a requirement.
        guard !text.lowercased().split(whereSeparator: { !$0.isLetter }).contains("may") else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        for match in standingLevelRunPattern.matches(in: text, range: whole) {
            guard let matchRange = Range(match.range, in: text),
                  let firstRange = Range(match.range(at: 1), in: text),
                  let first = standingLevel(String(text[firstRange]))
            else { continue }
            let lastRange = Range(match.range(at: 2), in: text)
            let second = lastRange.flatMap { standingLevel(String(text[$0])) }
            let lastWord = String(text[lastRange ?? firstRange])

            let after = String(text[matchRange.upperBound...])
            let afterRange = NSRange(after.startIndex..., in: after)
            var covered = matchRange
            if let standing = standingFollowsPattern.firstMatch(in: after, range: afterRange),
               let standingRange = Range(standing.range, in: after) {
                covered = matchRange.lowerBound..<text.index(matchRange.upperBound, offsetBy: after.distance(from: after.startIndex, to: standingRange.upperBound))
            } else if !namesStudents(lastWord),
                      studentGroupFollowsPattern.firstMatch(in: after, range: afterRange) == nil {
                continue
            }

            let requirement: StandingRequirement
            if let second {
                requirement = StandingRequirement(minimum: min(first, second), maximum: max(first, second))
            } else {
                // A lone level is that level or higher, unless the phrase
                // says "only" ("Open only to sophomore business majors").
                let saysOnly = text.lowercased()
                    .split { !$0.isLetter }
                    .contains("only")
                requirement = StandingRequirement(minimum: first, maximum: saysOnly ? first : .senior)
            }
            return (requirement, covered)
        }
        return nil
    }

    /// Replace unknown leaves that name a class standing with `.standing`
    /// leaves. Sets `residue` when a leaf held other unparsed words too
    /// ("senior standing in the IA program", "senior Finance majors"), so
    /// the course stays flagged.
    private static func extractStanding(from expr: PrereqExpr, residue: inout Bool) -> PrereqExpr {
        switch expr {
        case .unknown(let text):
            guard let match = standingMatch(in: text) else { return expr }
            var leftover = text
            leftover.removeSubrange(match.range)
            let words = leftover.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .filter { !standingFillerWords.contains(String($0)) }
            if !words.isEmpty { residue = true }
            return .standing(match.requirement)
        case .all(let children):
            return .all(children.map { extractStanding(from: $0, residue: &residue) })
        case .any(let children):
            return .any(children.map { extractStanding(from: $0, residue: &residue) })
        default:
            return expr
        }
    }

    private static func firstRange(of pattern: NSRegularExpression, in text: String) -> Range<String.Index>? {
        guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return Range(match.range, in: text)
    }

    private static func normalizeCode(_ raw: String) -> String {
        raw.uppercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsUnknown(_ expr: PrereqExpr) -> Bool {
        switch expr {
        case .unknown: return true
        case .all(let xs), .any(let xs): return xs.contains(where: containsUnknown)
        default: return false
        }
    }

    private static func normalize(_ expr: PrereqExpr) -> PrereqExpr {
        switch expr {
        case .all(let children):
            let flattened = children.flatMap { child -> [PrereqExpr] in
                let n = normalize(child)
                if case .all(let inner) = n { return inner }
                if case .empty = n { return [] }
                return [n]
            }
            if flattened.isEmpty { return .empty }
            if flattened.count == 1 { return flattened[0] }
            return .all(flattened)
        case .any(let children):
            let flattened = children.flatMap { child -> [PrereqExpr] in
                let n = normalize(child)
                if case .any(let inner) = n { return inner }
                if case .empty = n { return [] }
                return [n]
            }
            if flattened.isEmpty { return .empty }
            if flattened.count == 1 { return flattened[0] }
            return .any(flattened)
        default:
            return expr
        }
    }
}
