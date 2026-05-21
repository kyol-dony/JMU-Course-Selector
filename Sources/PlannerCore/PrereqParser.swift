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
    private let codeToID: [String: String]   // normalized "CS 159" → "cs-159"

    public init(coursesByID: [String: Course]) {
        var map: [String: String] = [:]
        for (id, course) in coursesByID {
            map[Self.normalizeCode(course.code)] = id
        }
        self.codeToID = map
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
        let stripped = Self.stripLeadingHeader(text)
        let rawTokens = PrereqLexer.tokenize(stripped)
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
        var index = 0
        let expr = parseExpr(resolved, &index)
        let normalized = Self.normalize(expr)
        if Self.containsUnknown(normalized) { hasUnknown = true }
        return normalized
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
