# Prerequisite and Corequisite Parsing & Enforcement

**Status:** Draft, awaiting user review
**Date:** 2026-05-21
**Scope:** PlannerCore parser + ConflictDetector + JMUCoursePlanner UI surfaces

## 1. Problem

The catalog HTML parser already scrapes the raw `prerequisiteText` for each course, but throws it away (`prerequisites: []` at `CatalogHTMLParser.swift:665`). As a result:

- The schedule generator's prereq topological check (`buildSemesters`, `PlannerCore.swift:781`) is a no-op for catalog-sourced courses.
- The `ConflictDetector.missingPrerequisite` warning path (`PlannerCore.swift:893`) never fires.
- Corequisites are unrepresented in the data model entirely.

A student can build a plan that is impossible to actually register for, and the app never tells them. The goal is to parse prereq and coreq text into a typed expression tree, enforce it during schedule generation, and surface a clear actionable warning when manual edits violate the requirement.

## 2. Goals & Non-Goals

**Goals**

- Parse atomic and boolean (`and`, `or`, parenthesized) prereq/coreq expressions from the JMU catalog HTML. Cover roughly 90% of CS, math, and business prereq text.
- Enforce prereq and coreq compliance during schedule generation (best-effort: schedule still produced even when impossible).
- Surface inline warnings on the Schedule tab when a student manually places a course whose prereqs or coreqs are unmet, with copy explaining what the student is missing.
- Show parsed prereqs and coreqs on the Course Detail sheet.

**Non-goals**

- Minimum-grade qualifiers ("C- or better in CS 159").
- Class-standing rules ("junior standing").
- Test-score gates ("MATH placement Level 4").
- Major-restricted prereqs ("open only to CS majors").
- Auto-fix UI ("move CS 159 to Fall 2025 to resolve this").
- Clickable course chips inside warning strips.
- Internationalization of warning copy.

Each non-goal is recorded as a TODO comment at the parser site where it would otherwise be handled, plus a "see catalog" partial fallback in the Course Detail sheet.

## 3. Decisions (from brainstorming)

| Question | Decision |
|---|---|
| Parse scope | Atomic + and/or boolean. Parenthesized groups. Treat comma and semicolon as implicit `and`. |
| Coreq handling | Same grammar as prereq, separate `ConflictKind.missingCorequisite`. Coreq is satisfied if course is in same term OR already completed. |
| Manual drop into invalid term | Warn but allow. Existing override path (`ConflictOverride`) handles "Keep anyway". |
| Unresolved course refs | Mark course `verificationStatus = .partial`, append source note. Other resolvable tokens in the same expression are still enforced. |
| Warning copy | Full expression: `"Needs (CS 159 or CS 149) and MATH 235. You have CS 159; still missing MATH 235."` |
| Completion source for prereq check | Transfer credits + earlier-term real courses + filled placeholder slots. Unfilled placeholders do not count. |
| Generator can't satisfy | Best-effort: place remaining courses, emit warnings. Never throw `impossibleSchedule` for prereq reasons. |
| Parser implementation | Hand-written recursive-descent parser. No external dependency. |

## 4. Data Model

New types and Course-model additions in `Sources/PlannerCore/PlannerCore.swift`:

```swift
public indirect enum PrereqExpr: Codable, Hashable, Sendable {
    case empty
    case course(String)              // resolved catalog course ID
    case unknown(String)             // raw text we could not resolve
    case all([PrereqExpr])           // and group
    case any([PrereqExpr])           // or group
}

public struct Course {
    // existing fields...
    public var prerequisites: [String]              // flat list of resolved IDs (back-compat)
    public var prerequisiteExpr: PrereqExpr = .empty
    public var corequisiteExpr: PrereqExpr = .empty
    public var hasUnknownPrereqTokens: Bool = false
}
```

`prerequisites: [String]` stays public and continues to feed the existing scheduler topological check. It is derived from `prerequisiteExpr` as the flat union of every `.course(id)` leaf. This over-constrains the scheduler (treats `(A or B)` as both A and B required), but the conflict detector uses the typed expression for fidelity, so the user-visible warnings remain correct.

New `ConflictKind` case:

```swift
public enum ConflictKind: String, Codable, Hashable, Sendable {
    case missingPrerequisite
    case missingCorequisite       // new
    case unknownAvailability
    case semesterAvailability
}
```

## 5. Parser

New file: `Sources/PlannerCore/PrereqParser.swift`.

```swift
public struct PrereqParser {
    public init(coursesByID: [String: Course])
    public func parse(_ text: String?) -> ParseResult
}

public struct ParseResult: Sendable {
    public var prerequisiteExpr: PrereqExpr
    public var corequisiteExpr: PrereqExpr
    public var hasUnknownTokens: Bool
}
```

### Pipeline

1. **Segment splitter.** Split raw text at any `Corequisite(s):` or `Corerequisite:` header into two strings (prereq, coreq). Either may be empty.
2. **Lexer.** Token kinds:
   - `.courseRef(rawCode)` — match `[A-Z]{2,5}\s+\d{3}[A-Z]?`.
   - `.and`, `.or`, `.lparen`, `.rparen`, `.comma`, `.semicolon`.
   - `.unknown(text)` — anything else (contiguous run of words between recognized tokens). Surrounding whitespace stripped.
3. **Course-ID resolution.** Each `.courseRef` lexeme normalized (`CS 159` → catalog ID via the injected `coursesByID` lookup, applying the same slug rules the parser uses elsewhere). Unresolved refs become `.unknown(raw)` and set `hasUnknownTokens = true`.
4. **Grammar (recursive descent).**
   ```
   Expr     := OrExpr
   OrExpr   := AndExpr ('or' AndExpr)*
   AndExpr  := Term (('and' | ',' | ';') Term)*
   Term     := COURSE | UNKNOWN | '(' Expr ')'
   ```
   Comma and semicolon collapse into the AND production. This matches JMU catalog convention: `"CS 159, MATH 235"` means both.
5. **Normalization** post-parse:
   - Collapse `.all([x])` to `x`, `.any([x])` to `x`.
   - Flatten nested `.all` inside `.all`, same for `.any`.
   - Empty group becomes `.empty`.

### Display helper

A pure function on `PrereqExpr`:

```swift
extension PrereqExpr {
    func displayString(coursesByID: [String: Course]) -> String
}
```

Renders the tree as catalog-style text: course IDs become codes (`CS 159`), nested groups parenthesize, AND joined with `" and "`, OR joined with `" or "`. Used by warning copy and Course Detail sheet.

### Tests

New `Tests/PlannerCoreTests/PrereqParserTests.swift`:

- Atomic: `"Prerequisite: CS 159."` → `.course("cs-159")`.
- AND: `"CS 159 and MATH 235"` → `.all([course, course])`.
- OR: `"CS 240 or CS 250"` → `.any([course, course])`.
- Nested: `"CS 159 and (MATH 235 or MATH 236)"` → `.all([course, .any([...])])`.
- Comma-AND: `"CS 159, MATH 235"` → `.all([...])`.
- Semicolon-AND: `"CS 159; MATH 235"` → `.all([...])`.
- Unknown: `"CS 159 or instructor permission"` → `.any([course, .unknown(...)])` with `hasUnknownTokens = true`.
- Coreq split: `"Prerequisite: CS 159. Corequisite: MATH 235."` → both expressions populated.
- Empty input: `nil` and `""` → both `.empty`, `hasUnknownTokens = false`.
- Plus 10+ lines extracted verbatim from the existing `_live_cs.html`, `_live_psyc.html`, `_live_accounting.html`, `_live_nursing.html`, and `_live_gened.html` fixtures, as a real-world regression suite.

## 6. Catalog Parser Integration

`CatalogHTMLParser` runs in two passes per program.

**Pass 1 (existing):** Build `coursesByID: [String: Course]` with `prerequisites: []` and the raw `prerequisiteText` retained on the course's detail blob.

**Pass 2 (new):** Instantiate `PrereqParser(coursesByID: ...)`. For each course:

- Run `parser.parse(course.prerequisiteText)`.
- Populate `prerequisiteExpr`, `corequisiteExpr`, `hasUnknownPrereqTokens`.
- Derive `prerequisites` as the flat union of `.course(id)` leaves in `prerequisiteExpr` (back-compat for scheduler).
- If `hasUnknownPrereqTokens`, keep `verificationStatus = .partial` and append a `sourceNote` line: `"Prereq mentions terms we couldn't resolve to catalog courses; verify before registering."`
- If parse result has zero unknowns and at least one resolved course, the course may bump to `verificationStatus = .verified` (when all other dimensions of the course are also verified; the parser only controls the prereq dimension).

**Cross-program prereqs.** A CS course may reference `MATH 235` from the math department. The two-pass approach must run after all programs in the catalog have been parsed into a shared `coursesByID` map. Implementation: introduce a `CatalogParseContext` that accumulates courses across program parses, then runs Pass 2 once at the end. `CatalogRepository` is the caller that orchestrates per-program parses today; the Pass 2 invocation lives in that orchestration layer, immediately after all programs have been collected and before the resulting `Catalog` value is returned.

**Concentration-internal courses.** Same handling. Pass 2 sees the union of program-level + concentration-level courses.

## 7. Conflict Detection

Extend `ConflictDetector` in `Sources/PlannerCore/PlannerCore.swift`.

### Evaluator

```swift
private struct PrereqEvaluator {
    let completedBefore: Set<String>      // transfer ∪ earlier-term real ∪ filled placeholders in earlier terms
    let scheduledThisTerm: Set<String>    // same-term real courses
    
    enum Mode { case prereq, coreq }
    enum Outcome {
        case satisfied
        case unmet(missing: PrereqExpr, original: PrereqExpr)
    }
    
    func evaluate(_ expr: PrereqExpr, mode: Mode) -> Outcome
}
```

- **`completedBefore` composition:** the union of transfer-credit course IDs, course IDs scheduled in strictly-earlier semesters, and *resolved* placeholder slots in strictly-earlier semesters. A placeholder is resolved when its `__pl::<categoryID>::<optionIndex>` ID has been replaced in the pathway by an actual catalog course ID. Unresolved placeholder slots (still bearing the `__pl::` prefix) do not contribute.
- **prereq mode:** A `.course(id)` leaf is satisfied iff `id ∈ completedBefore`.
- **coreq mode:** A `.course(id)` leaf is satisfied iff `id ∈ completedBefore ∪ scheduledThisTerm`.
- `.unknown(_)` leaf is never satisfied (the engine cannot prove anything about it). Warning copy explains "and we couldn't verify the rest, see catalog."
- `.all([...])` is satisfied iff every child is satisfied.
- `.any([...])` is satisfied iff any child is satisfied.

When unmet, the evaluator returns the minimal unmet sub-expression by walking the tree:

1. Replace satisfied `.course` and `.unknown` leaves with `.empty` sentinel.
2. For each `.any` group, if at least one child is satisfied, the whole group becomes `.empty`.
3. Flatten and prune `.empty` from `.all` and `.any` containers.
4. The result represents the smallest expression the student must satisfy to clear the warning.

The original `PrereqExpr` is also returned so warning copy can render both "what the requirement is" and "what is still missing."

### Loop integration

`ConflictDetector.warnings(for:overrides:)`:

```swift
for semester in pathway.semesters.sorted { ... } {
    let completedBefore = ... // transfer ∪ courses in strictly-earlier semesters (real IDs only)
    let scheduledThisTerm = Set(semester.courseIDs.filter { !PathwayPlaceholder.isPlaceholder($0) })
    let evaluator = PrereqEvaluator(completedBefore: completedBefore, scheduledThisTerm: scheduledThisTerm)
    
    for courseID in semester.courseIDs where !PathwayPlaceholder.isPlaceholder(courseID) {
        guard let course = catalog.coursesByID[courseID] else { continue }
        
        if case .unmet(let missing, let original) = evaluator.evaluate(course.prerequisiteExpr, mode: .prereq) {
            warnings.append(warning(
                courseID: courseID,
                semester: semester.id,
                kind: .missingPrerequisite,
                message: prereqMessage(original: original, missing: missing, hasUnknown: course.hasUnknownPrereqTokens),
                overrides: overrides
            ))
        }
        
        if case .unmet(let missing, let original) = evaluator.evaluate(course.corequisiteExpr, mode: .coreq) {
            warnings.append(warning(
                courseID: courseID,
                semester: semester.id,
                kind: .missingCorequisite,
                message: coreqMessage(original: original, missing: missing),
                overrides: overrides
            ))
        }
    }
}
```

### Message format

- **Prereq unmet, all resolvable:**
  `"Needs <original>. You have <satisfied-portion>; still missing <missing>."`
  Both `<original>` and `<missing>` render via `PrereqExpr.displayString(coursesByID:)`. `<satisfied-portion>` is a comma-separated list of every `.course` leaf in the original expression whose ID resolves into `completedBefore`, rendered as course codes. Nested group structure is intentionally flattened for the "you have" clause to keep the copy at a freshman reading level; the structural detail lives in the `<original>` and `<missing>` clauses on either side of it. If the satisfied-portion list is empty, the clause (including the leading "You have ... ;") is dropped.
- **Coreq unmet:**
  `"Take alongside this course: <missing>."`
- **Has unknown tokens:**
  Append `" Some prereqs couldn't be parsed; verify with the catalog."`

## 8. Scheduler

`buildSemesters` (`PlannerCore.swift:748`) changes:

1. Keep the existing optimistic placement pass that uses the flat `course.prerequisites` AND-check. This biases the generator toward producing prereq-valid orderings whenever possible.
2. **New best-effort fallback.** After the existing `maxPasses` retry loop, if any courses are still unplaced, drop them into the final semester (or append one extra semester if the final is already over the workload cap). Do not throw.
3. Add `Generator(strictPrereqs: Bool = false)`. When `true`, throw `PlannerError.impossibleSchedule` as before. Default is `false` (best-effort). Used by tests + future opt-in mode.
4. The `ConflictDetector` then surfaces the violations at render time. The user sees a complete schedule with explicit warnings, not a blank state.

## 9. UI

### Schedule tab (`ScheduleBoardView.swift`)

Existing warning strip stays. Adjustments:

1. **Multi-line message rendering.** Switch the strip's `Text` to `.lineLimit(nil)` with tightened line height. Full-expression copy can be 80–120 characters; current single-line truncation would lose the actionable detail.
2. **Icon disambiguation.**
   - `.missingPrerequisite` → `exclamationmark.triangle.fill` (current).
   - `.missingCorequisite` → `arrow.left.arrow.right.circle.fill` (same-term semantics).
   - `.unknownAvailability` → unchanged.
3. **Override copy.** Existing "Keep" button stays. Accessibility label clarified to `"Keep anyway (override prereq)"`. Visible text unchanged.

### Course Detail Sheet (`CourseDetailSheet.swift`)

New sections between the availability block and the existing meta lines:

1. **Prereqs section.** Header eyebrow `PREREQS` (small uppercase tertiary). Body renders `prerequisiteExpr.displayString(coursesByID:)` in `Typography.body`. Hidden when `.empty`.
2. **Coreqs section.** Same pattern, header `COREQS`. Hidden when `.empty`.
3. **Partial-parse note.** When `hasUnknownPrereqTokens`, append a `Typography.caption` line in `textTertiary` under the Prereqs body: `"Some terms couldn't be parsed. See JMU catalog."` Link target is the existing `course.registrarURL` when available.

No clickable course chips (out of scope).

### My Plan tab

No changes. Per-course prereq state is surfaced on the Schedule tab where the student is acting.

### Visual rules

- Warning copy multi-line stays inside the existing `warning.opacity(0.12)` strip with the existing border-stripe. No new colors. No new pills.
- Course Detail prereq sections honor the existing sheet rhythm: eyebrow → body → optional caption, with the same vertical spacing as other meta blocks.

## 10. Persistence & Migration

- New `Course` fields default to `.empty` / `false`. `Codable` synthesis handles backwards-compatible decode from old `catalog_seed.json`.
- New `ConflictKind.missingCorequisite` decodes from string `"missingCorequisite"`. Old persisted `ConflictOverride` records key by `(courseID, semester, kind)`; existing records with older kinds load unchanged. No migration required.
- `SavedStudentPlan` is unaffected (stores course IDs only).
- Catalog cache on disk (under app-support `Catalog/`) is rebuilt on next launch via `CatalogRepository`. Bump the existing schema version constant inside `CatalogRepository` (or introduce one if absent) so the cached `Catalog/` directory is treated as stale and re-parsed on next launch for users updating from the old binary.
- **Seed regeneration.** After the parser ships, regenerate `Data/catalog_seed.json` once so the shipped binary carries structured prereqs. Add a one-shot Swift target under `script/` (`script/regenerate_seed.swift`) that loads the HTML fixtures, runs `JMUHTMLCatalogParser`, and writes a fresh seed. Document in `script/`'s README.

## 11. Test Plan

**Parser unit tests (`PrereqParserTests.swift`)** — at minimum:

- 8 synthetic cases listed in §5.
- 12 extracted live cases, two from each of the five `_live_*.html` fixtures plus two cases sampled from the regenerated `catalog_seed.json`, each hand-verified against the source HTML.

**Conflict detector tests (`ConflictAndProgressTests.swift` + new file if needed)** — at minimum:

1. Prereq satisfied by transfer credit.
2. Prereq satisfied by an earlier-term scheduled course.
3. Prereq not satisfied by an unfilled placeholder slot.
4. OR group with only one branch met.
5. Nested AND-of-ORs where inner is partially met.
6. Coreq in same term, satisfied.
7. Coreq in earlier term, satisfied.
8. Coreq in later term, not satisfied.
9. Unknown token in expression: warning fires with "verify with catalog" suffix.

**Scheduler tests (`ScheduleGeneratorTests.swift`)**:

- Best-effort fallback: a deliberately impossible pathway returns a schedule with all courses placed and the expected count of prereq warnings.
- `strictPrereqs = true`: same input throws `impossibleSchedule`.

**Manual UAT** after implementation:

1. Build CS BBA plan from seed. Confirm Schedule tab shows ≤ 3 warnings on a freshly-generated pathway (sanity threshold).
2. Drag CS 240 into Fall of the first year (before CS 159). Confirm a warning strip appears within the same render frame.
3. Click "Keep" on a warning. Confirm it persists across app relaunch (`ConflictOverride` round-trip).
4. Open Course Detail for CS 240. Confirm a `PREREQS` section displays the parsed expression in catalog-style text.
5. Find a course with an unknown token (use an `instructor permission` example). Confirm the Course Detail sheet shows the "see catalog" caption.
6. Run `script/build_and_run.sh`. Confirm `swift build` and `swift test` both pass.

## 12. Acceptance Criteria

The feature is shippable when:

1. All parser tests in §11 pass.
2. All conflict-detector tests in §11 pass.
3. Scheduler best-effort and strict paths both pass their tests.
4. `Data/catalog_seed.json` regenerated and committed.
5. App launches via `script/build_and_run.sh` without errors.
6. CS BBA seed program produces a schedule with at least one parsed prereq surfaced in either the Schedule warning strip or the Course Detail sheet.
7. No regressions in existing tests (`Tests/PlannerCoreTests/`).

## 13. Open Risks

- **Cross-program scoping.** If JMU's HTML is parsed program-by-program in production today and the orchestration to merge `coursesByID` across programs is not yet present, the implementation plan must include that orchestration. Confirm in the writing-plans phase by reading `JMUHTMLCatalogParser` call sites.
- **Course-code disambiguation.** Some JMU courses share numbers across departments (e.g., `200`-level placeholders). The lexer matches `[A-Z]{2,5}\s+\d{3}[A-Z]?`; verify against fixtures that no false-positive matches occur (e.g., "MATH 200-level coursework" should not parse as a course ref).
- **Performance.** Two-pass parsing on a multi-thousand-course catalog adds work to first-launch. Spot-check the parse time on the existing live fixtures; if > 1 second cumulative, consider caching the parsed expressions in `catalog_seed.json`.

## 14. Out-of-Scope (Future Work)

Each of the following has a TODO comment placed at the parser site so future contributors find them easily:

- Minimum-grade qualifiers.
- Class-standing rules.
- Test-score gates.
- Major-restricted prereqs.
- Auto-fix UX ("move CS 159 to satisfy this").
- Clickable course chips in warning strips and prereq displays.
- Cross-language warning copy.
