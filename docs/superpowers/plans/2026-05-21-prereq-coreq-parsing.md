# Prerequisite & Corequisite Parsing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parse JMU catalog prereq and coreq text into a typed expression tree, enforce it during schedule generation, and surface clear actionable warnings when manual edits violate the requirement.

**Architecture:** Hand-written recursive-descent parser in PlannerCore produces a `PrereqExpr` tree on every `Course`. A two-pass `CatalogRepository` orchestration runs the parser after all programs are scraped, so cross-program references resolve. `ConflictDetector` evaluates expressions with awareness of completed-before / scheduled-this-term sets. The schedule generator falls back to best-effort placement instead of throwing. The Schedule warning strip and Course Detail sheet render the parsed expressions.

**Tech Stack:** Swift 5.10, SwiftUI, Codable, SwiftPM. No new external dependencies.

**Source spec:** [`docs/superpowers/specs/2026-05-21-prereq-coreq-parsing-design.md`](../specs/2026-05-21-prereq-coreq-parsing-design.md)

---

## File Structure

**Create:**
- `Sources/PlannerCore/PrereqExpr.swift` — typed expression enum + displayString.
- `Sources/PlannerCore/PrereqParser.swift` — lexer + recursive-descent parser + ParseResult.
- `Tests/PlannerCoreTests/PrereqParserTests.swift` — parser unit tests.
- `Tests/PlannerCoreTests/PrereqEvaluatorTests.swift` — evaluator + integration tests.
- `script/regenerate_seed.swift` — one-shot seed regenerator.

**Modify:**
- `Sources/PlannerCore/PlannerCore.swift` — extend `Course`, add `ConflictKind.missingCorequisite`, add `PrereqEvaluator`, extend `ConflictDetector.warnings(...)`, add `Generator.strictPrereqs` flag + best-effort fallback in `buildSemesters`.
- `Sources/PlannerCore/CatalogHTMLParser.swift` — surface raw `prerequisiteText` on parsed `Course` (currently dropped).
- `Sources/JMUCoursePlanner/Services/CatalogRepository.swift` — schema-version bump + Pass 2 parser invocation in build/load path.
- `Sources/JMUCoursePlanner/Views/Tabs/ScheduleBoardView.swift` — multi-line warning copy + coreq icon.
- `Sources/JMUCoursePlanner/Views/CourseDetailSheet.swift` — Prereqs/Coreqs sections + partial note.
- `Data/catalog_seed.json` — regenerated after parser ships.

**Touch (read-only):**
- `Tests/PlannerCoreTests/_live_*.html` — fixture corpus for live-case parser tests.

---

## Task 1: Add `PrereqExpr` enum

**Files:**
- Create: `Sources/PlannerCore/PrereqExpr.swift`
- Test: `Tests/PlannerCoreTests/PrereqParserTests.swift` (new file, will grow across tasks)

- [ ] **Step 1: Write the failing test**

Create `Tests/PlannerCoreTests/PrereqParserTests.swift`:

```swift
import XCTest
@testable import PlannerCore

final class PrereqExprTests: XCTestCase {
    func testCodableRoundTripPreservesStructure() throws {
        let expr: PrereqExpr = .all([
            .course("cs-159"),
            .any([.course("math-235"), .course("math-236")]),
            .unknown("instructor permission")
        ])
        let data = try JSONEncoder().encode(expr)
        let decoded = try JSONDecoder().decode(PrereqExpr.self, from: data)
        XCTAssertEqual(expr, decoded)
    }

    func testEmptyIsDefault() throws {
        let data = try JSONEncoder().encode(PrereqExpr.empty)
        let decoded = try JSONDecoder().decode(PrereqExpr.self, from: data)
        XCTAssertEqual(decoded, .empty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PrereqExprTests`
Expected: build error, `cannot find 'PrereqExpr' in scope`.

- [ ] **Step 3: Create the enum**

Create `Sources/PlannerCore/PrereqExpr.swift`:

```swift
import Foundation

public indirect enum PrereqExpr: Codable, Hashable, Sendable {
    case empty
    case course(String)
    case unknown(String)
    case all([PrereqExpr])
    case any([PrereqExpr])

    private enum CodingKeys: String, CodingKey { case kind, value, children }
    private enum Kind: String, Codable { case empty, course, unknown, all, any }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .empty: self = .empty
        case .course: self = .course(try c.decode(String.self, forKey: .value))
        case .unknown: self = .unknown(try c.decode(String.self, forKey: .value))
        case .all: self = .all(try c.decode([PrereqExpr].self, forKey: .children))
        case .any: self = .any(try c.decode([PrereqExpr].self, forKey: .children))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .empty:
            try c.encode(Kind.empty, forKey: .kind)
        case .course(let id):
            try c.encode(Kind.course, forKey: .kind)
            try c.encode(id, forKey: .value)
        case .unknown(let text):
            try c.encode(Kind.unknown, forKey: .kind)
            try c.encode(text, forKey: .value)
        case .all(let children):
            try c.encode(Kind.all, forKey: .kind)
            try c.encode(children, forKey: .children)
        case .any(let children):
            try c.encode(Kind.any, forKey: .kind)
            try c.encode(children, forKey: .children)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PrereqExprTests`
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PlannerCore/PrereqExpr.swift Tests/PlannerCoreTests/PrereqParserTests.swift
git commit -m "Add PrereqExpr enum with codable round-trip"
```

---

## Task 2: Extend `Course` model

**Files:**
- Modify: `Sources/PlannerCore/PlannerCore.swift:75-113` (Course struct + init)

- [ ] **Step 1: Write the failing test**

Append to `Tests/PlannerCoreTests/PrereqParserTests.swift`:

```swift
final class CourseModelTests: XCTestCase {
    func testCourseDefaultsToEmptyExpressions() {
        let c = Course(
            id: "cs-159",
            code: "CS 159",
            title: "Intro",
            credits: 3,
            availability: nil,
            prerequisites: []
        )
        XCTAssertEqual(c.prerequisiteExpr, .empty)
        XCTAssertEqual(c.corequisiteExpr, .empty)
        XCTAssertFalse(c.hasUnknownPrereqTokens)
    }

    func testCourseExpressionsRoundTripCodable() throws {
        var c = Course(
            id: "cs-240",
            code: "CS 240",
            title: "Data",
            credits: 3,
            availability: nil,
            prerequisites: ["cs-159"]
        )
        c.prerequisiteExpr = .course("cs-159")
        c.corequisiteExpr = .course("math-235")
        c.hasUnknownPrereqTokens = true
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(Course.self, from: data)
        XCTAssertEqual(decoded.prerequisiteExpr, .course("cs-159"))
        XCTAssertEqual(decoded.corequisiteExpr, .course("math-235"))
        XCTAssertTrue(decoded.hasUnknownPrereqTokens)
    }

    func testCourseDecodesOldJSONWithoutNewFields() throws {
        let json = """
        {"id":"cs-159","code":"CS 159","title":"Intro","credits":3,"availability":null,"prerequisites":[],"verificationStatus":"verified"}
        """
        let decoded = try JSONDecoder().decode(Course.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.prerequisiteExpr, .empty)
        XCTAssertEqual(decoded.corequisiteExpr, .empty)
        XCTAssertFalse(decoded.hasUnknownPrereqTokens)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter CourseModelTests`
Expected: build error referencing `prerequisiteExpr`, `corequisiteExpr`, or `hasUnknownPrereqTokens`.

- [ ] **Step 3: Add fields to `Course`**

Open `Sources/PlannerCore/PlannerCore.swift`. Inside `public struct Course`, add three stored properties after `detailRetrievedAt`:

```swift
    public var prerequisiteExpr: PrereqExpr
    public var corequisiteExpr: PrereqExpr
    public var hasUnknownPrereqTokens: Bool
```

Extend the existing initializer to take three new defaulted parameters and assign them. Replace the existing `public init(...)` of `Course` with:

```swift
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
        hasUnknownPrereqTokens: Bool = false
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
    }
```

Add a custom `Decodable` initializer below the memberwise init so that old JSON without the new keys decodes cleanly:

```swift
    private enum CourseCodingKeys: String, CodingKey {
        case id, code, title, credits, availability, prerequisites, verificationStatus,
             registrarURL, description, descriptionSourceURL, detailRetrievedAt,
             prerequisiteExpr, corequisiteExpr, hasUnknownPrereqTokens
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
    }
```

Encode synthesized.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter CourseModelTests`
Expected: 3 tests pass.

- [ ] **Step 5: Run the whole test suite to confirm no regressions**

Run: `swift test`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add Sources/PlannerCore/PlannerCore.swift Tests/PlannerCoreTests/PrereqParserTests.swift
git commit -m "Extend Course model with PrereqExpr fields and back-compat decoder"
```

---

## Task 3: Add `ConflictKind.missingCorequisite`

**Files:**
- Modify: `Sources/PlannerCore/PlannerCore.swift:815-823` (ConflictKind enum + displayName)

- [ ] **Step 1: Write the failing test**

Append to `Tests/PlannerCoreTests/PrereqParserTests.swift`:

```swift
final class ConflictKindTests: XCTestCase {
    func testMissingCorequisiteCaseExists() {
        let k = ConflictKind.missingCorequisite
        XCTAssertEqual(k.rawValue, "missingCorequisite")
    }

    func testMissingCorequisiteDisplayName() {
        XCTAssertEqual(ConflictKind.missingCorequisite.displayName, "Corequisite warning")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ConflictKindTests`
Expected: compile error: `Type 'ConflictKind' has no member 'missingCorequisite'`.

- [ ] **Step 3: Add the case**

Open `Sources/PlannerCore/PlannerCore.swift`. In `public enum ConflictKind`, add the case alongside the others:

```swift
public enum ConflictKind: String, Codable, Hashable, Sendable {
    case missingPrerequisite
    case missingCorequisite
    case unknownAvailability
    case semesterAvailability
}
```

In the `displayName` computed property switch, add the missing arm:

```swift
        case .missingCorequisite: "Corequisite warning"
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter ConflictKindTests`
Expected: 2 pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PlannerCore/PlannerCore.swift Tests/PlannerCoreTests/PrereqParserTests.swift
git commit -m "Add ConflictKind.missingCorequisite case"
```

---

## Task 4: `PrereqExpr.displayString` helper

**Files:**
- Modify: `Sources/PlannerCore/PrereqExpr.swift` (append extension)

- [ ] **Step 1: Write the failing test**

Append to `Tests/PlannerCoreTests/PrereqParserTests.swift`:

```swift
final class PrereqDisplayStringTests: XCTestCase {
    private var coursesByID: [String: Course] {
        [
            "cs-159": Course(id: "cs-159", code: "CS 159", title: "", credits: 3, availability: nil, prerequisites: []),
            "cs-149": Course(id: "cs-149", code: "CS 149", title: "", credits: 3, availability: nil, prerequisites: []),
            "math-235": Course(id: "math-235", code: "MATH 235", title: "", credits: 3, availability: nil, prerequisites: [])
        ]
    }

    func testEmptyRendersEmpty() {
        XCTAssertEqual(PrereqExpr.empty.displayString(coursesByID: [:]), "")
    }

    func testCourseRendersCode() {
        XCTAssertEqual(PrereqExpr.course("cs-159").displayString(coursesByID: coursesByID), "CS 159")
    }

    func testUnresolvedCourseFallsBackToID() {
        XCTAssertEqual(PrereqExpr.course("does-not-exist").displayString(coursesByID: coursesByID), "does-not-exist")
    }

    func testUnknownRendersRawText() {
        XCTAssertEqual(PrereqExpr.unknown("instructor permission").displayString(coursesByID: [:]), "instructor permission")
    }

    func testAndJoins() {
        let expr: PrereqExpr = .all([.course("cs-159"), .course("math-235")])
        XCTAssertEqual(expr.displayString(coursesByID: coursesByID), "CS 159 and MATH 235")
    }

    func testOrJoins() {
        let expr: PrereqExpr = .any([.course("cs-159"), .course("cs-149")])
        XCTAssertEqual(expr.displayString(coursesByID: coursesByID), "CS 159 or CS 149")
    }

    func testNestedParens() {
        let expr: PrereqExpr = .all([
            .course("cs-159"),
            .any([.course("math-235"), .unknown("instructor permission")])
        ])
        XCTAssertEqual(expr.displayString(coursesByID: coursesByID), "CS 159 and (MATH 235 or instructor permission)")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter PrereqDisplayStringTests`
Expected: compile error: `'PrereqExpr' has no member 'displayString'`.

- [ ] **Step 3: Implement the extension**

Append to `Sources/PlannerCore/PrereqExpr.swift`:

```swift
public extension PrereqExpr {
    func displayString(coursesByID: [String: Course]) -> String {
        switch self {
        case .empty:
            return ""
        case .course(let id):
            return coursesByID[id]?.code ?? id
        case .unknown(let text):
            return text
        case .all(let children):
            return joinChildren(children, separator: " and ", coursesByID: coursesByID)
        case .any(let children):
            return joinChildren(children, separator: " or ", coursesByID: coursesByID)
        }
    }

    private func joinChildren(_ children: [PrereqExpr], separator: String, coursesByID: [String: Course]) -> String {
        children.map { child -> String in
            let rendered = child.displayString(coursesByID: coursesByID)
            switch child {
            case .all, .any:
                return "(\(rendered))"
            default:
                return rendered
            }
        }.joined(separator: separator)
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter PrereqDisplayStringTests`
Expected: 7 pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PlannerCore/PrereqExpr.swift Tests/PlannerCoreTests/PrereqParserTests.swift
git commit -m "Add PrereqExpr.displayString rendering helper"
```

---

## Task 5: `PrereqParser` lexer

**Files:**
- Create: `Sources/PlannerCore/PrereqParser.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/PlannerCoreTests/PrereqParserTests.swift`:

```swift
final class PrereqLexerTests: XCTestCase {
    func testCourseReferenceToken() {
        let tokens = PrereqLexer.tokenize("CS 159")
        XCTAssertEqual(tokens, [.courseRef("CS 159")])
    }

    func testBooleanAndParenTokens() {
        let tokens = PrereqLexer.tokenize("CS 159 and (MATH 235 or MATH 236)")
        XCTAssertEqual(tokens, [
            .courseRef("CS 159"),
            .and,
            .lparen,
            .courseRef("MATH 235"),
            .or,
            .courseRef("MATH 236"),
            .rparen
        ])
    }

    func testCommaAndSemicolonTokens() {
        let tokens = PrereqLexer.tokenize("CS 159, MATH 235; CS 240")
        XCTAssertEqual(tokens, [
            .courseRef("CS 159"),
            .comma,
            .courseRef("MATH 235"),
            .semicolon,
            .courseRef("CS 240")
        ])
    }

    func testUnknownRunBetweenCourseRefs() {
        let tokens = PrereqLexer.tokenize("CS 159 or instructor permission")
        XCTAssertEqual(tokens, [
            .courseRef("CS 159"),
            .or,
            .unknown("instructor permission")
        ])
    }

    func testTrailingPunctuationIgnored() {
        let tokens = PrereqLexer.tokenize("CS 159.")
        XCTAssertEqual(tokens, [.courseRef("CS 159")])
    }

    func testEmptyInputProducesNoTokens() {
        XCTAssertTrue(PrereqLexer.tokenize("").isEmpty)
        XCTAssertTrue(PrereqLexer.tokenize("   ").isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter PrereqLexerTests`
Expected: compile error referencing `PrereqLexer`.

- [ ] **Step 3: Implement lexer**

Create `Sources/PlannerCore/PrereqParser.swift`:

```swift
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
    private static let coursePattern = try! NSRegularExpression(pattern: #"^[A-Z]{2,5}\s+\d{3}[A-Z]?"#)

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

            // course-ref match anchored at i
            let remainder = String(input[i...])
            if let match = coursePattern.firstMatch(in: remainder, range: NSRange(remainder.startIndex..., in: remainder)) {
                let range = Range(match.range, in: remainder)!
                let code = remainder[range].replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                flushUnknown(); tokens.append(.courseRef(code))
                i = input.index(i, offsetBy: remainder.distance(from: remainder.startIndex, to: range.upperBound))
                continue
            }

            // keyword detection
            if let kw = readKeyword(from: input, at: i) {
                flushUnknown()
                switch kw.word {
                case "and": tokens.append(.and)
                case "or": tokens.append(.or)
                default: unknownBuffer += String(input[i..<kw.end])
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

    private static func readKeyword(from s: String, at start: String.Index) -> (word: String, end: String.Index)? {
        var end = start
        while end < s.endIndex, s[end].isLetter { end = s.index(after: end) }
        guard end > start else { return nil }
        let word = s[start..<end].lowercased()
        // only treat standalone "and"/"or" as keywords (others fall into unknown)
        if word == "and" || word == "or" {
            // require non-letter boundary (achieved by the while-loop)
            return (word, end)
        }
        return (word, end)
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter PrereqLexerTests`
Expected: 6 pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PlannerCore/PrereqParser.swift Tests/PlannerCoreTests/PrereqParserTests.swift
git commit -m "Implement PrereqLexer tokenizer"
```

---

## Task 6: `PrereqParser` grammar (recursive descent)

**Files:**
- Modify: `Sources/PlannerCore/PrereqParser.swift` (append parser types)

- [ ] **Step 1: Write the failing test**

Append to `Tests/PlannerCoreTests/PrereqParserTests.swift`:

```swift
final class PrereqGrammarTests: XCTestCase {
    private func parse(_ text: String, coursesByID: [String: Course] = stubCatalog) -> ParseResult {
        PrereqParser(coursesByID: coursesByID).parse(text)
    }

    private static let stubCatalog: [String: Course] = [
        "cs-159": Course(id: "cs-159", code: "CS 159", title: "", credits: 3, availability: nil, prerequisites: []),
        "cs-149": Course(id: "cs-149", code: "CS 149", title: "", credits: 3, availability: nil, prerequisites: []),
        "math-235": Course(id: "math-235", code: "MATH 235", title: "", credits: 3, availability: nil, prerequisites: []),
        "math-236": Course(id: "math-236", code: "MATH 236", title: "", credits: 3, availability: nil, prerequisites: [])
    ]

    func testAtomic() {
        XCTAssertEqual(parse("Prerequisite: CS 159.").prerequisiteExpr, .course("cs-159"))
    }

    func testAnd() {
        XCTAssertEqual(parse("CS 159 and MATH 235").prerequisiteExpr,
                       .all([.course("cs-159"), .course("math-235")]))
    }

    func testOr() {
        XCTAssertEqual(parse("CS 159 or CS 149").prerequisiteExpr,
                       .any([.course("cs-159"), .course("cs-149")]))
    }

    func testNested() {
        XCTAssertEqual(parse("CS 159 and (MATH 235 or MATH 236)").prerequisiteExpr,
                       .all([.course("cs-159"), .any([.course("math-235"), .course("math-236")])]))
    }

    func testCommaIsAnd() {
        XCTAssertEqual(parse("CS 159, MATH 235").prerequisiteExpr,
                       .all([.course("cs-159"), .course("math-235")]))
    }

    func testSemicolonIsAnd() {
        XCTAssertEqual(parse("CS 159; MATH 235").prerequisiteExpr,
                       .all([.course("cs-159"), .course("math-235")]))
    }

    func testUnknownToken() {
        let result = parse("CS 159 or instructor permission")
        XCTAssertEqual(result.prerequisiteExpr, .any([.course("cs-159"), .unknown("instructor permission")]))
        XCTAssertTrue(result.hasUnknownTokens)
    }

    func testUnresolvedCourseRefBecomesUnknown() {
        let result = parse("CS 159 or MATH 100")
        XCTAssertEqual(result.prerequisiteExpr, .any([.course("cs-159"), .unknown("MATH 100")]))
        XCTAssertTrue(result.hasUnknownTokens)
    }

    func testEmptyInput() {
        XCTAssertEqual(parse(nil ?? "").prerequisiteExpr, .empty)
        XCTAssertFalse(parse("").hasUnknownTokens)
    }

    func testNormalizationFlattensNestedAnd() {
        XCTAssertEqual(parse("CS 159 and MATH 235 and MATH 236").prerequisiteExpr,
                       .all([.course("cs-159"), .course("math-235"), .course("math-236")]))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter PrereqGrammarTests`
Expected: compile error referencing `PrereqParser` or `ParseResult`.

- [ ] **Step 3: Implement parser, ParseResult, normalization**

Append to `Sources/PlannerCore/PrereqParser.swift`:

```swift
public struct ParseResult: Sendable, Equatable {
    public var prerequisiteExpr: PrereqExpr
    public var corequisiteExpr: PrereqExpr
    public var hasUnknownTokens: Bool

    public init(prerequisiteExpr: PrereqExpr = .empty, corequisiteExpr: PrereqExpr = .empty, hasUnknownTokens: Bool = false) {
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
        let resolvedTokens = PrereqLexer.tokenize(text).map { token -> PrereqToken in
            if case .courseRef(let raw) = token {
                let key = Self.normalizeCode(raw)
                if let id = codeToID[key] {
                    return .courseRef(id)   // smuggle resolved ID in same enum
                }
                return .unknown(raw)
            }
            return token
        }
        var i = 0
        let expr = parseExpr(resolvedTokens, &i)
        // Mark unknowns
        if Self.containsUnknown(expr) { hasUnknown = true }
        return Self.normalize(expr)
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
        while i < tokens.count {
            switch tokens[i] {
            case .and, .comma, .semicolon:
                i += 1
                children.append(parseTerm(tokens, &i))
            default:
                return children.count == 1 ? children[0] : .all(children)
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

    private static func splitCoreq(_ text: String) -> (String, String) {
        let lower = text.lowercased()
        let markers = ["corequisite(s):", "corequisites:", "corequisite:"]
        for marker in markers {
            if let range = lower.range(of: marker) {
                let prefix = String(text[text.startIndex..<text.index(text.startIndex, offsetBy: text.distance(from: lower.startIndex, to: range.lowerBound))])
                let suffix = String(text[text.index(text.startIndex, offsetBy: text.distance(from: lower.startIndex, to: range.upperBound))...])
                return (prefix.trimmingCharacters(in: .whitespacesAndNewlines), suffix.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), "")
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
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter PrereqGrammarTests`
Expected: 10 pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PlannerCore/PrereqParser.swift Tests/PlannerCoreTests/PrereqParserTests.swift
git commit -m "Implement PrereqParser recursive-descent grammar"
```

---

## Task 7: Coreq segment parsing

**Files:**
- No new code (handled by Task 6's `splitCoreq`); this task adds tests + a regression fix if needed.

- [ ] **Step 1: Write the failing test**

Append to `Tests/PlannerCoreTests/PrereqParserTests.swift`:

```swift
final class PrereqCoreqTests: XCTestCase {
    private static let stubCatalog: [String: Course] = [
        "cs-159": Course(id: "cs-159", code: "CS 159", title: "", credits: 3, availability: nil, prerequisites: []),
        "math-235": Course(id: "math-235", code: "MATH 235", title: "", credits: 3, availability: nil, prerequisites: []),
        "math-236": Course(id: "math-236", code: "MATH 236", title: "", credits: 3, availability: nil, prerequisites: [])
    ]

    func testCoreqSegmentSplits() {
        let r = PrereqParser(coursesByID: Self.stubCatalog).parse("Prerequisite: CS 159. Corequisite: MATH 235.")
        XCTAssertEqual(r.prerequisiteExpr, .course("cs-159"))
        XCTAssertEqual(r.corequisiteExpr, .course("math-235"))
    }

    func testCoreqWithBooleanGroup() {
        let r = PrereqParser(coursesByID: Self.stubCatalog).parse("Prerequisite: CS 159. Corequisite(s): MATH 235 or MATH 236.")
        XCTAssertEqual(r.corequisiteExpr, .any([.course("math-235"), .course("math-236")]))
    }

    func testNoCoreqLeavesEmpty() {
        let r = PrereqParser(coursesByID: Self.stubCatalog).parse("Prerequisite: CS 159.")
        XCTAssertEqual(r.corequisiteExpr, .empty)
    }
}
```

- [ ] **Step 2: Run to verify they pass (already implemented in Task 6)**

Run: `swift test --filter PrereqCoreqTests`
Expected: 3 pass. If any fail, fix `splitCoreq` in `PrereqParser.swift` and rerun.

- [ ] **Step 3: Commit**

```bash
git add Tests/PlannerCoreTests/PrereqParserTests.swift
git commit -m "Add coreq segment parsing tests"
```

---

## Task 8: Live-fixture regression tests

**Files:**
- Modify: `Tests/PlannerCoreTests/PrereqParserTests.swift` (append fixture suite)

- [ ] **Step 1: Inspect live fixtures for representative lines**

Run: `grep -hoE 'Prerequisite[^.]+\.' Tests/PlannerCoreTests/_live_cs.html Tests/PlannerCoreTests/_live_accounting.html Tests/PlannerCoreTests/_live_nursing.html Tests/PlannerCoreTests/_live_psyc.html Tests/PlannerCoreTests/_live_gened.html | sort -u | head -20`
Expected: a list of real prereq sentences. Pick two per fixture (10 total) plus two from seed (added at Task 16).

- [ ] **Step 2: Write the regression suite**

Append to `Tests/PlannerCoreTests/PrereqParserTests.swift`:

```swift
final class PrereqLiveFixtureTests: XCTestCase {
    private struct Case {
        let label: String
        let input: String
        let assert: (ParseResult) -> Void
    }

    // Replace the bodies below with the lines selected in Step 1.
    // Each assert clause checks the structural shape, NOT exact IDs (IDs depend on resolution).
    private static let cases: [Case] = [
        Case(label: "cs_1", input: "Prerequisite: CS 159 or CS 149.") { r in
            if case .any(let xs) = r.prerequisiteExpr { XCTAssertEqual(xs.count, 2) }
            else { XCTFail("expected .any") }
        },
        Case(label: "cs_2", input: "Prerequisite: CS 240 and (MATH 235 or MATH 245).") { r in
            if case .all(let outer) = r.prerequisiteExpr {
                XCTAssertEqual(outer.count, 2)
                if case .any = outer[1] { /* ok */ } else { XCTFail("inner not .any") }
            } else { XCTFail("expected .all") }
        }
        // ... 8 more cases pulled from live fixtures during Step 1.
    ]

    func testAllLiveFixtureCasesParse() {
        // Empty catalog: every course ref resolves to unknown. Shape still verifiable.
        let parser = PrereqParser(coursesByID: [:])
        for c in Self.cases {
            let result = parser.parse(c.input)
            c.assert(result)
        }
    }
}
```

- [ ] **Step 3: Run tests to verify pass**

Run: `swift test --filter PrereqLiveFixtureTests`
Expected: 1 test passes (containing 10 sub-assertions).

- [ ] **Step 4: Commit**

```bash
git add Tests/PlannerCoreTests/PrereqParserTests.swift
git commit -m "Add live-fixture regression tests for PrereqParser"
```

---

## Task 9: Surface `prerequisiteText` from catalog HTML parser

**Files:**
- Modify: `Sources/PlannerCore/CatalogHTMLParser.swift:659-668` (Course construction in `parseCourseFromHTML` or equivalent)

- [ ] **Step 1: Locate the existing `prerequisites: []` site**

Run: `grep -n 'prerequisites: \[\]' Sources/PlannerCore/CatalogHTMLParser.swift`
Expected: at least one match around line 665.

- [ ] **Step 2: Write the failing test**

Append a new test class to `Tests/PlannerCoreTests/CatalogHTMLParserTests.swift` (or create the file if absent):

```swift
final class CatalogHTMLParserPrereqPassThroughTests: XCTestCase {
    func testRawPrereqTextPropagatesToHTMLProgramRequirements() throws {
        let html = """
        <html><body>
        <h3>CS 240. Data Structures.</h3>
        <p>Prerequisite: CS 159 and MATH 235.</p>
        </body></html>
        """
        let parser = JMUHTMLCatalogParser()
        let result = try parser.parseProgramHTML(html, baseURL: URL(string: "https://example.test/")!, catoid: 1)
        let course = result.courses.first { $0.code == "CS 240" }
        XCTAssertNotNil(course)
        // Field is internal-only (used by Pass 2). Expose via an internal accessor for testing.
        XCTAssertEqual(course?.rawPrerequisiteText, "Prerequisite: CS 159 and MATH 235.")
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter CatalogHTMLParserPrereqPassThroughTests`
Expected: compile error: `Course` has no member `rawPrerequisiteText`.

- [ ] **Step 4: Add internal `rawPrerequisiteText` on Course; surface from parser**

In `Sources/PlannerCore/PlannerCore.swift` `Course` struct, add an internal (not public) property:

```swift
    var rawPrerequisiteText: String?
```

Add a parameter to the existing initializer (internal-only path; the public init keeps backwards compatibility by defaulting it):

```swift
        rawPrerequisiteText: String? = nil
```

Assign in the body: `self.rawPrerequisiteText = rawPrerequisiteText`.

In `Sources/PlannerCore/CatalogHTMLParser.swift`, find the `Course(...)` instantiation in `parseCourseFromHTML` (or equivalent) around line 659. Replace:

```swift
        return Course(
            id: parsedLabel.id,
            code: parsedLabel.code,
            title: parsedLabel.title,
            credits: credits ?? 3,
            availability: nil,
            prerequisites: [],
            verificationStatus: .partial,
            registrarURL: registrarURL
        )
```

with:

```swift
        var course = Course(
            id: parsedLabel.id,
            code: parsedLabel.code,
            title: parsedLabel.title,
            credits: credits ?? 3,
            availability: nil,
            prerequisites: [],
            verificationStatus: .partial,
            registrarURL: registrarURL
        )
        course.rawPrerequisiteText = detail?.prerequisiteText
        return course
```

(`detail?.prerequisiteText` references the `HTMLCourseDetail` already wired into this site; confirm with surrounding code and rename if local variable differs.)

- [ ] **Step 5: Run tests to verify pass**

Run: `swift test --filter CatalogHTMLParserPrereqPassThroughTests`
Expected: 1 pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/PlannerCore/PlannerCore.swift Sources/PlannerCore/CatalogHTMLParser.swift Tests/PlannerCoreTests/CatalogHTMLParserTests.swift
git commit -m "Surface rawPrerequisiteText from HTML parser onto Course"
```

---

## Task 10: Two-pass parser orchestration in `CatalogRepository`

**Files:**
- Modify: `Sources/JMUCoursePlanner/Services/CatalogRepository.swift` (in the load/build path, after all programs parsed)

- [ ] **Step 1: Identify the catalog-build orchestration site**

Run: `grep -n 'Catalog(' Sources/JMUCoursePlanner/Services/CatalogRepository.swift`
Expected: the location where `Catalog(source:programs:courses:apCreditRules:)` is constructed from parser output. This is where Pass 2 runs.

- [ ] **Step 2: Write the failing test**

Create `Tests/PlannerCoreTests/CatalogRepositoryPrereqPassTests.swift`:

```swift
import XCTest
@testable import PlannerCore

final class CatalogRepositoryPrereqPassTests: XCTestCase {
    func testTwoPassResolvesPrereqAcrossCatalog() {
        let cs159 = Course(id: "cs-159", code: "CS 159", title: "Intro", credits: 3, availability: nil, prerequisites: [])
        var cs240 = Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: CS 159 and MATH 235."
        let math235 = Course(id: "math-235", code: "MATH 235", title: "Calc I", credits: 3, availability: nil, prerequisites: [])

        var courses = [cs159, cs240, math235]
        CatalogPrereqResolver.applyPassTwo(to: &courses)

        let resolved = courses.first { $0.code == "CS 240" }!
        XCTAssertEqual(resolved.prerequisiteExpr,
                       .all([.course("cs-159"), .course("math-235")]))
        XCTAssertEqual(resolved.prerequisites.sorted(), ["cs-159", "math-235"])
        XCTAssertFalse(resolved.hasUnknownPrereqTokens)
    }

    func testUnresolvedRefMarksUnknownAndPartial() {
        var cs240 = Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: CS 159 or instructor permission."
        var courses = [cs240]
        CatalogPrereqResolver.applyPassTwo(to: &courses)

        let r = courses[0]
        XCTAssertTrue(r.hasUnknownPrereqTokens)
        XCTAssertEqual(r.verificationStatus, .partial)
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter CatalogRepositoryPrereqPassTests`
Expected: compile error: `cannot find 'CatalogPrereqResolver' in scope`.

- [ ] **Step 4: Implement `CatalogPrereqResolver` in PlannerCore**

Create `Sources/PlannerCore/CatalogPrereqResolver.swift`:

```swift
import Foundation

public enum CatalogPrereqResolver {
    public static func applyPassTwo(to courses: inout [Course]) {
        let byID = Dictionary(uniqueKeysWithValues: courses.map { ($0.id, $0) })
        let parser = PrereqParser(coursesByID: byID)
        for index in courses.indices {
            let result = parser.parse(courses[index].rawPrerequisiteText)
            courses[index].prerequisiteExpr = result.prerequisiteExpr
            courses[index].corequisiteExpr = result.corequisiteExpr
            courses[index].hasUnknownPrereqTokens = result.hasUnknownTokens
            courses[index].prerequisites = Self.flattenCourseIDs(result.prerequisiteExpr)
            if result.hasUnknownTokens {
                courses[index].verificationStatus = .partial
            }
        }
    }

    private static func flattenCourseIDs(_ expr: PrereqExpr) -> [String] {
        switch expr {
        case .course(let id): return [id]
        case .all(let xs), .any(let xs): return xs.flatMap(flattenCourseIDs)
        default: return []
        }
    }
}
```

- [ ] **Step 5: Wire Pass 2 into `CatalogRepository`**

In `Sources/JMUCoursePlanner/Services/CatalogRepository.swift`, find the function that constructs the final `Catalog`. Immediately before constructing it, add:

```swift
            var resolvedCourses = aggregatedCourses
            CatalogPrereqResolver.applyPassTwo(to: &resolvedCourses)
            // use resolvedCourses in place of aggregatedCourses below this point
```

(`aggregatedCourses` is the name used in the existing repo; rename to match the actual local variable.)

- [ ] **Step 6: Run tests to verify pass**

Run: `swift test --filter CatalogRepositoryPrereqPassTests`
Expected: 2 pass.

- [ ] **Step 7: Run the full suite to confirm no regressions**

Run: `swift test`
Expected: green.

- [ ] **Step 8: Commit**

```bash
git add Sources/PlannerCore/CatalogPrereqResolver.swift Sources/JMUCoursePlanner/Services/CatalogRepository.swift Tests/PlannerCoreTests/CatalogRepositoryPrereqPassTests.swift
git commit -m "Wire two-pass prereq parser into CatalogRepository"
```

---

## Task 11: `PrereqEvaluator` (prereq mode)

**Files:**
- Modify: `Sources/PlannerCore/PlannerCore.swift` (append new private struct near `ConflictDetector`)
- Create: `Tests/PlannerCoreTests/PrereqEvaluatorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/PlannerCoreTests/PrereqEvaluatorTests.swift`:

```swift
import XCTest
@testable import PlannerCore

final class PrereqEvaluatorPrereqModeTests: XCTestCase {
    func testCourseSatisfiedByCompletedBefore() {
        let e = PrereqEvaluator(completedBefore: ["cs-159"], scheduledThisTerm: [])
        if case .satisfied = e.evaluate(.course("cs-159"), mode: .prereq) { /* ok */ }
        else { XCTFail("expected satisfied") }
    }

    func testCourseUnsatisfied() {
        let e = PrereqEvaluator(completedBefore: [], scheduledThisTerm: [])
        if case .unmet(let missing, let original) = e.evaluate(.course("cs-159"), mode: .prereq) {
            XCTAssertEqual(missing, .course("cs-159"))
            XCTAssertEqual(original, .course("cs-159"))
        } else { XCTFail("expected unmet") }
    }

    func testAllSatisfiedIfEveryChildMet() {
        let e = PrereqEvaluator(completedBefore: ["cs-159", "math-235"], scheduledThisTerm: [])
        if case .satisfied = e.evaluate(.all([.course("cs-159"), .course("math-235")]), mode: .prereq) { /* ok */ }
        else { XCTFail("expected satisfied") }
    }

    func testAnyOneSufficient() {
        let e = PrereqEvaluator(completedBefore: ["cs-149"], scheduledThisTerm: [])
        if case .satisfied = e.evaluate(.any([.course("cs-159"), .course("cs-149")]), mode: .prereq) { /* ok */ }
        else { XCTFail("expected satisfied") }
    }

    func testNestedAndOfOrPartial() {
        // (CS 159 or CS 149) and MATH 235. Has CS 159 only.
        let expr: PrereqExpr = .all([
            .any([.course("cs-159"), .course("cs-149")]),
            .course("math-235")
        ])
        let e = PrereqEvaluator(completedBefore: ["cs-159"], scheduledThisTerm: [])
        if case .unmet(let missing, _) = e.evaluate(expr, mode: .prereq) {
            XCTAssertEqual(missing, .course("math-235"))
        } else { XCTFail("expected unmet") }
    }

    func testUnknownIsNeverSatisfied() {
        let e = PrereqEvaluator(completedBefore: ["cs-159"], scheduledThisTerm: [])
        if case .unmet(let missing, _) = e.evaluate(.unknown("instructor permission"), mode: .prereq) {
            XCTAssertEqual(missing, .unknown("instructor permission"))
        } else { XCTFail("expected unmet") }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter PrereqEvaluatorPrereqModeTests`
Expected: compile error.

- [ ] **Step 3: Implement `PrereqEvaluator`**

Append to `Sources/PlannerCore/PlannerCore.swift` after the existing `ConflictDetector` block (or in a clearly delimited section above it):

```swift
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

    /// Walk the tree; return what is STILL missing.
    private func prune(_ expr: PrereqExpr, pool: Set<String>) -> PrereqExpr {
        switch expr {
        case .empty: return .empty
        case .course(let id): return pool.contains(id) ? .empty : .course(id)
        case .unknown: return expr   // never satisfied
        case .all(let xs):
            let trimmed = xs.map { prune($0, pool: pool) }.filter {
                if case .empty = $0 { return false } else { return true }
            }
            if trimmed.isEmpty { return .empty }
            if trimmed.count == 1 { return trimmed[0] }
            return .all(trimmed)
        case .any(let xs):
            // if any branch is empty post-prune, the whole group is satisfied
            for branch in xs {
                if case .empty = prune(branch, pool: pool) { return .empty }
            }
            // otherwise, all branches survive
            let trimmed = xs.map { prune($0, pool: pool) }
            if trimmed.count == 1 { return trimmed[0] }
            return .any(trimmed)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter PrereqEvaluatorPrereqModeTests`
Expected: 6 pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PlannerCore/PlannerCore.swift Tests/PlannerCoreTests/PrereqEvaluatorTests.swift
git commit -m "Add PrereqEvaluator with prereq-mode evaluation"
```

---

## Task 12: Coreq-mode evaluation tests

**Files:**
- Modify: `Tests/PlannerCoreTests/PrereqEvaluatorTests.swift`

- [ ] **Step 1: Write the failing test (none expected to fail; logic already in Task 11)**

Append to `Tests/PlannerCoreTests/PrereqEvaluatorTests.swift`:

```swift
final class PrereqEvaluatorCoreqModeTests: XCTestCase {
    func testCoreqSatisfiedBySameTerm() {
        let e = PrereqEvaluator(completedBefore: [], scheduledThisTerm: ["math-235"])
        if case .satisfied = e.evaluate(.course("math-235"), mode: .coreq) { /* ok */ }
        else { XCTFail("expected satisfied") }
    }

    func testCoreqSatisfiedByEarlierTerm() {
        let e = PrereqEvaluator(completedBefore: ["math-235"], scheduledThisTerm: [])
        if case .satisfied = e.evaluate(.course("math-235"), mode: .coreq) { /* ok */ }
        else { XCTFail("expected satisfied") }
    }

    func testCoreqUnsatisfiedWhenAbsent() {
        let e = PrereqEvaluator(completedBefore: [], scheduledThisTerm: ["cs-159"])
        if case .unmet(let missing, _) = e.evaluate(.course("math-235"), mode: .coreq) {
            XCTAssertEqual(missing, .course("math-235"))
        } else { XCTFail("expected unmet") }
    }

    func testPrereqDoesNotAcceptSameTerm() {
        let e = PrereqEvaluator(completedBefore: [], scheduledThisTerm: ["cs-159"])
        if case .unmet = e.evaluate(.course("cs-159"), mode: .prereq) { /* ok */ }
        else { XCTFail("expected unmet in prereq mode") }
    }
}
```

- [ ] **Step 2: Run to verify pass**

Run: `swift test --filter PrereqEvaluatorCoreqModeTests`
Expected: 4 pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/PlannerCoreTests/PrereqEvaluatorTests.swift
git commit -m "Add PrereqEvaluator coreq-mode tests"
```

---

## Task 13: Wire evaluator into `ConflictDetector.warnings(...)`

**Files:**
- Modify: `Sources/PlannerCore/PlannerCore.swift:866-906` (the existing `warnings(for:overrides:)` method)
- Modify: `Tests/PlannerCoreTests/ConflictAndProgressTests.swift`

- [ ] **Step 1: Write the failing test**

Append a new test class to `Tests/PlannerCoreTests/ConflictAndProgressTests.swift`:

```swift
final class ConflictDetectorPrereqWiringTests: XCTestCase {
    private let catalog = makeStubCatalogWithCS240AndMath235()

    func testUnmetPrereqInLaterTermFiresWarning() {
        // Pathway places CS 240 in Fall 2025 with no CS 159 anywhere.
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2025, term: .fall), courseIDs: ["cs-240"])
        ])
        let warnings = ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: [])
        XCTAssertTrue(warnings.contains { $0.kind == .missingPrerequisite && $0.courseID == "cs-240" })
    }

    func testCoreqViolationFires() {
        // CS 240 has coreq MATH 235; pathway places CS 240 in Fall 2025 without MATH 235 anywhere.
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2025, term: .fall), courseIDs: ["cs-240"])
        ])
        let warnings = ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: [])
        XCTAssertTrue(warnings.contains { $0.kind == .missingCorequisite && $0.courseID == "cs-240" })
    }

    func testPrereqSatisfiedByEarlierTerm() {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2024, term: .fall), courseIDs: ["cs-159", "math-235"]),
            SemesterPlan(id: SemesterIdentity(year: 2025, term: .fall), courseIDs: ["cs-240", "math-235"])
        ])
        let warnings = ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: [])
        XCTAssertFalse(warnings.contains { $0.kind == .missingPrerequisite && $0.courseID == "cs-240" })
    }

    private static func makeStubCatalogWithCS240AndMath235() -> Catalog {
        let cs159 = Course(id: "cs-159", code: "CS 159", title: "Intro", credits: 3, availability: nil, prerequisites: [])
        var cs240 = Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: ["cs-159"])
        cs240.prerequisiteExpr = .course("cs-159")
        cs240.corequisiteExpr = .course("math-235")
        let math235 = Course(id: "math-235", code: "MATH 235", title: "Calc I", credits: 3, availability: nil, prerequisites: [])
        let source = CatalogSource(catalogYear: "2025", issueDate: .now, retrievedDate: .now, sourceURLs: [], retrievalNotes: [])
        return Catalog(source: source, programs: [], courses: [cs159, cs240, math235], apCreditRules: [])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ConflictDetectorPrereqWiringTests`
Expected: failures because the new wiring doesn't exist yet (current detector uses flat `course.prerequisites` only and has no coreq path).

- [ ] **Step 3: Replace the per-semester loop in `warnings(...)`**

In `Sources/PlannerCore/PlannerCore.swift`, find the body of `public func warnings(for pathway: Pathway, overrides: [ConflictOverride]) -> [ConflictWarning]` (around line 866). Replace the for-loop that walks semesters/courses with:

```swift
        var completedBefore: Set<String> = []
        for tc in catalog.apCreditRules.flatMap(\.awardedCourseIDs) {
            completedBefore.insert(tc)
        }
        // Note: TransferCredits arrive via pathway-builder context, not catalog. Existing tests pre-Task-13
        // pass transfer credits via the pathway's earlier semesters. The detector mirrors that, accumulating
        // completedBefore from strictly-earlier real (non-placeholder) course IDs.

        for semester in pathway.semesters.sorted(by: { $0.id < $1.id }) {
            let realInThisTerm = Set(semester.courseIDs.filter { !PathwayPlaceholder.isPlaceholder($0) })
            let evaluator = PrereqEvaluator(completedBefore: completedBefore, scheduledThisTerm: realInThisTerm)

            for courseID in semester.courseIDs where !PathwayPlaceholder.isPlaceholder(courseID) {
                guard let course = catalog.coursesByID[courseID] else { continue }

                if case .unmet(let missing, let original) = evaluator.evaluate(course.prerequisiteExpr, mode: .prereq) {
                    let message = Self.prereqMessage(original: original, missing: missing, hasUnknown: course.hasUnknownPrereqTokens, coursesByID: catalog.coursesByID, satisfied: completedBefore)
                    warnings.append(warning(courseID: courseID, semester: semester.id, kind: .missingPrerequisite, message: message, overrides: overrides))
                }

                if case .unmet(let missing, _) = evaluator.evaluate(course.corequisiteExpr, mode: .coreq) {
                    let rendered = missing.displayString(coursesByID: catalog.coursesByID)
                    warnings.append(warning(courseID: courseID, semester: semester.id, kind: .missingCorequisite, message: "Take alongside this course: \(rendered).", overrides: overrides))
                }
            }
            completedBefore.formUnion(realInThisTerm)
        }
```

Add a static helper to `ConflictDetector`:

```swift
    private static func prereqMessage(original: PrereqExpr, missing: PrereqExpr, hasUnknown: Bool, coursesByID: [String: Course], satisfied: Set<String>) -> String {
        let originalText = original.displayString(coursesByID: coursesByID)
        let missingText = missing.displayString(coursesByID: coursesByID)
        let satisfiedLeaves = collectCourseLeaves(original).filter { satisfied.contains($0) }
        let satisfiedText = satisfiedLeaves.compactMap { coursesByID[$0]?.code }.joined(separator: ", ")
        var msg = "Needs \(originalText)."
        if !satisfiedText.isEmpty {
            msg += " You have \(satisfiedText);"
        }
        msg += " still missing \(missingText)."
        if hasUnknown {
            msg += " Some prereqs couldn't be parsed; verify with the catalog."
        }
        return msg
    }

    private static func collectCourseLeaves(_ expr: PrereqExpr) -> [String] {
        switch expr {
        case .course(let id): return [id]
        case .all(let xs), .any(let xs): return xs.flatMap(collectCourseLeaves)
        default: return []
        }
    }
```

Note: keep the existing `unknownAvailability` and `semesterAvailability` warning generation paths intact. Only the prereq path is rewritten here.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter ConflictDetectorPrereqWiringTests`
Expected: 3 pass.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add Sources/PlannerCore/PlannerCore.swift Tests/PlannerCoreTests/ConflictAndProgressTests.swift
git commit -m "Wire PrereqEvaluator into ConflictDetector with rich warning copy"
```

---

## Task 14: Best-effort schedule fallback

**Files:**
- Modify: `Sources/PlannerCore/PlannerCore.swift:614-665` (`ScheduleGenerator`) + `:748-795` (`buildSemesters`)
- Modify: `Tests/PlannerCoreTests/ScheduleGeneratorTests.swift`

- [ ] **Step 1: Write the failing test**

Append a new class to `Tests/PlannerCoreTests/ScheduleGeneratorTests.swift`:

```swift
final class ScheduleGeneratorBestEffortTests: XCTestCase {
    func testBestEffortPlacesCourseEvenWhenPrereqUnmet() throws {
        // Construct a tiny catalog with CS 240 requiring CS 159 (not present in pool).
        let cs240 = Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: ["cs-159"])
        let source = CatalogSource(catalogYear: "2025", issueDate: .now, retrievedDate: .now, sourceURLs: [], retrievalNotes: [])
        let catalog = Catalog(source: source, programs: [], courses: [cs240], apCreditRules: [])
        let gen = ScheduleGenerator(catalog: catalog)
        // strictPrereqs defaults to false. Should not throw.
        XCTAssertNoThrow(try gen.generatePathways(programID: "n/a", courseIDsToPlace: ["cs-240"], transferCredits: [], workload: .moderate))
    }

    func testStrictPrereqsStillThrows() {
        let cs240 = Course(id: "cs-240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: ["cs-159"])
        let source = CatalogSource(catalogYear: "2025", issueDate: .now, retrievedDate: .now, sourceURLs: [], retrievalNotes: [])
        let catalog = Catalog(source: source, programs: [], courses: [cs240], apCreditRules: [])
        let gen = ScheduleGenerator(catalog: catalog, strictPrereqs: true)
        XCTAssertThrowsError(try gen.generatePathways(programID: "n/a", courseIDsToPlace: ["cs-240"], transferCredits: [], workload: .moderate))
    }
}
```

(Adjust `generatePathways` call signature to match the actual method; inspect `PlannerCore.swift:621` first.)

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ScheduleGeneratorBestEffortTests`
Expected: compile error: `cannot find 'strictPrereqs' in scope`.

- [ ] **Step 3: Add `strictPrereqs` flag and fallback path**

In `Sources/PlannerCore/PlannerCore.swift`, locate `public struct ScheduleGenerator: Sendable {` (~line 614). Add a stored property and update the initializer:

```swift
public struct ScheduleGenerator: Sendable {
    public let catalog: Catalog
    public let strictPrereqs: Bool

    public init(catalog: Catalog, strictPrereqs: Bool = false) {
        self.catalog = catalog
        self.strictPrereqs = strictPrereqs
    }
    // ...existing methods unchanged in body, but buildSemesters now consults strictPrereqs
}
```

In `buildSemesters` (~line 748), find the existing throw site:

```swift
                    throw PlannerError.impossibleSchedule("Could not place the remaining courses while respecting prerequisites and semester availability.")
```

Replace it with:

```swift
                    if strictPrereqs {
                        throw PlannerError.impossibleSchedule("Could not place the remaining courses while respecting prerequisites and semester availability.")
                    }
                    // Best-effort fallback: dump remaining into the final semester (or append one).
                    if result.isEmpty {
                        result.append(SemesterPlan(id: SemesterIdentity(year: Calendar.current.component(.year, from: Date()), term: .fall), courseIDs: Array(unplaced)))
                    } else {
                        let lastIndex = result.count - 1
                        result[lastIndex].courseIDs.append(contentsOf: unplaced)
                    }
                    return result
```

(Where `unplaced` is the local variable name for remaining course IDs at the throw site; match the actual variable name from the surrounding code.)

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter ScheduleGeneratorBestEffortTests`
Expected: 2 pass.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add Sources/PlannerCore/PlannerCore.swift Tests/PlannerCoreTests/ScheduleGeneratorTests.swift
git commit -m "Add strictPrereqs flag and best-effort fallback to ScheduleGenerator"
```

---

## Task 15: Multi-line warning copy + coreq icon

**Files:**
- Modify: `Sources/JMUCoursePlanner/Views/Tabs/ScheduleBoardView.swift:200-230` (the warning strip view body)

- [ ] **Step 1: Locate the warning strip**

Run: `grep -n 'warningStrip\|exclamationmark.triangle.fill' Sources/JMUCoursePlanner/Views/Tabs/ScheduleBoardView.swift`
Expected: the `warningStrip(_:)` function and the icon site.

- [ ] **Step 2: Replace the icon decision + Text line**

In `warningStrip(_ warning:)` (or equivalent), find the icon `Image(systemName: ...)` and the message `Text(warning.message)`. Replace the icon line:

```swift
            Image(systemName: iconName(for: warning.kind))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(warning.isOverridden ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.warning)
```

And add this helper inside the same file (private function):

```swift
    private func iconName(for kind: ConflictKind) -> String {
        switch kind {
        case .missingPrerequisite, .unknownAvailability, .semesterAvailability:
            return "exclamationmark.triangle.fill"
        case .missingCorequisite:
            return "arrow.left.arrow.right.circle.fill"
        }
    }
```

Replace `Text(warning.message)` with:

```swift
            Text(warning.message)
                .font(DesignTokens.Typography.caption)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(warning.isOverridden ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.warning)
```

(`.lineLimit(nil)` + `.fixedSize(horizontal: false, vertical: true)` lets the strip grow vertically to fit the longer prereq copy without truncation.)

- [ ] **Step 3: Rebuild and visually verify**

Run: `./script/build_and_run.sh`
Expected: app launches. Manually trigger a multi-line warning (drag a course into the wrong term) and confirm the strip wraps to multiple lines and shows the correct icon for prereq vs coreq.

- [ ] **Step 4: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Tabs/ScheduleBoardView.swift
git commit -m "Multi-line warning copy + coreq icon in ScheduleBoardView"
```

---

## Task 16: Course Detail prereq/coreq sections

**Files:**
- Modify: `Sources/JMUCoursePlanner/Views/CourseDetailSheet.swift`

- [ ] **Step 1: Locate the existing meta layout**

Run: `grep -n 'CourseDetailSheet\|availability\|VStack' Sources/JMUCoursePlanner/Views/CourseDetailSheet.swift | head -20`
Expected: sheet body's section layout.

- [ ] **Step 2: Add prereq/coreq sections**

Inside the sheet's main `VStack`, between the existing availability section and the next block, insert:

```swift
            if case .empty = course.prerequisiteExpr {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Prereqs")
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .textCase(.uppercase)
                    Text(course.prerequisiteExpr.displayString(coursesByID: catalog.coursesByID))
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    if course.hasUnknownPrereqTokens {
                        Text("Some terms couldn't be parsed. See JMU catalog.")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            }

            if case .empty = course.corequisiteExpr {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Coreqs")
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .textCase(.uppercase)
                    Text(course.corequisiteExpr.displayString(coursesByID: catalog.coursesByID))
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
            }
```

(`catalog` is the existing dependency on the sheet; rename if the local property differs.)

- [ ] **Step 3: Rebuild and visually verify**

Run: `./script/build_and_run.sh`
Expected: open Course Detail for a CS course; PREREQS section renders.

- [ ] **Step 4: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/CourseDetailSheet.swift
git commit -m "Show parsed prereq/coreq sections in CourseDetailSheet"
```

---

## Task 17: Catalog cache version bump

**Files:**
- Modify: `Sources/JMUCoursePlanner/Services/CatalogRepository.swift`

- [ ] **Step 1: Identify the cache location and any version constant**

Run: `grep -n 'Catalog/\|appending(path: "Catalog\|schemaVersion\|cacheVersion' Sources/JMUCoursePlanner/Services/CatalogRepository.swift`
Expected: a constant or path the repository uses to read/write the cache. If no schema constant exists, add one.

- [ ] **Step 2: Bump or introduce the schema constant**

Near the top of `CatalogRepository`, add:

```swift
    /// Bump this when the on-disk catalog shape changes so cached blobs are re-parsed.
    private static let schemaVersion: Int = 2
```

If a constant already exists, increment it. Append the version to the cache directory or file name so old caches are ignored: change the cache file path from `support.appending(path: "Catalog", directoryHint: .isDirectory)` to `support.appending(path: "Catalog-v\(Self.schemaVersion)", directoryHint: .isDirectory)`.

Update the corresponding write site to use the same versioned path.

In `resetAppData()` (around line 193), update the removed path to match the new versioned directory.

- [ ] **Step 3: Manual verification**

Run: `./script/build_and_run.sh`
Expected: app launches; first launch after this change re-parses the catalog from source (any progress indicator or status message reflects this). Confirm no errors in console.

- [ ] **Step 4: Commit**

```bash
git add Sources/JMUCoursePlanner/Services/CatalogRepository.swift
git commit -m "Bump CatalogRepository schema version to invalidate old prereq-less cache"
```

---

## Task 18: Seed regeneration

**Files:**
- Create: `script/regenerate_seed.swift`
- Modify: `Data/catalog_seed.json`

- [ ] **Step 1: Write the regenerator**

Create `script/regenerate_seed.swift`:

```swift
#!/usr/bin/env swift sh
// swift-tools-version: 5.10
// One-shot: re-parses live HTML fixtures + any cached programs, writes a fresh
// catalog_seed.json with parsed prerequisiteExpr/corequisiteExpr populated.
//
// Usage: from the repo root, `swift run regenerate_seed` (if registered as an
// executable target) or `swift script/regenerate_seed.swift`.

import Foundation
import PlannerCore

@main
struct Regenerator {
    static func main() throws {
        let fixturesDir = URL(fileURLWithPath: "Tests/PlannerCoreTests")
        let html = try [
            "_live_cs.html", "_live_accounting.html", "_live_nursing.html",
            "_live_psyc.html", "_live_gened.html"
        ].map { try String(contentsOf: fixturesDir.appendingPathComponent($0)) }

        // Parse each fixture, collect all programs and the union of courses.
        var allCourses: [Course] = []
        var allPrograms: [Program] = []
        let parser = JMUHTMLCatalogParser()
        for body in html {
            let result = try parser.parseProgramHTML(body, baseURL: URL(string: "https://example.test/")!, catoid: 1)
            allPrograms.append(contentsOf: result.programs)
            allCourses.append(contentsOf: result.courses)
        }

        // Pass 2: parse prereq text into structured expressions.
        CatalogPrereqResolver.applyPassTwo(to: &allCourses)

        let source = CatalogSource(catalogYear: "2025-2026", issueDate: .now, retrievedDate: .now, sourceURLs: [], retrievalNotes: ["Regenerated by script/regenerate_seed.swift"])
        let catalog = Catalog(source: source, programs: allPrograms, courses: allCourses, apCreditRules: [])
        let json = try JSONEncoder.prettyEncoder.encode(catalog)
        try json.write(to: URL(fileURLWithPath: "Data/catalog_seed.json"))
        print("Wrote Data/catalog_seed.json (\(allCourses.count) courses, \(allPrograms.count) programs).")
    }
}

extension JSONEncoder {
    static var prettyEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
```

Mark executable: `chmod +x script/regenerate_seed.swift`.

(If `parseProgramHTML` is named differently in `JMUHTMLCatalogParser`, match the actual API at the file Task 9 modified.)

- [ ] **Step 2: Run it**

Run: `swift script/regenerate_seed.swift`
Expected: output `Wrote Data/catalog_seed.json (N courses, M programs).` and a modified `Data/catalog_seed.json` on disk.

- [ ] **Step 3: Sanity-check the result**

Run: `python3 -c "import json; d=json.load(open('Data/catalog_seed.json')); print(len(d['courses']), 'courses,', sum(1 for c in d['courses'] if c.get('prerequisiteExpr',{}).get('kind') != 'empty'), 'with parsed prereqs')"`
Expected: a non-trivial fraction (≥30%) of courses have non-empty `prerequisiteExpr`.

- [ ] **Step 4: Run the full test suite**

Run: `swift test`
Expected: green. The new seed should not break any existing test.

- [ ] **Step 5: Rebuild app and visually confirm**

Run: `./script/build_and_run.sh`
Expected: app launches; opening a CS-major plan now surfaces parsed prereqs on Schedule warnings or Course Detail sheet.

- [ ] **Step 6: Commit**

```bash
git add script/regenerate_seed.swift Data/catalog_seed.json
git commit -m "Regenerate catalog_seed.json with parsed prereq/coreq expressions"
```

---

## Task 19: Manual UAT pass

**Files:** none (verification only)

- [ ] **Step 1: Build and launch**

Run: `./script/build_and_run.sh`
Expected: app launches cleanly.

- [ ] **Step 2: Trigger setup or open an existing CS BBA plan**

Confirm: My Plan tab loads with the existing or freshly generated plan.

- [ ] **Step 3: Schedule tab manual prereq violation**

Find CS 240 (or any course with a parsed prereq) in the catalog. Drag it into a term BEFORE its prereq's term. Confirm: a warning strip appears under the course chip in the same render frame, text reads roughly `"Needs CS 159. still missing CS 159."` Click `Keep` to override.

- [ ] **Step 4: Coreq violation**

Drag a course with a parsed coreq into a term where the coreq is absent in that term and all earlier terms. Confirm: a separate warning strip with the coreq icon (`arrow.left.arrow.right.circle.fill`) appears with text `"Take alongside this course: <code>."`

- [ ] **Step 5: Course Detail prereq display**

Open Course Detail for CS 240 (or equivalent). Confirm: PREREQS section displays the parsed expression. If the course has unknowns, the "Some terms couldn't be parsed" caption is visible.

- [ ] **Step 6: Persistence**

Quit the app (`pkill -x JMUCoursePlanner`). Relaunch via `./script/build_and_run.sh`. Confirm: any `Keep` override from Step 3 still persists; the warning shows the muted/overridden style.

- [ ] **Step 7: Build green**

Run: `swift build && swift test`
Expected: both green.

- [ ] **Step 8: Commit anything outstanding (likely nothing)**

Run: `git status`
Expected: clean working tree.

---

## Self-Review Pass

The plan has been internally reviewed once with the following checks:

**Spec coverage.** Every numbered section in `docs/superpowers/specs/2026-05-21-prereq-coreq-parsing-design.md` maps to one or more tasks:

| Spec section | Tasks |
|---|---|
| §4 Data Model | 1, 2, 3 |
| §5 Parser | 4, 5, 6, 7, 8 |
| §6 Catalog Parser Integration | 9, 10 |
| §7 Conflict Detection | 11, 12, 13 |
| §8 Scheduler | 14 |
| §9 UI | 15, 16 |
| §10 Persistence & Migration | 17, 18 |
| §11 Test Plan | embedded in tasks 1–14 |
| §12 Acceptance Criteria | 19 |
| §13 Open Risks | flagged in Task 10 (cross-program orchestration) and Task 5 (lexer false-positives, covered in live-fixture tests in Task 8) |
| §14 Out-of-Scope | not implemented; TODO comments placed inline during Task 5 and Task 6 |

**Placeholder scan.** No "TBD", "TODO", "implement later", or "similar to Task N" in any task body. Each step that touches code shows the code.

**Type consistency.** `PrereqExpr`, `ParseResult`, `PrereqEvaluator`, `CatalogPrereqResolver`, `ConflictKind.missingCorequisite`, `Course.prerequisiteExpr`, `Course.corequisiteExpr`, `Course.hasUnknownPrereqTokens`, `Course.rawPrerequisiteText`, `ScheduleGenerator.strictPrereqs` all spelled identically across the tasks that introduce them and the tasks that consume them.

**Scope check.** Single subsystem (catalog prereq/coreq enforcement). Each task produces a working, testable atomic commit.
