# Merge "My Plan" and "Progress" Tabs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse `AppTab.myPlan` and `AppTab.progress` into a single `My Plan` tab that absorbs the donut, Next-term shortcut, and Contributing-courses sub-list, without losing tap-to-schedule highlighting or hover affordances.

**Architecture:** Single SwiftUI view (`MyPlanView`) renders the merged surface as a vertical scroll: program identity cards → two-tile stats row (donut + projected grad + Next-term pill) → category breakdown cards with always-expanded contributing courses. `GraduationProgressView.swift` is deleted; its donut, contributing-courses logic, and Next-term button move into MyPlanView. `AppTab.progress` and its switch case in `ContentView` are removed.

**Tech Stack:** Swift 5.10+, SwiftUI on macOS 14+, existing PlannerCore types (`GraduationProgress`, `CategoryProgress`, `PathwayPlaceholder`, `ScheduleGenerator.openElectiveCategoryID`), existing design tokens.

---

## File Map

| Path | Action | Responsibility after change |
|---|---|---|
| `Sources/JMUCoursePlanner/Views/AppTab.swift` | edit | Tab enum without `.progress` case |
| `Sources/JMUCoursePlanner/Views/ContentView.swift` | edit | Tab switch without `.progress` arm |
| `Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift` | edit | Renders merged surface; owns donut + contributing-courses + Next-term button |
| `Sources/JMUCoursePlanner/Views/Tabs/GraduationProgressView.swift` | delete | (removed) |

`PlanStore.swift` needs no change — `selectedTab` is `@Published` runtime state, not persisted.

---

## Task 1: Remove `AppTab.progress` case

**Files:**
- Modify: `Sources/JMUCoursePlanner/Views/AppTab.swift`

- [ ] **Step 1: Update `AppTab.swift`**

Replace the full file contents with:

```swift
import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case myPlan
    case schedule
    case catalog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myPlan: "My Plan"
        case .schedule: "Schedule"
        case .catalog: "Catalog"
        }
    }

    var systemImage: String {
        switch self {
        case .myPlan: "graduationcap.fill"
        case .schedule: "calendar"
        case .catalog: "books.vertical.fill"
        }
    }
}
```

- [ ] **Step 2: Verify the build fails on `ContentView.swift`**

Run: `swift build`
Expected: error in `ContentView.swift` referencing `case .progress:` (it still mentions a value that no longer exists in the enum).

This failure is the trigger for Task 2. Don't commit yet — Task 2 finishes the same logical change.

---

## Task 2: Remove the `.progress` switch arm in `ContentView`

**Files:**
- Modify: `Sources/JMUCoursePlanner/Views/ContentView.swift:52-61` (current switch block)

- [ ] **Step 1: Read the current switch block**

Run: `grep -n "switch store.selectedTab" Sources/JMUCoursePlanner/Views/ContentView.swift`
Then `sed -n '50,65p' Sources/JMUCoursePlanner/Views/ContentView.swift` to read the block.

- [ ] **Step 2: Edit `ContentView.swift`**

Remove the `.progress` arm. The switch should end up with three cases: `.myPlan`, `.schedule`, `.catalog`. Example shape (use the existing values for each case — don't replace argument lists):

```swift
switch store.selectedTab {
case .myPlan:
    MyPlanView(catalog: catalog)
case .schedule:
    ScheduleBoardView(catalog: catalog)
case .catalog:
    CatalogView(catalog: catalog)
}
```

If your local file has different wrapping or arguments, preserve those — only delete the `case .progress: GraduationProgressView(catalog: catalog)` arm.

- [ ] **Step 3: Verify build now fails only on the GraduationProgressView reference (if any) and unused file**

Run: `swift build`
Expected: build succeeds (GraduationProgressView.swift compiles standalone; it's just no longer routed). If there are other unrelated errors, stop and investigate before continuing.

- [ ] **Step 4: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/AppTab.swift Sources/JMUCoursePlanner/Views/ContentView.swift
git commit -m "$(cat <<'EOF'
refactor: drop AppTab.progress case from tab nav

First step of merging the Progress tab into My Plan. The view file
GraduationProgressView.swift is still present and compiles, but no longer
routed; it will be removed once its logic is absorbed into MyPlanView.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Move `CourseContribution` struct + contributing-courses helpers into `MyPlanView`

**Files:**
- Modify: `Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift`

Goal: copy the helpers from GraduationProgressView into MyPlanView so the next task can wire them into category cards. After this task, MyPlanView contains unused helpers — that's fine. They go live in Task 5.

- [ ] **Step 1: Append the helpers at the bottom of `MyPlanView.swift`**

Add these inside the `MyPlanView` struct (above its closing brace, after `requirementLookup`):

```swift
@ViewBuilder
private func contributionList(rows: [CourseContribution]) -> some View {
    if !rows.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
            Text("Contributing courses")
                .font(DesignTokens.Typography.small)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .textCase(.uppercase)
            ForEach(rows) { row in
                HStack {
                    Text(row.code)
                        .font(DesignTokens.Typography.caption)
                        .monospacedDigit()
                    Spacer()
                    StatusPill(text: row.source, tone: row.isTransfer ? .info : .neutral)
                }
            }
        }
    }
}

/// Walk the pathway's `resolvedPlaceholders` map for entries whose key
/// matches an Open Elective slot.
private func openElectiveContributions() -> [CourseContribution] {
    guard let pathway = store.activePathway else { return [] }
    let openElectivePrefix = PathwayPlaceholder.id(
        categoryID: ScheduleGenerator.openElectiveCategoryID,
        optionIndex: 0
    ).split(separator: "::").dropLast().joined(separator: "::") + "::"
    let scheduled = Dictionary(
        pathway.semesters
            .sorted { $0.id < $1.id }
            .flatMap { semester in semester.courseIDs.map { ($0, semester.id.displayName) } },
        uniquingKeysWith: { first, _ in first }
    )
    return pathway.resolvedPlaceholders.compactMap { placeholderID, courseID in
        guard placeholderID.hasPrefix(openElectivePrefix) else { return nil }
        guard let course = catalog.coursesByID[courseID] else { return nil }
        let source = scheduled[courseID] ?? "Scheduled"
        return CourseContribution(code: course.code, source: source, isTransfer: false)
    }
    .sorted { $0.code < $1.code }
}

private func contributions(for requirement: RequirementCategory?) -> [CourseContribution] {
    guard let requirement else { return [] }
    let transferIDs = Set(store.plan.transferCredits.flatMap(\.courseIDs))
    let scheduled = Dictionary(
        (store.activePathway?.semesters ?? [])
            .sorted { $0.id < $1.id }
            .flatMap { semester in semester.courseIDs.map { ($0, semester.id.displayName) } },
        uniquingKeysWith: { first, _ in first }
    )
    return requirement.courseOptions.compactMap { option in
        if let transferID = option.first(where: transferIDs.contains),
           let course = catalog.coursesByID[transferID] {
            return CourseContribution(code: course.code, source: "Transfer", isTransfer: true)
        }
        if let scheduledID = option.first(where: { scheduled[$0] != nil }),
           let course = catalog.coursesByID[scheduledID],
           let semester = scheduled[scheduledID] {
            return CourseContribution(code: course.code, source: semester, isTransfer: false)
        }
        return nil
    }
}
```

- [ ] **Step 2: Add the `CourseContribution` struct at file scope**

At the bottom of `MyPlanView.swift`, after the existing `private struct RequirementProgressRow`, append:

```swift
private struct CourseContribution: Identifiable {
    var id: String { "\(code)-\(source)" }
    var code: String
    var source: String
    var isTransfer: Bool
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: build succeeds. New helpers are unused; Swift will warn but not fail.

- [ ] **Step 4: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift
git commit -m "$(cat <<'EOF'
refactor: copy contributing-courses helpers into MyPlanView

Moves CourseContribution, contributionList, openElectiveContributions, and
contributions(for:) from GraduationProgressView into MyPlanView so the
category cards can use them in the next step. Helpers are unused after this
commit — wired up in the follow-up.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Replace `completionTile` with a donut variant + add Next-term pill to `graduationTile`

**Files:**
- Modify: `Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift` (current `completionTile`, `graduationTile`)

- [ ] **Step 1: Replace `completionTile(progress:)` body with a donut layout**

Find the function `private func completionTile(progress: GraduationProgress) -> some View {` in `MyPlanView.swift`. Replace its entire body with:

```swift
private func completionTile(progress: GraduationProgress) -> some View {
    let pct = Int(progress.overallFraction * 100)
    let fraction = min(max(progress.overallFraction, 0), 1)
    let remaining = max(progress.overallRequiredCredits - progress.overallCompletedCredits, 0)
    return Card {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.m) {
            ZStack {
                Circle()
                    .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(
                        DesignTokens.Colors.brandGold,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(pct)%")
                        .font(DesignTokens.Typography.title)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Colors.brandPurple)
                    Text("complete")
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            .frame(width: 90, height: 90)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Completion")
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                Text("\(progress.overallCompletedCredits) of \(progress.overallRequiredCredits) credits")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .monospacedDigit()
                if remaining > 0 {
                    Text("\(remaining) credits to go")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
    }
    .frame(maxWidth: .infinity)
}
```

- [ ] **Step 2: Replace `graduationTile(progress:)` body with the Next-term pill version**

Find `private func graduationTile(progress: GraduationProgress) -> some View {`. Replace its body with:

```swift
private func graduationTile(progress: GraduationProgress) -> some View {
    let upcoming = nextUpcomingSemester()
    return Card {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Text("Projected graduation")
                .font(DesignTokens.Typography.small)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .textCase(.uppercase)
            Text(progress.projectedGraduation?.displayName ?? "Not yet")
                .font(DesignTokens.Typography.display)
                .monospacedDigit()
                .foregroundStyle(
                    progress.projectedGraduation == nil
                        ? DesignTokens.Colors.textTertiary
                        : DesignTokens.Colors.textPrimary
                )
            Text(semestersAwayText(progress: progress))
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .monospacedDigit()
            nextTermButton(upcoming)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity)
}
```

- [ ] **Step 3: Add `nextUpcomingSemester()` and `nextTermButton(_:)` helpers**

Append the following inside the `MyPlanView` struct, near the other private helpers:

```swift
private func nextUpcomingSemester() -> SemesterPlan? {
    guard let semesters = store.activePathway?.semesters else { return nil }
    let month = Calendar.current.component(.month, from: Date())
    let year = Calendar.current.component(.year, from: Date())
    let currentTerm: SemesterTerm = month >= 7 ? .fall : .spring
    let nowID = SemesterIdentity(year: year, term: currentTerm)
    return semesters.sorted { $0.id < $1.id }.first { $0.id >= nowID }
}

@ViewBuilder
private func nextTermButton(_ semester: SemesterPlan?) -> some View {
    if let semester {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                store.selectedTab = .schedule
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next term")
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(DesignTokens.Colors.brandGold.opacity(0.75))
                        .textCase(.uppercase)
                    Text("\(semester.id.displayName) · \(semester.courseIDs.count) course\(semester.courseIDs.count == 1 ? "" : "s")")
                        .font(DesignTokens.Typography.bodyEmphasized)
                        .foregroundStyle(DesignTokens.Colors.brandGold)
                        .monospacedDigit()
                }
                Spacer(minLength: DesignTokens.Spacing.s)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.brandGold)
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, DesignTokens.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                    .fill(DesignTokens.Colors.brandPurpleSoft)
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 5: Smoke test in app (manual)**

Open the app. Confirm:
1. My Plan tab shows the donut tile on the left and the projected-grad tile with a Next-term pill on the right.
2. Tapping the Next-term pill switches to the Schedule tab.

If the donut looks wrong (clipped, no fill animation), re-check the `ZStack` ordering against the snippet above.

- [ ] **Step 6: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift
git commit -m "$(cat <<'EOF'
feat(myplan): donut completion tile + Next-term pill in grad tile

Absorbs the Progress tab's donut chart shape and Next-term shortcut into
My Plan's existing twin-tile stats row. Completion tile renders the donut
with credit headline; graduation tile adds a tappable pill that switches
to the Schedule tab.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Upgrade `categoryBreakdown` to the Progress-style card with Contributing courses

**Files:**
- Modify: `Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift` (`categoryBreakdown`, `RequirementProgressRow`)

The current `RequirementProgressRow` only wraps a `ProgressRail`. The merged design needs a card with: name + status pill + credits headline, the rail, "Still need" caption, and the Contributing courses sub-list. The whole card stays tap-to-schedule and keeps hover background.

- [ ] **Step 1: Replace the `categoryBreakdown` view**

Find `@ViewBuilder private var categoryBreakdown: some View {`. Replace its body with:

```swift
@ViewBuilder
private var categoryBreakdown: some View {
    if let progress = store.progress, let program = store.activeProgram {
        let requirementProgram = store.effectiveActiveProgram ?? program
        let lookup = requirementLookup(primary: requirementProgram)
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                SectionHeader("Requirement progress")
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                    ForEach(progress.categories) { category in
                        let requirement = lookup[category.id]
                        let isOpenElective = category.id == ScheduleGenerator.openElectiveCategoryID
                        let rows = isOpenElective ? openElectiveContributions() : contributions(for: requirement)
                        RequirementProgressRow(
                            category: category,
                            requirement: requirement,
                            remainingCourseCodes: remainingCodes(for: requirement),
                            contributions: rows,
                            isOpenElective: isOpenElective,
                            contributionList: { rows in AnyView(contributionList(rows: rows)) },
                            onTap: {
                                store.scheduleCategoryFilter = category.id
                                withAnimation(.easeOut(duration: 0.15)) {
                                    store.selectedTab = .schedule
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Replace the `RequirementProgressRow` struct at the bottom of the file**

Replace the existing `private struct RequirementProgressRow: View { … }` with:

```swift
private struct RequirementProgressRow: View {
    var category: CategoryProgress
    var requirement: RequirementCategory?
    var remainingCourseCodes: [String]
    var contributions: [CourseContribution]
    var isOpenElective: Bool
    var contributionList: ([CourseContribution]) -> AnyView
    var onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.s) {
                    Text(category.name)
                        .font(DesignTokens.Typography.bodyEmphasized)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    if category.remainingCredits == 0 {
                        StatusPill(text: "Complete", tone: .success, systemImage: "checkmark.circle.fill")
                    } else if category.verificationStatus != .verified {
                        StatusPill(text: "Partial", tone: .warning)
                    }
                    Spacer(minLength: DesignTokens.Spacing.s)
                    Text("\(category.completedCredits)/\(category.requiredCredits)")
                        .font(DesignTokens.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                ProgressRail(
                    category: category,
                    hasCourseOptions: isOpenElective || !(requirement?.courseOptions.isEmpty ?? true),
                    remainingCourseCodes: remainingCourseCodes,
                    showHeader: false
                )
                if let note = requirement?.note, requirement?.courseOptions.isEmpty == true, !isOpenElective {
                    Text(note)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                contributionList(contributions)
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.vertical, DesignTokens.Spacing.s)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                    .fill(isHovering ? DesignTokens.Colors.brandPurpleSoft : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 4: Smoke test in app (manual)**

Open the app. Confirm:
1. Each category card shows: name + status pill + credits, gold rail, remaining text, and (when at least one option is scheduled or transferred) a "Contributing courses" sub-list.
2. Hover a card → soft purple background fades in.
3. Tap a card → Schedule tab opens with the chosen category's chips highlighted (recently fixed `isHighlighted` logic; verify primary, minor-prefixed, and open-elective ids all light up).
4. Open Electives category lists every resolved placeholder's chosen course code + the semester it landed in.

If the highlight doesn't fire, regenerate pathways first (existing limitation noted in earlier work).

- [ ] **Step 5: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift
git commit -m "$(cat <<'EOF'
feat(myplan): rich category cards with contributing courses

Each category card in My Plan now shows the status pill, credits headline,
remaining text, and a Contributing-courses sub-list. Open Electives pull
their contributors from pathway.resolvedPlaceholders. Hover background and
tap-to-schedule with highlight are preserved.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Delete `GraduationProgressView.swift`

**Files:**
- Delete: `Sources/JMUCoursePlanner/Views/Tabs/GraduationProgressView.swift`

- [ ] **Step 1: Confirm no references remain**

Run: `grep -rn "GraduationProgressView" Sources Tests`
Expected: only the file's own `struct GraduationProgressView: View {` line. Anything else means a stale call site — fix that first.

- [ ] **Step 2: Delete the file**

Run: `git rm Sources/JMUCoursePlanner/Views/Tabs/GraduationProgressView.swift`

- [ ] **Step 3: Build + tests**

Run:
```
swift build
swift test
```
Expected: build succeeds, all tests pass (no test touches this view).

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
refactor: delete GraduationProgressView

All functionality migrated into MyPlanView in the previous commits. No
remaining references, no test changes required.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

### Spec coverage

| Spec section | Task |
|---|---|
| Drop `AppTab.progress` | Task 1 |
| Drop `ContentView` switch arm | Task 2 |
| Hero cards unchanged | already in MyPlanView |
| Donut completion tile | Task 4 |
| Graduation tile + Next-term pill | Task 4 |
| Per-category card with status, rail, remaining, contributing courses | Task 5 |
| Tap-to-schedule + hover preserved | Task 5 |
| Open Electives contributing list via `resolvedPlaceholders` | Tasks 3 + 5 |
| Footer actions retained | (unchanged — present in MyPlanView already) |
| Delete `GraduationProgressView.swift` | Task 6 |
| `selectedTab` persistence fallback | not needed — verified `@Published` runtime-only |

### Placeholder scan

No "TBD", no "implement later", every code step shows full source. Manual smoke steps describe specific verification, not vague checks.

### Type consistency

- `CourseContribution` defined once in Task 3, used in Task 5 with the same shape.
- `RequirementProgressRow` redefined in Task 5 to take the additional `contributions`, `isOpenElective`, and `contributionList` parameters; the call site in `categoryBreakdown` (Task 5) passes them in.
- `nextTermButton(_:)` defined in Task 4, called only in Task 4's `graduationTile`.
- `openElectiveContributions()` and `contributions(for:)` defined in Task 3, called in Task 5.
- `ScheduleGenerator.openElectiveCategoryID` referenced in Task 5; already a `public static let` in PlannerCore (no new exports needed).

### Persisted plan ordering note

If a user has an autosaved plan from before this change, no migration is needed: `selectedTab` is not in `SavedStudentPlan`, so launches default to `.myPlan`.
