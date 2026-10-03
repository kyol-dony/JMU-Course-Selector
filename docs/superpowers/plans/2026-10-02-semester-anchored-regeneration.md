# Semester-Anchored Regeneration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Rebuild only the displayed pathway after a selected semester while preserving its entire anchored prefix and supporting recovery and undo.

**Architecture:** Extend the existing generator with an anchored-prefix context and a single-strategy entry point. PlanStore runs a cancellable operation and applies its result as one schedule transaction; the board animates presentation state while the original saved pathway remains intact. Setup/full regeneration shares the existing generation rules and remains backwards compatible.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Foundation, Swift Testing, existing Swift Package targets; no new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-02-semester-anchored-regeneration-design.md`

## Global Constraints

- The action affects only the displayed pathway.
- The student chooses the last semester to preserve: that semester and every earlier semester are anchors; regeneration starts in the following semester.
- Other pathways remain unchanged.
- Existing anchor warnings stay visible for reference but do not block generation or cause the generator to modify anchors.
- Unresolved anchored elective slots reserve their requirement and planned credits; they do not satisfy a named prerequisite until a specific course is chosen.
- No anchor course, lab, placeholder, or semester can be moved, added, removed, or rewritten by the generator.
- Do not convert anchored planned courses into earned academic-history records.
- The disappearance of future columns is presentation state only.
- Failure or cancellation clears presentation state and restores the original visible suffix, with no undo step or changed saved data.
- Do not clear unrelated earlier schedule undo history.
- Full regeneration remains a separate existing action.
- Each task gets its own commit. Preserve the user's chosen native execution method and one final independent review.
- At execution, use an isolated managed worktree based on the latest suitable committed state. The primary checkout has concurrent catalog/elective/transcript edits; do not stage or reset those edits. Reconcile final shared-generation changes before integration.

## Review Focus

- Resolved and unresolved slots sharing a category, including a second-major course that also fills an elective: preserve the exact reservation without duplicate credit or lost attribution (Tasks 1–2).
- Unknown, repeated, or corrected-credit anchor courses also appearing in prior credit: preserve their visible rows and use deduplicated effective hours without inventing equivalences (Task 2).
- Lecture/lab partners straddling the cutoff: preserve anchors even when pairing would normally move a partner (Task 2).
- Catalog/program/plan changes or cancellation between the final progress callback and result application: reject stale results and progress without affecting a newer operation (Task 3).
- Fast completion, no suffix, large horizontal scroll, and Reduce Motion: anchors must not recenter, vanish, or leave a permanent loading state (Task 5).

## File boundaries

- `Sources/PlannerCore/ScheduleRegeneration.swift`: strategy resolution and exact prefix/metadata context; no UI or persistence.
- `Sources/PlannerCore/AcademicCreditCalculator.swift`: effective hours for an anchored prefix and remaining graduation allocation.
- `Sources/PlannerCore/PlannerCore.swift`: shared requirement/variant/build pipeline and the regeneration entry point; keep new request/state types out of this large file.
- `Sources/JMUCoursePlanner/Models/PartialRegeneration.swift`: request and transient operation state.
- `Sources/JMUCoursePlanner/Services/AnchoredScheduleGenerator.swift`: injected asynchronous worker wrapping the core generator.
- `Sources/JMUCoursePlanner/Stores/PlanStore.swift`: lifecycle, context validation, one-pathway transaction, undo, autosave.
- `Models/RegenerationBoundarySelection.swift`, `Views/Schedule/RegenerationBoundarySheet.swift`, `PartialRegenerationStatusView.swift`: picker semantics and inline progress.
- `Views/Schedule/ScheduleBoardView.swift`: future-only transitions, stable anchors, interaction locks. Existing `ContentView` full-generation overlay remains tied to full generation.

## Task 1: Anchored prefix and metadata contract

**Files:** Create `Sources/PlannerCore/ScheduleRegeneration.swift`, `Tests/PlannerCoreTests/AnchoredRegenerationFixtures.swift`, `AnchoredScheduleContextTests.swift`.

**Interfaces:** Produce public `ScheduleGenerationStrategy: String, CaseIterable, Sendable` cases `balanced`, `majorFirst`, `genEdFirst`, with `static resolve(pathwayID: String, index: Int) -> Self` (path-1/2/3 first; position 0/1/2 next; otherwise Balanced). Produce public `AnchoredScheduleContext: Sendable` with `init(source: Pathway, through cutoff: SemesterIdentity) throws`, read-only `semesters: [SemesterPlan]`, `placeholders: [String: PlaceholderSpec]`, `resolvedPlaceholders: [String: String]`, `completedCourseIDs: Set<String>`, `reservedPlaceholderIDs: Set<String>`, `standingSemesterOffset: Int`, `preferenceSemesterOffset: Int`, and `startingSemester: SemesterIdentity`. Define `AnchoredRegenerationError: Error, LocalizedError` case `invalidCutoff` with copy `Choose an existing semester in the displayed pathway.` Create fixture methods `prerequisiteCatalog() -> Catalog`, `degreeCatalog() -> Catalog` (30 distinct required courses at 3 hours, 90 declared hours), and `pathway(id: String = "path-1") -> Pathway`.

- [x] Write `includesSelectedSemesterAndPreservesMetadata`, `resolutionsBelongToAnchors`, `invalidCutoffThrows`, and `strategyResolution` tests. First two prefix semesters are Fall 2026/Spring 2027; cutoff Spring 2027 starts Fall 2027. Include unknown ZZZ123 at 1.5 hours, an empty listed semester, an unresolved slot and a resolved slot in one category, and obsolete suffix metadata. Assert exact prefix equality, correct retained maps, concrete-only completion IDs, and missing cutoff rejection.
  Example assertions with a two-semester prefix:
  ```swift
  let context = try AnchoredScheduleContext(source: source, through: .init(year: 2027, term: .spring))
  #expect(context.semesters == Array(source.semesters.prefix(2)))
  #expect(context.startingSemester == .init(year: 2027, term: .fall))
  #expect(context.standingSemesterOffset == 2)
  #expect(!context.completedCourseIDs.contains(anchorPlaceholderID))
  ```
- [x] Run `swift test --disable-sandbox --filter AnchoredScheduleContextTests`. Expected: FAIL because the new contracts do not exist.
- [x] Implement the context. Retain definitions for unresolved anchored IDs and for resolution keys whose chosen course is in the prefix. Reserve both retained kinds of placeholder IDs against future collisions. Count listed prefix semesters for legacy standing; compute calendar preference offset with Spring=0/Fall=1 and `2 * year + termIndex`, ending at the first new term. Do not normalize anchors or reject them because of course warnings.
- [x] Run `swift test --disable-sandbox --filter AnchoredScheduleContextTests`. Expected: PASS.
- [x] Commit: `feat: model anchored schedule regeneration context`.

## Task 2: Shared generator with reserved anchors and one variant

**Files:** Modify `Sources/PlannerCore/PlannerCore.swift`, `AcademicCreditCalculator.swift`; create `Tests/PlannerCoreTests/AnchoredScheduleGeneratorTests.swift`.

**Interfaces:** Consume Task 1 context/strategy. Produce `ScheduleGenerator.regeneratePathway(from source: Pathway, through cutoff: SemesterIdentity, for programID: String, concentrationID: String? = nil, strategy: ScheduleGenerationStrategy, workload: WorkloadPreference, transferCredits: [TransferCredit], additionalPrograms: [Program] = [], earnedHoursAtStart: Double? = nil, progress: (@Sendable (Int, Int, String) -> Void)? = nil) throws -> Pathway`. Add `AcademicCreditCalculator.projectedHours(in semesters: [SemesterPlan], placeholders: [String: PlaceholderSpec], transferCredits: [TransferCredit], catalog: Catalog) -> Double` for credit/standing context; prior awards count once, concrete anchor IDs once excluding previously earned IDs, retained unresolved slots once at their defined fractional amount. Existing `generatePathways` signature stays compatible and still returns three variants.

- [x] Write generator tests using Task 1 fixtures. Minimum assertions:
  ```swift
  #expect(result.id == source.id && result.name == source.name)
  #expect(Array(result.semesters.prefix(anchors.count)) == anchors)
  #expect(result.semesters.dropFirst(anchors.count).allSatisfy { $0.id > cutoff })
  #expect(result.semesters.flatMap(\.courseIDs).filter { $0 == "CS149" }.count == 1)
  ```
  Include `anchoredPrerequisitesAndCorequisites`, `warningsDoNotModifyAnchors`, `reservedSlotDoesNotGrantPrerequisite`, `resolvedAndSharedElectiveReservations`, `fractionalPriorAndAnchorHoursCountOnce`, `boundaryDoesNotMoveLectureOrLab`, `standingAndTimingRetainOffsets`, `lastCutoffCanAppendOrHaveNoSuffix`, and `cancellationStopsBuilder`. Assert an anchored 3-hour open slot reduces the future open allowance by 3 without becoming completed in progress. In the 90-hour fixture with anchored REQ1=1.5 and general prior credit=10.5, the future top-up is 21 hours and total earned+planned hours is 120. Include placeholder collision, unsupported availability, and overlapping second-major cases.
- [x] Run `swift test --disable-sandbox --filter AnchoredScheduleGeneratorTests`. Expected: FAIL before the new entry point/accounting exists.
- [x] Factor shared requirement selection and variant ordering inside the existing generator. Generalize its preserved-semester seed to a prefix context; setup adapts its existing single current semester without changing its public API. Generate only the requested variant for partial regeneration. Preserve source ID/name and concatenate exact prefix plus generated suffix. Return the prefix even when no remaining work exists.
- [x] Extend requirement allocation to consume reserved slot IDs/category amounts before selecting suffix work. Preserve exact ordinary option-slot reservations; selective pools subtract reserved amounts and fill only their remaining allowance. Concrete anchored choices still participate in existing shared-program fulfillment. Generate new placeholder IDs around retained IDs and discard suffix-only definitions/resolutions. Unresolved anchors never enter named prerequisite/corequisite completion sets.
- [x] Extend credit allocation across the prefix and its retained slots. Keep the existing major/declared-credit substance gate (major and at least 60 declared credits) and 120-hour minimum. For eligible partial regeneration, derive remaining top-up from effective prior+anchor hours and the actual new required-course/slot hours; never subtract a required credit twice. Retain legacy full-generation outputs unless the approved anchor generalization requires a correction verified by a failing regression test.
- [x] Pass separate standing/preference offsets into builders and their fallback. Anchor hours feed future standing where earned context exists, including reserved planned-slot hours. Otherwise apply listed-semester offset to existing standing rules. Apply elapsed term offset to course-level/Gen Ed preferences. Apply pairing only within suffix work; previously anchored partners remain completion input. Check task cancellation between variant preparation, requirement categories, and semester iterations, including best-effort fallback.
- [x] Run `swift test --disable-sandbox --filter 'AnchoredScheduleGeneratorTests|ScheduleGeneratorTests|ContinuingStudentScheduleTests|TranscriptRegressionTests|StandingPrereqTests|LabPairing|ConflictAndProgressTests|SemesterLayoutTests'`. Expected: PASS. Run full suite if shared selection/credit behavior changes beyond these fixtures; expected PASS.
- [x] Commit: `feat: regenerate one pathway after anchored semesters`.

## Task 3: Cancellable store lifecycle and guarded replacement

**Files:** Create `Models/PartialRegeneration.swift`, `Services/AnchoredScheduleGenerator.swift`, `Tests/PlannerCoreTests/PlanStorePartialRegenerationTests.swift`; modify `Stores/PlanStore.swift`.

**Interfaces:** Produce `PartialRegenerationRequest: Sendable` holding `catalog: Catalog`, `source: Pathway`, `cutoff: SemesterIdentity`, `programID: String`, `concentrationID: String?`, `strategy: ScheduleGenerationStrategy`, `workload: WorkloadPreference`, `transferCredits: [TransferCredit]`, `additionalPrograms: [Program]`, `earnedHoursAtStart: Double?`. Produce `PartialRegenerationState: Equatable, Sendable` with `operationID: UUID`, `pathwayID: String`, `cutoff: SemesterIdentity`, `progress: ScheduleGenerationProgress`. Produce `protocol AnchoredScheduleGenerating: Sendable { func regenerate(_ request: PartialRegenerationRequest, progress: @escaping @Sendable (ScheduleGenerationProgress) -> Void) async throws -> Pathway }` and `LocalAnchoredScheduleGenerator`. Extend store initializer with `init(storageDirectory: URL? = nil, anchoredGenerator: any AnchoredScheduleGenerating = LocalAnchoredScheduleGenerator())`. Expose read-only published `partialRegeneration: PartialRegenerationState?`, `canEditSchedule: Bool`, `regenerateActivePathway(after: SemesterIdentity) async -> Void`, and `cancelPartialRegeneration() -> Void`. Define private `applyRegeneratedPathway(_ replacement: Pathway, source: Pathway)` as Task 4's application hook.

- [x] Write tests with a deterministic suspended worker: `successChangesOnlyCapturedPathway`, `failureAndCancelLeavePlanUntouched`, `lateResultCannotReplaceNewerOperation`, `lateProgressCannotReopenLoading`, `changedPlanOrCatalogRejectsResult`, and `mutationsAndCompetingGenerationAreLocked`. Include switching active pathway, changing program/workload/prior credit, loading another plan, cancellation immediately before delivery, and no valid cutoff. Assert original plan and history remain intact during the wait, operation state clears after every outcome, and other pathways stay byte-for-byte equivalent after success.
  Assert lifecycle state and isolation explicitly:
  ```swift
  #expect(store.plan == before) // suspended operation has not published a result
  #expect(store.partialRegeneration != nil && !store.canEditSchedule)
  // After delivery:
  #expect(store.plan.pathways[otherIndex] == before.pathways[otherIndex])
  #expect(store.plan.academicRecords == before.academicRecords)
  #expect(store.partialRegeneration == nil)
  ```
- [x] Run `swift test --disable-sandbox --filter PlanStorePartialRegenerationTests`. Expected: FAIL because state/worker injection/store actions do not exist.
- [x] Implement the worker using Task 2 on a detached task with cancellation propagation. Capture an immutable request plus plan/source identity and all relevant catalog/program/workload/credit context. Validate context and operation identity before progress publication and success application. Cancel old work before replacing its token; late cleanup cannot clear a newer state. Invalid prior-credit validation uses the existing guard; anchor course warnings are not a generation gate.
- [x] Keep partial progress separate from `scheduleGenerationProgress`, so existing full-generation overlays cannot obscure anchors. `canEditSchedule` is false for either generation mode. Guard competing generation and board course/semester/placeholder/override mutation actions; allow external plan-context changes to invalidate and cancel partial work. On failure/cancel restore presentation by clearing state without changing saved pathway; on success call the application hook once and invalidate caches through the existing plan setter.
- [x] Run `swift test --disable-sandbox --filter 'PlanStorePartialRegenerationTests|PlanStoreTranscriptTests|PlanStoreMoveTests|PlanStoreSemesterTests|PlanStoreWarningsTests'`. Expected: PASS.
- [x] Commit: `feat: add cancellable partial pathway regeneration`.

## Task 4: Undo, issue overrides, and persistence transaction

**Files:** Modify `Stores/PlanStore.swift`; create `Tests/PlannerCoreTests/PartialRegenerationUndoTests.swift`.

**Interfaces:** Consume Task 3 application hook and existing `ScheduleSnapshot`, `recordScheduleChange`, `registerUndo`, `autosave`, and `flushPendingAutosaves`. Add an internal defaulted `synchronizeCurrentEnrollment: Bool = true` option to `recordScheduleChange`; partial regeneration uses false because the anchor/current history is already preserved. No new saved-plan fields or permanent anchor boundary.

- [x] Write `oneUndoStepRestoresOldSuffixAndMetadata`, `redoRestoresNewSuffix`, `earlierUndoHistoryRemains`, `anchorOverridesAndUnrelatedPathwaysSurvive`, and `savedPlanRoundTrip`. Include `nativeUndoDuringGenerationCancelsPendingWork`: cancel the pending operation before the existing native undo/redo restore proceeds, and verify that its entry is not consumed without restoring the edit. Include resolved and unresolved old suffix choices, anchor warnings, obsolete suffix-specific overrides, an unrelated Keep decision, and unchanged current/academic records. Undo/redo must restore exact pathway maps and only this operation's override delta. Persistence tests flush the serial autosave queue before reading the injected directory's JSON.
  ```swift
  undoManager.undo()
  #expect(store.activePathway == oldPathway)
  #expect(store.plan.academicRecords == oldRecords)
  undoManager.redo()
  #expect(store.activePathway == regeneratedPathway)
  ```
- [x] Run `swift test --disable-sandbox --filter PartialRegenerationUndoTests`. Expected: FAIL because success does not yet register a complete undo transaction.
- [x] Implement the application hook through the existing undo mechanism without clearing schedule history or syncing unchanged current academic records. Keep source ID/name and active selection. An override subject is `(courseID, semester)`; for a semester-level override, existence means that semester still exists. Prune only suffix-specific overrides whose subject is absent from the replacement; preserve prefix and unrelated overrides. Autosave once after successful application and after undo/redo through existing queue behavior. Toast/action copy names the boundary: `Regenerate after Fall 2027`.
- [x] Run `swift test --disable-sandbox --filter 'PartialRegenerationUndoTests|PlanStorePartialRegenerationTests|PlanStoreUndoTests|PlanStoreTranscriptTests'`. Expected: PASS.
- [x] Commit: `feat: make partial regeneration undoable and persistent`.

## Task 5: Semester picker and anchored board transitions

**Files:** Create `Models/RegenerationBoundarySelection.swift`, `Views/Schedule/RegenerationBoundarySheet.swift`, `PartialRegenerationStatusView.swift`, `Tests/PlannerCoreTests/RegenerationBoundarySelectionTests.swift`; modify `Views/Schedule/ScheduleBoardView.swift` and relevant editing controls in `SemesterColumnView.swift` if their actions bypass the board lock; also disable competing Generate/Regenerate controls in `Views/Tabs/MyPlanView.swift` and `Views/Setup/SetupSheet.swift` using the same lock.

**Interfaces:** Produce `RegenerationBoundarySelection: Equatable` with `init(pathway: Pathway)`, `semesters: [SemesterIdentity]`, editable `selected: SemesterIdentity?`, computed `summary: String`, and `canConfirm: Bool`. Produce `RegenerationBoundarySheet(pathway: Pathway, onConfirm: (SemesterIdentity) -> Void)`, `PartialRegenerationStatusView(state: PartialRegenerationState, onCancel: () -> Void)`. Consume Task 3 state/actions/lock; animation state remains in the board and never mutates SavedStudentPlan for hiding.

- [x] Write picker tests asserting chronologically sorted existing choices, first-semester default, invalid/empty selection disabled, selected semester included, and last semester allowed. Exact example summary: `Keep everything through Fall 2027. Rebuild Spring 2028 onward.`
  ```swift
  #expect(selection.selected == .init(year: 2026, term: .fall))
  selection.selected = .init(year: 2027, term: .fall)
  #expect(selection.summary == "Keep everything through Fall 2027. Rebuild Spring 2028 onward.")
  #expect(selection.canConfirm)
  ```
- [x] Run `swift test --disable-sandbox --filter RegenerationBoundarySelectionTests`. Expected: FAIL before picker semantics exist.
- [x] Implement the sheet showing affected pathway, summary, replacement of later course/elective choices, Cancel, and regeneration confirmation. Add `Regenerate after…` beside the existing full action; retain `Regenerate` behavior. Disable unavailable/conflicting actions, selector, drag/edit controls and gap/add-semester controls through `canEditSchedule`.
- [x] Implement future-only fade-out, inline progress+Cancel after the cutoff, and fade-in on success. Retain invisible measured suffix space during the hide/loading transition so anchor columns and scroll position remain stable; use leading/stable layout during replacement. Keep the same anchor view identities. Coordinate fast worker completion with the hide/reveal lifecycle instead of relying only on semester IDs changing. Failure/cancel restores the original suffix; no remaining work clears loading and shows a brief completion message. Reduce Motion bypasses movement/stagger and unnecessary waits. Reset local presentation state on plan/pathway change or view departure, with stale worker protection handled by Task 3.
- [x] Run `swift test --disable-sandbox --filter 'RegenerationBoundarySelectionTests|PlanStorePartialRegenerationTests|ScheduleDragControllerTests'` and `swift build --disable-sandbox`. Expected: PASS and successful build. Before using library-specific animation APIs, follow repository documentation instructions.
- [x] Manually verify first/last cutoff, stable anchors while scrolled far right, unknown/fractional course chips, warnings remaining visible, picker keyboard navigation, Cancel, fast completion, empty suffix, and Reduce Motion. Expected: anchors remain visible/stationary, previous suffix returns on cancel/error, and no progress overlay obscures the board. Record any unavailable native check explicitly.
- [x] Commit: `feat: add regenerate-after controls and anchored transitions`.

## Task 6: End-to-end verification and integration readiness

**Files:** Create `Tests/PlannerCoreTests/PartialRegenerationWorkflowTests.swift`; update this plan's checkboxes/verification notes. Update AST graph artifacts according to repository policy.

**Interfaces:** Consume Tasks 1–5; no additional product subsystem.

- [x] Write workflow tests for edited prefix → choose cutoff → regenerate active variant → preserve other two pathways → undo/redo → save/load → regenerate again. Include actual earned credit plus imported current enrollment, unresolved reserved slots, changed suffix elective choices, last-semester anchors, and catalog/program invalidation after earlier successful regeneration. Assert history and anchors remain exact and a second regeneration does not grow totals or duplicate slot IDs.
  ```swift
  #expect(Array(store.activePathway!.semesters.prefix(anchors.count)) == anchors)
  #expect(store.plan.pathways[otherIndex] == untouchedAlternative)
  #expect(store.effectiveAcademicHistory.earnedHours == originalEarnedHours)
  #expect(regeneratedSuffix.flatMap(\.courseIDs).allSatisfy { !retainedPlaceholderIDs.contains($0) })
  ```
- [x] Run `swift test --disable-sandbox --filter PartialRegenerationWorkflowTests`. Expected: PASS if integration is correct; observe any behavioral failure before fixing a gap with its reproducing test.
- [x] Run `bash script/run_tests.sh`, `swift build --disable-sandbox`, and `git diff --check`. Expected: passing full suite, successful build, no whitespace errors. Run `graphify update .`; expected successful AST update.
- [x] Smoke-test the built native app with synthetic plans and an injected temporary storage directory through selected cutoff, future-only transition, successful suffix, Undo, redo, cancellation, error recovery, saved-plan reopen, and unchanged alternatives. Expected: spec behavior. Reconcile any newly committed catalog/elective/lab/transcript changes with this branch and repeat affected/full checks as appropriate before merging.
- [x] Commit: `test: verify semester-anchored regeneration workflow`.

## Execution handoff

The user previously chose native execution with a commit per task; preserve that preference after this written plan is approved. Native execution uses executing-plans, per-task red/green verification, and one final fresh-context whole-branch reviewer. Review all five Review Focus cases deliberately. Do not begin product changes before the user's plan review. Local merge remains a separately authorized integration action after the feature is complete.


## Execution verification

- Tasks 1–5 followed red/green checks and full-suite gates, with separate task commits.
- Task 6 workflow tests passed against the finished implementation: edited prefix, fractional earned/current credits, unresolved reservations, alternative isolation, undo/redo, real autosave JSON reopen, repeated regeneration, and stale-context rejection.
- Reconciled committed transcript-review improvements from 5d31913 into the isolated branch. Primary-checkout uncommitted catalog/elective changes were neither staged nor reset.
- Native synthetic app compiled and launched using /private/tmp/RegenerationSmokePlans. Native inspection repeatedly timed out, including after resetting the UI tool. Visual fade/scroll, keyboard, cancellation/error presentation, empty-suffix and system Reduce Motion checks remain unverified; do not treat those as manual passes.
- Private application hook takes the explicit cutoff for accurate undo naming and suffix-only override pruning; no public API or persistent-plan schema changed.
