# Placeholder Prerequisite Handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate feasible schedules through unresolved prerequisite-bearing slots and explain their conditional choices without resolving them or granting progress credit.

**Architecture:** Add a pure, bounded feasibility engine and a chronological pathway analyzer in PlannerCore. Generation, conflict detection, and drag previews share that analysis; PlanStore caches its derived output and the existing placeholder/picker views present it. Keep actual prerequisite evaluation and completion accounting separate.

**Tech Stack:** Swift 6 package, PlannerCore, macOS 14+, SwiftUI/AppKit, Swift Testing and XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-10-placeholder-prerequisite-design.md` (approved; commit `79dfb31`). Read it before this plan.

## Global Constraints

- "One slot represents one course; it cannot simultaneously supply incompatible alternatives. One supporting choice can unlock several dependent courses."
- "Choosing an incompatible option preserves placements and produces ordinary conflict warnings. It does not automatically reschedule courses or replace the student's choice."
- "Restricted slots, subject/level elective pools, and unrestricted Open Electives participate using the same course menus their pickers expose."
- "Limit each connected group to 10,000 explored search states per pass and check cancellation during exploration."
- "Never use an unproven assignment to admit a course during generation or hide a missing-prerequisite warning."
- "Ignore retained definitions of resolved or absent placeholders as possible unresolved providers."
- "No solver witness is persisted as a course selection."
- "Preserve every anchored SemesterPlan and its course order, credit overrides, resolved choices, and required placeholder definitions exactly."
- "Only actual selected courses can appear as named contributing work."
- Exact UI copy: **Prerequisite choice needed**; supporting rows use **Supports <course code> in <semester>**.
- Existing reserved workload estimates, catalog parser, academic-history records, and degree requirements keep their existing meanings. No catalog schema bump is needed.
- Use cancellation-safe, deterministic operations; stage only task-owned files. Leave the unrelated untracked illustration directories untouched.

## Review Focus

- Metadata retained after resolution/removal must not turn a vanished slot into a prerequisite provider (Tasks 1, 4).
- A prerequisite already scheduled too late must produce an ordering conflict, not an invented earlier repeat through an Open Elective (Tasks 1, 3).
- Supporting a lecture must not invent an unscheduled lab or exceed the semester cap when a choice has more credits than its reservation (Tasks 1, 2).
- A picker left open while the pathway/catalog changes must not keep stale supporting labels (Tasks 4, 5).
- A drag moving an unchanged warning between semesters must refresh dependency detail even when WarningDiff considers its identity unchanged (Task 4).

## File Responsibilities and Shared Interfaces

New files:

- `Sources/PlannerCore/PlaceholderCourseDomain.swift`: one domain resolver shared with picker policy; no UI code.
- `Sources/PlannerCore/ConditionalPrerequisiteTypes.swift`: transient analysis inputs, requests, results, and work-budget types; none are Codable or stored on Pathway.
- `Sources/PlannerCore/ConditionalPrerequisiteSolver.swift`: compatible assignments and provider feasibility, including cancellation and component budgets.
- `Sources/PlannerCore/PlaceholderPrerequisiteAnalyzer.swift`: chronological admission, complete supporting-option annotations, and dependency urgency.
- `Sources/JMUCoursePlanner/Views/Overlays/PlaceholderDependencyPresentation.swift`: pure formatting of notices and per-course picker marks.
- Test files named under their owning tasks below, with `Tests/PlannerCoreTests/PlaceholderPrerequisiteFixtures.swift` for shared fixtures.

Modify existing generator/detector definitions in `PlannerCore.swift` without moving unrelated code. Modify `ScheduleRegeneration.swift`, `DropVerdict.swift`, `PlanStore.swift`, placeholder/picker/board view call sites, and warning presentations only where integration requires it.

Public core contracts (all types Sendable; keys/results Equatable or Hashable as appropriate):

```swift
public enum ConditionalDependencyKind: Hashable, Sendable {
    case prerequisite, corequisite, labPairing
}
public struct ConditionalDependencyKey: Hashable, Sendable {
    public let courseID: String
    public let semester: SemesterIdentity
    public let kind: ConditionalDependencyKind
}
public struct ConditionalPrerequisiteRequest: Sendable {
    public let key: ConditionalDependencyKey
    public let expression: PrereqExpr
}
public struct ConditionalPrerequisiteInput: Sendable {
    public let pathway: Pathway
    public let completedAtStart: Set<String>
    public let standingBySemester: [SemesterIdentity: ClassStanding]
    public let workload: WorkloadPreference?
    public let activeProgramTitle: String?
}
public struct ConditionalProviderUse: Hashable, Sendable {
    public let placeholderID: String
    public let supportingCourseID: String
    public let dependent: ConditionalDependencyKey
}
public enum ConditionalFeasibility: Equatable, Sendable {
    case feasible(assignments: [String: String], uses: Set<ConditionalProviderUse>)
    case impossible
    case unconfirmed
}
public enum ConditionalPrerequisiteStatus: Equatable, Sendable {
    case satisfied, conditional, unmet, unconfirmed
}
public struct PlaceholderPrerequisiteAnalysis: Equatable, Sendable {
    public let statusByDependency: [ConditionalDependencyKey: ConditionalPrerequisiteStatus]
    // Slot -> eligible supporting option -> downstream requirements it supports.
    public let supportsByPlaceholder: [String: [String: Set<ConditionalDependencyKey>]]
}
```

Provide explicit public initializers for public input/key types. Introduce `ConditionalSearchBudget(limitPerGroup: Int = 10_000)` that counts explored states independently for each connected dependency group; baseline proofs and forced-option probes in one analysis pass share it. Requests inherit the root dependent key while recursively checking a provider, so upstream slots can explain the real scheduled course they eventually support.

Use these test commands from the execution checkout:

```bash
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift test --disable-sandbox --filter <SuiteName>
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift test --disable-sandbox
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift build
```

## Task 1: Feasible Conditional Providers

**Files:** Create the domain, types, and solver files above; create `Tests/PlannerCoreTests/ConditionalPrerequisiteSolverTests.swift` and `PlaceholderPrerequisiteFixtures.swift`. Modify `PlaceholderCoursePickerPolicy` in `CoursePickerSheet.swift` to delegate eligibility to the shared core resolver.

**Interfaces:**

- `PlaceholderCourseDomain.eligibleCourseIDs(for spec: PlaceholderSpec, catalog: Catalog) -> [String]`: valid explicit alternatives, or the full catalog for empty alternates; deduplicate without changing picker ordering semantics.
- `ConditionalPrerequisiteSolver.init(catalog: Catalog)`.
- `solve(_ requests: [ConditionalPrerequisiteRequest], in input: ConditionalPrerequisiteInput, forcedChoices: [String: String] = [:], budget: inout ConditionalSearchBudget) throws -> ConditionalFeasibility`.
- Test fixtures: `PlaceholderPrerequisiteFixtures.makeInput(slots: [[String]], dependencies: [PrereqExpr], slotSemesterOffset: Int = 0, dependentSemesterOffset: Int = 1) -> (catalog: Catalog, input: ConditionalPrerequisiteInput, requests: [ConditionalPrerequisiteRequest])`; create concrete course IDs A/B and dependent IDs D0/D1, three-credit activities, Fall 2026 followed by Spring 2027. Create program ID `test-major`, category ID `choice`, slot IDs `__pl::choice::<index>`, and real course codes MATH 300 for A, MATH 336 for B, MATH 410 for D0, and MATH 430 for D1. Standing input is senior in both semesters to isolate course dependencies.

- [ ] **Step 1: Add failing solver/domain tests.** `oneSlotCannotSupplyBothAAndB` expects `.impossible` for one `[A,B]` slot and `.all([.course("A"), .course("B")])`; `twoSlotsSupplyBoth` expects feasible distinct assignments for two such slots; `oneChoiceSupportsMultipleDependents` expects one A assignment with two dependent uses. Pin OR branch preservation, conflicting separate dependents, empty-menu full catalog behavior, resolved/absent metadata exclusion, and rejection of an already-scheduled later duplicate.

Representative assertion for Step 1:

```swift
@Test func oneSlotCannotSupplyBothAAndB() throws {
    let f = PlaceholderPrerequisiteFixtures.makeInput(
        slots: [["A", "B"]],
        dependencies: [.all([.course("A"), .course("B")])])
    var budget = ConditionalSearchBudget()
    let result = try ConditionalPrerequisiteSolver(catalog: f.catalog)
        .solve(f.requests, in: f.input, budget: &budget)
    #expect(result == .impossible)
}
```

- [ ] **Step 2: Run `ConditionalPrerequisiteSolverTests`.** Expect missing types/functions, then behavioral failures after contracts exist. Never count a compilation failure as the only evidence of the old behavioral defect; existing anchored tests cover it in Task 3.
- [ ] **Step 3: Implement the contracts and search.** Solve real work first with PrereqEvaluator; recursively bind missing course leaves to eligible timed slots and validate provider prerequisites/corequisites/standing/availability/labs. An OR branch gets a branch-local assignment state; AND requests and admitted dependents share compatible bindings. Canonicalize memo keys by active requests/bindings; detect recursion cycles. Replace reservation credits only in hypothetical workload checks, accounting for actual overrides and required same-term lab partners. Unrelated unbound slots remain reservations, not invented courses. Validate forced bindings. Work-limit exhaustion returns `.unconfirmed`; cancellation throws `CancellationError`.
- [ ] **Step 4: Add and run provider-feasibility tests.** `sameTermDoesNotSupplyPrerequisite`, `sameTermCanSupplyCorequisite`, `missingLabPreventsProvider`, `standingAndKnownAvailabilityFilterProvider`, `hypotheticalFourCreditChoiceExceedsCap`, `upstreamCycleCannotBootstrap`, `workLimitIsUnconfirmed`, and `cancelledSearchThrows`. Assert no input Pathway mutations. Run `ConditionalPrerequisiteSolverTests` and `CoursePickerIndexTests`; expect PASS.
- [ ] **Step 5: Commit task-owned files.** `feat(prereqs): add bounded conditional provider feasibility`.

## Task 2: Chronological Analysis and Complete Choice Explanations

**Files:** Create `PlaceholderPrerequisiteAnalyzer.swift`, `Tests/PlannerCoreTests/PlaceholderPrerequisiteAnalyzerTests.swift`. Consume Task 1 contracts and fixtures.

**Interfaces:**

- `PlaceholderPrerequisiteAnalyzer.init(catalog: Catalog, workLimitPerGroup: Int = 10_000)`.
- `analyze(_ input: ConditionalPrerequisiteInput) throws -> PlaceholderPrerequisiteAnalysis`.
- `providerPriority(itemID: String, pendingCourseIDs: [String], completedCourseIDs: Set<String>, placeholders: [String: PlaceholderSpec], activeProgramTitle: String?) -> Int`: lower values rank prerequisite-bearing slots/providers earlier; irrelevant items share normal priority. Keep this lookahead inside the analyzer's file, with shared domain resolution.

- [ ] **Step 1: Add failing analyzer tests.** `retainsCompatibleAlternativesInsteadOfFirstWitness` checks `[A,B]` under `A or B` marks both choices; `laterDependencyNarrowsEarlierChoice` adds a B-only dependent and expects B highlighted for the OR-dependent too. `singleSlotConflictStaysUnmet` expects first chronological dependent conditional and incompatible later dependent unmet. `chainAnnotationsNameRootDependent` checks upstream/provider-slot uses attribute the actual downstream course, not a phantom completed course.

Representative assertions for Step 1:

```swift
let f = PlaceholderPrerequisiteFixtures.makeInput(
    slots: [["A", "B"]], dependencies: [.any([.course("A"), .course("B")])])
let result = try PlaceholderPrerequisiteAnalyzer(catalog: f.catalog).analyze(f.input)
#expect(result.statusByDependency[f.requests[0].key] == .conditional)
#expect(result.supportsByPlaceholder["__pl::choice::0"]?["A"] == Set([f.requests[0].key]))
#expect(result.supportsByPlaceholder["__pl::choice::0"]?["B"] == Set([f.requests[0].key]))
```

- [ ] **Step 2: Run `PlaceholderPrerequisiteAnalyzerTests`.** Expect FAIL before implementation.
- [ ] **Step 3: Implement chronological admission and annotation probes.** Build prerequisite/corequisite/lab requests through PrereqRuleResolver and LabPairing. Admit complete expressions in chronological/item order only when compatible with all previously admitted requests. Re-solve requests rather than pinning the first witness. For each relevant slot option, use a forced-binding proof plus provider-use provenance to mark genuine support; options that are merely compatible but unused receive no support mark. Share component work budgets with baseline proofs. Preserve already-proven results if later annotation probes exhaust their budgets, but do not claim unproven options support anything. Satisfied real work generates no slot notices. Compute urgency from missing named dependencies and upstream routes, with cycle-safe traversal.
- [ ] **Step 4: Add regression tests and run the suite.** Pin independent component budgets; duplicate/unknown alternate IDs; real-course preference; partial annotation search retaining a proven baseline; full-chain feasibility with same-term lab; non-mutating repeated deterministic analysis. `providerPriority` must rank the necessary slot before an unrelated high-level slot. Expect PASS.
- [ ] **Step 5: Commit.** `feat(prereqs): derive compatible placeholder dependency explanations`.

## Task 3: Generate Through Placeholders, Including Anchored Prefixes

**Files:** Modify `PlannerCore.swift` (`generate`, `buildSemesters`, candidate comparison) and `ScheduleRegeneration.swift` documentation; create `Tests/PlannerCoreTests/PlaceholderScheduleGeneratorTests.swift`; update `AnchoredScheduleGeneratorTests.swift`.

**Consumes:** Task 2 analyzer and priority, Task 1 input with explicitly supplied semester standings.

**Produces:** Existing `generatePathways`/`regeneratePathway` signatures and Pathway storage remain compatible. Pass the immutable preserved prefix into `buildSemesters` as `preservedSemesters: [SemesterPlan] = []`; derive probe input from prefix + emitted suffix + proposed current-term items. Internal solver assignments never enter courseIDs/resolvedPlaceholders.

- [ ] **Step 1: Add failing observable generation tests.** Strict generation with `[A,B]` before D0 requiring A must place D0 in the next allowed semester and retain the slot unresolved. Check every generation strategy, a provider slot with misleadingly high median level, and two slots feeding a multi-step chain. Update `reservedSlotDoesNotGrantPrerequisite`: strict anchored regeneration now succeeds conditionally while preserving anchors and granting zero named completion.

Representative assertions for Step 1:

```swift
let f = PlaceholderPrerequisiteFixtures.makeInput(
    slots: [["A", "B"]], dependencies: [.course("A")])
let path = try #require(try ScheduleGenerator(catalog: f.catalog, strictPrereqs: true)
    .generatePathways(for: "test-major", workload: .light, transferCredits: [],
                      starting: .init(year: 2026, term: .fall)).first)
#expect(path.semesters[0].courseIDs.contains("__pl::choice::0"))
#expect(path.semesters[1].courseIDs.contains("D0"))
#expect(path.resolvedPlaceholders.isEmpty)
#expect(!path.semesters.flatMap(\.courseIDs).contains("A"))
```

- [ ] **Step 2: Run `PlaceholderScheduleGeneratorTests` and the changed anchored test.** Confirm the current strict scheduler throws or stalls where a feasible slot exists.
- [ ] **Step 3: Integrate conditional eligibility and urgency.** Keep existing candidate lists, workload packing, strategy tie-breakers, and lab units. Probe a proposed course against prior admitted dependencies with its complete current-semester unit represented. Same-term slots can support corequisites only; provider and dependent prerequisite cannot be admitted as same-term earlier/later work. Carry prefix chronology and exact existing earned-hour/position standing semantics into input. Maintain possible compatible routes, not a single auto-selection. Recheck final construction with shared analysis. Unsupported/unknown work follows existing strict/fallback paths; cancellation preserves existing transactional recovery.
- [ ] **Step 4: Run generation regressions.** Include same-term rejection; too-late concrete prerequisite not duplicated through Open Elective; non-supporting provider/availability; anchored lab not manufactured; no feasible route still fails strictly; cancellation. Run `PlaceholderScheduleGeneratorTests`, `AnchoredScheduleGeneratorTests`, `ScheduleGeneratorTests`, `ContinuingStudentScheduleTests`, and `LabPairingTests`; expect PASS.
- [ ] **Step 5: Commit.** `feat(schedule): place dependents through feasible unresolved slots`.

## Task 4: Live Warnings, PlanStore Cache, and Placeholder Drag Verdicts

**Files:** Modify `PlannerCore.swift` (ConflictKind/ConflictDetector), `DropVerdict.swift`, `PlanStore.swift`, `FixSuggester.swift`, `WarningPopover.swift`; create `Tests/PlannerCoreTests/PlaceholderConflictTests.swift` and `PlaceholderPlanStoreTests.swift`; extend `DropVerdictCalculatorTests.swift` and `ScheduleIssuesTests.swift`.

**Interfaces:**

- Add `.pendingPrerequisiteChoice` to ConflictKind with `.worthALook`, title/summary `Prerequisite choice needed`. Pending notices are non-overridable; no Keep/View Course/fix action for a synthetic placeholder subject.
- Add final optional `prerequisiteAnalysis: PlaceholderPrerequisiteAnalysis? = nil` parameter to `ConflictDetector.warnings`, preserving existing callers. Without supplied analysis, derive it from current pathway/context. Cancellation or unconfirmed analysis preserves ordinary conflicts conservatively; it must not become satisfaction.
- Add `PlanStore.placeholderPrerequisiteAnalysis: PlaceholderPrerequisiteAnalysis?` and `placeholderDependencies(for placeholderID: String) -> [String: Set<ConditionalDependencyKey>]`. Cache by existing plan/catalog revision and clear with `invalidateDerivedState`. Pass current analysis into warnings and expose immutable annotation data to views.

- [ ] **Step 1: Add failing warning/store tests.** For feasible earlier A-slot -> D0, assert yellow notice subject is slot ID, no `.missingPrerequisite` on D0, progress stays zero for A requirement, and no resolved mapping. Resolve with B: assert semesters unchanged and D0 now missing A. Resolve with A: no pending notice or missing prerequisite. Remove/undo: notice returns. Catalog/semester edits and obsolete metadata must recalculate.

Representative assertions for Step 1:

```swift
let f = PlaceholderPrerequisiteFixtures.makeInput(
    slots: [["A", "B"]], dependencies: [.course("A")])
let warnings = ConflictDetector(catalog: f.catalog)
    .warnings(for: f.input.pathway, overrides: [])
#expect(warnings.contains {
    $0.courseID == "__pl::choice::0" && $0.kind == .pendingPrerequisiteChoice
})
#expect(!warnings.contains { $0.courseID == "D0" && $0.kind == .missingPrerequisite })
#expect(f.input.pathway.resolvedPlaceholders.isEmpty)
```

- [ ] **Step 2: Run `PlaceholderConflictTests`, `PlaceholderPlanStoreTests`, and targeted placeholder drag tests.** Confirm previous red warnings/neutral placeholder verdicts fail expectations.
- [ ] **Step 3: Integrate status without hiding unrelated problems.** Conditional status replaces only its proven prerequisite/corequisite/lab conflict; partial/unmet/unknown requirements retain ordinary conflict detail. Emit one pending notice per relevant unresolved slot, with sorted dependent detail. Skip pending overrides/fix suggestions explicitly; update every exhaustive ConflictKind switch in DropVerdict. Remove DropVerdict's blanket placeholder-neutral return; reuse paired-move simulation and new warning analysis. Keep existing revision checks for background verdict publication; stale results cannot update a newer plan.
- [ ] **Step 4: Run mutation/preview tests.** Earlier -> same/later slot move yields blocking verdict and matching final conflicts; reverse restores yellow. `movingNoticeWithoutChangingWarningKeyRefreshesDetail` compares new dependent semester/option annotations, not just added-warning counts. Keep ordinary overrides, load warnings, cancellation, and undo tests passing. Run `PlaceholderConflictTests`, `PlaceholderPlanStoreTests`, `DropVerdictCalculatorTests`, `PlanStoreUndoTests`, `ConflictTextTests`, `FixSuggesterTests`, and `ScheduleIssuesTests`; expect PASS.
- [ ] **Step 5: Commit.** `feat(schedule): refresh pending prerequisite warnings on edits`.

## Task 5: Yellow Placeholder Notices and Supporting Picker Rows

**Files:** Create `PlaceholderDependencyPresentation.swift` and `Tests/PlannerCoreTests/PlaceholderDependencyPresentationTests.swift`; modify `PlaceholderChip.swift`, `CoursePickerSheet.swift`, `SemesterColumnView.swift`, `ScheduleBoardView.swift` floating-item call site, `IssuesButton.swift` placeholder subject labeling, and existing warning views where required.

**Interfaces:**

- `PlaceholderDependencyPresentation.init(supports: [String: Set<ConditionalDependencyKey>], coursesByID: [String: Course])`; produces `summary: String`, `detail: String`, and `labelsByCourseID: [String: String]`. Stable course-code/semester ordering; exact summary `Prerequisite choice needed`, row prefix `Supports`.
- Add optional `dependencyPresentation: PlaceholderDependencyPresentation? = nil` to `CoursePickerSheet.init(title:courses:dependencyPresentation:onSelect:)`. Do not capture stale labels solely at sheet initialization: the placeholder request retains its slot ID; current PlanStore revision supplies updated presentation, and disappearance/resolution closes or clears that slot context.
- Add optional warning accessory/context to PlaceholderChip with defaults preserving ordinary/lifted/ghost callers.

- [ ] **Step 1: Add failing presentation/picker-policy tests.** A -> D0 Spring 2027 yields `Supports <D0 code> in Spring 2027`; two dependent semesters appear in stable detail; B remains eligible/searchable but unmarked; no initial selection or onSelect call is introduced. `openPickerRevisionUpdatesSupportingLabels` replaces analysis and asserts formatting uses new dependencies, not original captured labels.

Representative assertions for Step 1:

```swift
let f = PlaceholderPrerequisiteFixtures.makeInput(
    slots: [["A", "B"]], dependencies: [.course("A")])
let presentation = PlaceholderDependencyPresentation(
    supports: ["A": Set([f.requests[0].key])], coursesByID: f.catalog.coursesByID)
#expect(presentation.summary == "Prerequisite choice needed")
#expect(presentation.labelsByCourseID["A"] == "Supports MATH 410 in Spring 2027")
#expect(presentation.labelsByCourseID["B"] == nil)
```

- [ ] **Step 2: Run `PlaceholderDependencyPresentationTests` and `CoursePickerIndexTests`.** Expect FAIL for missing presentation contracts.
- [ ] **Step 3: Wire existing UI.** Use existing yellow WarningTag tone/help/popover with keyboard access and an accessibility description. Ensure clicking badge opens explanation without starting drag or resolving slot. Provide header explanation and row marks using current presentation; preserve search/order/all selections and optional generic-picker behavior. Update ordinary and floating placeholder call sites; issue-list subjects show the slot category rather than its internal ID. Existing WarningPopover must omit misleading course/override actions for pending notices. Avoid color-only meaning and overlapping click targets.
- [ ] **Step 4: Verify presentation tests and app build.** Expect PASS. In running app, verify warning hover/click/keyboard, supporting row marks, incompatible choice preserving placements, narrow widths, reduced motion, and generic add-course picker. Use available computer-use tools for UI inspection; if unavailable, report the exact unverified interaction.
- [ ] **Step 5: Commit.** `feat(ui): explain prerequisite choices in placeholder pickers`.

## Task 6: End-to-End Accounting and Representative Schedule Verification

**Files:** Create `Tests/PlannerCoreTests/PlaceholderPrerequisiteWorkflowTests.swift`; extend existing progress/export tests only for relevant regressions; update `LIMITATIONS.md` for verified conditional behavior. Do not change parser or catalog cache version.

**Consumes:** Integrated Tasks 1–5. No new runtime interfaces.

- [ ] **Step 1: Add end-to-end regression tests.** Generate a strict pathway, inspect pending notice and supporting options, assert no provider ID in real schedule/history/contributions/export, resolve incompatible then compatible choices, and undo. Assert slot requirement completedCredits is zero before resolution and equals actual selected credits after; reserved semester workload remains unchanged until choice. Round-trip saved Pathway: recomputed analysis matches, solver assignment metadata is absent. Regenerate anchored unresolved slots: anchors byte-equivalent and suffix conditionally feasible.

Representative persistence/accounting assertions for Step 1 (use the unresolved
`path` generated in Task 3's fixture):

```swift
let data = try JSONEncoder().encode(path)
let restored = try JSONDecoder().decode(Pathway.self, from: data)
#expect(restored == path)
#expect(restored.resolvedPlaceholders.isEmpty)
#expect(!restored.semesters.flatMap(\.courseIDs).contains("A"))
let progress = try ProgressCalculator(catalog: f.catalog).progress(
    programID: "test-major", pathway: restored, transferCredits: [])
#expect(progress.categories.first { $0.id == "choice" }?.completedCredits == 0)
```

- [ ] **Step 2: Run `PlaceholderPrerequisiteWorkflowTests`; address any failing cross-component contract.** Do not weaken accounting assertions or use assumed selections to make tests pass.
- [ ] **Step 3: Run complete package tests and application build.** Use the commands above; require zero failures and successful build. Do not assume previous test counts remain current.
- [ ] **Step 4: Compare representative catalog-backed schedules.** Use actual required dependents blocked by bounded choices, a MATH elective pool, Open Electives, and anchored generation. Capture before/after course semesters, count missing-prerequisite conflicts, confirm both retained customization and unchanged unresolved completion totals. Keep diagnostic exports temporary; do not commit cached catalogs or personal academic records. Measure analysis on broad menus and exercise injected tiny work limits to confirm conservative recovery, with no UI freeze accepted as success.
- [ ] **Step 5: Update limitations and graph; commit verification artifacts.** Document pending-vs-completed semantics and conservative search-limit recovery. Run `graphify update .` (AST-only, no API cost); inspect results and commit only relevant tracked documentation/tests. Commit: `test(schedule): verify conditional placeholder prerequisite workflow`.

## Self-Review and Execution Handoff

Spec coverage: domain/compatibility/budget/temporal feasibility -> Tasks 1–2; all generation strategies/prefixes -> Task 3; edit/undo/drag/cache -> Task 4; yellow/keyboard/picker -> Task 5; accounting/persistence/real-catalog acceptance -> Task 6. Review Focus cases each have an owning test. Shared names and signatures above are authoritative; avoid parallel implementation of dependent interfaces before their task passes review.

Recommended execution: **Subagent-driven**, one implementer and fresh reviewer per task, then whole-branch review. The six tasks share a new feasibility contract; staged reviews reduce the risk of one unsound conditional assumption propagating into both generated schedules and warnings.

Alternative: **Native** execution in this chat with one whole-branch reviewer at the end, using `superpowers:executing-plans`. Lower overhead, fewer independent checkpoints.

User must review this written plan and choose execution method before implementation. At execution time, inspect current Git state and follow using-git-worktrees instructions if isolation is needed; do not copy or reset unrelated user changes.
