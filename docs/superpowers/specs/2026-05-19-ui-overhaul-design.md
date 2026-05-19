# JMU Course Planner — UI Overhaul Design

**Date:** 2026-05-19
**Status:** Approved (pending user review of this document)
**Author:** Brainstorming session

## 1. Goal & scope

Replace the current SwiftUI UI (sidebar + main workspace + pinned 310px progress panel; long scrolling onboarding form; default Mac chrome) with a from-scratch dashboard-style interface that is more intuitive and more visually polished while expressing JMU's brand more clearly.

**In scope:** Every user-visible screen. The entire navigation skeleton. A real design-token layer (colors, spacing, type scale) replacing the two-color `JMUStyle` enum. Setup, schedule, catalog browsing, progress tracking, course detail.

**Out of scope:** Any change to `PlannerCore` (data model, schedule generator, conflict detector, progress calculator). The `PlanStore` API surface stays the same except for adding helpers needed for filter/selection state introduced by new screens. No change to the catalog refresh or data pipeline.

**Non-goals:** Custom illustrations, custom fonts beyond Inter/SF, animation libraries, a tutorial/help system, accessibility audit beyond keeping system defaults functional.

## 2. Decisions

The following choices were made interactively during brainstorming and are now fixed inputs to the implementation plan:

| Decision | Choice |
|---|---|
| Overhaul focus | Both intuitiveness and aesthetics — from-scratch redesign |
| Navigation skeleton | Modern dashboard with top tabs (no permanent sidebar) |
| Visual personality | Modern SaaS (Inter font, soft borders + shadows, status pills, gradient stat tiles) |
| Schedule layout | Horizontal-scroll semester columns |
| Onboarding placement | Modal sheet over the dashboard; dashboard renders empty-state behind |

## 3. Information architecture

A single window with four top-level tabs: **My Plan · Schedule · Catalog · Progress**. The active tab fills the workspace edge-to-edge. No permanent sidebar. No permanent right panel.

**Sticky top bar (~64px height, always present):**
- Left: small JMU logo mark + program title + degree-type pill
- Center: four-tab segmented control with active-tab indicator in `brand-purple`
- Right: two stat chips (completion %, projected graduation), plus a kebab menu containing Save, Export (PDF / .ics), Edit Setup, Refresh Requirements, Reset App Data, Start Over

**Setup is a modal sheet** layered over the dashboard. On first launch and any time the user has no program selected, the sheet opens automatically. The dashboard renders its empty-state behind it. Reopened from the kebab menu's "Edit Setup" action.

## 4. Visual design system

### Typography

- **Family:** Inter (with SF Pro fallback) for everything.
- **Tracking:** `-0.5px` on 18px+; `-0.3px` on 14–16px; default on body and below.
- **Numeric:** course codes, credit counts, percentages, dates use the `tabular-nums` feature so they align in lists.
- **Scale:** 11 / 12 / 13 / 14 / 16 / 18 / 22 / 28. Weights: 400 / 500 / 600 / 700 / 800 for the wordmark only.

### Color tokens (auto-adapt to light/dark)

Semantic names, not raw hex. Implementation switches values via `@Environment(\.colorScheme)`.

| Token | Light | Dark |
|---|---|---|
| `surface` | `#fafafa` | `#0a0a0c` |
| `surface-elevated` | `#ffffff` | `#15151a` |
| `surface-tinted` (hover) | `#f4f0fa` | `#1f1530` |
| `border-subtle` | `#e4e4e7` | `#2a2a30` |
| `border-strong` | `#a1a1aa` | `#52525b` |
| `text-primary` | `#0a0a0c` | `#fafafa` |
| `text-secondary` | `#52525b` | `#a1a1aa` |
| `text-tertiary` | `#71717a` | `#71717a` |
| `brand-purple` | `#450084` | `#7c3aed` (vivid for dark contrast) |
| `brand-purple-soft` | `#f4f0fa` | `#2a1840` |
| `brand-gold` | `#CBB677` | `#b8a168` (slightly desaturated) |
| `success` | `#16a34a` | `#22c55e` |
| `warning` | `#d97706` | `#f59e0b` |
| `danger` | `#dc2626` | `#ef4444` |

Brand-purple remains the active-tab indicator and primary-action color in both modes. Semantic colors are used for status pills only — never as base surfaces.

### Spacing

Scale: `4 / 8 / 12 / 16 / 24 / 32 / 48`. Tab content padding 24px. Card padding 16px. Section gap 24px.

### Components (Views/Design/)

| Primitive | Description |
|---|---|
| `Card` | `surface-elevated`, 1px `border-subtle`, 12px corner radius. Light mode: shadow `0 1px 2px rgba(0,0,0,0.06)`. Dark mode: no shadow (border carries the elevation) |
| `StatChip` | Small rounded-pill chip, used in the top bar for completion% and projected graduation |
| `StatusPill` | Filled rounded badge with semantic color (`success`, `warning`, `danger`, `info`) |
| `CourseChip` | Inline course representation. 3px left-border in category color, code in bold, title secondary, hover reveals drag handle and trash |
| `Button` styles | `.primary` (filled purple), `.secondary` (outline), `.tertiary` (text-only), `.destructive` (red ghost) |
| `EmptyState` | Centered card with title, body text, primary action button |
| `ProgressRail` | The progress bar (see below) |
| `SectionHeader` | Bold heading + optional helper text + optional trailing action |

### ProgressRail (the progress bar component)

- Track: 6px tall, fully rounded corners (3px radius), `border-subtle` background.
- Fill: `brand-purple` (or `warning` if the category is unverified), same rounding, subtle inner shadow (`rgba(0,0,0,0.06)` 1px inset) to give it depth without being heavy. No gradient, no stripes, no animation on idle.
- Layout per row:
  ```
  Category name                                                 8/24
  ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  ← 6px rail
  8 of 24 credits · Still need: CS 240, CS 261, CS 327, CS 345  ← helper line
  ```
- The "Still need" line lists remaining course codes (up to ~5) followed by `+ N more` if it overflows. Click/hover expands inline to the full list.
- For categories whose `courseOptions` are empty (Free Electives, partially-verified Gen Ed clusters), helper reads `"X credits to plan"` instead of listing courses.
- For 100%-complete categories, helper reads `"Complete ✓"` in `success` color.

### Motion

- Tab switch: 150ms crossfade on content.
- Sheet present/dismiss: 250ms slide from bottom with material backdrop.
- Course drag pickup: subtle scale to 1.03 + shadow elevation.
- No flashy or attention-grabbing animation. Motion reinforces structure, never decorates.

## 5. Screens

### 5.1 My Plan tab (landing / summary)

- **Hero card** — program title (28px bold), degree type pill (e.g. "B.S."), college and department line in `text-secondary`, verification badge (`Verified`, `Partial`, or `Unverified` status pill).
- **Two stat tiles** side by side:
  - **Completion** — large `42%` number, `ProgressRail` underneath, "X semesters remaining" subtitle. Tile background is a soft purple gradient (`brand-purple-soft` → `surface-elevated`) to make this the visual anchor of the screen.
  - **Projected graduation** — large `Fall 2029` text, "X semesters away" subtitle. Plain `surface-elevated` background.
- **Requirement category breakdown** — vertical list of `ProgressRail` rows (one per `RequirementCategory`). Each row clickable. Clicking a row switches to the Schedule tab, scrolls to the first semester that contains a contributing course, and applies a 2px `brand-purple` ring to every `CourseChip` belonging to that category (ring clears on next click or category change).
- **Footer action row** — "Edit setup" secondary button, "Generate alternative pathway" tertiary button.

### 5.2 Schedule tab (horizontal-scroll semester columns)

- **Sub-toolbar** — pathway picker (`Balanced / Major-First / Flexible` segmented control), regenerate button, total-credits-per-pathway readout.
- **Columns** — one `Card` per semester, 280px wide, 90vh tall. Header inside each card: term + year (e.g. "Fall 2026") in bold, "15 credits" in secondary, course-count chip on the right.
- **CourseChip rows** inside each column. Left border 3px in category color: `brand-purple` for major core, `brand-gold` for gen ed, `text-tertiary` for free electives, `danger` for chips with active warnings.
- **Drag and drop** — chip is draggable to other columns. Drop highlight uses `brand-purple-soft`.
- **Inline warning** — appears as a one-line strip directly below the offending chip, amber background, "Keep anyway" tertiary button at the end. Stays until resolved or overridden.
- **Column footer** — `+ Add course` tertiary button that opens an inline picker (search field + grouped course list).

### 5.3 Catalog tab (full program browser)

- **Left rail** (collapsible, 280px) — College → Department disclosure tree, with search field pinned at top. Selected program highlighted.
- **Right pane** — selected program detail: title hero, degree type pill, college/department, verification status, source note. Requirements rendered as expandable category sections; each requirement uses the same `ProgressRail` component, but in "view-only" mode (no completion fill, just the credit total and course list).
- Click any course code in a requirement to open the **Course Detail** sheet.

### 5.4 Progress tab (deep view)

- **Top hero** — large donut ring (180px diameter) showing overall completion, with segments colored by category. Center of the donut shows the % numerically.
- **Category card list** below the donut — each `RequirementCategory` gets its own `Card` containing: category name + verification badge, `ProgressRail`, helper line with remaining courses, and an inline list of contributing courses (those satisfied by transfer credit shown with a "transfer" pill, those scheduled shown with their semester).
- For categories with no parseable course options, the card shows the advisor note and a "View catalog source" link.

### 5.5 Course Detail (side sheet)

- Slides in from the right, ~480px wide, full window height.
- Hero: course code (28px bold), title (16px secondary), credits chip, semester availability pill.
- Sections (top-to-bottom): Description (from registrar, with loading and "unavailable" states), Semester availability with the "if you move this to off-semester, the warning stays visible" helper, Prerequisites (each prereq is a clickable chip that opens that course's detail in place), Difficulty + Professor list (Rate My Professor section keeps current "not enough data" empty state), Links (JMU registrar page, each professor's RMP page).
- Dismissed by Esc, clicking outside, or a Close button in the top-right.

### 5.6 Setup sheet

- 4 ordered steps with a top dots indicator (filled / outline / outline / outline):
  1. **Major** — search field + College → Department disclosure tree, single-select. Verification badge shown on each program row. Cannot proceed without a selection.
  2. **Optional minor / second major** — same picker style, multi-select. Can be skipped.
  3. **Transfer credit** — two sub-sections: AP exam (dropdown + score stepper + "Add" button, lists already-added AP credits below), Dual enrollment (course-name field + JMU course code field + credits stepper). Can be skipped.
  4. **Workload** — segmented control: Light / Standard / Heavy, with credit-range and brief description under each.
- Footer: `Back` (disabled on step 1) · `Skip` (steps 2 and 3 only) · `Next` (primary) or `Generate Plan` (primary, step 4 only).
- Closing the sheet without finishing returns the dashboard to its empty state.

## 6. State, errors, partials

| State | Behavior |
|---|---|
| **First launch, no plan** | Setup sheet auto-opens over an empty dashboard. Empty dashboard shows a centered `EmptyState`: "Let's build your plan" + primary button to reopen the sheet if the user dismissed it. |
| **Catalog initial refresh** | Non-blocking top-bar progress strip showing "Parsing X of N: program title". Tabs remain interactive; the Catalog tab can be browsed while parsing continues. |
| **Partial program data** | Verification badge on every reference to the program. Categories whose `courseOptions` are empty show "—" instead of "0%" with an amber tooltip explaining advisor verification is needed. Schedule generation still runs against what *is* parsed (per the scheduler-gate fix earlier this session). |
| **Network failure during refresh** | Persistent `StatusPill` reading "Using cached data" appears in the top bar's right cluster. Reverts when next refresh succeeds. |
| **Schedule with active warnings** | Top of Schedule tab gets a warning summary banner ("3 warnings"). Each warning row is also inline in the relevant column. |
| **Empty pathway list** | Schedule tab shows `EmptyState` with a "Generate pathways" primary action. |

## 7. Implementation approach

### File structure

```
Sources/JMUCoursePlanner/
├── App/
├── Models/
├── Services/
├── Stores/
├── Support/
│   ├── JMUStyle.swift              (deprecated; will be removed)
│   └── DesignTokens.swift          (NEW — color/spacing/type tokens)
└── Views/
    ├── ContentView.swift           (rewrite — tab host + top bar + sheet manager)
    ├── Design/                     (NEW — design primitives)
    │   ├── Card.swift
    │   ├── StatChip.swift
    │   ├── StatusPill.swift
    │   ├── CourseChip.swift
    │   ├── ProgressRail.swift
    │   ├── PrimaryButton.swift
    │   ├── EmptyState.swift
    │   └── SectionHeader.swift
    ├── TopBar.swift                (NEW)
    ├── Tabs/
    │   ├── MyPlanView.swift        (NEW)
    │   ├── ScheduleBoardView.swift (replaces ScheduleView.swift)
    │   ├── CatalogView.swift       (NEW)
    │   └── GraduationProgressView.swift  (NEW — named to avoid SwiftUI ProgressView collision)
    ├── Setup/
    │   ├── SetupSheet.swift        (replaces OnboardingView.swift)
    │   ├── SetupStepMajor.swift
    │   ├── SetupStepMinor.swift
    │   ├── SetupStepTransfer.swift
    │   └── SetupStepWorkload.swift
    └── CourseDetailSheet.swift     (replaces CourseDetailView.swift)
```

### `PlanStore` surface additions

The existing API stays. New additions to support new screens:

- `@Published var selectedTab: AppTab = .myPlan` — drives the tab host.
- `@Published var setupSheetPresented: Bool = false` — drives the modal.
- `@Published var catalogSelectedProgramID: String?` — independent of `plan.programID` so the Catalog tab can be used to browse without changing the active plan.
- `@Published var scheduleCategoryFilter: String?` — set when the user clicks a category bar in My Plan to deep-link into Schedule.

### Removed / changed files

- `JMUStyle.swift` is deleted after `DesignTokens.swift` migration is complete.
- `OnboardingView.swift`, `ScheduleView.swift`, `ProgressPanel.swift`, `ProgramPickerView.swift`, `CourseDetailView.swift`, `TransferCreditView.swift` are replaced by the new structure. Their logic moves into the new files.

### Light/dark adaptation

Every color reference goes through `DesignTokens`. Each token is a SwiftUI `Color` initialized with `dark:` and `light:` variants using the macOS `NSColor` dynamic constructor. No view checks `colorScheme` directly.

## 8. Testing

- **No new unit tests for views.** SwiftUI macOS testing tooling is too weak to justify.
- **Existing `PlannerCore` tests stay** — 12 tests already cover scheduler, parser, conflicts, progress.
- **Build verification** — `Build App.command` continues to be the smoke test. The build script must succeed after the overhaul and produce a launchable `.app`.
- **Manual checklist** in the limitations doc: open each tab, run setup, drag a course, override a warning, open course detail, switch light/dark, resize window, hit Reset App Data, hit Start Over.

## 9. Acceptance criteria

The overhaul is done when all of the following are true:

1. The four tabs (My Plan, Schedule, Catalog, Progress) all render with real data when a plan exists.
2. The Setup sheet replaces the old onboarding flow and runs the same store mutations.
3. Every progress bar in the app uses `ProgressRail` and lists remaining required courses (or credit count for unspecified-course categories) directly beneath the bar.
4. The schedule tab supports drag-and-drop between semesters with inline warnings.
5. `JMUStyle.swift` is removed; all color references go through `DesignTokens`.
6. The build succeeds via `Build App.command`.
7. All 12 existing tests still pass.
8. The app auto-adapts to light/dark mode without manual toggling.
9. `LIMITATIONS.md` is updated to reflect the new UI structure.

## 10. Non-goals / explicit deferrals

- No new tutorial, walkthrough, or help system.
- No custom illustrations or imagery beyond the JMU wordmark.
- No accessibility audit beyond keeping system defaults functional.
- No changes to the data layer (`PlannerCore`, `CatalogRepository`, parsers).
- No new export formats beyond PDF and .ics.
- No animation library or third-party dependencies.
