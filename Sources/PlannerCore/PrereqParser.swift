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
    /// "/" between two course codes: a cross-listing ("CS 227 / MATH 227")
    /// or a lecture/lab pair ("BIO 240 / BIO 240L").
    case slash
    /// "either A or B": opens a choice group that binds tighter than the
    /// surrounding "and".
    case either
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
            if ch == "/", unknownBuffer.isEmpty, case .courseRef? = tokens.last {
                let next = input[input.index(after: i)...].drop(while: \.isWhitespace)
                let rest = String(next)
                if coursePattern.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)) != nil {
                    tokens.append(.slash); i = input.index(after: i); continue
                }
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
                } else if lower == "either" {
                    flushUnknown(); tokens.append(.either)
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

    static func isCourseCode(_ text: String) -> Bool {
        guard let match = coursePattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return false
        }
        return match.range.length == (text as NSString).length
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
            // The grammar stops at a term it can't connect ("CS 240 . You may
            // only attempt ..."); what follows is unparsed, not absent.
            if index < resolved.count { hasUnknown = true }
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
        var result = parseClause(tokens, &i)
        while i < tokens.count, case .semicolon = tokens[i] {
            i += 1
            var isAlternative = false
            if i < tokens.count, case .and = tokens[i] {
                i += 1
            } else if i < tokens.count, case .or = tokens[i] {
                i += 1
                isAlternative = true
            }
            let next = parseClause(tokens, &i)
            result = isAlternative ? .any([result, next]) : .all([result, next])
        }
        return result
    }

    /// A comma list closed by "and" separates its items more loosely than
    /// "or": "A or B , and C" is (A or B) and C, "A , B or C , and D" is A
    /// and (B or C) and D, and "A or B , C and D" is (A or B) and C and D.
    /// Lists closed by "or" keep commas binding tighter than "or", since
    /// "A , B or C" usually means one choice. Inside such a list, ", or X"
    /// makes X an alternative to the items since the last ", and" ("A , B ,
    /// or C , and D"). A plain list closed by ", or" ("A , B , or C") is a
    /// choice among all its items, as is a list of courses closed by a bare
    /// "or" ("A , B or C").
    private func parseClause(_ tokens: [PrereqToken], _ i: inout Int) -> PrereqExpr {
        if Self.clauseIsOrList(tokens, from: i) {
            var choices = [parseTerm(tokens, &i)]
            while i + 1 < tokens.count {
                if case .comma = tokens[i] {
                    i += 1
                    if case .or = tokens[i] { i += 1 }
                } else if case .or = tokens[i] {
                    i += 1
                } else {
                    break
                }
                choices.append(parseTerm(tokens, &i))
            }
            return .any(choices)
        }
        guard Self.clauseIsAndList(tokens, from: i) else { return parseOr(tokens, &i) }
        var items = [parseOr(tokens, &i, commasSeparate: true)]
        var runStart = 0
        while i < tokens.count, case .comma = tokens[i] {
            i += 1
            if i < tokens.count, case .and = tokens[i] {
                i += 1
                runStart = items.count
                items.append(parseOr(tokens, &i, commasSeparate: true))
            } else if i < tokens.count, case .or = tokens[i] {
                i += 1
                let alternatives = Array(items[runStart...]) + [parseOr(tokens, &i, commasSeparate: true)]
                items.replaceSubrange(runStart..., with: [.any(alternatives)])
            } else {
                items.append(parseOr(tokens, &i, commasSeparate: true))
            }
        }
        return items.count == 1 ? items[0] : .all(items)
    }

    /// Whether the clause starting at `start` — up to the next semicolon or
    /// unmatched ")" — is a comma list closed by "and": it has a top-level
    /// ", and", or its last top-level comma is followed by "and" with no
    /// "or" ("A or B , C and D", but not "A , B or C and D", nor "A and B ,
    /// or C , D and E", whose ", or" splits two groups).
    private static func clauseIsAndList(_ tokens: [PrereqToken], from start: Int) -> Bool {
        var depth = 0
        var index = start
        var sawComma = false
        var sawCommaOr = false
        var andAfterLastComma = false
        var orAfterLastComma = false
        scan: while index < tokens.count {
            switch tokens[index] {
            case .lparen:
                depth += 1
            case .rparen:
                if depth == 0 { break scan }
                depth -= 1
            case .semicolon where depth == 0:
                break scan
            case .comma where depth == 0:
                if index + 1 < tokens.count, case .and = tokens[index + 1] { return true }
                if isCommaOr(tokens, at: index) { sawCommaOr = true }
                sawComma = true
                andAfterLastComma = false
                orAfterLastComma = false
            case .and where depth == 0:
                andAfterLastComma = true
            case .or where depth == 0, .either where depth == 0:
                orAfterLastComma = true
            default:
                break
            }
            index += 1
        }
        return sawComma && !sawCommaOr && andAfterLastComma && !orAfterLastComma
    }

    /// Whether the clause starting at `start` is a plain list of terms
    /// closed by ", or" ("A , B , or C", "A / B , C , or D"), or a list of
    /// course codes closed by a bare "or" ("A , B or C"), with no other
    /// connectors before it ends. The bare form needs every item to be a
    /// course so "junior standing , A or B" keeps its standing required.
    private static func clauseIsOrList(_ tokens: [PrereqToken], from start: Int) -> Bool {
        enum Closer { case commaOr, bareOr }
        var index = start
        var sawComma = false
        var closer: Closer?
        var allCourses = true
        var expectTerm = true
        func isOrList() -> Bool {
            guard !expectTerm, let closer else { return false }
            return closer == .commaOr || (sawComma && allCourses)
        }
        while index < tokens.count {
            switch tokens[index] {
            case .courseRef, .unknown:
                // An unconnected term starts trailing text ("... or D .
                // Courses not on the list ..."); the clause ends before it.
                guard expectTerm else { return isOrList() }
                if case .unknown(let text) = tokens[index], !PrereqLexer.isCourseCode(text) { allCourses = false }
                expectTerm = false
            case .slash:
                guard !expectTerm else { return false }
                expectTerm = true
            case .comma:
                guard !expectTerm, closer == nil else { return false }
                if isCommaOr(tokens, at: index) {
                    closer = .commaOr
                    index += 1
                } else {
                    sawComma = true
                }
                expectTerm = true
            case .or:
                guard !expectTerm, closer == nil else { return false }
                closer = .bareOr
                expectTerm = true
            case .semicolon, .rparen:
                return isOrList()
            default:
                return false
            }
            index += 1
        }
        return isOrList()
    }

    /// ", or" makes what follows an alternative to everything before it
    /// in the clause ("A and B , or C"), except in a comma-separated list,
    /// where `parseClause` places it.
    private func parseOr(_ tokens: [PrereqToken], _ i: inout Int, commasSeparate: Bool = false) -> PrereqExpr {
        var children = [parseAnd(tokens, &i, commasSeparate: commasSeparate)]
        while !commasSeparate, Self.isCommaOr(tokens, at: i) {
            i += 2
            children.append(parseAnd(tokens, &i, commasSeparate: commasSeparate))
        }
        return children.count == 1 ? children[0] : .any(children)
    }

    private static func isCommaOr(_ tokens: [PrereqToken], at index: Int) -> Bool {
        guard index + 1 < tokens.count, case .comma = tokens[index], case .or = tokens[index + 1] else { return false }
        return true
    }

    /// `commasSeparate` leaves commas to `parseClause`, which splits on them.
    private func parseAnd(_ tokens: [PrereqToken], _ i: inout Int, commasSeparate: Bool = false) -> PrereqExpr {
        // Runs of items joined only by commas; "and" (or ", and") starts a
        // new run.
        var runs: [[PrereqExpr]] = [[parseChoice(tokens, &i)]]
        loop: while i < tokens.count {
            switch tokens[i] {
            case .comma where commasSeparate || Self.isCommaOr(tokens, at: i):
                break loop
            case .and:
                i += 1
                runs.append([parseChoice(tokens, &i)])
            case .comma:
                i += 1
                // Oxford comma: ", and X" is one separator, not an empty term.
                if i < tokens.count, case .and = tokens[i] {
                    i += 1
                    runs.append([parseChoice(tokens, &i)])
                } else {
                    runs[runs.count - 1].append(parseChoice(tokens, &i))
                }
            default:
                break loop
            }
        }
        // A comma run closed by an "or" choice lists alternatives: "CIS 221
        // , CS 149 or ISAT 252" is one of the three, as in a standalone list.
        // Trailing prose ("..., as appropriate to course content") doesn't
        // reopen the list.
        let children = runs.flatMap { run -> [PrereqExpr] in
            let isProse: (PrereqExpr) -> Bool = { item in
                if case .unknown(let text) = item { return !PrereqLexer.isCourseCode(text) }
                return false
            }
            guard let closer = run.lastIndex(where: { !isProse($0) }),
                  closer > 0,
                  case .any(let closing) = run[closer]
            else { return run }
            // "A , B or permission of the instructor" closes with an escape
            // hatch for the whole list, not a choice between courses; "or
            // equivalent" still marks a choice list.
            let closesWithCourseChoice = closing.filter { !isProse($0) }.count >= 2
                || closing.contains { item in
                    if case .unknown(let text) = item { return text.lowercased().contains("equivalent") }
                    return false
                }
            guard closesWithCourseChoice else {
                let escapes = closing.filter(isProse)
                let required = Array(run[..<closer]) + closing.filter { !isProse($0) }
                return [.any([.all(required)] + escapes)] + run[(closer + 1)...]
            }
            let alternatives = run[...closer].flatMap { item -> [PrereqExpr] in
                if case .any(let choices) = item { return choices }
                return [item]
            }
            return [.any(alternatives)] + run[(closer + 1)...]
        }
        return children.count == 1 ? children[0] : .all(children)
    }

    /// JMU puts "or" between substitutable courses, so it binds tighter than
    /// "and": "MATH 300 or MATH 238 and MATH 321 or MATH 322" is (300 or
    /// 238) and (321 or 322).
    private func parseChoice(_ tokens: [PrereqToken], _ i: inout Int) -> PrereqExpr {
        var children = [parseTerm(tokens, &i)]
        while i < tokens.count, case .or = tokens[i] {
            i += 1
            children.append(parseTerm(tokens, &i))
        }
        return children.count == 1 ? children[0] : .any(children)
    }

    private func parseTerm(_ tokens: [PrereqToken], _ i: inout Int) -> PrereqExpr {
        guard i < tokens.count else { return .empty }
        switch tokens[i] {
        case .lparen:
            i += 1
            let inner = parseExpr(tokens, &i)
            if i < tokens.count, case .rparen = tokens[i] { i += 1 }
            return inner
        case .either:
            i += 1
            return parseEither(tokens, &i)
        case .courseRef(let id):
            i += 1
            return parseSlashed(.course(id), tokens, &i)
        case .unknown(let text):
            i += 1
            return parseSlashed(.unknown(text), tokens, &i)
        default:
            i += 1
            return .empty
        }
    }

    /// "A / B": a lecture and its lab ("BIO 240 / BIO 240L") are both
    /// required; any other pair is a cross-listing, where either counts.
    /// Both sides name one offering, so a side missing from the catalog
    /// (often the lab) drops out rather than flagging the rule.
    private func parseSlashed(_ first: PrereqExpr, _ tokens: [PrereqToken], _ i: inout Int) -> PrereqExpr {
        var result = first
        while i + 1 < tokens.count, case .slash = tokens[i] {
            i += 1
            let next = parseTerm(tokens, &i)
            switch (result, next) {
            case (.unknown, .course):
                result = next
            case (_, .unknown) where !result.containsUnknown:
                continue
            default:
                let isLabPair = Self.slashKey(result).map { $0 + "L" } == Self.slashKey(next)
                    || Self.slashKey(next).map { $0 + "L" } == Self.slashKey(result)
                result = isLabPair ? .all([result, next]) : .any([result, next])
            }
        }
        return result
    }

    /// A course leaf's code with spacing removed — "BIO240L" for both the
    /// resolved id and an unresolved "BIO 240L" — for lab-pair matching.
    private static func slashKey(_ expr: PrereqExpr) -> String? {
        switch expr {
        case .course(let text), .unknown(let text):
            return text.uppercased().filter { $0.isLetter || $0.isNumber }
        default:
            return nil
        }
    }

    /// "either A or B", "either A , B , or C": alternatives separated by
    /// commas and "or", ending at the first comma after an "or" or at any
    /// other connector, so "either A or B , and C" leaves ", and C" to the
    /// caller.
    private func parseEither(_ tokens: [PrereqToken], _ i: inout Int) -> PrereqExpr {
        var choices = [parseTerm(tokens, &i)]
        var sawOr = false
        while i + 1 < tokens.count {
            if case .or = tokens[i] {
                i += 1
                sawOr = true
            } else if !sawOr, case .comma = tokens[i] {
                if case .and = tokens[i + 1] { break }
                i += 1
                if case .or = tokens[i] { i += 1; sawOr = true }
            } else {
                break
            }
            choices.append(parseTerm(tokens, &i))
        }
        return choices.count == 1 ? choices[0] : .any(choices)
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
        // 'a minimum grade of "C" in', 'minimum grades of "C-" or better in both',
        // 'A grade of "C" or higher in the following courses:'.
        try! NSRegularExpression(pattern: #"(?i)\b(?:with\s+)?(?:an?\s+)?(?:minimum\s+)?grades?\s+of\s+["“”']?\s*[A-F][+-]?\s*["“”']?\s*(?:or\s+(?:better|higher)\s+)?in\b\s*(?:(?:both|each\s+of)\b\s*)?(?:the\s+following(?:\s+courses?)?\b)?\s*:?\s*"#),
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?i)\b[A-F][+-]?\s+or\s+better\s+in\s+"#),
        // Trailing: 'SCOM 280 with a minimum grade of "C-"', 'GEOG 210 with a
        // "C" or better'. The grade letter stays case-sensitive so "with a"
        // alone never reads as a grade.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"\s*\b(?i:with\s+(?:an?\s+)?(?:minimum\s+)?(?:grades?\s+of\s+)?)["“”']?\s*[A-F][+-]?\s*\.?\s*["“”']?(?![A-Za-z])(?i:\s*or\s+(?:better|higher))?"#)
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
