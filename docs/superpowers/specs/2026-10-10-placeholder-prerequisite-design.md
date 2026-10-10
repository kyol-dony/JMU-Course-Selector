# Conditional prerequisites through unresolved course placeholders

## Intent and agreed behavior

Students use the planner to explore a customizable pathway before deciding every elective. An unresolved course placeholder can offer a prerequisite that unlocks later required courses. Generation currently ignores that possibility, stalls those courses, and eventually places them through best-effort fallback.

Generate a pathway that can work with compatible choices from its placeholders, while leaving every placeholder unselected. Explain the outstanding choices on the Schedule board and in the picker. Conditional assumptions must never become named courses, earned credits, or contributing courses in My Plan.

The user approved the following behavior:

- An earlier unresolved slot can conditionally support a later course when an eligible choice can satisfy the prerequisite.
- One slot represents one course; it cannot simultaneously supply incompatible alternatives. One supporting choice can unlock several dependent courses.
- Supporting choices must themselves be feasible in their proposed semesters.
- Prerequisites require an earlier semester. Corequisites retain their existing alongside-or-before rules, and lecture/lab pairs retain their same-semester rule.
- Feasible outstanding choices receive a yellow warning on the placeholder and explanatory marks in its picker.
- Choosing an incompatible option preserves placements and produces ordinary conflict warnings. It does not automatically reschedule courses or replace the student's choice.
- Restricted slots, subject/level elective pools, and unrestricted Open Electives participate using the same course menus their pickers expose.
- Dependencies refresh after edits, undo, and regeneration. An unresolved preserved slot can conditionally support a regenerated suffix without changing the preserved semesters.
- Relationships are derived from the current pathway, not saved as assumed course selections.

This specification supersedes the earlier semester-anchored regeneration specification's prohibition on using unresolved slots as future prerequisite input. Its preservation and completion-accounting guarantees still apply.

## Existing implementation and integration points

`ScheduleGenerator.buildSemesters` gives placeholders their reserved workload credits, unrestricted availability, and an empty prerequisite expression. It evaluates real courses against a set of completed course IDs. Adding a placeholder ID to that set cannot satisfy a named course leaf. After eight empty iterations, the normal non-strict generator falls back to best-effort placement.

`PlaceholderSpec` already describes a slot's course menu and reserved credits. `Pathway` stores unresolved IDs and explicit `resolvedPlaceholders` mappings. `PlanStore.resolvePlaceholder` only creates a mapping when the student chooses a course, and retains the definition for reversal.

`ConflictDetector` evaluates concrete scheduled courses chronologically and skips unresolved slots. `DropVerdictCalculator` returns neutral verdicts for every placeholder without simulating its move. `ProgressCalculator` filters unresolved IDs out of requirement completion, and `ProgressContributionBuilder` only finds actual courses.

`PlaceholderChip` renders an unresolved slot. `SemesterColumnView` opens `CoursePickerSheet` using `PlaceholderCoursePickerPolicy`. The picker currently has no per-course prerequisite annotations. `PlanStore` already invalidates warning, progress, and drag-verdict caches on plan or catalog changes.

These are the integration boundaries. Do not replace the scheduler, alter requirement parsing, or change the academic-history model for this feature.

## Shared conditional analysis

Introduce a focused, pure PlannerCore analysis component. It consumes the catalog, effective program context, prior completed courses, standing context, workload policy, and chronological schedule items with their placeholder definitions. It returns:

- prerequisite status for each concrete course: satisfied by real courses, conditionally supportable, or unmet;
- unresolved slot IDs involved in conditional dependencies;
- feasible supporting option IDs for each relevant slot, with dependent course IDs and semesters;
- ordinary unresolved conflicts and explanations when slots cannot cover the required combination;
- feasibility status that distinguishes a proven result from a search interrupted by cancellation or its work limit.

Keep the existing `PrereqEvaluator` as the evaluator of real completed and scheduled courses. The new component first uses real-course evaluation, then analyzes the remaining expression against possible slot choices. It must not insert alternate IDs into the real completed-course set.

Generation and warning analysis share these semantics through this component. The picker consumes its output; it does not implement a second prerequisite algorithm.

## Feasibility and compatible choices

Each unresolved slot is a variable whose domain is its eligible course menu. For explicit alternates, use valid catalog IDs from the definition. For an empty alternate list, use the full catalog, matching the existing Open Elective picker. Subject/level pools are already expanded by catalog loading. Share domain resolution between core analysis and the app's picker policy so eligibility cannot diverge.

Restrict conditional providers to course choices relevant to missing prerequisite/corequisite expressions and their upstream dependencies. Unrelated menu options remain selectable in the UI; omitting them from a dependency search does not remove them from the menu.

A course expression is supportable only if there is a compatible assignment of courses to relevant slots that satisfies all admitted dependencies. Preserve conjunctions and disjunctions from `PrereqExpr`; do not flatten them into a union of course IDs. Test supporting choices together with previously admitted dependencies, and retain feasible alternatives rather than treating the first search witness as a student selection.

Examples:

- One earlier `[A, B]` slot can support a later course requiring `A or B`.
- It cannot support a course requiring `A and B` without another provider.
- It cannot support separate later courses requiring A and B simultaneously.
- An A choice can support multiple later courses that each require A.
- Two earlier slots can cover A and B when their domains and the requirement's distinct-course rules allow it.

Distinct slots represent distinct scheduled activities. Do not invent duplicate course enrollments or count one hypothetical enrollment twice to cover separate slots. A concrete course already scheduled too late is an ordering problem; do not invent an earlier duplicate enrollment through a placeholder to hide it.

For each hypothetical provider, check its own resolved prerequisites against real courses and earlier eligible providers, its standing, and its known semester availability. Apply the existing permissive treatment of unknown catalog prose and unknown availability. Detect dependency cycles; a slot cannot justify itself, and mutually dependent choices cannot bootstrap one another. An unresolved placeholder is not a source of unparsed permission or a substitute for a standing requirement.

Corequisites can use eligible same-term or earlier providers where the existing rule allows them. Lecture/lab candidates must have a feasible same-term partner already represented by concrete work or an eligible slot. Do not pretend an unrepresented lab exists. The analysis cannot add or relocate a lab in a preserved semester.

Feasibility must also respect the semester's workload cap using the hypothetical course and required lab credits in place of the affected reservations. Reserved credits remain the displayed planning estimate until a real choice is made. Hypothetical credit substitutions are internal feasibility input, not earned credits or extra displayed courses.

Use deterministic, memoized search, partitioned by connected slot/dependency groups. Limit each connected group to 10,000 explored search states per pass and check cancellation during exploration. A limit reached is unknown feasibility, not proof that a choice works or cannot work. Never use an unproven assignment to admit a course during generation or hide a missing-prerequisite warning. On the board, explain that the dependency could not be confirmed and the student can select a concrete course or regenerate. Existing warning/fallback behavior provides conservative recovery. Keep this limit injectable for deterministic tests.

## Generation behavior

Build possible dependency links from the effective required courses and eligible slot menus before semester placement. These links provide lookahead: a slot needed for a pending course should gain priority early enough to unlock that course. Existing workload caps, program interleaving, strategy preferences, availability, and standing remain applicable. Prerequisite urgency takes precedence over a placeholder's median course-level preference; the existing preferences order otherwise-equivalent candidates.

At each semester, use real completed work plus earlier unresolved slots as conditional eligibility input. Within the current semester, jointly check selected candidates and their possible prerequisite/corequisite requirements before admitting them. A slot cannot count as an earlier prerequisite for another item in the same semester merely because it appears first in the row.

Maintain the constraints introduced by admitted courses throughout construction. Later choices may narrow or change a feasible internal scenario, but cannot invalidate earlier dependencies. Existing deterministic candidate order resolves competition when one slot cannot support every required course. A candidate without a feasible compatible route remains unmet; do not silently add a new prerequisite course, invent a new slot, or claim the whole schedule is valid.

Preserve the existing strict-mode error and non-strict best-effort fallback for genuinely unsupported work. The intended fix removes fallback caused solely by ignoring feasible slots. It does not promise to repair missing requirements or impossible catalog rules.

Generated `SemesterPlan.courseIDs` continue to contain placeholder IDs. `resolvedPlaceholders` is unchanged unless it already records real user choices. No solver witness is persisted as a course selection.

## Schedule warnings and editing

Analyze the current pathway, including saved pathways that predate this feature. Process dependents in stable chronological order, retaining compatible dependencies across them. Use the existing within-semester item order as a deterministic tie-breaker where incompatible requirements compete for insufficient slots.

When a real prerequisite is satisfied, it needs no conditional notice. When a feasible unresolved choice can supply it, replace the false missing-prerequisite error with a yellow notice attached to the relevant placeholder. The dependent is conditionally planned, not recorded as having its prerequisite completed.

When no compatible route exists, retain the ordinary missing-prerequisite/corequisite conflict on the dependent. Where relevant, explain that a single slot cannot cover both choices. An impossible or unconfirmed route must not become a reassuring yellow notice.

Derive notices from every current plan revision, not just generator output. Selection, removal, moving a slot or course, adding/deleting semesters, undo/redo, catalog changes, and regeneration invalidate this derived analysis through PlanStore's existing invalidation path. Reuse one cached analysis per revision for warnings and picker annotations rather than independently searching in each chip.

If the student chooses an incompatible option, retain their chosen course and all placements. The pending notice disappears for that resolved slot, and affected courses receive normal conflicts. If another actual course or feasible earlier slot still supplies the prerequisite, do not emit a false conflict. Removing a selected course restores the slot and recalculates conditional possibilities. Existing undo and warning-count toasts remain applicable.

Remove the blanket neutral verdict for placeholder dragging. Simulate its move through the shared analysis, including any existing lecture/lab movement rules. Moving it into the dependent's semester or later can turn a pending choice into a blocking conflict. Moving it earlier can restore conditional support. Preview messages and post-drop warnings must agree, and previews must not mutate the pathway.

## Placeholder and picker UI

Add a visible yellow warning affordance to an unresolved placeholder that the current schedule depends on. Default label: **Prerequisite choice needed**. Hover/help text explains the compatible course choices and names the dependent courses with their semesters. Provide the same explanation through a keyboard-operable popover and an accessibility description; do not rely on yellow alone.

Example: "Choose MATH 300 here to support MATH 410 in Fall 2028." If several choices work, list them or summarize with a readable count and expose the full detail in the popover/picker.

When opening that placeholder, show a short explanation above the existing searchable course list. Mark supporting rows with a visible label such as **Supports MATH 410 in Fall 2028**. A course supporting multiple dependents lists those dependents in accessible detail. An annotation is based on compatible feasibility, not merely sharing an ID with a prerequisite leaf.

Keep search, current course ordering, and all eligible selections available. Do not preselect, resolve, restrict the menu to highlighted courses, or automatically regenerate after a selection. The student may intentionally choose another course and review its resulting warnings.

The same picker is used outside placeholders. Dependency annotations are optional context; ordinary add-course pickers retain their existing behavior.

## Anchored regeneration and persisted state

Seed conditional analysis with unresolved slots in the preserved prefix, while concrete preserved courses continue to supply ordinary eligibility. Preserve every anchored SemesterPlan and its course order, credit overrides, resolved choices, and required placeholder definitions exactly. No annotation changes the saved anchor.

Generation after the cutoff can depend on a feasible choice in an earlier preserved slot. It must not pull a placeholder, course, or lab across the boundary to manufacture that feasibility. Existing anchor conflicts remain visible and do not become a reason to modify anchors. Use the full pathway's chronology and standing context.

No new assumed-selection fields or catalog schema migration are required. Compute conditional dependencies from current pathway IDs, placeholder definitions, explicit selections, catalog rules, and academic history. Ignore retained definitions of resolved or absent placeholders as possible unresolved providers.

Preserve existing completion and contribution behavior in My Plan, transcript/transfer history, exports, and classification. Only actual selected courses can appear as named contributing work. Unresolved slots retain their existing reserved workload/projected-hour estimates; this feature does not change that accounting policy or invent extra credits.

## Focused implementation boundaries

- Add the shared conditional analysis/feasibility component to PlannerCore, with separate domain and result types where necessary to keep its responsibilities understandable.
- Integrate eligibility and dependency urgency in `ScheduleGenerator` and conditional status in `ConflictDetector`.
- Extend `DropVerdictCalculator` to analyze placeholder moves.
- Cache the analysis through PlanStore's normal plan/catalog revision invalidation.
- Add notice presentation to `PlaceholderChip` and its Schedule board call sites, and optional dependency context to `CoursePickerSheet` and its eligibility policy.
- Update tests that intentionally assert unresolved anchored slots cannot support prerequisites; retain tests proving they grant no completion credit.

Avoid unrelated parser changes, requirement-model redesign, automatic prerequisite insertion, or a replacement scheduler. Existing warning override behavior for real conflicts remains available. Pending-choice notices are derived explanations, not a mechanism to declare an unresolved prerequisite completed.

## Validation and acceptance

Use focused fixtures with concrete semesters, prerequisite expressions, bounded/unrestricted slots, and actual program requirements. Tests must verify observable scheduling, warnings, and completion behavior rather than merely mirroring helper internals.

1. A feasible earlier slot unlocks a later required course without eight-empty-term fallback, including strict generation. The slot remains unresolved in every generated strategy.
2. Same-term and later slots cannot satisfy a prerequisite. Allowed same-term corequisites and lecture/lab rules retain their temporal distinctions.
3. AND/OR expressions, multiple supporting slots, reuse of one provider for several dependents, and contradictory choices are handled consistently across the whole analyzed pathway.
4. A supporting option with unmet own prerequisites, a cycle, inadequate standing, unavailable term, missing mandatory lab, or excess hypothetical workload cannot justify placement.
5. Chains involving several slots propagate support only through a feasible chronological route. Real earned/selected work is preferred and avoids unnecessary pending notices.
6. Open Electives and expanded subject/level pools use the actual eligible course menus and obey the same feasibility rules.
7. Conditional options do not appear in completed course IDs, resolved-placeholder mappings, My Plan credits/contributions, academic history, or exports. Existing reserved workload estimates remain intact.
8. A compatible selection clears its pending notice and supports dependents normally. An incompatible selection preserves placements and creates the correct ordinary conflicts; another valid provider prevents false conflicts.
9. Moving a placeholder before/alongside/after a dependent produces consistent drag previews and final warnings. Removal/restoration, semester edits, undo/redo, and catalog changes refresh annotations.
10. Anchored regeneration uses feasible prefix placeholders without modifying preserved semesters or manufacturing actual course selections. Obsolete/resolved metadata never acts as an unresolved provider.
11. Search work limits and cancellation are exercised explicitly: neither creates false satisfaction nor leaks partial plan mutations. Deterministic inputs produce deterministic outputs.
12. UI verification covers a visible yellow affordance, hover and keyboard explanations, clearly marked supporting picker rows, unrestricted selection, search, narrow layouts, and accessibility. Existing generic picker uses remain unchanged.

Run the complete Swift package tests and application build after implementation, plus a representative catalog-backed schedule comparison to check that feasible dependent courses move into sensible earlier semesters without changing degree progress. Verify the warning and picker flow in the running app; compilation alone does not establish the UI behavior.

## Review status

The conversational architecture and integration design were approved on October 10, 2026. This written specification requires user review before the implementation plan is written. Implementation begins only after the written plan is reviewed and its execution method selected, as required by the invoked brainstorming workflow.
