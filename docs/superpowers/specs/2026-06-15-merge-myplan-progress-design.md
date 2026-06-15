# Merge "My Plan" and "Progress" tabs

## Goal

Collapse the `AppTab.myPlan` and `AppTab.progress` tabs into a single `AppTab.myPlan` surface so the user sees their identity, completion, and per-category breakdown without bouncing between two views that overlap on most of their content.

## Why

The two tabs duplicate the spine of the data:

- Both render `store.progress.overallFraction` and `projectedGraduation`.
- Both list `progress.categories` with the same `ProgressRail` widget and remaining-credits text.

`MyPlanView` carries unique program identity cards and footer actions. `GraduationProgressView` carries unique chart polish (donut), at-a-glance counters, a "Next term" shortcut, and a per-category Contributing-courses list. Today the user must learn that "progress detail" lives on a different tab than "plan summary," even though every requirement bar on Progress mirrors a bar on My Plan.

## Out of scope

- New analytics fields (semesters-left counter, categories-done counter from the current Progress at-a-glance row are intentionally dropped — they aren't load-bearing enough to keep when the donut already shows completion fraction).
- Touching the Schedule or Catalog tabs.
- Changing the underlying `ProgressCalculator` data model.

## User-facing layout

Single vertical scroll inside `MyPlanView`. Top-down:

1. **Program identity cards** — primary major hero card + one card per minor/second major (unchanged).
2. **Stats row** — two side-by-side tiles:
   - **Completion tile**: gold-ring donut around the "X%" headline, with "X of 120 credits planned · N to go" caption below the donut.
   - **Graduation tile**: "Projected graduation" label, semester string, and a "Next term: <semester> →" pill button. Pill tap switches `store.selectedTab` to `.schedule`. (Schedule board's own auto-scroll-to-current-semester behavior, if any, decides whether the user lands directly on that column; this design does not add new scroll plumbing.)
3. **By category list** — one card per `progress.categories`:
   - Header row: category name, status pill (`Complete` / `Partial`), `X/Y` credit total.
   - Gold `ProgressRail`.
   - "Still need: …" text using `remainingCourseCodes`.
   - "Contributing courses" sub-list: one row per scheduled or transferred course, showing course code + semester (or `Transfer` pill). Open Electives pull rows from `pathway.resolvedPlaceholders`. Sub-list is always expanded; no chevron.
   - Card is a tap target: tap sets `store.scheduleCategoryFilter = category.id` and switches to the Schedule tab, where `ScheduleBoardView.isHighlighted(courseID:)` already glows every chip whose ID belongs to the chosen category (primary, minor-prefixed, or open-elective).
   - Hover state retained: `RequirementProgressRow` paints its background `brandPurpleSoft` on hover, matching today's MyPlan behavior.
4. **Footer actions** — `Edit setup` + `Regenerate pathways` buttons (unchanged from current MyPlan).

## Architecture changes

### File-level changes

- **Delete** `Sources/JMUCoursePlanner/Views/Tabs/GraduationProgressView.swift` after migrating its donut, `contributionList`, `openElectiveContributions`, and `CourseContribution` helpers into `MyPlanView.swift`.
- **Edit** `Sources/JMUCoursePlanner/Views/AppTab.swift`: drop `case progress` and its entries in `title` / `systemImage`.
- **Edit** `Sources/JMUCoursePlanner/Views/ContentView.swift`: remove `case .progress: GraduationProgressView(catalog: catalog)` from the tab switch.
- **Edit** `Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift`:
  - Replace the `stats` HStack with the hybrid two-tile row described above. The left tile becomes a donut variant of `completionTile`; the right tile is `graduationTile` plus the "Next term →" pill button.
  - Replace `categoryBreakdown` with the richer card shape from GraduationProgressView's `categoryList`, keeping `RequirementProgressRow`'s tap + hover plumbing.
  - Move `contributionList(rows:)`, `openElectiveContributions()`, `contributions(for:)`, and the `CourseContribution` struct over from GraduationProgressView.
- **Edit** `Sources/JMUCoursePlanner/Stores/PlanStore.swift`: confirm `selectedTab` default stays `.myPlan`. If a persisted plan ever holds `.progress`, coerce it to `.myPlan` during decode (defensive, since `selectedTab` may or may not be persisted today — verify and add the fallback only if needed).
- **Edit** `Sources/JMUCoursePlanner/Views/TopBar.swift`: tab nav rebuild is automatic via `AppTab.allCases`; the chip count drops by one with no further code changes.

### Behavior to preserve

- Tap-to-schedule highlight (`store.scheduleCategoryFilter`) — already wired in `ScheduleBoardView.isHighlighted(courseID:)` to handle primary, minor-prefixed, and open-elective category IDs.
- Hover background fill on each requirement row.
- Open Electives row: gold `ProgressRail` (status `.partial`), Contributing-courses rows sourced from `pathway.resolvedPlaceholders`, full-catalog picker on placeholder taps in Schedule.
- Footer button styles + actions.

### Risks

- **Tall cards** — categories with many resolved courses produce tall cards. Acceptable at the typical 15-25 category count; the outer `ScrollView` already handles overflow.
- **Persisted tab id** — if a prior `.progress` value lives in serialized state, the enum decode would fail. Mitigation: coerce on load. Confirm during implementation whether the field is in fact persisted.

## Verification

- Build clean, `swift test` green (no test currently asserts on `AppTab.progress`; if one is added before this lands, it must be updated or removed).
- Manual smoke:
  1. Launch app with an existing plan that had `selectedTab = .progress` (simulate by editing the saved plan JSON). App should open on `My Plan` without crashing.
  2. From `My Plan`, tap a category card whose courses are scheduled. Verify Schedule tab opens and the matching chips have the highlight ring.
  3. Hover a category card. Verify the soft purple background fades in.
  4. Resolve an Open Elective placeholder, return to My Plan, verify the resolved course appears in the Open Electives "Contributing courses" sub-list with the correct semester.
  5. Tap the "Next term →" pill, verify Schedule tab opens.
