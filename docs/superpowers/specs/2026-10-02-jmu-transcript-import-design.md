# JMU transcript import and continuing-student setup

Date: 2026-10-02
Status: Written specification awaiting user review

## Intent and agreed scope

Expand the planner from an incoming-freshman-focused tool to students of all undergraduate years. Students should be able to import a JMU unofficial transcript, review their classes and credits, and generate a plan for their remaining requirements without rescheduling completed or currently enrolled courses.

The user approved local parsing of text-based JMU unofficial transcript PDFs. The importer detects classes, credits, grades, and terms only; it must not detect or choose majors, minors, or concentrations. Students select their programs before uploading. In-progress classes remain separate from earned credit, appear in the current semester, and participate in planning and prerequisite checks for subsequent semesters. Generation preserves that semester exactly.

Upload is optional. Both import and manual entry support reviewing and adding courses through the existing open-elective catalog picker. The current semester is prefilled from the latest transcript term and is editable. After review, students proceed directly to credit load.

Scans, screenshots, OCR, transcripts from other institutions, remote parsing services, and automatic program detection are outside this release. A JMU transcript can still supply JMU-awarded equivalents for AP and transfer work.

## Existing implementation and integration points

- `SetupSheet` currently uses four numbered steps: major, minor, transfer, workload. Replace numeric branching with explicit steps and route history so Back follows the path actually taken.
- `SetupStepMajor` and `SetupStepMinor` retain the existing primary/secondary program and concentration selection behavior.
- `CoursePickerSheet` already accepts a course collection and selection callback. Reuse it against the full catalog for manual additions; do not apply elective requirement restrictions to transcript review.
- `SavedStudentPlan` persists program choices, AP scores, transfer credits, and pathways. Add backward-compatible student-year, prior-course, current-semester, and setup-completion data.
- `TransferCredit` currently supplies completed-at-start course IDs and credit totals. Adapt confirmed prior courses into that pipeline without describing JMU resident courses as transfer work in the UI.
- `PlanStore.recomputeAPCredits` currently identifies AP entries by description text. Introduce explicit credit provenance, preserving legacy decoding, so transcript imports and manual entries survive AP remapping and are deduplicated deliberately.
- `ScheduleGenerator.generatePathways` currently accepts prior credit but no preserved semester. `PlanStore.generateSchedules` also hardcodes Fall 2026. Replace that start selection with plan term data and an optional preserved current semester.
- Progress, warnings, drop verdicts, and schedule generation must consume the same effective prior-credit data. Avoid a second, divergent prerequisite implementation.

## Setup and navigation

The first interactive screen for a new plan asks for year in school: Incoming freshman, Freshman (already enrolled), Sophomore, Junior, Senior, or Fifth year or beyond. These selections are descriptive; earned credit drives academic-standing checks, rather than converting a year label directly into credit.

New-plan routes:

1. Incoming freshman: Year → Major/concentration → Optional minors/secondary programs → Existing AP/dual-enrollment entry → Credit load → Generate.
2. Other years: Year → Major/concentration → Optional minors/secondary programs → Transcript upload → Course review → Credit load → Generate.
3. Skip upload / enter manually: Follow the continuing-student route, then open an empty review with catalog additions, current-term selection, and access to existing AP/dual-enrollment entry. Continue to credit load when ready.

Selecting a non-incoming year no longer immediately opens upload: the user's later instruction explicitly places major/minor selection before upload. Optional minor selection remains skippable. Required concentrations must be chosen before advancing beyond program selection.

The year screen can render before catalog loading finishes; program selection waits for catalog availability. Ordinary reopening of an existing plan does not replay onboarding. A legacy plan with a selected major remains usable without forced migration through the wizard. Reopening setup uses saved choices and provides transcript import/manual review access.

Back navigation preserves draft edits. Changing year changes the remaining route but does not silently delete existing course data. Canceling an unconfirmed import discards the import draft while retaining previously confirmed credits and courses.

## Local extraction and parsing

Separate these responsibilities:

1. A local PDF reader obtains selectable text page by page and reports file/readability failures. Use the platform PDF facilities; no product parsing service or transcript network request is introduced.
2. A deterministic JMU text parser, independent of UI and PDF reading, recognizes section headings, term boundaries, course rows, and numeric fields.
3. A catalog reconciliation layer normalizes codes, resolves known JMU course IDs and existing general-education aliases, and creates review issues for unmatched or ambiguous rows.
4. A review draft holds extracted rows and user corrections. Only explicit confirmation commits the effective academic history to the plan.

Read all pages. Ignore identifying headers, program declarations, GPA summaries, page numbers, and transcript totals as course rows. Detect JMU transcript structure instead of accepting any arbitrary PDF containing course-like strings. Printed totals may be used for reconciliation warnings, never as an additional credit award.

Each candidate row includes a stable draft identifier, normalized course code, printed description, attempted credits, earned credits, grade when present, term when present, credit source, status, and any review issues. Preserve fractional credits. Credit arithmetic and persistence must support non-integer awards rather than truncating them to the existing integer model.

Classification:

- Positive earned credit with a passing/credit-bearing result becomes earned credit. Completed JMU courses and JMU-awarded test/transfer equivalents retain distinct provenance.
- Zero earned credit, positive attempted credit, and a blank grade in an academic-term course section is an in-progress candidate. These candidates require confirmation against the selected current semester.
- Failed, withdrawn, incomplete, and otherwise unearned attempts do not become earned credit or automatic in-progress enrollment. Show excluded/uncertain attempts in a review disclosure so students can correct classifications.
- Unrecognized grades, malformed rows, and conflicting values require a visible review decision. Do not infer credit from the catalog when the transcript says no credit was earned.
- A latest term containing completed courses can prefill the term selector without turning completed classes into in-progress courses. In-progress candidates from a different term are flagged and cannot be applied silently.

The supplied one-page sample has 49 earned test-credit hours and five ungraded Fall 2026 classes totaling 16 attempted hours. The initial parser acceptance case must reproduce those course groups and totals. It contains general-credit entries such as `CS OOO`; preserve the printed code and earned amount instead of guessing a specific course equivalence. Do not store the personal PDF or identifying fields in repository fixtures.

## Review and manual corrections

Show Earned credit and In progress as separate groups with course code, title, credits, source, and status. Provide a disclosure for excluded attempts and parsing issues. Show earned and current-load totals separately.

Students can remove rows, change status and credit amounts, replace an incorrect course match, and add missed courses using `CoursePickerSheet`. Additions explicitly target Earned credit or In progress. Catalog credits provide the initial value for manual additions; the student can correct it. Manual completed courses need no historic semester because they apply before the planning horizon.

Unknown codes retain their description and amount. They may contribute general earned hours but cannot satisfy a named course prerequisite or named requirement without a recognized equivalence. Students can map them to a catalog course, retain them as general credit, or exclude them. Review must make that distinction visible.

Prefill the current term from the latest transcript academic term and allow year and term editing. Changing the term places the reviewed in-progress group into that selected term; warn about inconsistent printed terms and require a decision. A continuing student with no current enrollment can confirm an empty current semester and choose its identity explicitly.

Confirmation requires resolved credit/status conflicts and valid nonnegative amounts. Retaining an unmatched row explicitly as general credit resolves its matching issue. No program data is extracted or modified during review. Successful confirmation advances to workload preference without another AP/transfer screen; those awards should already be represented by the transcript or added during review.

## Persistence, provenance, and duplicate handling

Persist only confirmed academic data: year selection, canonical course records, credit source/status, any grade needed to preserve the import, current term and its enrollment, and setup completion. Do not persist original PDF bytes, raw page text, identifying headers, or the user's sample file path.

Source kinds distinguish legacy/manual/AP-mapped credit, transcript JMU coursework, and transcript test/transfer awards. A centralized adapter produces effective earned credit for existing consumers. Keep raw confirmed rows separate from effective deduplicated credit so students can understand overlap decisions.

Known course IDs receive credit once when the same class appears in multiple sources or repeated attempts. Prefer the confirmed transcript award over an overlapping manually mapped AP award; AP recomputation treats confirmed prior coursework as already credited. Flag conflicting amounts and repeatable-course ambiguity for correction rather than blindly summing. A reviewed aggregate amount can represent legitimate repeatable credit while course satisfaction remains a set membership check.

Reimport replaces transcript-derived records after review; it does not append another copy. Preserve independent manual/AP entries unless the student explicitly removes them, then deduplicate the effective result. Conflicts between earned and current enrollment for the same course require a review choice before confirmation.

Decode new fields with defaults so existing saved plans continue to load. Existing integer credit values must decode into the fractional-capable representation. Legacy credits remain effective, and legacy AP descriptions can be migrated once into typed provenance. Imported data changes invalidate all dependent caches and are saved atomically on confirmation.

## Scheduling and prerequisite behavior

For continuing students, each generated pathway starts with the identical reviewed current semester. Do not add courses to it, remove imported courses, move them, or apply workload balancing to it during generation or regeneration. Generate new requirements beginning with the next supported chronological term according to the existing semester model.

Earned course IDs are completed before the current semester. Current enrollment satisfies prerequisite checks only for later semesters; a current prerequisite is not completed before another course in that same semester. Existing corequisite evaluation handles valid same-term relationships. Imported enrollment can show existing prerequisite/corequisite warnings without being changed by generation.

Build remaining requirements against earned courses plus the projected completion of current enrollment. Count current enrollment once toward projected program requirements and graduation hours, while keeping actual earned totals distinct. Unknown general credit contributes earned hours but does not invent course-specific fulfillment. Ensure earned credit reduces open-elective needs so the planner does not overfill the remaining path to graduation.

Generation retains the current semester even when no further requirements remain. If the current load is outside the selected workload range, show the normal warning and apply the chosen range only to generated future semesters. Incoming-freshman plans have no preserved enrollment semester; generate from their selected/default planning start term using existing behavior.

Schedule edits remain available through existing board controls after generation. Editing the preserved current enrollment must update the stored enrollment source as well as the active pathway so regeneration preserves the corrected roster, not an obsolete import. Confirming a changed import invalidates generated pathways; keep the user in setup until regeneration succeeds rather than presenting a stale plan as current.

Reuse the existing prerequisite evaluator. This release adds temporal treatment of enrollment, not a new grade-threshold evaluation subsystem; retain existing handling of unsupported grade-specific prerequisite rules and their warnings.

## Failure behavior and privacy

Process extraction off the UI thread, with progress and cancellation. Unsupported/image-only PDFs, encrypted/unreadable files, non-JMU documents, and no recognizable course rows produce actionable retry/manual-entry messages. Do not overwrite confirmed data on failure or cancellation.

Partial recognition opens review with explicit issues and a credit-total mismatch notice when applicable. An empty result cannot masquerade as a successful import; manual empty-history confirmation remains available separately. Never log raw transcript text or identifying fields. Use the local file only for the active extraction operation.

## Validation and acceptance criteria

- A new plan's first interactive screen asks year; all routes enforce program selection before import and reach credit load correctly. Back, skip, retry, and cancel retain the intended state.
- A de-identified text fixture based on the supplied layout yields 49 earned hours and the five Fall 2026 in-progress classes totaling 16 hours, without importing majors or personal fields.
- Synthetic fixtures cover multiple pages/terms, repeated headers, completed resident courses, passing credit, failed/withdrawn/incomplete rows, blank grades, lab suffixes, general-credit codes, fractional credits, and malformed rows. The supplied example alone does not validate all JMU transcript variants.
- Review additions reuse the full-catalog picker; removal, status correction, general-credit retention, term correction, and conflicting duplicate resolution affect the committed result.
- Importing the same academic history twice does not double credits. AP recomputation, major changes, and duplicate resident/test/manual entries preserve the correct effective awards.
- Existing saved plans decode and retain behavior; imported plans round-trip their year, provenance, fractional credit, and current enrollment.
- Every generated pathway preserves the reviewed current roster and term, schedules future work afterward, and avoids duplicating earned/current courses. Include a prerequisite chain whose first course is currently enrolled and an invalid same-term prerequisite case.
- Current enrollment affects projected progress without increasing actual earned credit. General earned hours reduce remaining open electives without satisfying an unrelated named prerequisite. Fractional and overlapping credits remain consistent across progress, warnings, standing checks, and generation.
- Regeneration preserves reviewed or subsequently edited current enrollment, including an empty current term and a plan with no future requirements.
- Unreadable and partial imports leave existing confirmed data intact and expose the manual route. No private transcript is committed as a fixture or retained by the import feature.

## Next stage

After user review and approval of this written specification, use the writing-plans skill to prepare the implementation plan. No product implementation is authorized by conversational design approval alone under the invoked brainstorming workflow.
