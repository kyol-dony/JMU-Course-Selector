# JMU Course Planner v1.0.0 release plan

**This document is the source of truth for what remains before release.** Check items off here as they land. If work is not listed here, it is not part of v1.0.0; add it here before starting it.

- Revision 2, 2026-11-10. Revision 1 was the readiness audit; this revision folds in the plan review (new findings B10–B16, packages 0, G, and H, a reordered release path, and open decisions).
- Items marked *(review)* came from the plan review and have not been verified against the code. Confirm each before acting on it.

## 1. Release decision and scope

**Current verdict: no-go for public v1.0.0.** Builds succeed, but generated plans can omit academic obligations, understate required credits, and misrepresent completion.

Release contract:

- Public release for JMU students.
- Catalog year **2026–2027 only**. The app must ask which catalog year the student follows and warn clearly when it is not 2026–2027 (see B10).
- Every offered major, minor, concentration, and option is modeled. Each carries a visible **review status**: *reviewed*, *modeled, not yet reviewed*, or *unsupported*. Only reviewed programs may present a pathway as complete. This replaces the revision 1 contract ("all programs fully modeled" as a single all-or-nothing gate); decided 2026-11-10 (D1).
- Advisor decisions are represented as explicit unresolved approval tasks.
- Apple Silicon and Intel support; macOS 14 minimum.
- No paid Apple Developer Program membership (see open decision D2).
- The app is unofficial. It says so in the app, in exports, and in the documentation (see B13).
- Private beta precedes public release. Beta cannot waive public-release correctness gates.

Audit baseline (from revision 1):

| Check | Result |
|---|---|
| Standard automated suite | **655 tests across 88 suites passed, with 2 known issues** |
| Opt-in whole-catalog suite | **4 tests passed**, including generation for 89 majors |
| Local catalog inventory | **89 majors, 111 minors, 238 concentrations** |
| Optimized builds | ARM64 and x86_64 succeeded; binaries declare macOS 14 minimum |
| Existing app bundle | ARM64 only; ad hoc executable signature, no sealed bundle resources, no version metadata |
| GitHub | No open issues or PRs returned |
| Integration scope | Local refs show 129 commits beyond `origin/main`; checkout 19 commits beyond tracked feature-branch ref |

Testing does **not** establish release readiness: the catalog audit lacks minimum-credit assertions and independent requirement validation. Native visual behavior, downloaded-app installation, and runtime compatibility on other Macs remain unverified.

## 2. Must-fix findings

### From the audit

| ID | Finding and evidence | Required outcome |
|---|---|---|
| **B1 — Incorrect requirement structure** | Current ISAT minor cache models "choose one sequence" as **one course from a flattened menu**. Probe generates 16 credits; the official requirement specifies a whole 6–7-credit sequence plus foundation and additional coursework. [Official ISAT requirements](https://catalog.jmu.edu/programs/integrated-science-technology-minor/) | Preserve whole sequences and their credit ranges; validate foundation lecture/lab groups and distinct-course requirements. |
| **B2 — Required work disappears** | CS's **9-credit upper-level elective requirement** has no course options and disappears from progress. Hospitality's **required 18-credit minor** also disappears. The current catalog explicitly requires a General Business or Entrepreneurship minor. [CS requirements](https://catalog.jmu.edu/programs/computer-science-bs/), [Hospitality requirements](https://catalog.jmu.edu/programs/hospitality-management-bs/) | Every enforceable requirement represented in planning and progress, including linked programs, restricted pools, and approval tasks. |
| **B3 — Bachelor's plans below graduation minimum** | The whole-catalog audit accepts Anthropology B.A. **71**, Anthropology B.S. **59**, Individualized Study B.A. **60**, and B.S. **51** credits. Production top-up contains a threshold intended to keep small test fixtures convenient. [Credit-gap logic](Sources/PlannerCore/PlannerCore.swift:2014) | Validated program minimum enforced independently of fixture size; incomplete models cannot produce apparently complete pathways. |
| **B4 — False verification and completion claims** | A new CS plan reports **37 completed credits with zero earned credits**. Future scheduled courses count as completed. The "Verified" badge uses `requirementDataComplete`, which means some schedulable courses exist, even though cached program status remains partial. [Progress calculation](Sources/PlannerCore/PlannerCore.swift:2914), [Verification badge](Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift:73) | Separate earned, in-progress, planned, and unresolved work. Verification must reflect actual review evidence. |
| **B5 — Unsafe catalog availability and refresh** | Bundled seed contains 164 program shells, 49 courses, and only **2 majors marked schedulable**. During refresh, Gen Ed is appended before schedulability is determined; failed major pages can become "complete" using Gen Ed alone. Gen Ed retrieval failures are swallowed; the refreshed cache replaces the previous catalog. [Refresh pipeline](Sources/JMUCoursePlanner/Services/CatalogRepository.swift:59) | Complete reviewed offline baseline; staged refresh with validation, retained working data, and explicit degradation reporting. |
| **B6 — Save/resume and recovery defects** | Explicit Save and autosave share a plan filename. Save writes a named plan; startup restores only records named "Autosave." No saved-plan picker appears in views. Autosave write errors and unreadable saved files are silently discarded. Reset deletes all app data immediately. [Startup restoration](Sources/JMUCoursePlanner/Stores/PlanStore.swift:664), [Persistence](Sources/JMUCoursePlanner/Stores/PlanStore.swift:1674) | Reliable Save → Quit → Relaunch; accessible saved plans; visible failures; recoverable corruption; confirmation before destructive reset. |
| **B7 — Export misrepresents unresolved plans** | PDF looks up placeholder IDs as courses, yielding internal IDs and **0-credit rows** despite nonzero placeholder estimates. Calendar uses the same raw-ID fallback and fixed illustrative dates. [Export implementation](Sources/JMUCoursePlanner/Services/ExportService.swift:61) | Human-readable unresolved requirements, accurate credit totals, clear planning assumptions, and valid calendar output. |
| **B8 — Academic-policy coverage incomplete** | The requirement model lacks general representation for program GPA, course minimum grades, required-minor relationships, and program-specific sharing restrictions. The CS catalog includes minimum-grade and major-GPA rules. Bundled AP rules explicitly retain **2025–2026** source labels pending re-verification. | Model each applicable 2026–2027 policy; evaluate known facts and expose unavailable evidence as unresolved. |
| **B9 — UX and distribution gates unmet** | Minimum window 1180×760 risks small-display usability. Light-mode gold text measures roughly **2:1** against white; success/warning text also falls below the stated normal-text AA target. The build helper produces a development app without release versioning or distribution packaging. The installation guide's right-click instructions are insufficient for current macOS behavior. | Accessible essential flows, completed visual matrix, versioned universal artifact, and verified installation instructions. |

### From the plan review

| ID | Finding | Required outcome |
|---|---|---|
| **B10 — Catalog-year mismatch** *(review)* | Students follow the catalog of their entry year. A 2026–2027-only app is correct mainly for students who entered in fall 2026, yet the beta recruits continuing and transfer students, most of whom follow older catalogs. | Setup asks which catalog year the student follows. Any other year gets a clear warning that requirements may differ, repeated on the plan and in exports. |
| **B11 — No path to correct catalog data after launch** *(review)* | Automatic updates are deferred, but catalog errors will be found after release. Without a data channel, every correction needs a new download and a repeat of the Gatekeeper steps. | Corrected catalog snapshots can reach installed apps without a new app build, through the staged refresh in package D. The app can tell the user a newer version exists. |
| **B12 — No error-reporting channel** *(review)* | No telemetry and no crash reporting. Correctness depends on catalog data, and there is no way for a student to report a wrong requirement. | In-app "Report a catalog problem" that prefills program, catalog revision, and app version, and sends nothing without the user's action. |
| **B13 — Branding and legal exposure** *(review)* | The app name uses "JMU" and the interface uses JMU's colors. Bundled catalog content is scraped from JMU's site. No statement that the app is unofficial. | Unofficial-tool disclaimer in the app, exports, and README. A decision on the name and on bundling catalog content (see D3). |
| **B14 — Transcript import has no automated gate** *(review)* | Transcript review appears only in the manual visual matrix. A wrong import silently corrupts earned credit and everything computed from it. | Fixture-based transcript parser tests are part of the mandatory suite. |
| **B15 — Term availability not modeled as a requirement** *(review)* | Fall-only and spring-only offerings are mentioned once as "availability uncertainty." No data source or policy is stated. | A stated policy: either model term availability from a named source, or mark every placement as unconfirmed and say so in the plan and exports. |
| **B16 — No performance budget** *(review)* | No limit on generation time or launch time, and Intel is the slower target. | Stated budgets for cold launch and plan generation, measured on both architectures. |

**Historical findings require careful classification.** Both accepted known issues reproduce against older Acalog fixtures: ISAT accumulates 69 credits; Applied Physics accumulates 188. The newer cached Applied Physics structure has improved. Historical failures alone do not establish a current-format Physics defect; fixtures need catalog-year metadata and explicit support status.

**Coverage diagnostic:** 95 cached programs contain positive-credit categories without course options. Some are summary headers; others are real missing obligations. Classify each before calling it fixed or defective.

## 3. Work packages

Packages run in the order given in section 5, not in letter order.

### 0. Gates and quick wins — do first

Small, isolated changes. The test changes come first because they turn B1–B3 into failing tests that the later packages must make pass.

- [ ] Push the current branch to the remote. 129 local commits beyond `origin/main` have no backup.
- [x] Confirm macOS CI exists; if not, add a GitHub Actions workflow that runs the standard suite on every push. *(review)*
- [x] Tests: caught generation errors fail the test. A missing audit dataset fails the release check instead of skipping.
- [x] Tests: whole-catalog suite asserts the degree minimum (120 credits for bachelor's programs unless the reviewed manifest says otherwise).
- [x] B3: remove the fixture threshold from production credit-gap logic; fixtures declare their own minimum.
- [x] B4: stop driving the "Verified" badge from `requirementDataComplete`; label the graduation date "Projected."
- [x] B5: stop swallowing Gen Ed retrieval failures; determine schedulability before appending Gen Ed; write the cache atomically.
- [x] B6: confirmation before Reset App Data; restore the active workspace regardless of its display name; surface autosave write errors.
- [x] B7: PDF and calendar resolve placeholder IDs to readable names and estimated credits.
- [x] B9: correct the gold, success, and warning text colors; add version and build numbers to the bundle; rewrite the installation steps for the Privacy & Security → Open Anyway flow.
- [x] B13: add the unofficial-tool disclaimer to the app, exports, and README.

**Acceptance:** the suite fails on the four sub-120 programs until B3 is fixed, then passes. Each item above has a test or a recorded manual check.

### A. Establish authoritative catalog truth — addresses B1, B2, B8, B10

- [ ] Inventory every program, concentration, and option from the current official index. Record canonical ID, catalog year, source URL, retrieval date, content hash, and **review status**.
- [ ] Capture current program pages, course descriptions, Gen Ed policies, degree policies, AP chart, and degree-eligible course lists as reproducible fixtures.
- [ ] Build the expectation manifest: required courses, alternatives, credit ranges, level restrictions, sharing rules, linked minors, and non-course obligations.
- [ ] Name the reviewer for the manifest and estimate review time per program. Review proceeds in order of enrollment: the highest-enrollment majors first (target about 15 for beta), then the rest. *(review)*
- [ ] Classify parsed rows as **enforceable requirement**, **summary**, **recommendation**, or **reference**. Never discard enforceable work because its course list is empty. Classify all 95 programs from the coverage diagnostic.
- [ ] Use the existing option/part model for complete ISAT sequences. Add explicit restricted-credit predicates and required-program relationships where the existing model cannot express catalog policy.
- [ ] Represent advisor approval, auditions, admissions, and individualized curricula as pending tasks with source evidence and required credit budgets.
- [ ] Reverify all 57 bundled AP rules against the applicable official policy; retain threshold, award alternatives, earned hours, and provenance.
- [ ] Add catalog-year metadata and support status to historical fixtures; separate them from current-catalog tests.
- [ ] Ask one JMU academic advisor or registrar staff member to review a few programs. *(review)*

**Acceptance:** every offered branch has a requirement mapping and a review status. No unclassified enforceable prose remains in reviewed programs. Unknown approval decisions stay visible and unresolved.

### B. Correct generation and independent validation — addresses B1–B3, B8, B15

- [ ] Store the reviewed degree minimum separately from parser-extracted section subtotals.
- [ ] Allocate each scheduled course or placeholder to the requirement it serves. Count physical earned and planned hours once; apply explicit rules when coursework satisfies multiple requirements.
- [ ] Preserve whole-course groups, distinct selections, repeated enrollment, variable credits, and upper-level subminimums.
- [ ] A required minor becomes a mandatory selection during setup; include the selected minor's obligations and legal overlap.
- [ ] Add an independent validator that consumes the reviewed manifest and the generated pathway. It must not reuse the generator's selection algorithm as its oracle.
- [ ] Return structured validation results: satisfied obligations, unresolved choices and approvals, violated constraints, and incomplete source data.
- [ ] Prevent incomplete or unreviewed models from presenting graduation-ready output. Open Electives must never conceal missing major requirements.
- [ ] Decide and implement the term-availability policy from B15. *(review)*

**Acceptance:** all four sub-120 examples corrected; CS elective restrictions enforced; ISAT selects a complete sequence; Hospitality requires an eligible minor. Every generated item has a reason for inclusion.

### C. Make progress and verification truthful — addresses B4, B8, B10

- [ ] Extend the progress interface to separate **earned**, **in progress**, **planned**, and **unresolved** contributions.
- [ ] Primary completion percentage uses earned, eligible coursework only. Planned coverage gets a separate label.
- [ ] Include all enforceable obligations, including empty-menu credit requirements and non-course tasks.
- [ ] Replace the Boolean-driven "Verified" with the program's review status plus outstanding checks. Show the review date and a link to the source catalog page. Parser success cannot confer academic verification.
- [ ] Evaluate grade thresholds where grades exist. Unknown grades, GPA evidence, or approvals remain unresolved rather than implicitly passing.
- [ ] Surface unresolved conditions and availability uncertainty next to the projected graduation date.
- [ ] Persist the selected catalog year and catalog revision with each plan.
- [ ] Setup asks which catalog year the student follows and shows the B10 warning for any year other than 2026–2027. *(review)*

**Acceptance:** a new student with no earned credit shows 0 earned completion. Scheduling a future course changes planned coverage only. No requirement vanishes from the denominator. An unreviewed program never shows a "reviewed" or "complete" state.

### D. Ship stable catalog data and safe refresh — addresses B5, B11

- [ ] Bundle the complete catalog snapshot, including required supporting data and per-program review status.
- [ ] Load the bundled snapshot offline on first launch; network refresh becomes optional.
- [ ] Validate HTTP response and page identity, including bot-challenge, empty-page, and changed-markup detection.
- [ ] Stage a candidate refresh separately. Require complete program coverage, Gen Ed integrity, valid references, and semantic checks before promotion.
- [ ] Preserve the previous working snapshot and affected program data when refresh fails.
- [ ] Allow one refresh at a time; support cancellation and reject stale results.
- [ ] Catalog changes affecting saved plans require explicit review; retain the previous plan and catalog revision for recovery.
- [ ] Publish corrected snapshots as hashed files on the project's release host, and let the staged refresh pull them, so data fixes do not need a new app build. *(review)*
- [ ] Check the release host for a newer app version and tell the user; no automatic install. *(review)*

**Acceptance:** an offline fresh install supports reviewed programs. Failure of one major page, one Gen Ed page, or course enrichment cannot silently remove obligations. A corrected snapshot published after release reaches an installed app and passes the same validation as a refresh.

### E. Repair persistence and exports — addresses B6, B7

- [ ] Separate active-workspace autosave from named saved-plan files.
- [ ] Add a saved-plan list with Open, Rename, and Delete.
- [ ] Introduce a saved-plan schema version and backward migration. Preserve legacy files during migration.
- [ ] Report autosave failures on the main actor; retain the last valid copy. Quarantine unreadable files with a recovery notice.
- [ ] Prevent an in-flight refresh from restoring state deleted by Reset App Data.
- [ ] Build a shared export representation for concrete courses, repeated enrollments, placeholders, credits, warnings, and approvals.
- [ ] PDF includes catalog revision, review status, earned/planned distinction, unresolved requirements, the unofficial-tool disclaimer, and complete pagination.
- [ ] Calendar remains a semester planning export: human-readable entries, explicit illustrative dates, valid escaped text, stable event identifiers.

**Acceptance:** Save → Quit → Relaunch restores the exact plan; named saves remain reachable. Exported totals match the board; unresolved rows show correct names and estimated credits.

### F. Finish usability and release packaging — addresses B9, B16

- [ ] Adjust the responsive layout so essential controls fit a 1280×800 display with normal macOS chrome; scroll dense content instead of clipping.
- [ ] Preserve status distinctions through labels and icons as well as color.
- [ ] Honor Reduce Motion throughout essential interactions.
- [ ] Verify keyboard access and VoiceOver for setup, choice resolution, moving courses, warning review, save, and export.
- [ ] Add a dedicated release packaging command: optimized ARM64 and x86_64 binaries combined into a universal app; bundled data and license; stable identifier; version and build metadata; complete ad hoc bundle seal.
- [ ] Produce a ZIP and SHA-256 checksum. Keep debug symbols separately.
- [ ] Set and measure budgets for cold launch and plan generation on both architectures. *(review)*
- [ ] Replace outdated documentation: current navigation, transcript handling and privacy, supported catalog year, data locations, recovery, export limits, and installation.
- [ ] Record a short installation video or GIF showing the Open Anyway steps. Without Developer ID this is required, not optional. *(review)*

**Acceptance:** the downloaded artifact works on both architectures without development tools. Essential flows remain usable with keyboard and supported accessibility settings.

### G. Feedback, legal, and launch readiness — addresses B12, B13

*(All items from the plan review.)*

- [ ] In-app "Report a catalog problem": prefilled with program, catalog revision, and app version; opens a draft the user sends themselves.
- [ ] Privacy statement: what transcript data is read, that it stays on the Mac, and that the app sends no telemetry.
- [ ] Resolve D3: app name and use of JMU's name and colors; terms covering bundled catalog content.
- [ ] Landing page: screenshots, a one-minute demo, the installation video, the checksum, known limits, and how to report problems.
- [ ] Distribution list: where the release is announced (student communities, student organizations, department advisors).
- [ ] Write down the catalog rollover procedure for 2027–2028, since the single-year scope expires when the next catalog is published.

**Acceptance:** a student who finds a wrong requirement can report it in under a minute. Every public surface states that the app is unofficial.

### H. Launch features — not release blockers

*(All items from the plan review.)* These raise the value of launch but do not gate it. Build them only after packages 0 and A–C are done. H1 is cheap because unresolved tasks are already modeled; do it before beta.

- [ ] **H1 — Advisor meeting sheet.** One-page PDF listing unresolved approvals, open choices, and questions to bring to an advisor.
- [ ] **H2 — What-if comparison.** Add a minor or switch a major and see the change in credits and projected graduation.
- [ ] **H3 — Program trust badge.** Review status, review date, and source link on the plan and in setup. (Delivered by packages A and C; listed here because it is user-facing.)

## 4. Verification and release gates

### Automated correctness

- Run all programs and offered concentrations and options through **all three pathway strategies**.
- Cover zero credit, AP, transfer, continuing-student history, repeated courses, language placement, and partial regeneration.
- Exercise each minor independently and stacked with representative majors; exhaustively cover known overlap and restriction combinations, then pairwise coverage elsewhere.
- Assert reviewed degree minimums, exact obligation coverage, permitted sharing, distinct choices, valid references, and credit conservation.
- Replace the universal "≤140 credits" rule with program-specific expectations.
- Caught generation errors fail tests. A missing audit dataset fails the release check rather than skipping it.
- Supported-current-catalog defects cannot remain accepted known issues. Label historical fixtures separately.
- Add deterministic tests for partial refresh, failed writes, corruption, migration, export formatting, and cancellation.
- Transcript parser tests run against fixture transcripts covering first-year, continuing, and transfer records. *(review)*
- Launch and generation times stay inside the budgets from package F on both architectures. *(review)*
- Run mandatory checks in macOS CI against the merged release commit and packaged resources.

### Native visual and workflow matrix

| Area | Required scenarios |
|---|---|
| Setup | Fresh launch, catalog-year question and warning, search, long program names, required minor, concentrations, options, manual entry, transcript review |
| Board | Drag across offscreen semesters, cancel/Escape, invalid destination, lecture/lab pairing, unresolved prerequisites, undo/redo |
| Regeneration | Preserved prefix, cancellation, stale result, option switch, save/reopen |
| Presentation | Light/dark, 1280×800 and larger, Reduce Motion, increased contrast, keyboard, VoiceOver |
| Recovery | Offline, refresh failure, corrupt cache, unreadable plan, failed autosave |
| Export | Long multi-page plan, unresolved choices, repeated courses, punctuation, calendar import, advisor meeting sheet |
| Feedback | Report a catalog problem, newer-version notice, corrected snapshot applied |

Record screenshots and outcomes against the exact build. Fix functional obstruction, misleading state, unreadable text, and inaccessible essential actions before public release; cosmetic spacing refinements can wait.

### Installation and beta

- Test the actual browser-downloaded ZIP with quarantine intact.
- Cover both architectures, macOS 14 minimum, and current stable macOS; add intermediate-version smoke checks.
- Verify first open, Applications-folder installation, offline launch, restart, update, and rollback.
- Recruit five invited student testers covering first-year, continuing, and transfer workflows. Record which catalog year each tester follows; testers on older catalogs confirm the B10 warning is clear.
- Each tester installs using the written instructions and completes setup → generate → edit → save/reopen → export without developer intervention.

No GUI or clean-machine results from the audit should be recorded as passed.

## 5. Release path

1. **Package 0.** Push the branch, get CI running, tighten the tests, land the quick wins.
2. **Freeze candidate scope and baseline.** Review the branch's full integration delta; preserve the exact commit and catalog snapshot. Create evidence-backed blocker records.
3. **Package C.** Truthful progress and verification, so every later change is judged against honest numbers.
4. **Packages A and B for the first reviewed set** (about 15 highest-enrollment majors plus the minors they require). Independent validation passes for that set.
5. **Packages D, E, F, and G, plus H1.** Rerun checks after integration into `main`.
6. **Publish invited `1.0.0-beta.1`.** Reviewed set labeled as reviewed; everything else labeled as not yet reviewed.
7. **Run beta and installation gates** while widening package A review to the remaining programs. Resolve blockers, issue a release candidate, and retest changed behavior.
8. **Publish v1.0.0 from the exact tested commit.** Attach the universal ZIP, checksum, installation guide and video, release notes, known limits, and feedback instructions. Preserve the previous artifact for rollback.
9. **After release:** continue review of any remaining programs through published snapshots (package D); build H2.

No target dates are set. Choose a public-release date with JMU's registration calendar in mind, and note that the 2027–2028 catalog will supersede this scope.

**Free distribution constraint:** direct download remains practical, but ad hoc signing does not establish developer identity or replace notarization. Developer ID requires Apple Developer Program membership. [Apple distribution guidance](https://developer.apple.com/developer-id/)

Installation instructions should use Apple's per-app **Privacy & Security → Open Anyway** flow where available. They must not require disabling Gatekeeper or globally weakening security. Managed Macs may prevent exceptions; document that limitation. [Apple installation guidance](https://support.apple.com/en-us/102445)

## 6. Open decisions

| ID | Decision | Default in this plan |
|---|---|---|
| **D1** | Does public v1.0.0 require every program reviewed, or may unreviewed programs ship with a visible "not yet reviewed" status? | **Decided 2026-11-10:** unreviewed programs may ship, labeled, and can never present a complete pathway. |
| **D2** | Pay for the Apple Developer Program to sign and notarize? | No. The Open Anyway flow is expected to lose some installs and blocks managed Macs; the installation video is the mitigation. |
| **D3** | Keep "JMU" in the app name and JMU's colors in the interface? Is bundling scraped catalog content acceptable? | Undecided. Disclaimer ships regardless. |
| **D4** | Term availability (B15): model it from a named source, or label all placements as unconfirmed? | Undecided. |
| **D5** | Who reviews the expectation manifest, and is an advisor or registrar contact available? | Undecided. |

## 7. Deferred until after launch

Automatic updates, paid signing and notarization (unless D2 changes), App Store or TestFlight distribution, designed PDF layouts, bundled custom font, professor datasets, RMP integration, live registration-section scheduling, older catalog years, and cosmetic refinements.

## 8. Public-release exit criterion

- Every offered program is modeled and carries a review status; every reviewed program passes independent validation; no unreviewed program presents a complete pathway.
- Every unresolved human decision is visible.
- Students on other catalog years are warned.
- Saved work survives restart; exports remain truthful.
- Both Mac architectures pass downloaded-artifact testing.
- A corrected catalog snapshot can reach installed apps, and students can report catalog problems from inside the app.
- The app states that it is unofficial on every public surface.
- No unresolved blocker remains.
