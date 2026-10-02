# JMU Transcript Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Give continuing JMU students editable local transcript imports and generate remaining coursework after their preserved current enrollment.

**Architecture:** Parse locally extracted PDF text into an uncommitted review draft, reconcile it with the catalog, and commit confirmed academic records through one effective-credit adapter. Extend the existing scheduler with a preserved semester and reuse existing prerequisite evaluation. Explicit setup routes place year and program selection before upload or manual entry.

**Tech Stack:** Swift 6, macOS 14+, SwiftUI, Foundation, platform PDFKit, Swift Testing; no new package dependency or parsing service.

**Spec:** `docs/superpowers/specs/2026-10-02-jmu-transcript-import-design.md` (read alongside this plan).

## Global Constraints

- The importer detects classes, credits, grades, and terms only; it must not detect or choose majors, minors, or concentrations.
- Upload is optional.
- Generation preserves that semester exactly.
- Scans, screenshots, OCR, transcripts from other institutions, remote parsing services, and automatic program detection are outside this release.
- Preserve fractional credits.
- Do not persist original PDF bytes, raw page text, identifying headers, or the user's sample file path.
- Existing saved plans continue to load; legacy plans do not require repeated onboarding.
- After confirmed review, go directly to credit load; only future semesters use workload balancing.
- Do not commit the supplied private PDF. Build de-identified fixtures with course rows only.

## Review Focus

- Split headings/rows across pages: preserve parser context without treating repeated totals or headers as courses (Task 2).
- Summer or other unsupported printed terms: require an explicit supported-term choice rather than guessing Fall/Spring (Tasks 2 and 7).
- Partially overlapping multi-course AP awards: require a credit-amount decision instead of dividing an aggregate award arbitrarily (Task 3).
- Canceled or superseded asynchronous imports: late results cannot overwrite a newer draft or committed data (Task 5).
- Unknown current courses and corrected credit amounts: retain their roster entries and load even without a catalog match (Tasks 4 and 7).

## File boundaries and shared contracts

Create core files under `Sources/PlannerCore/`:

- `AcademicHistory.swift`: source/status enums, course records, effective history, fractional credit formatting.
- `JMUTranscriptParser.swift`: deterministic text-to-row extraction only.
- `TranscriptReconciler.swift`: matching, issues, draft corrections, validation, and effective-credit deduplication.
- `AcademicCreditCalculator.swift`: earned/projected totals, per-term credit lookup, and graduation-hour allocation used by generation and progress.

Create app files under `Sources/JMUCoursePlanner/`:

- `Services/TranscriptPDFReader.swift`: local file access and off-main PDF text extraction only.
- `Stores/TranscriptImportController.swift`: cancellable import lifecycle and review draft; does not autosave raw extraction.
- `Models/SetupFlow.swift`: year choices, step routing, and Back history.
- `Views/Setup/SetupStepYear.swift`, `SetupStepTranscript.swift`, `SetupStepCourseReview.swift`: focused wizard screens.
- `Views/Setup/TranscriptCourseRow.swift`: editing one course and its issues.

Modify existing core/store/setup/progress/schedule files in the tasks below; avoid unrelated splits of `PlannerCore.swift` or `PlanStore.swift`.

Tests live in `Tests/PlannerCoreTests/` and can import both modules as existing store tests do. Add `TranscriptTestFixtures.swift` with inline de-identified text and catalog builders; no resource configuration is needed. Fixture functions are `sampleText() -> String`, `sampleCatalog() -> Catalog`, `prerequisiteCatalog() -> Catalog`, and `degreeCatalog() -> Catalog`. The sample contains the supplied 19 earned rows (49 hours) and five current rows (16 hours), but no identifying information. The prerequisite catalog contains CS149 → CS159; the degree catalog has 90 distinct required hours and a 120-hour graduation target.

All tasks use `swift test --disable-sandbox --filter <SuiteName>` for their red/green cycle. Run the named suite before implementation and require a behavioral failure or missing-symbol compile failure; run again afterward and require all tests passed. Commit only each task's explicit files and necessary compilation adjustments. Refresh graph data after product changes with `graphify update .`; expected result is successful AST update. Finish with the full suite in Task 8.

## Task 1: Academic records and compatible persistence

**Files:** Create `Sources/PlannerCore/AcademicHistory.swift`, `Sources/JMUCoursePlanner/Models/SetupFlow.swift`, `Tests/PlannerCoreTests/AcademicHistoryTests.swift`; modify `Sources/PlannerCore/PlannerCore.swift`, `Sources/JMUCoursePlanner/Models/SavedStudentPlan.swift`.

**Interfaces:** Produce public Codable/Hashable/Sendable `AcademicCourseRecord` with `id: UUID`, `code: String`, `title: String`, `courseIDs: [String]`, `attemptedCredits: Double`, `earnedCredits: Double`, `grade: String?`, `printedTerm: String?`, `status: AcademicCourseStatus`, `source: AcademicCreditSource`. Status cases: earned, inProgress, excluded, needsReview. Source cases: transcriptResident, transcriptTest, transcriptTransfer, manual, apMapped, legacy. Add `TransferCredit.source` with a legacy decoding default and change its `credits` to Double. Produce the value snapshot `AcademicHistory(records: [AcademicCourseRecord], currentSemester: SemesterPlan?, effectiveCredits: [TransferCredit] = [], earnedHours: Double = 0)`, exposing those fields and `completedCourseIDs: Set<String>` derived from effectiveCredits. Task 3 fills effective values at confirmation; Task 1 tests can construct snapshots without depending on a future builder. Effective snapshots are rebuilt from canonical persisted records rather than persisted as a competing source of truth.

Persist `SavedStudentPlan.studentYear: StudentYear?`, `academicRecords: [AcademicCourseRecord] = []`, `currentSemester: SemesterPlan?`, `setupCompleted: Bool = false`, and `planningStart: SemesterIdentity?`. Add `SemesterPlan.creditOverrides: [String: Double] = [:]` and `courseTitles: [String: String] = [:]`, with default decoding, for unknown or corrected current courses. Existing courseIDs remain the schedule identity. Do not change integer catalog/requirement credit fields unnecessarily. Add `CreditHoursFormatter.string(_ hours: Double) -> String` so whole credits render as `3`, fractional credits as `1.5`. New-plan default start is the current Fall or Spring term (January–July Spring, August–December Fall) in the user's local calendar; reviewed term selection overrides it.

- [x] Write `AcademicHistoryTests` for legacy decode, new-data round-trip, and credit formatting. Assertions:
  ```swift
  #expect(decodedLegacy.academicRecords.isEmpty)
  #expect(decodedLegacy.currentSemester == nil)
  #expect(decodedLegacy.transferCredits.first?.credits == 3)
  #expect(roundTripped == original)
  #expect(CreditHoursFormatter.string(1.5) == "1.5")
  #expect(CreditHoursFormatter.string(3) == "3")
  ```
- [x] Run `AcademicHistoryTests` and confirm failure.
- [x] Implement the declared data types, initializers, Codable defaults, and formatter. `StudentYear` has incomingFreshman, enrolledFreshman, sophomore, junior, senior, fifthYearOrBeyond, matching the spec's displayed labels.
- [x] Run `AcademicHistoryTests` and require pass; compile the app to locate Double-related callers. Convert numeric values explicitly at legacy integer boundaries without rounding imported amounts.
- [x] Commit as `feat: model reviewed academic history and compatible credit provenance`.

## Task 2: Deterministic JMU transcript text parser

**Files:** Create `Sources/PlannerCore/JMUTranscriptParser.swift`, `Tests/PlannerCoreTests/JMUTranscriptParserTests.swift`, `Tests/PlannerCoreTests/TranscriptTestFixtures.swift`.

**Interfaces:** Consume Task 1 records. Produce `JMUTranscriptParser.parse(pages: [String]) throws -> ParsedTranscript`, with `records: [AcademicCourseRecord]`, `latestPrintedTerm: String?`, `printedEarnedTotal: Double?`, and `issues: [TranscriptIssue]`. Define `TranscriptIssue: Identifiable, Hashable, Sendable` with `id: UUID`, `recordID: UUID?`, `kind: TranscriptIssueKind`, `message: String`, `isBlocking: Bool`; kinds cover malformedRow, unknownGrade, unknownCourse, conflictingCredit, repeatedCourse, unsupportedTerm, termMismatch, totalMismatch, overlappingAward. Typed parser failures cover notJMUTranscript and noCourseRows.

- [x] Write sample acceptance and synthetic parser tests. Assertions:
  ```swift
  let parsed = try JMUTranscriptParser.parse(pages: [TranscriptTestFixtures.sampleText()])
  #expect(parsed.records.filter { $0.status == .earned }.count == 19)
  #expect(parsed.records.filter { $0.status == .earned }.reduce(0) { $0 + $1.earnedCredits } == 49)
  #expect(parsed.records.filter { $0.status == .inProgress }.reduce(0) { $0 + $1.attemptedCredits } == 16)
  #expect(parsed.latestPrintedTerm == "Fall Semester 2026")
  #expect(parsed.records.contains { $0.code == "CSOOO" && $0.earnedCredits == 3 })
  ```
  Add `multiPageContinuation`, `fractionalAward`, `failedWithdrawnIncompleteAreExcluded`, `unknownGradeNeedsReview`, `unsupportedSummerTerm`, and `totalsAndProgramHeadersAreNotCourses`. Assert split row completion occurs once, 1.5 stays 1.5, F/W/I rows are not earned/current, unknown grade blocks, and Summer stays a printed term requiring correction. Include no-space laboratory codes and a footer inserted between a course row's code and numeric tail.
- [x] Run `JMUTranscriptParserTests` and confirm failure.
- [x] Implement section-aware parsing across all pages. Recognize right-hand attempted/earned/grade/points columns, preserve descriptions, and normalize code whitespace/case without turning letter O into zero. Discard identity/program headers immediately. Recognize A–D with +/- and CR/P as possible credit-bearing grades only with positive earned hours; exclude F/W/I and retain unknown codes/grades for review. Use transcript totals only for reconciliation issues.
- [x] Run `JMUTranscriptParserTests` and require pass.
- [x] Commit as `feat: parse JMU unofficial transcript course rows locally`.

## Task 3: Catalog reconciliation and duplicate-safe credit accounting

**Files:** Create `Sources/PlannerCore/TranscriptReconciler.swift`, `Sources/PlannerCore/AcademicCreditCalculator.swift`, `Tests/PlannerCoreTests/TranscriptReconcilerTests.swift`.

**Interfaces:** Produce `TranscriptReconciler.makeDraft(parsed: ParsedTranscript?, catalog: Catalog, existingRecords: [AcademicCourseRecord], existingCredits: [TransferCredit], defaultSemester: SemesterIdentity) -> TranscriptReviewDraft`; draft exposes `records`, `issues`, `currentSemester`, and `semesterConfirmed: Bool`. Produce `TranscriptReconciler.validate(_ draft: TranscriptReviewDraft, catalog: Catalog) -> [TranscriptIssue]` and `TranscriptReconciler.confirm(_ draft: TranscriptReviewDraft, catalog: Catalog) throws -> AcademicHistory`. Produce `EffectiveCreditBuilder.build(records: [AcademicCourseRecord], legacyCredits: [TransferCredit]) -> EffectiveCreditResult` with `credits`, `earnedHours`, `completedCourseIDs`, `issues`. `AcademicCreditCalculator.hours(in semester: SemesterPlan, catalog: Catalog) -> Double` uses overrides before catalog values; `totals(history: AcademicHistory, pathway: Pathway, catalog: Catalog) -> AcademicCreditTotals` exposes earnedHours and projectedHours with course IDs counted once.

- [x] Write `TranscriptReconcilerTests`: sample produces known IDs and retains CSOOO as flagged general credit; duplicate earned rows require a decision; repeat import replacement leaves 49 hours; earned/current duplicate blocks; 1.5-credit awards survive confirmation; negative/nonfinite values block; explicit general credit resolves unknown match. Use these assertions:
  ```swift
  #expect(confirmed.earnedHours == 49)
  #expect(!confirmed.completedCourseIDs.contains("CS149")) // CSOOO is not CS149
  #expect(confirmed.currentSemester?.courseIDs.count == 5)
  #expect(EffectiveCreditBuilder.build(records: records, legacyCredits: []).issues.isEmpty)
  ```
  Add `partialBundledAPOverlapRequiresReview`: legacy 6-hour award for CS149/CS000 overlaps a transcript CS149 row; assert an overlappingAward issue and no invented 3/3 split. Add `repeatableCourseExplicitAggregate`: the reviewed amount contributes hours once while course completion is one ID.
- [x] Run `TranscriptReconcilerTests` and confirm failure.
- [x] Implement reconciliation and validation. Import records replace prior transcript sources in the draft while independent manual/AP sources persist. Preserve existing GNED alias semantics. Unknown general awards contribute hours but have no named courseIDs; current unknown courses use their normalized printed code as roster identity and credit/title overrides. Prefill supported latest term; unsupported terms require explicit selection. Validation compares candidate printed terms to the selected current semester.
- [x] Implement effective accounting with transcript precedence, explicit issues for differing amounts or partial bundled overlaps, and one result reused by all consumers. Convert independent legacy/manual/AP entries into the confirmed history's canonical records without appending both representations to effective totals. Block confirmation until decisions resolve conflicts. Do not split multi-course awards using guessed per-course amounts. If later AP/program remapping creates a conflict, surface it and require review before generation rather than silently selecting a credit amount.
- [x] Run `TranscriptReconcilerTests` and require pass.
- [x] Commit as `feat: reconcile transcript courses and deduplicate prior credit`.

## Task 4: Preserve current enrollment in generation, progress, and warnings

**Files:** Modify `Sources/PlannerCore/PlannerCore.swift`, `Sources/PlannerCore/PrereqExpr.swift`, `Sources/PlannerCore/DropVerdict.swift`, `Sources/PlannerCore/AcademicCreditCalculator.swift`; create `Tests/PlannerCoreTests/ContinuingStudentScheduleTests.swift`; extend `StandingPrereqTests.swift` and `ConflictAndProgressTests.swift`.

**Interfaces:** Extend `ScheduleGenerator.generatePathways` with `preservedSemester: SemesterPlan? = nil` and `earnedHoursAtStart: Double? = nil` while retaining existing arguments/default behavior. Extend `ConflictDetector.warnings` and `DropVerdictCalculator.verdicts` with `earnedHoursAtStart: Double? = nil`; pass it through simulations. Add `ClassStanding.forEarnedCredits(_ hours: Double) -> ClassStanding`: below 28 firstYear, below 60 sophomore, below 90 junior, otherwise senior, per [JMU advising](https://www.jmu.edu/advising/isc-to-jmu/advising-isc/index.shtml). A nil earned-hour context retains legacy semester-position behavior. Add earnedHours/projectedHours to `GraduationProgress` with compatible decoding; existing category progress remains projected requirement progress. Make accumulated/category-completed credit values Double, keeping integer required credits through explicit conversion. Fractional open-elective placeholder amounts and candidate/load arithmetic must also use Double.

- [x] Write `ContinuingStudentScheduleTests` using prerequisite and degree fixtures. Assertions:
  ```swift
  #expect(pathways.count == 3)
  #expect(pathways.allSatisfy { $0.semesters.first == preserved })
  #expect(pathways.allSatisfy { $0.semesters.dropFirst().allSatisfy { $0.id > preserved.id } })
  #expect(pathways.allSatisfy { $0.semesters.flatMap(\.courseIDs).filter { $0 == "CS149" }.count == 1 })
  #expect(progress.earnedHours == 49)
  #expect(progress.projectedHours >= 65)
  #expect(ClassStanding.forEarnedCredits(49) == .sophomore)
  #expect(ClassStanding.forEarnedCredits(65) == .junior)
  ```
  Test same-term prerequisite failure and valid corequisite; current unknown 1.5-hour roster/load retained; empty current term retained; all requirements complete still yields current term; current overload preserved; current prerequisite enables CS159 next term. In the 90-hour degree fixture, 10.5 hours of general earned credit reduce the 30-hour open-elective gap to 19.5; earned required-course credit does not reduce that gap twice. Include overlapping second-major requirements and standing boundary cases 27.5/28/59.5/60/89.5/90.
- [x] Run `ContinuingStudentScheduleTests` and confirm failure.
- [x] Implement generation seeding: exclude earned and current IDs from remaining work, prepend current exactly, and start builders at `preserved.id.next`. Preserve current even on the no-remaining-work branch. Extend builders with earned-hour context accumulated only after each term; current credits are available for future standing but not the current term. Share credit allocation with progress: credit satisfying declared requirements is not also subtracted as general elective credit; extra earned/current hours reduce remaining graduation top-up.
- [x] Implement warning/progress/verdict context and current credit overrides. Retain existing corequisite/grade-rule behavior. Validate fractional arithmetic and update only credit-related callers needed for compilation.
- [x] Run `swift test --disable-sandbox --filter 'ContinuingStudentScheduleTests|StandingPrereqTests|ConflictAndProgressTests|ScheduleGeneratorTests|ConflictLoadTests|DropVerdictCalculatorTests'`; require pass.
- [x] Commit as `feat: plan remaining coursework after preserved current enrollment`.

## Task 5: Local PDF lifecycle and plan-store integration

**Files:** Create `Sources/JMUCoursePlanner/Services/TranscriptPDFReader.swift`, `Sources/JMUCoursePlanner/Stores/TranscriptImportController.swift`, `Tests/PlannerCoreTests/TranscriptImportControllerTests.swift`, `Tests/PlannerCoreTests/PlanStoreTranscriptTests.swift`; modify `Sources/JMUCoursePlanner/Stores/PlanStore.swift`, `Services/ProgressContributionBuilder.swift`, `Services/ExportService.swift`.

**Interfaces:** `protocol TranscriptTextReading: Sendable { func readPages(from url: URL) async throws -> [String] }`; `TranscriptPDFReader` implements it. `@MainActor TranscriptImportController` exposes read-only `state: TranscriptImportState` (idle, processing, reviewing, failed), editable `draft: TranscriptReviewDraft?`, `importPDF(at url: URL, catalog: Catalog, existingRecords: [AcademicCourseRecord], existingCredits: [TransferCredit], defaultSemester: SemesterIdentity) async -> Void`, `beginManual(catalog: Catalog, existingRecords: [AcademicCourseRecord], existingCredits: [TransferCredit], defaultSemester: SemesterIdentity) -> Void`, and `cancel() -> Void`. Inject the reader for tests. Add `PlanStore.confirmAcademicHistory(_ history: AcademicHistory) throws`, `effectiveAcademicHistory: AcademicHistory`, and `syncCurrentEnrollmentFromActivePathway() -> Void`; the latter runs inside schedule mutation/undo transactions.

- [x] Write controller tests with deterministic suspended fake reads for cancel, retry, and older-result races. Assert canceled or superseded work cannot replace draft; no failure changes confirmed plan. PDF reader tests generate a synthetic local text PDF, empty/image-only PDF, and locked/unreadable cases in temporary directories; assert only text PDF yields pages and errors expose retry/manual entry. Write store tests asserting confirmation invalidates pathways/caches, reimport does not grow totals, program/AP remapping preserves resident credit, and edits plus undo/redo update current enrollment.
- [x] Run `TranscriptImportControllerTests` and `PlanStoreTranscriptTests`; confirm failure.
- [x] Implement off-main PDF reading with scoped file access, encrypted/file/no-selectable-text errors, and cancellation between pages. Use platform document APIs; verify current documentation before library-specific implementation as required by repository instructions. Never log raw text. Retain neither URL nor pages after the operation. Guard results with operation identity and cancellation.
- [x] Implement controller draft lifecycle and store confirmation. Validate and build a proposed saved snapshot, write it atomically (`Data.write` with `.atomic`), then publish all academic fields together, clear obsolete pathways/undo history, and invalidate caches. A failed write leaves the prior plan and draft available. Refactor existing AP remapping to typed provenance with legacy migration. Route warnings, progress, verdicts, remaining courses, and generation through effective history, using nil earned context for untouched legacy plans.
- [x] Integrate board add/remove/move/placeholder resolution and undo/redo so changing current roster updates its stored records and overrides without changing earned history. Extend the existing schedule snapshot with currentSemester and affected academicRecords so undo restores persistence as well as pathway contents. For an active-pathway current edit, regeneration propagates that reviewed roster across generated variants. Update contribution labels and export to identify earned JMU coursework separately from transfer and projected enrollment; preserve unknown titles/credit amounts.
- [x] Run `swift test --disable-sandbox --filter 'TranscriptImportControllerTests|PlanStoreTranscriptTests|PlanStoreConcentrationTests|PlanStoreMoveTests|PlanStoreUndoTests|PlanStoreWarningsTests'`; require pass.
- [x] Commit as `feat: integrate cancellable local transcript imports with saved plans`.

## Task 6: Explicit setup routes and year-first startup

**Files:** Modify `Models/SetupFlow.swift`, `Views/ContentView.swift`, `Views/Setup/SetupSheet.swift`, `Stores/PlanStore.swift`; create `Views/Setup/SetupStepYear.swift`, `Tests/PlannerCoreTests/SetupFlowTests.swift`.

**Interfaces:** Produce `SetupStep` cases year, major, minor, transfer, transcript, review, workload; `SetupFlow` stores `step`, visited history, selected year and branch. Methods: `selectYear(_ year: StudentYear)`, `advance(majorSelectionComplete: Bool)`, `skipUpload()`, `importReady()`, `reviewConfirmed()`, `back()`. Navigation takes validated review confirmation explicitly; never advances to workload merely because extraction completed.

- [x] Write `SetupFlowTests` asserting incoming route year/major/minor/transfer/workload; all other years year/major/minor/transcript/review/workload; missing concentration prevents major advance; skip opens manual review; Back follows actual route and does not skip programs. Legacy selected-major plan avoids automatic wizard; new plan exposes year while catalog is still loading.
- [x] Run `SetupFlowTests` and confirm failure.
- [x] Implement explicit routing and dynamic progress indicators. Move the setup presentation outside the catalog-only dashboard branch so the first year screen can render while loading. Show catalog loading/retry before major controls become available; reuse current major/minor screens once loaded. Preserve draft on Back and year changes. Persist year; set setupCompleted only after successful Generate. Existing selected-major legacy plans remain usable.
- [x] Run `SetupFlowTests` and require pass; build with `swift build --disable-sandbox` and require success.
- [x] Commit as `feat: add year-first setup routes for continuing students`.

## Task 7: Upload and editable course review

**Files:** Create `Views/Setup/SetupStepTranscript.swift`, `SetupStepCourseReview.swift`, `TranscriptCourseRow.swift`, `Tests/PlannerCoreTests/TranscriptReviewTests.swift`; modify `Views/Setup/SetupSheet.swift`, `SetupStepTransfer.swift`, `Views/Overlays/CoursePickerSheet.swift`, credit displays in `Views/Design/ProgressRail.swift`, `CourseChip.swift`, `PlaceholderChip.swift`, `Views/Tabs/MyPlanView.swift`, `Views/Schedule/SemesterColumnView.swift`, and `Views/Schedule/ScheduleBoardView.swift`.

**Interfaces:** `SetupStepTranscript(controller: TranscriptImportController, onSkip: () -> Void)` offers file import, progress/cancel, and retry/manual entry. `SetupStepCourseReview(controller: TranscriptImportController, catalog: Catalog, onConfirm: (AcademicHistory) -> Void)` consumes the draft. Put mutation methods on `TranscriptReviewDraft`: `add(course: Course, status: AcademicCourseStatus)`, `remove(recordID: UUID)`, `update(record: AcademicCourseRecord)`, `retainAsGeneralCredit(recordID: UUID)`, `retainUnmatchedEnrollment(recordID: UUID)`, and `setCurrentSemester(_ semester: SemesterIdentity)`. General credit is for earned rows; unmatched enrollment stays on the roster with no invented equivalence. They rebuild issues through Task 3 rather than implementing separate validation in views.

- [x] Write `TranscriptReviewTests` asserting catalog addition to earned/current groups, record removal, credit and status corrections, explicit unknown retention, replacing a false course match, required term-mismatch decisions, and rejection of unresolved partial AP overlap. Assert editing does not touch saved plan until confirmation, imported 1.5 credits render without rounding, and changing Summer to an explicitly chosen Fall allows confirmation only after semesterConfirmed is true.
- [x] Run `TranscriptReviewTests` and confirm failure.
- [x] Implement PDF file picker, local progress/cancel/error copy, and `Skip upload / enter manually`. Use the full existing catalog picker; only change its API if the existing initializer cannot be reused. Review groups are Earned credit, In progress, and an excluded/issues disclosure. Show separate earned/current totals, editable term/year, source, status and amount controls; provide replace/remove/add actions and visible general-credit explanations. Expose existing AP/dual-enrollment entry for manual route through draft edits, never autosave directly from that embedded screen.
- [x] Wire confirmation through `PlanStore.confirmAcademicHistory`, then `SetupFlow.reviewConfirmed`. Render credit values with the shared formatter; unknown scheduled codes use stored title/amount and remain visible in board menus rather than dropping out through catalog-only lookup. Preserve the current load when workload selection changes and show its usual warning if out of range.
- [x] Run `TranscriptReviewTests`, `CoursePickerIndexTests`, and `SetupFlowTests`; require pass. Build app and manually verify import/manual routes, correction controls, keyboard access, and Back behavior.
- [x] Commit as `feat: add transcript upload and editable course review screens`.

## Task 8: End-to-end verification and handoff

**Files:** Create `Tests/PlannerCoreTests/TranscriptWorkflowTests.swift`; modify `docs/superpowers/plans/2026-10-02-jmu-transcript-import.md` checkboxes and generated `graphify-out/` artifacts only as repository policy permits.

**Interfaces:** Consume the completed parser, reconciliation, store confirmation, setup routing, and scheduler contracts; introduce no product subsystem.

- [x] Write `TranscriptWorkflowTests` exercising sample text → catalog review → edits → confirmed history → three pathways → saved-plan round-trip → regeneration. Assert 49 actual earned hours, five preserved courses totaling 16 current hours, no detection of programs, future terms after Fall 2026, and no duplicated import credit. Add manual-only empty/current cases and failure after a previously successful import; confirm previous data remains available. Test false unknown-to-CS149 equivalence cannot satisfy CS159 until explicitly mapped.
- [x] Run `TranscriptWorkflowTests` and confirm any behavioral failure before fixing integration gaps.
- [x] Resolve integration gaps within the relevant task files, without expanding scope into OCR or transcript program detection.
- [x] Run `bash script/run_tests.sh` and `swift build --disable-sandbox`; require passing suite and successful build. Run `git diff --check`; require no whitespace errors. Run `graphify update .`; require successful AST update.
- [x] Smoke-test the built app: new plan starts at year; major/minor before upload; sample import shows earned/current groups; picker can add a missed class; current term editable; successful review reaches workload; every pathway preserves current semester; AP remapping/reimport retains totals; relaunch retains history; image-only PDF offers manual route. Use the user's PDF locally for the smoke test only; do not copy it into fixtures or record private contents in logs/screenshots.
- [x] Commit passing integration changes as `test: verify continuing-student transcript workflow`; report validation results and any limitations. Do not push or create a PR unless requested by the user or the chosen execution workflow.

## Execution handoff

This is one connected feature: review UI depends on parser/credit contracts, and the scheduler/store must agree on temporal and credit semantics. Implement tasks in order. Recommend subagent-driven execution because independent task reviews can catch mistakes in duplicate handling and prerequisite timing before dependent UI work lands. Native execution remains available, using executing-plans and one final independent branch review. User must review this written plan and select an execution method before implementation.

## Verification record

All eight tasks are implemented. Native isolated-app checks verified year → major → minor → upload/manual → review, credit editing controls, catalog addition, and Back. The supplied PDF extracted 24 rows (49 earned and 16 current hours) locally. Persistence, cancellation, reimport, image-only errors, term confirmation, and all three generated pathways are covered by automated tests; the full relaunch and image-only flows were not repeated interactively.
