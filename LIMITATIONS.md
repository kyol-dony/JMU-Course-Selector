# Known Limitations

## User interface

- The 2026-05-19 UI overhaul replaces the previous sidebar layout with a tabbed dashboard (My Plan, Schedule, Catalog, Progress) and a modal setup sheet. Old views (`OnboardingView`, `ScheduleView`, `ProgressPanel`, `ProgramPickerView`, `CourseDetailView`, `TransferCreditView`) are removed; their logic lives in the new structure.
- Color, typography, and spacing now flow through `DesignTokens.swift`. Light/dark mode auto-follows macOS appearance.
- The design spec calls for the Inter typeface; the app ships with the system SF Pro fallback rather than bundling a font file, so headlines render in SF Pro at the spec's weights. Substituting Inter later only requires bundling the font and updating the `Typography` enum.
- The Progress tab renders an overall completion donut and per-category `ProgressRail` cards. Each progress rail lists up to 5 remaining required courses beneath the bar; categories without parsed course options show a credit-only helper line.
- Drag-and-drop between semesters is preserved. Inline warning strips appear under prerequisite and known semester-conflict course chips with a "Keep" override link. Unknown semester availability warnings are hidden on the schedule board to keep the plan scannable.

## Manual smoke checklist

After each rebuild, verify by hand:

- Setup sheet opens on first launch.
- Picking a major, completing setup, and clicking Generate Plan lands in My Plan with real numbers.
- Each tab renders without an error alert.
- Dragging a course between semesters updates credit totals and re-evaluates warnings.
- Clicking a category bar in My Plan switches to Schedule and highlights matching chips.
- Course detail sheet opens from any course chip, shows the JMU registrar link, and closes via Esc or the X button.
- Toggling macOS appearance in System Settings updates colors live.
- "Reset App Data" in the menu wipes the cache and reloads.

## Catalog requirements

- The app lists JMU undergraduate majors and minors from the official 2025-2026 Undergraduate Catalog table of contents (200+ programs).
- On first launch, the app automatically fetches official `catalog.jmu.edu` HTML for every listed program when fewer than 10% of majors have schedulable data cached. A progress message is shown while this runs (one program per ~150ms, so roughly 30-60 seconds end-to-end). The **Refresh Requirements** button repeats the fetch on demand.
- Programs with fixed course lists become schedulable after the refresh completes. Broad prose requirements ("choose 9 credits of upper-division electives", "see advisor"), unrestricted electives, and advisor-selected choices are flagged partial and surface a per-program note rather than being silently inferred.
- General Education is now seeded from the live JMU Gen Ed program page (`poid=26976`). All 14 clusters are pulled with their full course buckets and merged into every undergraduate major's requirement set. Cluster credit allocations (C1CT, C1HC, C1W, C2HQC, C2VPA, C2L, C3QR, C3PP, C3NS, C3L, C4AE, C4GE, C5SD, C5W) are hand-coded from the JMU 2025-2026 catalog narrative because they don't appear in the cluster headings.
- Concentrations/tracks are supported in the data model and now wired through `SeedCatalog` to `Program`. The catalog HTML refresh does not yet split concentration sections into separate selectable tracks — they appear as additional requirement categories on the parent major.

## Course availability

- The official catalog PDF used here did not provide reliable Fall/Spring offering patterns for each course.
- Seeded courses therefore show `availability unknown`.
- The generator does not fabricate availability. The Schedule tab hides unknown-availability warnings to reduce clutter, but still surfaces warnings for known Fall/Spring conflicts.

## Transfer credit

- AP mapping is seeded only for AP rules explicitly entered from the catalog excerpt used during implementation.
- Dual enrollment entries are student-entered placeholders until an official JMU transfer equivalency is verified.

## Course details and Rate My Professor

- Course detail panels show official JMU descriptions when the catalog HTML refresh has cached the course's registrar detail page.
- Courses without a discovered JMU registrar course URL show an unavailable description state and should be verified through the registrar before registration.
- Rate My Professor data is not scraped or fabricated. The app links to the James Madison University professor search page so students can manually look up instructors.
- Professor lists and automatic RMP ratings are not populated without a future curated local dataset.

## Export

- PDF export is a clean text summary rather than a designed print layout.
- Calendar export creates all-day placeholder course blocks for each semester. It does not include actual meeting days/times because those depend on live registration sections.

## Packaging

- `dist/JMU Course Planner.app` is a local unsigned development build. It runs on this Mac, but it is not notarized for public distribution.
- Rebuilding and running tests require Apple’s Swift/Xcode command line tools.
