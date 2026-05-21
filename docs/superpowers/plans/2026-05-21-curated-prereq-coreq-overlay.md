# Curated Prerequisite/Corequisite Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a source-backed curated prerequisite/corequisite overlay that wins over parser output while preserving parser and legacy prerequisite fallbacks.

**Architecture:** PlannerCore owns the overlay data model and a pure `PrereqRuleResolver` that resolves effective prereq/coreq rules in this order: curated overlay, raw catalog parser, legacy flat prerequisites, empty. `Catalog` carries the overlay so `ScheduleGenerator`, `ConflictDetector`, and SwiftUI course details all see the same rule source. The app repository loads `Data/prereq_coreq_overrides.json` beside `catalog_seed.json`, and validation scripts keep the agent-authored data source-backed and internally consistent.

**Tech Stack:** Swift 6 package, PlannerCore, SwiftUI, Codable, Swift Testing/XCTest, Foundation JSON tooling. No new external dependencies.

**Source spec:** [`docs/superpowers/specs/2026-05-21-curated-prereq-coreq-overlay-design.md`](../specs/2026-05-21-curated-prereq-coreq-overlay-design.md)

---

## File Structure

**Create:**
- `Sources/PlannerCore/PrereqRuleOverlay.swift` - overlay Codable types, resolver, helper validation primitives.
- `Tests/PlannerCoreTests/PrereqRuleOverlayTests.swift` - overlay decoding and resolver priority tests.
- `Data/prereq_coreq_overrides.json` - separate curated overlay file.
- `script/validate_prereq_overlay.swift` - standalone JSON validator and coverage reporter.

**Modify:**
- `Sources/PlannerCore/PlannerCore.swift` - add `Catalog.prereqRuleOverlay`, custom `Catalog` Codable defaults, fixture support, scheduler resolver usage, conflict detector resolver usage and richer messages.
- `Sources/JMUCoursePlanner/Services/CatalogRepository.swift` - load overlay beside seed/cache, tolerate missing/invalid overlay, bump cache schema.
- `Sources/JMUCoursePlanner/Views/CourseDetailSheet.swift` - display resolver-backed prereqs/coreqs, confidence, source text, and notes.
- `script/build_and_run.sh` - copy `prereq_coreq_overrides.json` into the app bundle resources.
- `Tests/PlannerCoreTests/ScheduleGeneratorTests.swift` - scheduler overlay behavior tests.
- `Tests/PlannerCoreTests/ConflictAndProgressTests.swift` - warning source/confidence tests.
- `Tests/PlannerCoreTests/CourseDetailCacheTests.swift` - app repository overlay loading tests.

**Read-only during implementation:**
- `docs/superpowers/specs/2026-05-21-curated-prereq-coreq-overlay-design.md`
- Existing dirty `dist/` bundle files unless the user explicitly asks to rebuild the app bundle.

---

## Task 1: Add Overlay Models And Resolver

**Files:**
- Create: `Sources/PlannerCore/PrereqRuleOverlay.swift`
- Create: `Tests/PlannerCoreTests/PrereqRuleOverlayTests.swift`

- [ ] **Step 1: Write failing overlay/resolver tests**

Create `Tests/PlannerCoreTests/PrereqRuleOverlayTests.swift`:

```swift
import Foundation
import XCTest
@testable import PlannerCore

final class PrereqRuleOverlayTests: XCTestCase {
    private let sourceURL = URL(string: "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=123&print")!

    func testOverlayJSONDecodesExplicitAndInferredRules() throws {
        let json = """
        {
          "schemaVersion": 1,
          "rules": [
            {
              "courseID": "CS240",
              "prerequisiteExpr": { "kind": "course", "value": "CS159" },
              "corequisiteExpr": { "kind": "empty" },
              "confidence": "curated",
              "basis": "explicit",
              "sourceURL": "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=123&print",
              "sourceText": "Prerequisite: CS 159.",
              "notes": "Catalog wording directly names CS 159."
            },
            {
              "courseID": "CS345",
              "prerequisiteExpr": { "kind": "course", "value": "CS240" },
              "corequisiteExpr": { "kind": "empty" },
              "confidence": "curated",
              "basis": "inferred",
              "sourceURL": "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=999&print",
              "sourceText": "The program sequence lists CS 240 before CS 345.",
              "notes": "Official sequence presents CS 240 as required preparation before CS 345."
            }
          ]
        }
        """.data(using: .utf8)!

        let overlay = try JSONDecoder().decode(PrereqRuleOverlay.self, from: json)

        XCTAssertEqual(overlay.schemaVersion, 1)
        XCTAssertEqual(overlay.rules.count, 2)
        XCTAssertEqual(overlay.rule(for: "CS240")?.basis, .explicit)
        XCTAssertEqual(overlay.rule(for: "CS345")?.basis, .inferred)
    }

    func testResolverPrefersCuratedOverlayOverRawParserText() throws {
        var cs240 = Course(id: "CS240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: CS 159."
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS149", code: "CS 149", title: "Intro", credits: 3, availability: nil, prerequisites: []),
                Course(id: "CS159", code: "CS 159", title: "Advanced", credits: 3, availability: nil, prerequisites: []),
                cs240
            ],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: [])
        )
        let overlay = PrereqRuleOverlay(schemaVersion: 1, rules: [
            PrereqRule(
                courseID: "CS240",
                prerequisiteExpr: .course("CS149"),
                corequisiteExpr: .empty,
                confidence: .curated,
                basis: .explicit,
                sourceURL: sourceURL,
                sourceText: "Prerequisite: CS 149.",
                notes: "Curated rule must win over stale parser text."
            )
        ])

        let resolved = PrereqRuleResolver(catalog: catalog, overlay: overlay)
            .rule(for: cs240, activeProgramTitle: "Computer Science, B.S.")

        XCTAssertEqual(resolved.prerequisiteExpr, .course("CS149"))
        XCTAssertEqual(resolved.confidence, .curated)
        XCTAssertEqual(resolved.basis, .explicit)
        XCTAssertEqual(resolved.sourceText, "Prerequisite: CS 149.")
    }

    func testResolverFallsBackToRawCatalogParser() throws {
        var cs240 = Course(id: "CS240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: CS 159."
        cs240.descriptionSourceURL = sourceURL
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS159", code: "CS 159", title: "Advanced", credits: 3, availability: nil, prerequisites: []),
                cs240
            ],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: [])
        )

        let resolved = PrereqRuleResolver(catalog: catalog, overlay: .empty)
            .rule(for: cs240, activeProgramTitle: nil)

        XCTAssertEqual(resolved.prerequisiteExpr, .course("CS159"))
        XCTAssertEqual(resolved.confidence, .parsed)
        XCTAssertEqual(resolved.sourceURL, sourceURL)
        XCTAssertEqual(resolved.sourceText, "Prerequisite: CS 159.")
    }

    func testResolverFallsBackToLegacyFlatPrerequisites() throws {
        let cs240 = Course(id: "CS240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: ["CS159", "MATH235"])
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS159", code: "CS 159", title: "Advanced", credits: 3, availability: nil, prerequisites: []),
                Course(id: "MATH235", code: "MATH 235", title: "Calculus", credits: 4, availability: nil, prerequisites: []),
                cs240
            ],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: [])
        )

        let resolved = PrereqRuleResolver(catalog: catalog, overlay: .empty)
            .rule(for: cs240, activeProgramTitle: nil)

        XCTAssertEqual(resolved.prerequisiteExpr, .all([.course("CS159"), .course("MATH235")]))
        XCTAssertEqual(resolved.corequisiteExpr, .empty)
        XCTAssertEqual(resolved.confidence, .parsed)
    }

    func testResolverReturnsNoneForCourseWithoutKnownRequirements() throws {
        let cs149 = Course(id: "CS149", code: "CS 149", title: "Intro", credits: 3, availability: nil, prerequisites: [])
        let catalog = Catalog.fixture(
            courses: [cs149],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: [])
        )

        let resolved = PrereqRuleResolver(catalog: catalog, overlay: .empty)
            .rule(for: cs149, activeProgramTitle: nil)

        XCTAssertEqual(resolved.prerequisiteExpr, .empty)
        XCTAssertEqual(resolved.corequisiteExpr, .empty)
        XCTAssertEqual(resolved.confidence, .none)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter PrereqRuleOverlayTests`

Expected: build fails because `PrereqRuleOverlay`, `PrereqRule`, `PrereqRuleResolver`, `ResolvedPrereqRule`, `PrereqRuleConfidence`, and `PrereqRuleBasis` do not exist.

- [ ] **Step 3: Create the overlay model and resolver**

Create `Sources/PlannerCore/PrereqRuleOverlay.swift`:

```swift
import Foundation

public enum PrereqRuleConfidence: String, Codable, Hashable, Sendable {
    case curated
    case parsed
    case none

    public var displayName: String {
        switch self {
        case .curated: "Curated"
        case .parsed: "Parsed from catalog"
        case .none: "No known rule"
        }
    }
}

public enum PrereqRuleBasis: String, Codable, Hashable, Sendable {
    case explicit
    case inferred

    public var displayName: String {
        switch self {
        case .explicit: "Explicit catalog rule"
        case .inferred: "Source-backed inference"
        }
    }
}

public struct PrereqRuleOverlay: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var rules: [PrereqRule]

    public static let empty = PrereqRuleOverlay(schemaVersion: 1, rules: [])

    public init(schemaVersion: Int, rules: [PrereqRule]) {
        self.schemaVersion = schemaVersion
        self.rules = rules
    }

    public func rule(for courseID: String) -> PrereqRule? {
        rules.first { $0.courseID == courseID }
    }
}

public struct PrereqRule: Codable, Hashable, Sendable {
    public var courseID: String
    public var prerequisiteExpr: PrereqExpr
    public var corequisiteExpr: PrereqExpr
    public var confidence: PrereqRuleConfidence
    public var basis: PrereqRuleBasis
    public var sourceURL: URL
    public var sourceText: String
    public var notes: String?

    public init(
        courseID: String,
        prerequisiteExpr: PrereqExpr,
        corequisiteExpr: PrereqExpr,
        confidence: PrereqRuleConfidence,
        basis: PrereqRuleBasis,
        sourceURL: URL,
        sourceText: String,
        notes: String? = nil
    ) {
        self.courseID = courseID
        self.prerequisiteExpr = prerequisiteExpr
        self.corequisiteExpr = corequisiteExpr
        self.confidence = confidence
        self.basis = basis
        self.sourceURL = sourceURL
        self.sourceText = sourceText
        self.notes = notes
    }
}

public struct ResolvedPrereqRule: Hashable, Sendable {
    public var courseID: String
    public var prerequisiteExpr: PrereqExpr
    public var corequisiteExpr: PrereqExpr
    public var confidence: PrereqRuleConfidence
    public var basis: PrereqRuleBasis?
    public var sourceText: String?
    public var sourceURL: URL?
    public var notes: String?
    public var hasUnknownTokens: Bool

    public init(
        courseID: String,
        prerequisiteExpr: PrereqExpr,
        corequisiteExpr: PrereqExpr,
        confidence: PrereqRuleConfidence,
        basis: PrereqRuleBasis? = nil,
        sourceText: String? = nil,
        sourceURL: URL? = nil,
        notes: String? = nil,
        hasUnknownTokens: Bool = false
    ) {
        self.courseID = courseID
        self.prerequisiteExpr = prerequisiteExpr
        self.corequisiteExpr = corequisiteExpr
        self.confidence = confidence
        self.basis = basis
        self.sourceText = sourceText
        self.sourceURL = sourceURL
        self.notes = notes
        self.hasUnknownTokens = hasUnknownTokens
    }
}

public struct PrereqRuleResolver: Sendable {
    public var catalog: Catalog
    public var overlay: PrereqRuleOverlay

    public init(catalog: Catalog, overlay: PrereqRuleOverlay? = nil) {
        self.catalog = catalog
        self.overlay = overlay ?? catalog.prereqRuleOverlay
    }

    public func rule(for course: Course, activeProgramTitle: String?) -> ResolvedPrereqRule {
        if let curated = overlay.rule(for: course.id) {
            return ResolvedPrereqRule(
                courseID: course.id,
                prerequisiteExpr: curated.prerequisiteExpr,
                corequisiteExpr: curated.corequisiteExpr,
                confidence: .curated,
                basis: curated.basis,
                sourceText: curated.sourceText,
                sourceURL: curated.sourceURL,
                notes: curated.notes,
                hasUnknownTokens: curated.prerequisiteExpr.containsUnknown || curated.corequisiteExpr.containsUnknown
            )
        }

        let trimmedRaw = course.rawPrerequisiteText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedRaw.isEmpty {
            let parser = PrereqParser(coursesByID: catalog.coursesByID, activeProgramTitle: activeProgramTitle)
            let parsed = parser.parse(trimmedRaw)
            return ResolvedPrereqRule(
                courseID: course.id,
                prerequisiteExpr: parsed.prerequisiteExpr,
                corequisiteExpr: parsed.corequisiteExpr,
                confidence: .parsed,
                sourceText: trimmedRaw,
                sourceURL: course.descriptionSourceURL ?? course.registrarURL,
                notes: parsed.hasUnknownTokens ? "Some catalog text could not be converted to course-only prereq/coreq rules." : nil,
                hasUnknownTokens: parsed.hasUnknownTokens
            )
        }

        if course.prerequisiteExpr != .empty || course.corequisiteExpr != .empty {
            return ResolvedPrereqRule(
                courseID: course.id,
                prerequisiteExpr: course.prerequisiteExpr,
                corequisiteExpr: course.corequisiteExpr,
                confidence: .parsed,
                sourceText: nil,
                sourceURL: course.descriptionSourceURL ?? course.registrarURL,
                notes: course.hasUnknownPrereqTokens ? "Some catalog text could not be converted to course-only prereq/coreq rules." : nil,
                hasUnknownTokens: course.hasUnknownPrereqTokens
            )
        }

        if !course.prerequisites.isEmpty {
            return ResolvedPrereqRule(
                courseID: course.id,
                prerequisiteExpr: Self.legacyPrerequisiteExpr(course.prerequisites),
                corequisiteExpr: .empty,
                confidence: .parsed,
                sourceText: nil,
                sourceURL: course.descriptionSourceURL ?? course.registrarURL,
                notes: nil,
                hasUnknownTokens: false
            )
        }

        return ResolvedPrereqRule(
            courseID: course.id,
            prerequisiteExpr: .empty,
            corequisiteExpr: .empty,
            confidence: .none
        )
    }

    private static func legacyPrerequisiteExpr(_ prerequisites: [String]) -> PrereqExpr {
        switch prerequisites.count {
        case 0: return .empty
        case 1: return .course(prerequisites[0])
        default: return .all(prerequisites.map(PrereqExpr.course))
        }
    }
}

public extension PrereqExpr {
    var containsUnknown: Bool {
        switch self {
        case .unknown:
            return true
        case .all(let children), .any(let children):
            return children.contains { $0.containsUnknown }
        default:
            return false
        }
    }

    var courseLeaves: [String] {
        switch self {
        case .course(let id):
            return [id]
        case .all(let children), .any(let children):
            return children.flatMap(\.courseLeaves)
        default:
            return []
        }
    }
}
```

- [ ] **Step 4: Run tests to verify the expected remaining failure**

Run: `swift test --filter PrereqRuleOverlayTests`

Expected: build fails on `catalog.prereqRuleOverlay`, because `Catalog` does not yet carry the overlay. Task 2 adds it.

- [ ] **Step 5: Commit**

Do not commit yet if Task 2 is not complete, because Task 1 intentionally leaves the package not building.

---

## Task 2: Add Overlay To Catalog With Backward-Compatible Codable

**Files:**
- Modify: `Sources/PlannerCore/PlannerCore.swift`
- Modify: `Tests/PlannerCoreTests/PrereqRuleOverlayTests.swift`

- [ ] **Step 1: Add failing Catalog decode/default tests**

Append these tests to `PrereqRuleOverlayTests`:

```swift
final class CatalogPrereqOverlayCodableTests: XCTestCase {
    func testCatalogDefaultsToEmptyOverlayWhenDecodedFromOldJSON() throws {
        let json = """
        {
          "source": {
            "catalogYear": "Fixture",
            "issueDate": "1970-01-01T00:00:00Z",
            "retrievedDate": "1970-01-01T00:00:00Z",
            "sourceURLs": [],
            "retrievalNotes": []
          },
          "programs": [],
          "courses": [],
          "apCreditRules": []
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let catalog = try decoder.decode(Catalog.self, from: json)

        XCTAssertEqual(catalog.prereqRuleOverlay, .empty)
    }

    func testCatalogRoundTripsOverlay() throws {
        let overlay = PrereqRuleOverlay(schemaVersion: 1, rules: [
            PrereqRule(
                courseID: "CS240",
                prerequisiteExpr: .course("CS159"),
                corequisiteExpr: .empty,
                confidence: .curated,
                basis: .explicit,
                sourceURL: URL(string: "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=123&print")!,
                sourceText: "Prerequisite: CS 159.",
                notes: nil
            )
        ])
        let catalog = Catalog.fixture(
            courses: [],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: []),
            prereqRuleOverlay: overlay
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(catalog)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(Catalog.self, from: data)

        XCTAssertEqual(decoded.prereqRuleOverlay, overlay)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter CatalogPrereqOverlayCodableTests`

Expected: build fails because `Catalog.prereqRuleOverlay` and the fixture argument do not exist.

- [ ] **Step 3: Update `Catalog`**

In `Sources/PlannerCore/PlannerCore.swift`, replace the existing `public struct Catalog` block with:

```swift
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
```

Then update the fixture near the bottom of `PlannerCore.swift`:

```swift
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
```

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter PrereqRuleOverlayTests`

Expected: all tests in `PrereqRuleOverlayTests.swift` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PlannerCore/PrereqRuleOverlay.swift Sources/PlannerCore/PlannerCore.swift Tests/PlannerCoreTests/PrereqRuleOverlayTests.swift
git commit -m "feat: add curated prereq rule resolver"
```

---

## Task 3: Load Overlay File Beside Catalog Seed

**Files:**
- Create: `Data/prereq_coreq_overrides.json`
- Modify: `Sources/JMUCoursePlanner/Services/CatalogRepository.swift`
- Modify: `script/build_and_run.sh`
- Modify: `Tests/PlannerCoreTests/CourseDetailCacheTests.swift`

- [ ] **Step 1: Create the valid starter overlay file**

Create `Data/prereq_coreq_overrides.json`:

```json
{
  "schemaVersion": 1,
  "rules": []
}
```

- [ ] **Step 2: Add failing repository tests**

Append to `Tests/PlannerCoreTests/CourseDetailCacheTests.swift`:

```swift
@Suite("Prereq overlay repository loading")
struct PrereqOverlayRepositoryTests {
    @MainActor
    @Test("repository decodes prereq overlay JSON")
    func repositoryDecodesPrereqOverlayJSON() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let overlayURL = directory.appending(path: "prereq_coreq_overrides.json")
        try """
        {
          "schemaVersion": 1,
          "rules": [
            {
              "courseID": "CS240",
              "prerequisiteExpr": { "kind": "course", "value": "CS159" },
              "corequisiteExpr": { "kind": "empty" },
              "confidence": "curated",
              "basis": "explicit",
              "sourceURL": "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=123&print",
              "sourceText": "Prerequisite: CS 159.",
              "notes": "Direct catalog rule."
            }
          ]
        }
        """.write(to: overlayURL, atomically: true, encoding: .utf8)

        let overlay = try CatalogRepository().loadPrereqRuleOverlay(from: overlayURL)

        #expect(overlay.schemaVersion == 1)
        #expect(overlay.rule(for: "CS240")?.prerequisiteExpr == .course("CS159"))
    }

    @MainActor
    @Test("repository treats invalid prereq overlay as non-fatal parser fallback")
    func repositoryTreatsInvalidPrereqOverlayAsNonFatalFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let overlayURL = directory.appending(path: "prereq_coreq_overrides.json")
        try "{ invalid json".write(to: overlayURL, atomically: true, encoding: .utf8)

        let status = CatalogRepository().optionalPrereqRuleOverlay(from: overlayURL)

        #expect(status.overlay == .empty)
        #expect(status.note.contains("parser fallback"))
    }

    @MainActor
    @Test("repository attaches current overlay to bundled catalog")
    func repositoryAttachesCurrentOverlayToBundledCatalog() throws {
        let catalog = try CatalogRepository().loadBundledCatalog()

        #expect(catalog.prereqRuleOverlay.schemaVersion == 1)
        #expect(catalog.source.retrievalNotes.contains { $0.contains("prereq/coreq overlay") })
    }
}
```

- [ ] **Step 3: Run tests to verify failure**

Run: `swift test --filter PrereqOverlayRepositoryTests`

Expected: build fails because `CatalogRepository.loadPrereqRuleOverlay(from:)` and `CatalogRepository.optionalPrereqRuleOverlay(from:)` do not exist.

- [ ] **Step 4: Add repository loading helpers**

In `Sources/JMUCoursePlanner/Services/CatalogRepository.swift`, add this method after `loadBundledCatalog()`:

```swift
    func loadPrereqRuleOverlay(from url: URL) throws -> PrereqRuleOverlay {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(PrereqRuleOverlay.self, from: data)
    }

    func optionalPrereqRuleOverlay(from url: URL?) -> (overlay: PrereqRuleOverlay, note: String) {
        guard let url else {
            return (.empty, "Curated prereq/coreq overlay unavailable; parser fallback active.")
        }
        do {
            let overlay = try loadPrereqRuleOverlay(from: url)
            return (overlay, "Curated prereq/coreq overlay loaded with \(overlay.rules.count) rule(s).")
        } catch {
            return (.empty, "Curated prereq/coreq overlay could not be loaded; parser fallback active.")
        }
    }
```

Change `loadCatalog()` so cached catalogs always get the current overlay:

```swift
    func loadCatalog() throws -> Catalog {
        if var cached = try? loadCachedHTMLCatalog() {
            if let bundled = try? loadBundledCatalog() {
                cached = Catalog(
                    source: cached.source,
                    programs: cached.programs,
                    courses: cached.courses,
                    apCreditRules: bundled.apCreditRules,
                    prereqRuleOverlay: .empty
                )
            }
            return attachCurrentPrereqOverlay(to: cached)
        }
        return try loadBundledCatalog()
    }
```

Change `loadBundledCatalog()`:

```swift
    func loadBundledCatalog() throws -> Catalog {
        let url = try bundledCatalogURL()
        let data = try Data(contentsOf: url)
        let seed = try SeedCatalog.decode(from: data)
        return attachCurrentPrereqOverlay(to: seed.catalog())
    }
```

When constructing the refreshed `Catalog`, build the catalog normally, then attach the current overlay before saving:

```swift
        let catalog = attachCurrentPrereqOverlay(to: Catalog(
            source: catalogSource,
            programs: refreshedPrograms.sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.title < rhs.title
            },
            courses: coursesByID.values.sorted { $0.code < $1.code },
            apCreditRules: seed.apCreditRules
        ))
```

Add these helpers near `bundledCatalogURL()`:

```swift
    private func currentPrereqRuleOverlay() -> PrereqRuleOverlay {
        return optionalPrereqRuleOverlay(from: try? bundledPrereqOverlayURL()).overlay
    }

    private func attachCurrentPrereqOverlay(to catalog: Catalog) -> Catalog {
        let status = optionalPrereqRuleOverlay(from: try? bundledPrereqOverlayURL())
        var source = catalog.source
        source.retrievalNotes.removeAll { $0.contains("prereq/coreq overlay") }
        source.retrievalNotes.append(status.note)
        Catalog(
            source: source,
            programs: catalog.programs,
            courses: catalog.courses,
            apCreditRules: catalog.apCreditRules,
            prereqRuleOverlay: status.overlay
        )
    }

    private func bundledPrereqOverlayURL() throws -> URL {
        let candidates = [
            Bundle.main.url(forResource: "prereq_coreq_overrides", withExtension: "json"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "Data/prereq_coreq_overrides.json")
        ].compactMap { $0 }

        guard let url = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
```

Bump the cache schema comment and value:

```swift
    /// Bump this whenever cached catalog requirement shape changes. v7 adds
    /// the curated prereq/coreq overlay to `Catalog`, so cached catalogs need
    /// the latest separate overlay attached on load.
    private static let cacheSchemaVersion = 7
```

- [ ] **Step 5: Copy overlay into app bundle**

In `script/build_and_run.sh`, after the existing `catalog_seed.json` copy, add:

```bash
cp "$ROOT_DIR/Data/prereq_coreq_overrides.json" "$APP_RESOURCES/prereq_coreq_overrides.json"
```

- [ ] **Step 6: Run focused tests**

Run: `swift test --filter PrereqOverlayRepositoryTests`

Expected: repository overlay tests pass.

- [ ] **Step 7: Commit**

```bash
git add Data/prereq_coreq_overrides.json Sources/JMUCoursePlanner/Services/CatalogRepository.swift script/build_and_run.sh Tests/PlannerCoreTests/CourseDetailCacheTests.swift
git commit -m "feat: load curated prereq overlay"
```

---

## Task 4: Use Resolver In Schedule Generation

**Files:**
- Modify: `Sources/PlannerCore/PlannerCore.swift`
- Modify: `Tests/PlannerCoreTests/ScheduleGeneratorTests.swift`

- [ ] **Step 1: Add failing scheduler test**

Append to `ScheduleGeneratorParsedPrereqTests` in `Tests/PlannerCoreTests/ScheduleGeneratorTests.swift`:

```swift
    @Test("curated overlay any-prereq rule wins during schedule placement")
    func curatedOverlayAnyPrereqWinsDuringSchedulePlacement() throws {
        let cs149 = Course(id: "CS149", code: "CS 149", title: "Intro", credits: 3, availability: [.fall, .spring], prerequisites: [])
        let cs159 = Course(id: "CS159", code: "CS 159", title: "Advanced", credits: 3, availability: [.fall, .spring], prerequisites: [])
        var cs240 = Course(id: "CS240", code: "CS 240", title: "Data", credits: 3, availability: [.fall, .spring], prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: CS 159."
        let overlay = PrereqRuleOverlay(schemaVersion: 1, rules: [
            PrereqRule(
                courseID: "CS240",
                prerequisiteExpr: .any([.course("CS149"), .course("CS159")]),
                corequisiteExpr: .empty,
                confidence: .curated,
                basis: .explicit,
                sourceURL: URL(string: "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=123&print")!,
                sourceText: "Prerequisite: CS 149 or CS 159.",
                notes: "Curated OR group should replace stale parser fallback."
            )
        ])
        let catalog = Catalog.fixture(
            courses: [cs149, cs159, cs240],
            program: Program.fixture(
                id: "cs-bs",
                title: "Computer Science, B.S.",
                requirements: [
                    RequirementCategory(id: "core", name: "Core", requiredCredits: 6, courseOptions: [["CS149"], ["CS240"]])
                ]
            ),
            prereqRuleOverlay: overlay
        )

        let pathway = try #require(try ScheduleGenerator(catalog: catalog, strictPrereqs: true).generatePathways(
            for: "cs-bs",
            workload: .standard,
            transferCredits: [],
            starting: SemesterIdentity(year: 2026, term: .fall)
        ).first)

        let cs149Semester = try #require(pathway.semesters.first { $0.courseIDs.contains("CS149") }?.id)
        let cs240Semester = try #require(pathway.semesters.first { $0.courseIDs.contains("CS240") }?.id)
        #expect(cs149Semester < cs240Semester)
        #expect(!pathway.semesters.flatMap(\.courseIDs).contains("CS159"))
    }
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter ScheduleGeneratorParsedPrereqTests/curatedOverlayAnyPrereqWinsDuringSchedulePlacement`

Expected: strict scheduler throws because it still parses raw text and requires unscheduled `CS159`.

- [ ] **Step 3: Replace scheduler parser priority with resolver priority**

In `ScheduleGenerator.buildSemesters(...)`, replace:

```swift
        let parser = PrereqParser(coursesByID: catalog.coursesByID, activeProgramTitle: activeProgramTitle)
```

with:

```swift
        let resolver = PrereqRuleResolver(catalog: catalog)
```

Inside the course lookup branch, replace:

```swift
                    prerequisiteExpr = effectivePrerequisiteExpr(for: course, parser: parser)
```

with:

```swift
                    prerequisiteExpr = resolver.rule(for: course, activeProgramTitle: activeProgramTitle).prerequisiteExpr
```

Delete the private `ScheduleGenerator.effectivePrerequisiteExpr(for:parser:)` method, because resolver now owns that priority.

- [ ] **Step 4: Run scheduler tests**

Run: `swift test --filter ScheduleGeneratorParsedPrereqTests`

Expected: parsed fallback tests and curated overlay test pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PlannerCore/PlannerCore.swift Tests/PlannerCoreTests/ScheduleGeneratorTests.swift
git commit -m "feat: schedule with curated prereq overlay"
```

---

## Task 5: Use Resolver In Conflict Warnings

**Files:**
- Modify: `Sources/PlannerCore/PlannerCore.swift`
- Modify: `Tests/PlannerCoreTests/ConflictAndProgressTests.swift`

- [ ] **Step 1: Add failing warning tests**

Append to `ConflictDetectorPrereqWiringTests` in `Tests/PlannerCoreTests/ConflictAndProgressTests.swift`:

```swift
    @Test("curated overlay wins over raw parser in conflict detector")
    func curatedOverlayWinsInConflictDetector() throws {
        var cs240 = Course(id: "CS240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: CS 159."
        let overlay = PrereqRuleOverlay(schemaVersion: 1, rules: [
            PrereqRule(
                courseID: "CS240",
                prerequisiteExpr: .course("CS149"),
                corequisiteExpr: .empty,
                confidence: .curated,
                basis: .explicit,
                sourceURL: URL(string: "https://catalog.jmu.edu/preview_course.php?catoid=62&coid=123&print")!,
                sourceText: "Prerequisite: CS 149.",
                notes: nil
            )
        ])
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS149", code: "CS 149", title: "Intro", credits: 3, availability: nil, prerequisites: []),
                Course(id: "CS159", code: "CS 159", title: "Advanced", credits: 3, availability: nil, prerequisites: []),
                cs240
            ],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: []),
            prereqRuleOverlay: overlay
        )
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["CS149"]),
            SemesterPlan(id: SemesterIdentity(year: 2027, term: .spring), courseIDs: ["CS240"])
        ])

        let warnings = ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: [])

        #expect(!warnings.contains { $0.kind == .missingPrerequisite && $0.courseID == "CS240" })
    }

    @Test("parsed prereq warning identifies low-confidence parser source")
    func parsedPrereqWarningIdentifiesParserSource() throws {
        var cs240 = Course(id: "CS240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: [])
        cs240.rawPrerequisiteText = "Prerequisite: CS 159."
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS159", code: "CS 159", title: "Advanced", credits: 3, availability: nil, prerequisites: []),
                cs240
            ],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: [])
        )
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["CS240"])
        ])

        let warning = try #require(ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: []).first {
            $0.kind == .missingPrerequisite && $0.courseID == "CS240"
        })

        #expect(warning.message.contains("Parsed from catalog text; verify before registering."))
    }

    @Test("curated warning appends source-backed note")
    func curatedWarningAppendsSourceBackedNote() throws {
        let overlay = PrereqRuleOverlay(schemaVersion: 1, rules: [
            PrereqRule(
                courseID: "CS345",
                prerequisiteExpr: .course("CS240"),
                corequisiteExpr: .empty,
                confidence: .curated,
                basis: .inferred,
                sourceURL: URL(string: "https://catalog.jmu.edu/preview_program.php?catoid=62&poid=999&print")!,
                sourceText: "The recommended sequence lists CS 240 before CS 345.",
                notes: "Official sequence supports treating CS 240 as required preparation."
            )
        ])
        let catalog = Catalog.fixture(
            courses: [
                Course(id: "CS240", code: "CS 240", title: "Data", credits: 3, availability: nil, prerequisites: []),
                Course(id: "CS345", code: "CS 345", title: "Software Engineering", credits: 3, availability: nil, prerequisites: [])
            ],
            program: Program.fixture(id: "cs-bs", title: "Computer Science, B.S.", requirements: []),
            prereqRuleOverlay: overlay
        )
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: SemesterIdentity(year: 2026, term: .fall), courseIDs: ["CS345"])
        ])

        let warning = try #require(ConflictDetector(catalog: catalog).warnings(for: pathway, overrides: []).first {
            $0.kind == .missingPrerequisite && $0.courseID == "CS345"
        })

        #expect(warning.message.contains("Catalog note: Official sequence supports treating CS 240 as required preparation."))
    }
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter ConflictDetectorPrereqWiringTests`

Expected: at least the overlay-wins and parsed-copy tests fail because conflict detection still parses directly and message copy has no confidence note.

- [ ] **Step 3: Replace conflict parser priority with resolver priority**

In `ConflictDetector.warnings(...)`, replace:

```swift
        let parser = PrereqParser(coursesByID: coursesByID, activeProgramTitle: activeProgramTitle)
```

with:

```swift
        let resolver = PrereqRuleResolver(catalog: catalog)
```

Replace prereq lookup:

```swift
                let prereqExpr = Self.effectivePrerequisiteExpr(for: course, parser: parser)
                if case .unmet(let missing, let original) = evaluator.evaluate(prereqExpr, mode: .prereq) {
```

with:

```swift
                let resolvedRule = resolver.rule(for: course, activeProgramTitle: activeProgramTitle)
                if case .unmet(let missing, let original) = evaluator.evaluate(resolvedRule.prerequisiteExpr, mode: .prereq) {
```

Use this exact final call:

```swift
                        message: Self.prereqMessage(
                            original: original,
                            missing: missing,
                            hasUnknown: resolvedRule.hasUnknownTokens,
                            confidence: resolvedRule.confidence,
                            notes: resolvedRule.notes,
                            coursesByID: coursesByID,
                            satisfied: completedBefore
                        ),
```

Replace coreq lookup:

```swift
                let coreqExpr = Self.effectiveCorequisiteExpr(for: course, parser: parser)
                if case .unmet(let missing, _) = evaluator.evaluate(coreqExpr, mode: .coreq) {
```

with:

```swift
                if case .unmet(let missing, _) = evaluator.evaluate(resolvedRule.corequisiteExpr, mode: .coreq) {
```

Update coreq copy:

```swift
                        message: "Take alongside or before this course: \(rendered).",
```

Delete the private `ConflictDetector.effectivePrerequisiteExpr(for:parser:)` and `ConflictDetector.effectiveCorequisiteExpr(for:parser:)` methods.

- [ ] **Step 4: Update prereq warning message builder**

Change `prereqMessage` signature:

```swift
    private static func prereqMessage(
        original: PrereqExpr,
        missing: PrereqExpr,
        hasUnknown: Bool,
        confidence: PrereqRuleConfidence,
        notes: String?,
        coursesByID: [String: Course],
        satisfied: Set<String>
    ) -> String {
```

Inside the method, after the existing unknown-text append, add:

```swift
        if confidence == .parsed {
            message += " Parsed from catalog text; verify before registering."
        }
        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            message += " Catalog note: \(notes)"
        }
```

- [ ] **Step 5: Run focused tests**

Run: `swift test --filter ConflictDetectorPrereqWiringTests`

Expected: all conflict detector prereq/coreq wiring tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/PlannerCore/PlannerCore.swift Tests/PlannerCoreTests/ConflictAndProgressTests.swift
git commit -m "feat: report curated prereq warnings"
```

---

## Task 6: Show Resolver Confidence In Course Details

**Files:**
- Modify: `Sources/JMUCoursePlanner/Views/CourseDetailSheet.swift`

- [ ] **Step 1: Add resolver-backed view state**

In `CourseDetailSheet`, add:

```swift
    private var resolvedPrereqRule: ResolvedPrereqRule {
        PrereqRuleResolver(catalog: catalog).rule(for: course, activeProgramTitle: store.effectiveActiveProgram?.title)
    }
```

- [ ] **Step 2: Replace prereq/coreq section logic**

Replace `prereqSection` with:

```swift
    @ViewBuilder
    private var prereqSection: some View {
        let rule = resolvedPrereqRule
        if rule.prerequisiteExpr != .empty {
            requirementExpressionSection(
                title: "Prereqs",
                expr: rule.prerequisiteExpr,
                rule: rule
            )
        }

        if rule.corequisiteExpr != .empty {
            requirementExpressionSection(
                title: "Coreqs",
                expr: rule.corequisiteExpr,
                rule: rule
            )
        }
    }
```

Delete `displayedPrerequisiteExpr`.

- [ ] **Step 3: Replace expression section rendering**

Replace `requirementExpressionSection(title:expr:showsUnknownNote:)` with:

```swift
    private func requirementExpressionSection(title: String, expr: PrereqExpr, rule: ResolvedPrereqRule) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.s) {
                Text(title)
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                StatusPill(
                    text: rule.confidence == .curated ? "Curated" : "Parsed from catalog",
                    tone: rule.confidence == .curated ? .success : .warning
                )
            }
            Text(expr.displayString(coursesByID: catalog.coursesByID))
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            if rule.hasUnknownTokens {
                Text("Some terms could not be parsed. See JMU catalog.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            if let sourceText = rule.sourceText, !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(sourceText)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            if let notes = rule.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(notes)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
    }
```

- [ ] **Step 4: Build**

Run: `swift build`

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/CourseDetailSheet.swift
git commit -m "feat: show prereq rule source in course details"
```

---

## Task 7: Add Overlay Validation Script

**Files:**
- Create: `script/validate_prereq_overlay.swift`

- [ ] **Step 1: Create standalone validator script**

Create `script/validate_prereq_overlay.swift`:

```swift
#!/usr/bin/env swift
import Foundation

struct ValidationError: Error, CustomStringConvertible {
    var description: String
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let seedURL = root.appending(path: "Data/catalog_seed.json")
let overlayURL = root.appending(path: "Data/prereq_coreq_overrides.json")

func readObject(_ url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ValidationError(description: "\(url.path) is not a JSON object")
    }
    return object
}

func string(_ object: [String: Any], _ key: String) -> String? {
    object[key] as? String
}

func courseLeaves(in expr: Any?) -> [String] {
    guard let expr = expr as? [String: Any],
          let kind = expr["kind"] as? String
    else { return [] }
    switch kind {
    case "course":
        return (expr["value"] as? String).map { [$0] } ?? []
    case "all", "any":
        return (expr["children"] as? [Any] ?? []).flatMap(courseLeaves)
    default:
        return []
    }
}

func exprKind(_ expr: Any?) -> String {
    guard let expr = expr as? [String: Any],
          let kind = expr["kind"] as? String
    else { return "missing" }
    return kind
}

let seed = try readObject(seedURL)
let overlay = try readObject(overlayURL)
let courses = seed["courses"] as? [[String: Any]] ?? []
let courseIDs = Set(courses.compactMap { string($0, "id") })
let courseByID = Dictionary(uniqueKeysWithValues: courses.compactMap { course -> (String, [String: Any])? in
    guard let id = string(course, "id") else { return nil }
    return (id, course)
})

guard (overlay["schemaVersion"] as? Int) == 1 else {
    throw ValidationError(description: "schemaVersion must be 1")
}
let rules = overlay["rules"] as? [[String: Any]] ?? []
var errors: [String] = []
var seenRules: Set<String> = []

for rule in rules {
    guard let courseID = string(rule, "courseID") else {
        errors.append("rule missing courseID")
        continue
    }
    if !seenRules.insert(courseID).inserted {
        errors.append("duplicate rule for \(courseID)")
    }
    if !courseIDs.contains(courseID) {
        errors.append("overlay courseID not in catalog: \(courseID)")
    }
    if string(rule, "confidence") != "curated" {
        errors.append("\(courseID) confidence must be curated")
    }
    let basis = string(rule, "basis")
    if basis != "explicit" && basis != "inferred" {
        errors.append("\(courseID) basis must be explicit or inferred")
    }
    if string(rule, "sourceURL")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
        errors.append("\(courseID) missing sourceURL")
    }
    if string(rule, "sourceText")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
        errors.append("\(courseID) missing sourceText")
    }
    if basis == "inferred", string(rule, "notes")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
        errors.append("\(courseID) inferred rule missing notes")
    }
    for referencedID in courseLeaves(in: rule["prerequisiteExpr"]) + courseLeaves(in: rule["corequisiteExpr"]) {
        if !courseIDs.contains(referencedID) {
            errors.append("\(courseID) references unknown course \(referencedID)")
        }
    }
}

let requirementsByProgram = seed["requirementsByProgram"] as? [String: Any] ?? [:]
let concentrationsByProgram = seed["concentrationsByProgram"] as? [String: Any] ?? [:]
var schedulable: Set<String> = []

func collectCourseOptions(from value: Any?) {
    guard let categories = value as? [[String: Any]] else { return }
    for category in categories {
        let options = category["courseOptions"] as? [[String]] ?? []
        for option in options {
            schedulable.formUnion(option)
        }
    }
}

for (_, categories) in requirementsByProgram {
    collectCourseOptions(from: categories)
}
for (_, rawConcentrations) in concentrationsByProgram {
    guard let concentrations = rawConcentrations as? [[String: Any]] else { continue }
    for concentration in concentrations {
        collectCourseOptions(from: concentration["requirements"])
    }
}

let overlayCourseIDs = Set(rules.compactMap { string($0, "courseID") })
let parserCovered = schedulable.filter { id in
    guard let course = courseByID[id] else { return false }
    if overlayCourseIDs.contains(id) { return true }
    if let raw = string(course, "rawPrerequisiteText"), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
    if exprKind(course["prerequisiteExpr"]) != "empty" { return true }
    if exprKind(course["corequisiteExpr"]) != "empty" { return true }
    if let prerequisites = course["prerequisites"] as? [String], !prerequisites.isEmpty { return true }
    return true
}
let missingFromCatalog = schedulable.filter { !courseIDs.contains($0) }.sorted()
for id in missingFromCatalog {
    errors.append("schedulable course missing from catalog courses list: \(id)")
}

if !errors.isEmpty {
    for error in errors.sorted() {
        FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
    }
    throw ValidationError(description: "prereq overlay validation failed with \(errors.count) error(s)")
}

let curated = overlayCourseIDs.intersection(schedulable).count
let coverage = schedulable.isEmpty ? 100.0 : (Double(curated) / Double(schedulable.count)) * 100.0
print("Curated rules: \(rules.count)")
print("Schedulable courses: \(schedulable.count)")
print(String(format: "Curated schedulable coverage: %.1f%%", coverage))
print("Parser/legacy fallback available: \(parserCovered.count)")
print("Missing curated schedulable rules: \(schedulable.subtracting(overlayCourseIDs).count)")
print("Invalid referenced course IDs: 0")
```

- [ ] **Step 2: Run validator**

Run: `swift script/validate_prereq_overlay.swift`

Expected with the starter empty overlay:

```text
Curated rules: 0
Schedulable courses: a positive integer from the current seed
Curated schedulable coverage: 0.0%
Parser/legacy fallback available: the same positive integer from the current seed
Missing curated schedulable rules: the same positive integer from the current seed
Invalid referenced course IDs: 0
```

- [ ] **Step 3: Commit**

```bash
git add script/validate_prereq_overlay.swift
git commit -m "test: add prereq overlay validator"
```

---

## Task 8: Curate First Overlay Batch With Source-Backed Agent Entries

**Files:**
- Modify: `Data/prereq_coreq_overrides.json`

- [ ] **Step 1: Assign curation scopes**

Use subagents only after Tasks 1-7 pass. Assign non-overlapping write scopes by course family so agents do not edit the same JSON entries:

```text
Agent A: CS core courses in schedulable CS programs.
Agent B: CIS core and CIS concentration courses.
Agent C: COB core courses and common B.B.A. lower core.
Agent D: common math/stat courses used by CS, CIS, COB, and Gen Ed quantitative requirements.
Agent E: common lab/coreq Gen Ed science pairs.
```

Each agent must return JSON entries only for its assigned course IDs. Entries must include `courseID`, `prerequisiteExpr`, `corequisiteExpr`, `confidence: "curated"`, `basis`, `sourceURL`, `sourceText`, and `notes` when basis is `inferred` or any prose was dropped.

- [ ] **Step 2: Agent curation rules**

Give each curation agent this exact instruction:

```text
Read official JMU catalog course/program pages for the assigned course IDs. Add source-backed curated rules to Data/prereq_coreq_overrides.json for assigned courses only. Preserve explicit course AND/OR structure with PrereqExpr JSON. Use basis "explicit" when source text directly states a prereq/coreq. Use basis "inferred" only when official source text, official program sequencing, or official catalog context strongly supports treating a course as a prereq/coreq even though the text is not standard prereq prose. Inferred rules require notes explaining the reasoning. Ignore grade thresholds, GPA, class standing, permission, placement, and admission gates as blockers unless a named course requirement is also present; mention dropped non-course rules in notes. If evidence is weak or conflicting, do not add a blocking inferred rule.
```

- [ ] **Step 3: Merge agent entries deterministically**

After agents return entries, sort `rules` by `courseID` ascending. Keep JSON formatting as two-space indentation. Preserve existing entries that another agent wrote unless validation reports a duplicate.

- [ ] **Step 4: Validate curated data**

Run: `swift script/validate_prereq_overlay.swift`

Expected: no `ERROR:` lines. Curated rule count is greater than 0. Invalid referenced course IDs remains 0.

- [ ] **Step 5: Run focused resolver test**

Run: `swift test --filter PrereqRuleOverlayTests`

Expected: overlay data still decodes and resolver tests pass.

- [ ] **Step 6: Commit curated batch**

```bash
git add Data/prereq_coreq_overrides.json
git commit -m "data: add initial curated prereq overlay"
```

---

## Task 9: Full Verification

**Files:**
- No planned file edits.

- [ ] **Step 1: Run full test suite**

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 2: Run overlay validator**

Run: `swift script/validate_prereq_overlay.swift`

Expected: no validation errors; report includes curated rule count, schedulable course count, coverage percentage, missing curated count, and invalid referenced course IDs.

- [ ] **Step 3: Build app**

Run: `swift build`

Expected: build succeeds.

- [ ] **Step 4: Optional bundle verification when user wants a rebuilt app**

Run only when the user wants the local app bundle refreshed:

```bash
script/build_and_run.sh --no-launch
```

Expected: `dist/JMU Course Planner.app/Contents/Resources/prereq_coreq_overrides.json` exists beside `catalog_seed.json`.

- [ ] **Step 5: Commit any verification-only resource changes**

If `script/build_and_run.sh --no-launch` was run and the user wants the rebuilt bundle tracked, stage the bundle changes explicitly. Otherwise leave `dist/` dirty files alone.

```bash
git status --short
```

Expected before final handoff: source/test/data changes are committed; pre-existing `dist/` dirty files are either intentionally untouched or explicitly handled per user instruction.

---

## Self-Review Notes

- Spec coverage: data model, inferred/manual entries, resolver priority, scheduling, warnings, course details, repository loading, validation, and agent curation workflow are covered.
- Parser fallback remains intact through `PrereqRuleResolver`; parser removal is not part of this plan.
- Missing/invalid overlay is non-fatal because repository loading falls back to `.empty` and appends a parser-fallback retrieval note.
- Curated overlay starts as valid empty JSON, then grows through the source-backed curation task after infrastructure is testable.
