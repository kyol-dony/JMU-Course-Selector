# Semester-anchored schedule regeneration

## Intent and agreed scope

The planner is also a brainstorming tool. A student should be able to craft the early part of a pathway, then ask the existing algorithm to rebuild the remaining work without restarting setup or losing those decisions.

The action affects only the displayed pathway. The student chooses the last semester to preserve: that semester and every earlier semester are anchors; regeneration starts in the following semester. Other pathways remain unchanged. Existing anchor warnings stay visible for reference but do not block generation or cause the generator to modify anchors.

The user selected extending the existing generator to support multiple anchored semesters. Unresolved anchored elective slots reserve their requirement and planned credits; they do not satisfy a named prerequisite until a specific course is chosen. The user approved the UI, animation, recovery, and undo behavior below.

## Generation architecture

Extend the shared generation pipeline with an explicit anchored prefix and its relevant placeholder metadata. Setup generation and partial regeneration must use the same requirement selection, workload, prerequisites/corequisites, availability, elective allocation, standing, and lecture/lab rules. Preserve existing setup/full-regeneration behavior and backwards-compatible saved-plan loading.

A core regeneration entry point consumes the source pathway, the selected cutoff semester, the active strategy, declared programs/concentrations, workload, and effective prior credit. It returns one replacement pathway. Internally, select only the requested strategy rather than generating three pathways and discarding two.

The core owns generation context and remaining-work allocation. PlanStore owns asynchronous lifecycle, active-pathway replacement, undo, and persistence. ScheduleBoardView owns the picker and display transitions; it must not change the saved pathway merely to animate it.

Use the displayed pathway's existing Balanced, Major-First, or Gen Ed-First strategy. Its ID and name survive replacement. For legacy nonstandard pathway IDs, use the existing variant's position where available, falling back to Balanced. This release adds no separate strategy chooser.

## Anchor preservation and remaining work

- Require a selected semester that exists in the displayed pathway. Derive the prefix chronologically through that semester.
- Preserve every anchored SemesterPlan exactly: identity, course order, empty semesters, credit overrides, and unknown-course titles. Preserve the prefix's existing gaps rather than normalizing its calendar.
- Preserve placeholder definitions needed by unresolved anchor IDs and resolved-placeholder links attributable to anchored course choices. New suffix placeholder IDs must not collide with those retained IDs. Remove metadata belonging solely to the discarded suffix.
- Seed future course eligibility with effective earned-credit IDs and concrete anchored course IDs. Do not validate anchors as a condition of regeneration. No anchor course, lab, placeholder, or semester can be moved, added, removed, or rewritten by the generator.
- Reserve each unresolved anchor slot against its associated requirement and planned hours. Keep it unresolved in progress and on the board. It provides no invented named-course prerequisite/corequisite equivalence. If a future dependent requires a concrete course not supplied by the prefix, use the existing prerequisite behavior; do not silently treat an alternate slot as that course.
- Preserve the existing prerequisite/corequisite evaluator semantics. Anchored concrete courses are available before the first regenerated semester. A lecture/lab issue in an anchor remains visible; automatic pairing may operate only on the new suffix and cannot pull a partner across the boundary.
- Account for anchored concrete and reserved placeholder hours when computing remaining graduation hours. Respect fractional overrides and avoid counting prior credit again when it also appears in the prefix. Do not convert anchored planned courses into earned academic-history records.
- Carry temporal context into standing, course-level preferences, and Gen Ed timing. A regenerated semester does not become a student's first semester merely because the builder begins a new suffix. Use the existing earned-hour context where present; otherwise preserve the existing semester-position rules with the anchored calendar offset.
- Apply normal generation rules to all new semesters, using the currently selected workload and program choices. Discard future manual placements and elective selections after the cutoff; the picker explains that this portion will be rebuilt.
- Allow any existing semester, including the last one, as a cutoff. Generate additional future semesters when work remains. When nothing remains, keep the anchors and report that no further semesters are needed.

Anchor warnings remain in normal issue lists, counts, and board affordances. Suffix warnings use the complete chronological pathway and normal effective credit so anchor courses can satisfy future rules. Regeneration neither hides anchor warnings nor changes their overrides.

## UI and motion

Add a dedicated **Regenerate after…** button beside the existing full-regeneration action on the Schedule page. Disable it when there is no displayed semester or another generation operation is running. Existing full regeneration remains available.

The button opens a semester picker listing the displayed pathway's existing semesters chronologically. Default to its first semester, which also naturally preserves imported current enrollment. The dialog clearly states that the selected semester is included in the preserved prefix, names the first future semester, identifies the affected pathway, and states that later course/elective choices will be replaced. It offers Cancel and a clear regeneration confirmation.

On confirmation, keep anchor columns stationary and visible. Fade out the future columns and show a loading area after the cutoff, with progress and Cancel. Maintain the anchor columns' positions and scroll context; removing suffix views must not recenter the anchors or jump the board back to its beginning. Temporarily disable schedule edits, pathway switching, and competing regeneration actions while the operation is active.

When the replacement is ready, publish it once and fade the new suffix into the board. If there is no future work, show a brief completion message after the anchors. Respect Reduce Motion by using immediate transitions without movement or staggered reveals. Provide accessible semester labels, explanatory dialog text, keyboard-operable controls, and readable generation status.

Partial regeneration uses inline board progress rather than the full-generation overlay that covers the anchors. Full/setup generation retains its existing overlay.

## Transaction, cancellation, and recovery

Keep the original pathway and all metadata in memory and saved state while work runs. The disappearance of future columns is presentation state only. Failure or cancellation clears presentation state and restores the original visible suffix, with no undo step or changed saved data. A generation failure shows a useful retry message.

Capture the plan ID, source pathway ID/content, catalog/program/workload/credit context, and a unique operation token before dispatching work. Reject stale results and progress callbacks if the operation was canceled, superseded, or its relevant context changed. Changing/loading a plan while work runs must never cause an old result to overwrite the new plan. Propagate cancellation into the detached worker and check it during meaningful generation iterations.

On success, replace only the captured pathway, preserve its ID/name and active selection, invalidate derived warning/progress/verdict caches, and autosave through the existing serial persistence flow. Leave other pathways, earned credit, current-semester academic records, program selections, workload, and prior-credit records unchanged. Do not store a permanent anchor boundary: a subsequent request can choose any semester again, and anchors remain normally editable after generation ends.

Register success as one existing schedule undo/redo transaction, named for the cutoff. Undo restores the previous suffix and its exact placeholder definitions and resolutions; redo restores the regenerated suffix. Do not clear unrelated earlier schedule undo history. Preserve anchor issue overrides; remove only obsolete suffix-specific overrides when their subjects no longer exist, and include that change in undo/redo.

## Verification

Core tests will cover:

- Exact preservation of multiple anchors, course order, empty semesters, gaps, unknown titles, and fractional overrides.
- Only future semesters rebuilt, existing active strategy retained, and no duplicate scheduling of anchored concrete courses.
- Anchored prerequisite/corequisite eligibility, normal future availability/workload/standing behavior, and existing lecture/lab rules without moving anchor partners.
- Anchor warnings/invalid order or load remaining untouched and not blocking regeneration.
- Unresolved anchor slots reserving their exact requirements/hours without granting named prerequisite eligibility; resolved anchor metadata retained and discarded suffix metadata removed; placeholder ID collisions avoided.
- Prior credit, anchored credits, and general electives counted once; corrected amounts and graduation top-up retained; original temporal offsets preserved.
- Last-semester cutoffs, no remaining work, and invalid/stale cutoff rejection.

Store tests will verify one-pathway replacement, other pathways unchanged, unchanged academic history/current enrollment, undo/redo, persistence round-trip, generation failure/cancellation, stale result/progress rejection, and protection when relevant plan context changes mid-operation.

UI verification will cover picker wording and keyboard access, anchor inclusion, future-only disappearance/reveal, stable anchor position/scrolling, cancellation/error restoration, inline progress, no competing mutations, and Reduce Motion. Run the full existing test suite and build, plus the repository's AST graph update after implementation.

## Release boundaries

This feature introduces no persistent course locks, future pinned-course exceptions, new pathway strategies, transcript detection, changes to prerequisite semantics, or prerequisite repair inside anchors. Full regeneration remains a separate existing action. Only the selected displayed pathway is partially regenerated.

Existing unrelated uncommitted catalog/elective/transcript work is outside this design's implementation ownership. Integration must preserve that work and test the combined result.
