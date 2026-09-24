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
        let normalized = Self.normalize(expr)
        if Self.containsUnknown(normalized) { hasUnknown = true }
        return normalized
    }

    private enum SegmentMode {
        case normal
        case choiceList
    }

    private struct PreparedSegment {
        var text: String
        var mode: SegmentMode
    }

    private func parseExpr(_ tokens: [PrereqToken], _ i: inout Int) -> PrereqExpr {
        return parseOr(tokens, &i)
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
            case .and, .comma, .semicolon:
                i += 1
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
        let withoutHeader = stripLeadingHeader(text)
        let conditional = selectApplicableMajorClause(in: withoutHeader, activeProgramTitle: activeProgramTitle)
        let gradeAdjusted = stripGradeQualifier(from: conditional)
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
        var label: String
        var body: String
    }

    private static let majorClausePattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?i)\bfor\s+(non[-\s]+)?(.+?)\s+majors?\s*:"#)
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
            return MajorClause(
                isNonMajor: isNonMajor,
                label: String(trimmed[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                body: body
            )
        }

        let active = activeProgramTitle.map(normalizeProgramMatchText)
        let selected: MajorClause?
        if let active,
           let matchingMajor = clauses.first(where: { !$0.isNonMajor && program(active, matches: $0.label) }) {
            selected = matchingMajor
        } else if let active,
                  let nonMajor = clauses.first(where: { $0.isNonMajor && !program(active, matches: $0.label) }) {
            selected = nonMajor
        } else if active == nil,
                  let nonMajor = clauses.first(where: \.isNonMajor) {
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
