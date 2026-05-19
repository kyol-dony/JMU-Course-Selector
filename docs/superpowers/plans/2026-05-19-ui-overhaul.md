# JMU Course Planner — UI Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current sidebar+pinned-panel SwiftUI UI with a from-scratch tabbed dashboard using a real design-token layer, Modern SaaS visual language, horizontal-scroll schedule columns, modal setup sheet, and a `ProgressRail` component that lists remaining required courses beneath each bar.

**Architecture:** Pure UI refactor. No changes to `PlannerCore`. New `Support/DesignTokens.swift` carries semantic color/spacing/type tokens that auto-adapt to system light/dark. New `Views/Design/` folder contains primitives consumed by 4 tabbed screens, a setup sheet, a top bar, and a side sheet for course detail. `ContentView` becomes the tab host + top bar + sheet manager. Old onboarding/schedule/progress views are deleted in the cutover task.

**Tech Stack:** Swift 6, SwiftUI for macOS 14+, no third-party dependencies, no bundled fonts (system SF Pro substitutes for Inter per the spec's "Inter with SF Pro fallback" allowance).

**Per spec §8: no new view-layer unit tests.** Each task's verification is `swift build` succeeding. The existing 12 `PlannerCore` tests stay untouched and must still pass at the cutover task.

**Reference spec:** `docs/superpowers/specs/2026-05-19-ui-overhaul-design.md`

---

## File Structure

**New files (24):**

```
Sources/JMUCoursePlanner/
├── Support/
│   └── DesignTokens.swift                       Task 2
└── Views/
    ├── AppTab.swift                             Task 1
    ├── Design/
    │   ├── Card.swift                           Task 3
    │   ├── StatChip.swift                       Task 4
    │   ├── StatusPill.swift                     Task 5
    │   ├── PrimaryButton.swift                  Task 6
    │   ├── EmptyState.swift                     Task 7
    │   ├── SectionHeader.swift                  Task 8
    │   ├── ProgressRail.swift                   Task 9
    │   └── CourseChip.swift                     Task 10
    ├── Setup/
    │   ├── SetupStepMajor.swift                 Task 11
    │   ├── SetupStepMinor.swift                 Task 12
    │   ├── SetupStepTransfer.swift              Task 13
    │   ├── SetupStepWorkload.swift              Task 14
    │   └── SetupSheet.swift                     Task 15
    ├── TopBar.swift                             Task 16
    ├── Tabs/
    │   ├── MyPlanView.swift                     Task 17
    │   ├── ScheduleBoardView.swift              Task 18
    │   ├── CatalogView.swift                    Task 19
    │   └── GraduationProgressView.swift         Task 20
    └── CourseDetailSheet.swift                  Task 21
```

**Modified files:**
- `Sources/JMUCoursePlanner/Stores/PlanStore.swift` — Task 1 (additions only)
- `Sources/JMUCoursePlanner/Views/ContentView.swift` — Task 22 (rewrite)
- `LIMITATIONS.md` — Task 23

**Deleted files (Task 22, atomically with ContentView rewrite):**
- `Sources/JMUCoursePlanner/Support/JMUStyle.swift`
- `Sources/JMUCoursePlanner/Views/OnboardingView.swift`
- `Sources/JMUCoursePlanner/Views/ScheduleView.swift`
- `Sources/JMUCoursePlanner/Views/ProgressPanel.swift`
- `Sources/JMUCoursePlanner/Views/ProgramPickerView.swift`
- `Sources/JMUCoursePlanner/Views/CourseDetailView.swift`
- `Sources/JMUCoursePlanner/Views/TransferCreditView.swift`

---

## Task 1: Add `AppTab` enum and extend `PlanStore` with new state

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/AppTab.swift`
- Modify: `Sources/JMUCoursePlanner/Stores/PlanStore.swift`

- [ ] **Step 1: Create `AppTab.swift`**

Create `Sources/JMUCoursePlanner/Views/AppTab.swift` with:

```swift
import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case myPlan
    case schedule
    case catalog
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myPlan: "My Plan"
        case .schedule: "Schedule"
        case .catalog: "Catalog"
        case .progress: "Progress"
        }
    }

    var systemImage: String {
        switch self {
        case .myPlan: "graduationcap.fill"
        case .schedule: "calendar"
        case .catalog: "books.vertical.fill"
        case .progress: "chart.bar.fill"
        }
    }
}
```

- [ ] **Step 2: Add new `@Published` state to `PlanStore`**

Open `Sources/JMUCoursePlanner/Stores/PlanStore.swift`. Find the existing `@Published` block (lines ~8-15). Add these four new fields directly under `@Published var isRefreshingCatalog = false`:

```swift
    @Published var selectedTab: AppTab = .myPlan
    @Published var setupSheetPresented: Bool = false
    @Published var catalogSelectedProgramID: String?
    @Published var scheduleCategoryFilter: String?
```

- [ ] **Step 3: Add `completedCourseIDs` and `remainingCourses(in:)` helpers to `PlanStore`**

In `Sources/JMUCoursePlanner/Stores/PlanStore.swift`, after the existing computed `progress` property (around line 36-39), add:

```swift
    /// Set of course IDs the student has completed (transfer credit + scheduled in active pathway).
    var completedCourseIDs: Set<String> {
        var ids = Set(plan.transferCredits.flatMap(\.courseIDs))
        if let pathway = activePathway {
            ids.formUnion(pathway.semesters.flatMap(\.courseIDs))
        }
        return ids
    }

    /// Course codes still required for a given requirement category, derived from
    /// the catalog. For each unsatisfied option group, returns the first option's
    /// `code` (e.g. "CS 240"). Returns an empty array when the category has no
    /// course options (free electives / partial gen ed clusters) or is fully
    /// satisfied — the caller renders different copy in those cases.
    func remainingCourses(in category: PlannerCore.RequirementCategory) -> [String] {
        guard let catalog else { return [] }
        let completed = completedCourseIDs
        let courses = catalog.coursesByID

        return category.courseOptions.compactMap { option in
            // Option is satisfied if any alternative is already in completed.
            guard !option.contains(where: completed.contains) else { return nil }
            // Otherwise show the first alternative's code.
            guard let firstID = option.first,
                  let course = courses[firstID]
            else { return nil }
            return course.code
        }
    }
```

(Note: `PlannerCore.RequirementCategory` is already imported via `import PlannerCore` at top of the file.)

- [ ] **Step 4: Verify build**

Run from project root:

```bash
swift build 2>&1 | tail -5
```

Expected output ends with `Build complete!` and no errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/AppTab.swift Sources/JMUCoursePlanner/Stores/PlanStore.swift
git commit -m "$(cat <<'EOF'
Add AppTab enum and PlanStore state for new UI

Introduces the four tabs (My Plan, Schedule, Catalog, Progress),
modal setup sheet state, catalog browsing state, and a schedule
category filter for deep-linking from My Plan into Schedule.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create `DesignTokens.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Support/DesignTokens.swift`

- [ ] **Step 1: Write the file**

Create `Sources/JMUCoursePlanner/Support/DesignTokens.swift`:

```swift
import AppKit
import SwiftUI

/// Centralized design tokens — colors, spacing, typography. Every color
/// reference in the new UI goes through this file so light/dark mode adapts
/// automatically via macOS's dynamic color provider.
///
/// Typography note: the design spec calls for Inter with SF Pro fallback.
/// We do not bundle Inter to keep the .app lean; `Font.system` resolves to
/// SF Pro on macOS which renders the same intent at the spec's weights.
enum DesignTokens {

    // MARK: - Colors

    enum Colors {
        static let surface = dynamic(light: 0xfafafa, dark: 0x0a0a0c)
        static let surfaceElevated = dynamic(light: 0xffffff, dark: 0x15151a)
        static let surfaceTinted = dynamic(light: 0xf4f0fa, dark: 0x1f1530)

        static let borderSubtle = dynamic(light: 0xe4e4e7, dark: 0x2a2a30)
        static let borderStrong = dynamic(light: 0xa1a1aa, dark: 0x52525b)

        static let textPrimary = dynamic(light: 0x0a0a0c, dark: 0xfafafa)
        static let textSecondary = dynamic(light: 0x52525b, dark: 0xa1a1aa)
        static let textTertiary = dynamic(light: 0x71717a, dark: 0x71717a)

        /// Brand purple. Stays vivid in dark mode so it remains the unmistakable
        /// active-tab and primary-action signal.
        static let brandPurple = dynamic(light: 0x450084, dark: 0x7c3aed)
        static let brandPurpleSoft = dynamic(light: 0xf4f0fa, dark: 0x2a1840)

        /// JMU gold. Slightly desaturated in dark mode so it doesn't vibrate.
        static let brandGold = dynamic(light: 0xCBB677, dark: 0xb8a168)

        static let success = dynamic(light: 0x16a34a, dark: 0x22c55e)
        static let warning = dynamic(light: 0xd97706, dark: 0xf59e0b)
        static let danger = dynamic(light: 0xdc2626, dark: 0xef4444)

        /// Shadow used for elevated cards in LIGHT mode only. Dark mode uses
        /// border-subtle to convey elevation without shadow noise.
        static let cardShadowLight = Color.black.opacity(0.06)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    // MARK: - Corner radii

    enum Radius {
        static let pill: CGFloat = 999
        static let card: CGFloat = 12
        static let chip: CGFloat = 6
        static let rail: CGFloat = 3
    }

    // MARK: - Typography

    /// System fonts (SF Pro on macOS) at the spec's sizes with weights and
    /// tracking applied. Use these in views via `.font(DesignTokens.Typography.body)`.
    enum Typography {
        static let display = Font.system(size: 28, weight: .bold)
        static let title = Font.system(size: 22, weight: .semibold)
        static let heading = Font.system(size: 18, weight: .semibold)
        static let body = Font.system(size: 14, weight: .regular)
        static let bodyEmphasized = Font.system(size: 14, weight: .semibold)
        static let label = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 12, weight: .regular)
        static let small = Font.system(size: 11, weight: .medium)
    }

    // MARK: - Helpers

    /// Build a dynamic SwiftUI Color that resolves to `light` in Aqua / `dark`
    /// in DarkAqua appearances. Hex values are 0xRRGGBB.
    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return nsColor(fromHex: isDark ? dark : light)
        }))
    }

    private static func nsColor(fromHex hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Support/DesignTokens.swift
git commit -m "$(cat <<'EOF'
Add DesignTokens with dynamic light/dark colors

Centralizes semantic colors (surface, border, brand, semantic),
spacing scale, corner radii, and a typography scale built on
Font.system. Colors use NSColor's dynamic provider so the entire
UI auto-adapts to macOS appearance changes with no per-view
checks of @Environment(\.colorScheme).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Create `Card.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Design/Card.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

/// The base elevated surface. 12pt corner radius, 1px subtle border,
/// soft shadow in light mode only.
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = DesignTokens.Spacing.l
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 1)
            )
            .shadow(
                color: scheme == .light ? DesignTokens.Colors.cardShadowLight : .clear,
                radius: 2, x: 0, y: 1
            )
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Design/Card.swift
git commit -m "Add Card design primitive

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 4: Create `StatChip.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Design/StatChip.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

/// Compact pill used in the top bar for quick stats (e.g. "42%", "Fall 2029").
struct StatChip: View {
    var label: String
    var value: String
    var emphasized: Bool = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Text(label)
                .font(DesignTokens.Typography.small)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(DesignTokens.Typography.bodyEmphasized)
                .monospacedDigit()
                .foregroundStyle(emphasized ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.textPrimary)
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.vertical, DesignTokens.Spacing.s)
        .background(
            Capsule(style: .continuous)
                .fill(emphasized ? DesignTokens.Colors.brandPurpleSoft : DesignTokens.Colors.surfaceElevated)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 1)
        )
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Design/StatChip.swift
git commit -m "Add StatChip design primitive

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 5: Create `StatusPill.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Design/StatusPill.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

/// Filled badge using a semantic color. Used for verification status,
/// pathway counts, "On track" / "Behind" annotations, etc.
struct StatusPill: View {
    enum Tone {
        case success, warning, danger, info, neutral
    }

    var text: String
    var tone: Tone = .neutral
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(DesignTokens.Typography.small)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, DesignTokens.Spacing.s)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous).fill(background)
        )
    }

    private var foreground: Color {
        switch tone {
        case .success: DesignTokens.Colors.success
        case .warning: DesignTokens.Colors.warning
        case .danger: DesignTokens.Colors.danger
        case .info: DesignTokens.Colors.brandPurple
        case .neutral: DesignTokens.Colors.textSecondary
        }
    }

    private var background: Color {
        switch tone {
        case .success: DesignTokens.Colors.success.opacity(0.15)
        case .warning: DesignTokens.Colors.warning.opacity(0.15)
        case .danger: DesignTokens.Colors.danger.opacity(0.15)
        case .info: DesignTokens.Colors.brandPurpleSoft
        case .neutral: DesignTokens.Colors.borderSubtle.opacity(0.5)
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Design/StatusPill.swift
git commit -m "Add StatusPill design primitive

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 6: Create `PrimaryButton.swift` (and the four button styles)

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Design/PrimaryButton.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

/// Four SwiftUI ButtonStyles that match the design system. Apply with
/// `.buttonStyle(.dtPrimary)`, `.dtSecondary`, `.dtTertiary`, `.dtDestructive`.

struct DTPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.Typography.bodyEmphasized)
            .foregroundStyle(.white)
            .padding(.horizontal, DesignTokens.Spacing.l)
            .padding(.vertical, DesignTokens.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.Colors.brandPurple)
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
    }
}

struct DTSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.Typography.bodyEmphasized)
            .foregroundStyle(DesignTokens.Colors.textPrimary)
            .padding(.horizontal, DesignTokens.Spacing.l)
            .padding(.vertical, DesignTokens.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? DesignTokens.Colors.surfaceTinted : DesignTokens.Colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 1)
            )
    }
}

struct DTTertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.Typography.label)
            .foregroundStyle(DesignTokens.Colors.brandPurple)
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct DTDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.Typography.bodyEmphasized)
            .foregroundStyle(DesignTokens.Colors.danger)
            .padding(.horizontal, DesignTokens.Spacing.l)
            .padding(.vertical, DesignTokens.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? DesignTokens.Colors.danger.opacity(0.15) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DesignTokens.Colors.danger.opacity(0.5), lineWidth: 1)
            )
    }
}

extension ButtonStyle where Self == DTPrimaryButtonStyle {
    static var dtPrimary: DTPrimaryButtonStyle { DTPrimaryButtonStyle() }
}
extension ButtonStyle where Self == DTSecondaryButtonStyle {
    static var dtSecondary: DTSecondaryButtonStyle { DTSecondaryButtonStyle() }
}
extension ButtonStyle where Self == DTTertiaryButtonStyle {
    static var dtTertiary: DTTertiaryButtonStyle { DTTertiaryButtonStyle() }
}
extension ButtonStyle where Self == DTDestructiveButtonStyle {
    static var dtDestructive: DTDestructiveButtonStyle { DTDestructiveButtonStyle() }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Design/PrimaryButton.swift
git commit -m "Add DT button styles (primary, secondary, tertiary, destructive)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 7: Create `EmptyState.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Design/EmptyState.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

/// Centered card explaining there's nothing to show yet, plus a primary action.
struct EmptyState: View {
    var systemImage: String
    var title: String
    var body: String
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DesignTokens.Colors.brandPurple)
                .padding(.bottom, DesignTokens.Spacing.s)
            Text(title)
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(self.body)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.dtPrimary)
                    .padding(.top, DesignTokens.Spacing.s)
            }
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Design/EmptyState.swift
git commit -m "Add EmptyState design primitive

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 8: Create `SectionHeader.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Design/SectionHeader.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

struct SectionHeader<Trailing: View>: View {
    var title: String
    var helper: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.heading)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let helper {
                    Text(helper)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, helper: String? = nil) {
        self.init(title: title, helper: helper, trailing: { EmptyView() })
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Design/SectionHeader.swift
git commit -m "Add SectionHeader design primitive

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 9: Create `ProgressRail.swift` — the progress bar

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Design/ProgressRail.swift`

This is the centerpiece of the per-user request. The rail itself is minimal; the helper line beneath it lists remaining required courses.

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import PlannerCore

/// Simple rounded progress bar with a credit total inline (right of the title)
/// and a helper line beneath that lists remaining required courses.
///
/// Use the `category:` initializer for live progress bars driven by a
/// `RequirementCategory`. Use the `value:` initializer for static / non-category
/// usage (e.g. on the My Plan completion tile).
struct ProgressRail: View {
    var title: String?
    var completedCredits: Int
    var requiredCredits: Int
    var remainingCourseCodes: [String]
    var hasCourseOptions: Bool
    var isVerified: Bool

    private var fraction: Double {
        guard requiredCredits > 0 else { return 1 }
        return min(Double(completedCredits) / Double(requiredCredits), 1)
    }

    private var fillColor: Color {
        isVerified ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.warning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            if title != nil || requiredCredits > 0 {
                HStack(alignment: .firstTextBaseline) {
                    if let title {
                        Text(title)
                            .font(DesignTokens.Typography.bodyEmphasized)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }
                    Spacer(minLength: 0)
                    Text("\(completedCredits)/\(requiredCredits)")
                        .font(DesignTokens.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }

            // The rail itself.
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.rail, style: .continuous)
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 6)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.rail, style: .continuous)
                        .fill(fillColor)
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 6 : 0), height: 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.rail, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                                .blendMode(.multiply)
                        )
                }
                .frame(height: 6)
            }
            .frame(height: 6)

            helperLine
        }
    }

    @ViewBuilder
    private var helperLine: some View {
        if fraction >= 1 {
            Text("Complete ✓")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.success)
        } else if !hasCourseOptions {
            // Free elective / partial gen ed clusters.
            let remaining = max(requiredCredits - completedCredits, 0)
            Text("\(remaining) credits to plan")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        } else if remainingCourseCodes.isEmpty {
            Text("\(max(requiredCredits - completedCredits, 0)) credits remaining")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(completedCredits) of \(requiredCredits) credits ·")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .monospacedDigit()
                Text(stillNeedText)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    private var stillNeedText: String {
        let visible = remainingCourseCodes.prefix(5)
        let extra = remainingCourseCodes.count - visible.count
        if extra > 0 {
            return "Still need: \(visible.joined(separator: ", ")) + \(extra) more"
        }
        return "Still need: \(visible.joined(separator: ", "))"
    }
}

extension ProgressRail {
    /// Convenience initializer driven by a CategoryProgress + the calling store's
    /// remaining-courses lookup.
    init(
        category: CategoryProgress,
        hasCourseOptions: Bool,
        remainingCourseCodes: [String]
    ) {
        self.init(
            title: category.name,
            completedCredits: category.completedCredits,
            requiredCredits: category.requiredCredits,
            remainingCourseCodes: remainingCourseCodes,
            hasCourseOptions: hasCourseOptions,
            isVerified: category.verificationStatus == .verified
        )
    }

    /// Convenience initializer for the bare progress bar without a category
    /// (e.g. overall completion on the My Plan tile).
    init(fraction: Double, label: String? = nil) {
        let pct = Int((min(max(fraction, 0), 1)) * 100)
        self.init(
            title: label,
            completedCredits: pct,
            requiredCredits: 100,
            remainingCourseCodes: [],
            hasCourseOptions: false,
            isVerified: true
        )
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Design/ProgressRail.swift
git commit -m "Add ProgressRail design primitive

Renders a 6px rounded progress bar with a credit-count readout on
the right and a helper line below that lists remaining required
courses. Falls back to a credit-count message when courseOptions
are empty (free electives / partial gen ed) and shows
\"Complete ✓\" at 100%.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 10: Create `CourseChip.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Design/CourseChip.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import PlannerCore

/// One course as it appears in a semester column. 3px left border in the
/// category color, code in bold, title secondary, trash on hover, optional
/// ring overlay for category-filter highlighting.
struct CourseChip: View {
    enum Category {
        case major, genEd, elective, warning

        var color: Color {
            switch self {
            case .major: DesignTokens.Colors.brandPurple
            case .genEd: DesignTokens.Colors.brandGold
            case .elective: DesignTokens.Colors.textTertiary
            case .warning: DesignTokens.Colors.danger
            }
        }
    }

    var course: Course
    var category: Category = .elective
    var isHighlighted: Bool = false
    var onTap: () -> Void = {}
    var onRemove: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(category.color)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(course.code)
                            .font(DesignTokens.Typography.bodyEmphasized)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .monospacedDigit()
                        Spacer(minLength: 0)
                        Text("\(course.credits) cr")
                            .font(DesignTokens.Typography.small)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .monospacedDigit()
                    }
                    Text(course.title)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, DesignTokens.Spacing.m)
                .padding(.vertical, DesignTokens.Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                    .stroke(
                        isHighlighted ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.borderSubtle,
                        lineWidth: isHighlighted ? 2 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isHovering, let onRemove {
                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.danger)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Design/CourseChip.swift
git commit -m "Add CourseChip design primitive

3px left-border in category color (purple/gold/gray/red), code +
credits header, title beneath, hover-revealed trash, optional
highlight ring for category-filter deep-linking from My Plan.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 11: Create `SetupStepMajor.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Setup/SetupStepMajor.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import PlannerCore

struct SetupStepMajor: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog
    @State private var searchText: String = ""

    private var filtered: [Program] {
        let majors = catalog.programs.filter { $0.kind == .major }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return majors }
        return majors.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
            || $0.college.localizedCaseInsensitiveContains(trimmed)
            || $0.department.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var grouped: [(college: String, departments: [(name: String, programs: [Program])])] {
        let byCollege = Dictionary(grouping: filtered, by: \.college)
        return byCollege.keys.sorted().map { college in
            let byDept = Dictionary(grouping: byCollege[college] ?? [], by: \.department)
            let departments = byDept.keys.sorted().map { name in
                (name: name, programs: (byDept[name] ?? []).sorted { $0.title < $1.title })
            }
            return (college: college, departments: departments)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            SectionHeader(
                "Choose your major",
                helper: "Pick the exact program and degree type. You can change this later from the kebab menu."
            )
            TextField("Search by major, college, or department", text: $searchText)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                    ForEach(grouped, id: \.college) { college, departments in
                        DisclosureGroup {
                            ForEach(departments, id: \.name) { dept in
                                DisclosureGroup {
                                    ForEach(dept.programs) { program in
                                        programRow(program)
                                    }
                                } label: {
                                    Text(dept.name)
                                        .font(DesignTokens.Typography.label)
                                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                                }
                            }
                        } label: {
                            Text(college)
                                .font(DesignTokens.Typography.bodyEmphasized)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                        }
                    }
                }
                .padding(.trailing, DesignTokens.Spacing.s)
            }
        }
    }

    private func programRow(_ program: Program) -> some View {
        let isSelected = store.plan.programID == program.id
        return Button {
            store.selectProgram(program)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.title)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    HStack(spacing: DesignTokens.Spacing.s) {
                        if let deg = program.degreeType {
                            StatusPill(text: deg, tone: .info)
                        }
                        StatusPill(
                            text: program.requirementDataComplete ? "Verified" : "Partial",
                            tone: program.requirementDataComplete ? .success : .warning
                        )
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DesignTokens.Colors.brandPurple)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, DesignTokens.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? DesignTokens.Colors.brandPurpleSoft : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Setup/SetupStepMajor.swift
git commit -m "Add SetupStepMajor view

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 12: Create `SetupStepMinor.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Setup/SetupStepMinor.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import PlannerCore

struct SetupStepMinor: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog
    @State private var searchText: String = ""

    private var candidates: [Program] {
        let pool = catalog.programs.filter { $0.kind == .minor || $0.kind == .major }
            .filter { $0.id != store.plan.programID }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return pool }
        return pool.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
            || $0.college.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            SectionHeader(
                "Add a minor or second major",
                helper: "Optional. You can come back to this later. Adds the additional credit hours to your plan."
            )
            TextField("Search programs", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if !store.plan.minorProgramIDs.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                        Text("Currently added")
                            .font(DesignTokens.Typography.small)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        ForEach(store.plan.minorProgramIDs, id: \.self) { id in
                            HStack {
                                Text(catalog.programsByID[id]?.title ?? id)
                                    .font(DesignTokens.Typography.body)
                                Spacer()
                            }
                        }
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(candidates.sorted { $0.title < $1.title }) { program in
                        let isAdded = store.plan.minorProgramIDs.contains(program.id)
                        Button {
                            store.addMinor(program)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(program.title)
                                        .font(DesignTokens.Typography.body)
                                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                                    Text(program.college)
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                }
                                Spacer(minLength: 0)
                                if isAdded {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(DesignTokens.Colors.success)
                                } else {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(DesignTokens.Colors.brandPurple)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, DesignTokens.Spacing.s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Setup/SetupStepMinor.swift
git commit -m "Add SetupStepMinor view

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 13: Create `SetupStepTransfer.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Setup/SetupStepTransfer.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import PlannerCore

struct SetupStepTransfer: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog
    @State private var selectedExam: String = ""
    @State private var selectedScore: Int = 5
    @State private var dualLabel: String = ""
    @State private var dualCourse: String = ""
    @State private var dualCredits: Int = 3

    private var apExamNames: [String] {
        Array(Set(catalog.apCreditRules.compactMap { rule in
            if case .apExam(let name, _) = rule.source { return name }
            return nil
        })).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            SectionHeader(
                "Transfer credit",
                helper: "Optional. Add AP exam scores and dual enrollment courses you've completed."
            )

            Card {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                    Text("AP Exam")
                        .font(DesignTokens.Typography.bodyEmphasized)
                    HStack(spacing: DesignTokens.Spacing.s) {
                        Picker("Exam", selection: $selectedExam) {
                            ForEach(apExamNames, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        Stepper("Score \(selectedScore)", value: $selectedScore, in: 1...5)
                            .frame(width: 130)
                        Button("Add") {
                            guard !selectedExam.isEmpty else { return }
                            store.addAPScore(examName: selectedExam, score: selectedScore)
                        }
                        .buttonStyle(.dtSecondary)
                        .disabled(selectedExam.isEmpty)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                    Text("Dual Enrollment")
                        .font(DesignTokens.Typography.bodyEmphasized)
                    Grid(alignment: .leading, horizontalSpacing: DesignTokens.Spacing.s, verticalSpacing: DesignTokens.Spacing.s) {
                        GridRow {
                            TextField("Source course (e.g. AP Calc BC)", text: $dualLabel)
                            TextField("JMU course code (e.g. MATH235)", text: $dualCourse)
                        }
                        GridRow {
                            Stepper("\(dualCredits) credits", value: $dualCredits, in: 1...8)
                            Button("Add") {
                                store.addDualEnrollment(
                                    label: dualLabel.isEmpty ? "Dual Enrollment" : dualLabel,
                                    courseID: dualCourse.replacingOccurrences(of: " ", with: "").uppercased(),
                                    credits: dualCredits
                                )
                                dualLabel = ""
                                dualCourse = ""
                            }
                            .buttonStyle(.dtSecondary)
                            .disabled(dualCourse.isEmpty)
                        }
                    }
                }
            }

            if !store.plan.transferCredits.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                        Text("Added so far")
                            .font(DesignTokens.Typography.small)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        ForEach(store.plan.transferCredits) { credit in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(credit.sourceDescription)
                                        .font(DesignTokens.Typography.body)
                                    Text(credit.courseIDs.joined(separator: ", "))
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                                }
                                Spacer()
                                StatusPill(text: "\(credit.credits) cr", tone: .neutral)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .onAppear {
            if selectedExam.isEmpty {
                selectedExam = apExamNames.first ?? ""
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Setup/SetupStepTransfer.swift
git commit -m "Add SetupStepTransfer view

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 14: Create `SetupStepWorkload.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Setup/SetupStepWorkload.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import PlannerCore

struct SetupStepWorkload: View {
    @EnvironmentObject private var store: PlanStore

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            SectionHeader(
                "Workload preference",
                helper: "The generator stays inside this range while respecting prerequisites and semester availability. You can change it later."
            )

            VStack(spacing: DesignTokens.Spacing.m) {
                ForEach(WorkloadPreference.allCases, id: \.self) { workload in
                    workloadRow(workload)
                }
            }
        }
    }

    private func workloadRow(_ workload: WorkloadPreference) -> some View {
        let isSelected = store.plan.workload == workload
        return Button {
            store.setWorkload(workload)
        } label: {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.borderStrong)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text(workload.rawValue)
                        .font(DesignTokens.Typography.bodyEmphasized)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(workload.displayName)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(DesignTokens.Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(isSelected ? DesignTokens.Colors.brandPurpleSoft : DesignTokens.Colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .stroke(
                        isSelected ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.borderSubtle,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Setup/SetupStepWorkload.swift
git commit -m "Add SetupStepWorkload view

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 15: Create `SetupSheet.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Setup/SetupSheet.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import PlannerCore

/// Modal sheet hosting the 4-step setup flow.
struct SetupSheet: View {
    @EnvironmentObject private var store: PlanStore
    @Environment(\.dismiss) private var dismiss
    var catalog: Catalog
    @State private var step: Int = 0

    private let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            stepContent
                .padding(DesignTokens.Spacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider().opacity(0.5)
            footer
        }
        .frame(minWidth: 640, minHeight: 560)
        .background(DesignTokens.Colors.surface)
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.m) {
            Text("Build your plan")
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Circle()
                        .fill(index <= step ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.borderSubtle)
                        .frame(width: 8, height: 8)
                }
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.l)
    }

    @ViewBuilder
    private var stepContent: some View {
        ScrollView {
            switch step {
            case 0: SetupStepMajor(catalog: catalog)
            case 1: SetupStepMinor(catalog: catalog)
            case 2: SetupStepTransfer(catalog: catalog)
            default: SetupStepWorkload()
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Back") {
                if step > 0 { step -= 1 }
            }
            .buttonStyle(.dtSecondary)
            .disabled(step == 0)

            Spacer()

            if step == 1 || step == 2 {
                Button("Skip") {
                    advance()
                }
                .buttonStyle(.dtTertiary)
            }

            if step < stepCount - 1 {
                Button("Next") {
                    advance()
                }
                .buttonStyle(.dtPrimary)
                .disabled(step == 0 && store.plan.programID == nil)
            } else {
                Button("Generate Plan") {
                    store.generateSchedules()
                    dismiss()
                }
                .buttonStyle(.dtPrimary)
                .disabled(store.plan.programID == nil)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.l)
    }

    private func advance() {
        if step < stepCount - 1 { step += 1 }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Setup/SetupSheet.swift
git commit -m "Add SetupSheet host for the 4-step setup flow

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 16: Create `TopBar.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/TopBar.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import PlannerCore

struct TopBar: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.l) {
            leadingCluster
            Spacer(minLength: DesignTokens.Spacing.l)
            tabBar
            Spacer(minLength: DesignTokens.Spacing.l)
            trailingCluster
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.m)
        .frame(height: 64)
        .background(DesignTokens.Colors.surfaceElevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 1)
        }
    }

    private var leadingCluster: some View {
        HStack(spacing: DesignTokens.Spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DesignTokens.Colors.brandPurple)
                Text("J")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.brandGold)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(store.activeProgram?.title ?? "JMU Course Planner")
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                if let deg = store.activeProgram?.degreeType {
                    Text(deg)
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                } else if store.activeProgram == nil {
                    Text("No plan yet")
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 1)
        )
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isActive = store.selectedTab == tab
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                store.selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(tab.title)
                    .font(DesignTokens.Typography.label)
            }
            .foregroundStyle(isActive ? .white : DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? DesignTokens.Colors.brandPurple : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var trailingCluster: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            if let progress = store.progress {
                StatChip(label: "Done", value: "\(Int(progress.overallFraction * 100))%", emphasized: true)
                StatChip(label: "Grad", value: progress.projectedGraduation?.displayName ?? "—")
            }
            if store.isRefreshingCatalog {
                StatusPill(text: "Refreshing", tone: .info, systemImage: "arrow.triangle.2.circlepath")
            }

            Menu {
                Button("Edit setup") { store.setupSheetPresented = true }
                Button("Save") { store.saveCurrentPlan() }
                Menu("Export") {
                    Button("PDF") { store.exportPDF() }
                    Button("Calendar (.ics)") { store.exportICS() }
                }
                Divider()
                Button("Refresh Requirements") { store.refreshCatalog() }
                Button("Start Over") { store.startFresh() }
                Divider()
                Button("Reset App Data", role: .destructive) { store.resetAppData() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .frame(maxWidth: 320, alignment: .trailing)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/TopBar.swift
git commit -m "Add TopBar with logo, program title, tab pills, stat chips, kebab menu

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 17: Create `MyPlanView.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import PlannerCore

struct MyPlanView: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog

    var body: some View {
        if let program = store.activeProgram {
            content(program: program)
        } else {
            EmptyState(
                systemImage: "graduationcap",
                title: "Let's build your plan",
                body: "Choose your major, add any transfer credit, pick a workload, and we'll draft three pathway options you can edit.",
                actionLabel: "Start setup",
                action: { store.setupSheetPresented = true }
            )
        }
    }

    private func content(program: Program) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                hero(program: program)
                stats
                categoryBreakdown
                footerActions
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func hero(program: Program) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                HStack(spacing: DesignTokens.Spacing.s) {
                    Text(program.title)
                        .font(DesignTokens.Typography.display)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .tracking(-0.5)
                    if let deg = program.degreeType {
                        StatusPill(text: deg, tone: .info)
                    }
                    StatusPill(
                        text: program.requirementDataComplete ? "Verified" : "Partial",
                        tone: program.requirementDataComplete ? .success : .warning,
                        systemImage: program.requirementDataComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                }
                Text("\(program.college) · \(program.department)")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                if !program.requirementDataComplete {
                    Text(program.sourceNote)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.top, DesignTokens.Spacing.s)
                }
            }
        }
    }

    @ViewBuilder
    private var stats: some View {
        if let progress = store.progress {
            HStack(spacing: DesignTokens.Spacing.l) {
                completionTile(progress: progress)
                graduationTile(progress: progress)
            }
        }
    }

    private func completionTile(progress: GraduationProgress) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                Text("Completion")
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text("\(Int(progress.overallFraction * 100))%")
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Colors.brandPurple)
                ProgressRail(fraction: progress.overallFraction)
                Text("\(progress.overallCompletedCredits) of \(progress.overallRequiredCredits) credits")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .monospacedDigit()
            }
        }
        .background(
            LinearGradient(
                colors: [DesignTokens.Colors.brandPurpleSoft, DesignTokens.Colors.surfaceElevated],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
        )
        .frame(maxWidth: .infinity)
    }

    private func graduationTile(progress: GraduationProgress) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                Text("Projected graduation")
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(progress.projectedGraduation?.displayName ?? "—")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(semestersAwayText(progress: progress))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func semestersAwayText(progress: GraduationProgress) -> String {
        guard let target = progress.projectedGraduation else { return "Generate a pathway to project a date" }
        let currentYear = Calendar.current.component(.year, from: Date())
        let monthsAway = (target.year - currentYear) * 12
        let semesters = max(monthsAway / 6, 1)
        return "About \(semesters) semester\(semesters == 1 ? "" : "s") from now"
    }

    @ViewBuilder
    private var categoryBreakdown: some View {
        if let progress = store.progress, let program = store.activeProgram {
            let lookup = Dictionary(uniqueKeysWithValues: program.requirements.map { ($0.id, $0) })
            Card {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                    SectionHeader("Requirement progress")
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                        ForEach(progress.categories) { category in
                            Button {
                                store.scheduleCategoryFilter = category.id
                                store.selectedTab = .schedule
                            } label: {
                                let req = lookup[category.id]
                                ProgressRail(
                                    category: category,
                                    hasCourseOptions: !(req?.courseOptions.isEmpty ?? true),
                                    remainingCourseCodes: remainingCodes(for: req)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func remainingCodes(for category: RequirementCategory?) -> [String] {
        guard let category else { return [] }
        return store.remainingCourses(in: category)
    }

    private var footerActions: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Button("Edit setup") { store.setupSheetPresented = true }
                .buttonStyle(.dtSecondary)
            Button("Regenerate pathways") { store.generateSchedules() }
                .buttonStyle(.dtTertiary)
            Spacer()
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Tabs/MyPlanView.swift
git commit -m "Add MyPlanView landing tab

Hero card with program info, two stat tiles (completion gradient
+ graduation), and a requirement-category list using ProgressRail.
Clicking a category deep-links to the Schedule tab.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 18: Create `ScheduleBoardView.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Tabs/ScheduleBoardView.swift`

This replaces the existing `ScheduleView.swift` but as a new file so the old one keeps building until Task 22.

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import PlannerCore

struct ScheduleBoardView: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog

    var body: some View {
        if store.plan.pathways.isEmpty {
            EmptyState(
                systemImage: "calendar.badge.plus",
                title: "No pathways yet",
                body: "Pick a major and generate pathways to see your semester plan.",
                actionLabel: "Open setup",
                action: { store.setupSheetPresented = true }
            )
        } else {
            VStack(spacing: 0) {
                subToolbar
                Divider().opacity(0.5)
                warningsBanner
                board
            }
        }
    }

    private var subToolbar: some View {
        HStack(spacing: DesignTokens.Spacing.m) {
            Picker("Pathway", selection: Binding(
                get: { store.plan.activePathwayID ?? store.plan.pathways.first?.id ?? "" },
                set: { store.plan.activePathwayID = $0 }
            )) {
                ForEach(store.plan.pathways) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Spacer()

            if let pathway = store.activePathway {
                let total = pathway.semesters.flatMap(\.courseIDs)
                    .compactMap { catalog.coursesByID[$0]?.credits }.reduce(0, +)
                StatChip(label: "Pathway", value: "\(total) cr")
            }

            Button("Regenerate") { store.generateSchedules() }
                .buttonStyle(.dtSecondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.m)
    }

    @ViewBuilder
    private var warningsBanner: some View {
        let active = store.warnings.filter { !$0.isOverridden }
        if !active.isEmpty {
            HStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.Colors.warning)
                Text("\(active.count) warning\(active.count == 1 ? "" : "s") in this pathway")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.s)
            .background(DesignTokens.Colors.warning.opacity(0.1))
        }
    }

    private var board: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
                if let pathway = store.activePathway {
                    ForEach(pathway.semesters) { semester in
                        SemesterColumn(
                            semester: semester,
                            catalog: catalog,
                            highlightedCategoryID: store.scheduleCategoryFilter
                        )
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
    }
}

private struct SemesterColumn: View {
    @EnvironmentObject private var store: PlanStore
    var semester: SemesterPlan
    var catalog: Catalog
    var highlightedCategoryID: String?

    private var coursesByID: [String: Course] { catalog.coursesByID }

    private var totalCredits: Int {
        semester.courseIDs.compactMap { coursesByID[$0]?.credits }.reduce(0, +)
    }

    var body: some View {
        Card(padding: DesignTokens.Spacing.m) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                header
                Divider().opacity(0.5)
                ForEach(semester.courseIDs, id: \.self) { id in
                    if let course = coursesByID[id] {
                        let warnings = store.warnings.filter { $0.courseID == id && $0.semester == semester.id }
                        let activeWarnings = warnings.filter { !$0.isOverridden }
                        CourseChip(
                            course: course,
                            category: chipCategory(courseID: id, hasWarning: !activeWarnings.isEmpty),
                            isHighlighted: isHighlighted(courseID: id),
                            onTap: { store.showCourse(id) },
                            onRemove: { store.removeCourse(id) }
                        )
                        .draggable(id)
                        ForEach(warnings) { warning in
                            warningStrip(warning)
                        }
                    }
                }
                Spacer(minLength: 0)
                addCourseMenu
            }
        }
        .frame(width: 280)
        .frame(minHeight: 540, alignment: .top)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first else { return false }
            store.moveCourse(id, to: semester.id)
            return true
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(semester.id.displayName)
                    .font(DesignTokens.Typography.bodyEmphasized)
                Text("\(totalCredits) credits")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .monospacedDigit()
            }
            Spacer()
            StatusPill(text: "\(semester.courseIDs.count)", tone: .neutral)
        }
    }

    private func warningStrip(_ warning: ConflictWarning) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(warning.message)
                .font(DesignTokens.Typography.small)
                .lineLimit(2)
            Spacer(minLength: 0)
            if !warning.isOverridden {
                Button("Keep") { store.override(warning) }
                    .buttonStyle(.dtTertiary)
            }
        }
        .foregroundStyle(warning.isOverridden ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.warning)
        .padding(.horizontal, DesignTokens.Spacing.s)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(warning.isOverridden ? DesignTokens.Colors.surface : DesignTokens.Colors.warning.opacity(0.12))
        )
    }

    private var addCourseMenu: some View {
        Menu {
            ForEach(catalog.courses.sorted { $0.code < $1.code }) { course in
                Button("\(course.code) — \(course.title)") {
                    store.moveCourse(course.id, to: semester.id)
                }
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add course")
                    .font(DesignTokens.Typography.label)
            }
            .foregroundStyle(DesignTokens.Colors.brandPurple)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(DesignTokens.Colors.brandPurpleSoft)
            )
        }
        .menuStyle(.borderlessButton)
    }

    private func chipCategory(courseID: String, hasWarning: Bool) -> CourseChip.Category {
        if hasWarning { return .warning }
        guard let program = store.activeProgram else { return .elective }
        for requirement in program.requirements {
            let inOption = requirement.courseOptions.contains { $0.contains(courseID) }
            if inOption {
                if requirement.id.contains("gened") || requirement.name.lowercased().contains("general education") {
                    return .genEd
                }
                return .major
            }
        }
        return .elective
    }

    private func isHighlighted(courseID: String) -> Bool {
        guard let filterID = highlightedCategoryID,
              let program = store.activeProgram,
              let requirement = program.requirements.first(where: { $0.id == filterID })
        else { return false }
        return requirement.courseOptions.contains { $0.contains(courseID) }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Tabs/ScheduleBoardView.swift
git commit -m "Add ScheduleBoardView (new schedule tab)

Sub-toolbar with pathway picker + pathway-credit chip + regenerate.
Warnings banner if active. Horizontal-scroll columns of Cards, each
with a CourseChip list, inline warning strips, drag-and-drop, and
an Add course menu. Highlights chips matching the deep-linked
category filter from My Plan.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 19: Create `CatalogView.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Tabs/CatalogView.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import PlannerCore

struct CatalogView: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog
    @State private var searchText: String = ""

    private var filteredPrograms: [Program] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return catalog.programs }
        return catalog.programs.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
            || $0.college.localizedCaseInsensitiveContains(trimmed)
            || $0.department.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var grouped: [(college: String, programs: [Program])] {
        let byCollege = Dictionary(grouping: filteredPrograms, by: \.college)
        return byCollege.keys.sorted().map { college in
            (college: college, programs: (byCollege[college] ?? []).sorted { $0.title < $1.title })
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            leftRail
            Divider()
            detail
        }
    }

    private var leftRail: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            TextField("Search programs", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, DesignTokens.Spacing.l)
                .padding(.top, DesignTokens.Spacing.l)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(grouped, id: \.college) { college, programs in
                        DisclosureGroup {
                            ForEach(programs) { program in
                                programRow(program)
                            }
                        } label: {
                            Text(college)
                                .font(DesignTokens.Typography.bodyEmphasized)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.l)
            }
        }
        .frame(width: 320)
        .background(DesignTokens.Colors.surface)
    }

    private func programRow(_ program: Program) -> some View {
        let isSelected = store.catalogSelectedProgramID == program.id
        return Button {
            store.catalogSelectedProgramID = program.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.title)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(program.department)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                Spacer(minLength: 0)
                if !program.requirementDataComplete {
                    Circle()
                        .fill(DesignTokens.Colors.warning)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, DesignTokens.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? DesignTokens.Colors.brandPurpleSoft : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        if let id = store.catalogSelectedProgramID, let program = catalog.programsByID[id] {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                    detailHero(program)
                    ForEach(program.requirements) { req in
                        requirementCard(req)
                    }
                }
                .padding(DesignTokens.Spacing.xl)
            }
        } else {
            EmptyState(
                systemImage: "book.closed",
                title: "Browse JMU programs",
                body: "Pick a program from the list to see its requirement breakdown.",
                actionLabel: nil,
                action: nil
            )
        }
    }

    private func detailHero(_ program: Program) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                HStack(spacing: DesignTokens.Spacing.s) {
                    Text(program.title)
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    if let deg = program.degreeType {
                        StatusPill(text: deg, tone: .info)
                    }
                    StatusPill(
                        text: program.requirementDataComplete ? "Verified" : "Partial",
                        tone: program.requirementDataComplete ? .success : .warning
                    )
                }
                Text("\(program.college) · \(program.department)")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text(program.sourceNote)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
    }

    private func requirementCard(_ req: RequirementCategory) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(req.name)
                        .font(DesignTokens.Typography.bodyEmphasized)
                    Spacer()
                    Text("\(req.requiredCredits) credits")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .monospacedDigit()
                }
                if let note = req.note {
                    Text(note)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                ForEach(req.courseOptions.indices, id: \.self) { i in
                    let alts = req.courseOptions[i]
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .font(.system(size: 9))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text(alts.compactMap { catalog.coursesByID[$0]?.code }.joined(separator: " or "))
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .onTapGesture {
                                if let firstID = alts.first { store.showCourse(firstID) }
                            }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Tabs/CatalogView.swift
git commit -m "Add CatalogView (program browser tab)

Left rail with search + college-grouped program list, right pane
with selected program hero + requirement cards. Click any course
to open the Course Detail sheet.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 20: Create `GraduationProgressView.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/Tabs/GraduationProgressView.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import PlannerCore

struct GraduationProgressView: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog

    var body: some View {
        if let progress = store.progress, let program = store.activeProgram {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                    donut(progress: progress)
                    categoryList(progress: progress, program: program)
                }
                .padding(DesignTokens.Spacing.xl)
                .frame(maxWidth: 980, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        } else {
            EmptyState(
                systemImage: "chart.bar.xaxis",
                title: "No progress to show",
                body: "Generate a pathway from setup to see live graduation tracking.",
                actionLabel: "Open setup",
                action: { store.setupSheetPresented = true }
            )
        }
    }

    private func donut(progress: GraduationProgress) -> some View {
        Card {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.xl) {
                ZStack {
                    Circle()
                        .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: CGFloat(progress.overallFraction))
                        .stroke(
                            DesignTokens.Colors.brandPurple,
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int(progress.overallFraction * 100))%")
                            .font(.system(size: 36, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(DesignTokens.Colors.brandPurple)
                        Text("complete")
                            .font(DesignTokens.Typography.small)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
                .frame(width: 180, height: 180)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                    Text("Graduation tracker")
                        .font(DesignTokens.Typography.heading)
                    Text("\(progress.overallCompletedCredits) of \(progress.overallRequiredCredits) credits planned")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .monospacedDigit()
                    if let target = progress.projectedGraduation {
                        Text("Projected: \(target.displayName)")
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func categoryList(progress: GraduationProgress, program: Program) -> some View {
        let reqByID = Dictionary(uniqueKeysWithValues: program.requirements.map { ($0.id, $0) })
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            SectionHeader("By category")
            ForEach(progress.categories) { category in
                let req = reqByID[category.id]
                let hasOptions = !(req?.courseOptions.isEmpty ?? true)
                Card {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(category.name)
                                .font(DesignTokens.Typography.bodyEmphasized)
                            if category.verificationStatus != .verified {
                                StatusPill(text: "Partial", tone: .warning)
                            }
                            Spacer()
                        }
                        ProgressRail(
                            category: category,
                            hasCourseOptions: hasOptions,
                            remainingCourseCodes: store.remainingCourses(in: req ?? RequirementCategory(id: category.id, name: category.name, requiredCredits: category.requiredCredits, courseOptions: []))
                        )
                        if let note = req?.note, !hasOptions {
                            Text(note)
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/Tabs/GraduationProgressView.swift
git commit -m "Add GraduationProgressView (progress tab)

Donut hero showing overall completion + per-category ProgressRail
cards listing remaining required courses beneath each bar.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 21: Create `CourseDetailSheet.swift`

**Files:**
- Create: `Sources/JMUCoursePlanner/Views/CourseDetailSheet.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI
import PlannerCore

struct CourseDetailSheet: View {
    @EnvironmentObject private var store: PlanStore
    @Environment(\.dismiss) private var dismiss
    var course: Course
    var catalog: Catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                    descriptionSection
                    availabilitySection
                    prereqSection
                    professorSection
                    linksSection
                }
                .padding(DesignTokens.Spacing.xl)
            }
        }
        .frame(width: 480)
        .frame(maxHeight: .infinity)
        .background(DesignTokens.Colors.surface)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.code)
                    .font(DesignTokens.Typography.display)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .tracking(-0.5)
                Text(course.title)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                HStack(spacing: DesignTokens.Spacing.s) {
                    StatusPill(text: "\(course.credits) credits", tone: .info)
                    if let avail = course.availability, !avail.isEmpty {
                        StatusPill(
                            text: avail.map(\.rawValue).sorted().joined(separator: " · "),
                            tone: .neutral
                        )
                    } else {
                        StatusPill(text: "Availability unknown", tone: .warning)
                    }
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignTokens.Spacing.xl)
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            SectionHeader("Description")
            if let detail = store.courseDetail, let description = detail.description {
                Text(description)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            } else {
                Text(store.courseDetail?.descriptionStatus ?? "Loading official course details...")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
    }

    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            SectionHeader("Semester availability")
            if let avail = course.availability, !avail.isEmpty {
                Text("Typically offered: \(avail.map(\.rawValue).sorted().joined(separator: " and "))")
                    .font(DesignTokens.Typography.body)
            } else {
                Text("Availability is not verified in the local catalog. Confirm with the registrar before placing this course.")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.warning)
            }
            Text("If you move this course into a term where it isn't typically offered, the warning stays visible until you change it.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private var prereqSection: some View {
        if !course.prerequisites.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                SectionHeader("Prerequisites")
                FlexibleHStack(spacing: 6) {
                    ForEach(course.prerequisites, id: \.self) { id in
                        Button {
                            store.showCourse(id)
                        } label: {
                            Text(catalog.coursesByID[id]?.code ?? id)
                                .font(DesignTokens.Typography.small)
                                .padding(.horizontal, DesignTokens.Spacing.s)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(DesignTokens.Colors.brandPurpleSoft)
                                )
                                .foregroundStyle(DesignTokens.Colors.brandPurple)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var professorSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            SectionHeader("Difficulty & professors")
            Text(store.courseDetail?.rmpStatus ?? "Loading professor data...")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            if let profs = store.courseDetail?.professors, !profs.isEmpty {
                ForEach(profs) { p in
                    HStack {
                        Text(p.name).font(DesignTokens.Typography.body)
                        Spacer()
                        Text(p.rating.map { String(format: "%.1f", $0) } ?? "No reviews yet")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var linksSection: some View {
        if course.registrarURL != nil {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                SectionHeader("Links")
                if let url = course.registrarURL {
                    Link("Open JMU registrar page →", destination: url)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.brandPurple)
                }
            }
        }
    }
}

/// Simple horizontal wrap layout for chip rows.
private struct FlexibleHStack<Content: View>: View {
    var spacing: CGFloat = 4
    @ViewBuilder var content: () -> Content

    var body: some View {
        // SwiftUI on macOS 14 has `Layout` but we keep it simple with FlowLayout.
        // For small chip counts an HStack with wrapping via HStack works visually.
        // Use the system FlowLayout shim via the new Layout protocol if available.
        FlowLayout(spacing: spacing) {
            content()
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                width = max(width, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        width = max(width, rowWidth)
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x - bounds.minX + size.width > maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/CourseDetailSheet.swift
git commit -m "Add CourseDetailSheet (side sheet, ~480px)

Hero with code/title/credits + availability pill, sections for
description, availability, prereqs (clickable chips), professors,
and links. Includes a small FlowLayout for wrapping prereq chips.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 22: Cutover — rewrite `ContentView` and delete obsolete files

This task is intentionally a single atomic commit. The new `ContentView` references the new views; the old views are removed in the same commit so the build never goes through an inconsistent state.

**Files:**
- Modify (rewrite): `Sources/JMUCoursePlanner/Views/ContentView.swift`
- Delete: `Sources/JMUCoursePlanner/Support/JMUStyle.swift`
- Delete: `Sources/JMUCoursePlanner/Views/OnboardingView.swift`
- Delete: `Sources/JMUCoursePlanner/Views/ScheduleView.swift`
- Delete: `Sources/JMUCoursePlanner/Views/ProgressPanel.swift`
- Delete: `Sources/JMUCoursePlanner/Views/ProgramPickerView.swift`
- Delete: `Sources/JMUCoursePlanner/Views/CourseDetailView.swift`
- Delete: `Sources/JMUCoursePlanner/Views/TransferCreditView.swift`

- [ ] **Step 1: Overwrite `ContentView.swift`**

Replace the entire contents of `Sources/JMUCoursePlanner/Views/ContentView.swift`:

```swift
import SwiftUI
import PlannerCore

struct ContentView: View {
    @EnvironmentObject private var store: PlanStore

    var body: some View {
        Group {
            if let catalog = store.catalog {
                dashboard(catalog: catalog)
            } else {
                LoadingView()
            }
        }
        .tint(DesignTokens.Colors.brandPurple)
    }

    private func dashboard(catalog: Catalog) -> some View {
        VStack(spacing: 0) {
            TopBar(catalog: catalog)
            Divider().opacity(0.5)
            tabContent(catalog: catalog)
        }
        .background(DesignTokens.Colors.surface)
        .sheet(isPresented: $store.setupSheetPresented) {
            SetupSheet(catalog: catalog)
                .environmentObject(store)
        }
        .sheet(item: $store.selectedCourse) { course in
            CourseDetailSheet(course: course, catalog: catalog)
                .environmentObject(store)
        }
        .alert(
            "Planner Notice",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onAppear {
            // Auto-open setup if the user has no program yet.
            if store.activeProgram == nil {
                store.setupSheetPresented = true
            }
        }
    }

    @ViewBuilder
    private func tabContent(catalog: Catalog) -> some View {
        switch store.selectedTab {
        case .myPlan:
            MyPlanView(catalog: catalog)
        case .schedule:
            ScheduleBoardView(catalog: catalog)
        case .catalog:
            CatalogView(catalog: catalog)
        case .progress:
            GraduationProgressView(catalog: catalog)
        }
    }
}

private struct LoadingView: View {
    @EnvironmentObject private var store: PlanStore

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.l) {
            ProgressView()
            Text(store.statusMessage)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if store.errorMessage != nil {
                Button("Retry") {
                    Task { await store.load() }
                }
                .buttonStyle(.dtPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.surface)
    }
}
```

- [ ] **Step 2: Delete the seven obsolete files**

```bash
git rm Sources/JMUCoursePlanner/Support/JMUStyle.swift \
       Sources/JMUCoursePlanner/Views/OnboardingView.swift \
       Sources/JMUCoursePlanner/Views/ScheduleView.swift \
       Sources/JMUCoursePlanner/Views/ProgressPanel.swift \
       Sources/JMUCoursePlanner/Views/ProgramPickerView.swift \
       Sources/JMUCoursePlanner/Views/CourseDetailView.swift \
       Sources/JMUCoursePlanner/Views/TransferCreditView.swift
```

- [ ] **Step 3: Verify build**

```bash
swift build 2>&1 | tail -10
```

Expected: `Build complete!` and no errors. If anything still references `JMUStyle`, fix that reference now (most likely candidates: the new files would have been written to use `DesignTokens` already, so this should be clean).

- [ ] **Step 4: Run existing tests**

```bash
swift test 2>&1 | tail -3
```

Expected: `Test run with 12 tests in 4 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/JMUCoursePlanner/Views/ContentView.swift
git commit -m "$(cat <<'EOF'
Cutover ContentView to tabbed dashboard; delete obsolete views

ContentView is now a tab host: TopBar + active tab body + setup
sheet + course detail sheet. Auto-opens setup on launch when no
program is selected.

Deletes:
- JMUStyle.swift (replaced by DesignTokens)
- OnboardingView.swift (replaced by SetupSheet)
- ScheduleView.swift (replaced by ScheduleBoardView)
- ProgressPanel.swift (folded into GraduationProgressView + TopBar chips)
- ProgramPickerView.swift (replaced by SetupStep* and CatalogView left rail)
- CourseDetailView.swift (replaced by CourseDetailSheet)
- TransferCreditView.swift (replaced by SetupStepTransfer)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 23: Update `LIMITATIONS.md` with UI-overhaul status

**Files:**
- Modify: `LIMITATIONS.md`

- [ ] **Step 1: Read the current LIMITATIONS.md**

```bash
cat LIMITATIONS.md
```

- [ ] **Step 2: Add a new UI section at the top, beneath the H1**

Insert these lines into `LIMITATIONS.md` immediately after the line `# Known Limitations`:

```markdown

## User interface

- The 2026-05-19 UI overhaul replaces the previous sidebar layout with a tabbed dashboard (My Plan · Schedule · Catalog · Progress) and a modal setup sheet. Old views (`OnboardingView`, `ScheduleView`, `ProgressPanel`, `ProgramPickerView`, `CourseDetailView`, `TransferCreditView`) are removed; their logic lives in the new structure.
- Color, typography, and spacing now flow through `DesignTokens.swift`. Light/dark mode auto-follows macOS appearance.
- The design spec calls for the Inter typeface; the app ships with the system SF Pro fallback rather than bundling a font file, so headlines render in SF Pro at the spec's weights and tracking. Substituting Inter later only requires bundling the .ttf and updating the `Typography` enum.
- The Progress tab renders an overall completion donut and per-category `ProgressRail` cards. Each progress rail lists up to 5 remaining required courses beneath the bar; categories without parsed course options (free electives, partial gen ed clusters) show a credit-only helper line.
- Drag-and-drop between semesters is preserved. Inline warning strips appear under offending course chips with a "Keep" override link.

## Manual smoke checklist

After each rebuild, verify by hand:

- Setup sheet opens on first launch.
- Picking a major, completing setup, and clicking Generate Plan lands in My Plan with real numbers.
- Each tab renders without an error alert.
- Dragging a course between semesters updates credit totals and re-evaluates warnings.
- Clicking a category bar in My Plan switches to Schedule and highlights matching chips.
- Course detail sheet opens from any course chip, shows the JMU registrar link, and closes via Esc or the X button.
- Toggling macOS appearance (System Settings → Appearance) updates colors live.
- "Reset App Data" in the kebab menu wipes the cache and reloads.

```

(After Step 2, the file should begin with `# Known Limitations`, then the new `## User interface` and `## Manual smoke checklist` sections, then the existing `## Catalog requirements` section, etc.)

- [ ] **Step 3: Commit**

```bash
git add LIMITATIONS.md
git commit -m "Document UI overhaul in LIMITATIONS.md

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 24: Rebuild the `.app` bundle and smoke-test launch

**Files:** none modified.

- [ ] **Step 1: Run the build script**

```bash
./script/build_and_run.sh --no-launch
```

Expected output ends with `Built /Users/Kyle/VSC/JMU-Course-Selector/dist/JMU Course Planner.app`.

- [ ] **Step 2: Verify the bundle has a fresh binary**

```bash
ls -la "dist/JMU Course Planner.app/Contents/MacOS/JMUCoursePlanner"
```

Expected: a recent timestamp (today's date).

- [ ] **Step 3: Run all tests one more time**

```bash
swift test 2>&1 | tail -3
```

Expected: `Test run with 12 tests in 4 suites passed`.

- [ ] **Step 4: Launch the app**

```bash
open "dist/JMU Course Planner.app"
```

Then run through the manual smoke checklist from `LIMITATIONS.md` (Task 23 Step 2). If any item fails, file follow-up tasks rather than cramming fixes into this task.

- [ ] **Step 5: Final commit (if anything was changed during smoke)**

If nothing needed fixing, no commit. Otherwise:

```bash
git add -A
git commit -m "Polish from UI overhaul smoke test

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Self-review

Spec coverage:
- §3 IA (tabbed dashboard, top bar, modal setup) — Tasks 1, 15, 16, 22 ✓
- §4 Typography & color tokens — Task 2 ✓
- §4 Components (Card, StatChip, StatusPill, CourseChip, Button styles, EmptyState, ProgressRail, SectionHeader) — Tasks 3–10 ✓
- §4 ProgressRail spec (rail visuals, helper line, complete state, no-options state) — Task 9 ✓
- §4 Motion (tab crossfade, sheet slide, drag pickup scale) — TopBar uses `.easeOut(duration: 0.15)`; sheet slide and drag pickup are SwiftUI defaults ✓
- §5.1 My Plan (hero, two stat tiles, category breakdown, deep-link to Schedule, footer actions) — Task 17 ✓
- §5.2 Schedule (sub-toolbar, columns, course chips, drag/drop, inline warnings, add-course menu) — Task 18 ✓
- §5.3 Catalog (left rail, search, right pane, expandable requirements, click course → detail) — Task 19 ✓
- §5.4 Progress (donut + category cards w/ progress rails) — Task 20 ✓
- §5.5 Course Detail side sheet — Task 21 ✓
- §5.6 Setup sheet (4 steps, dots indicator, footer with Back/Skip/Next/Generate) — Tasks 11–15 ✓
- §6 State / errors / partials (empty state, refresh strip, partial badges, warnings banner) — Tasks 17–20 + TopBar refreshing pill ✓
- §7 File structure — matches across all tasks ✓
- §7 PlanStore additions — Task 1 ✓
- §7 Removed files — Task 22 ✓
- §8 Testing approach (no view tests; build is smoke) — Task 24 ✓
- §9 Acceptance criteria — covered in Tasks 22 (cutover deletes JMUStyle, tests still pass), 23 (LIMITATIONS updated), 24 (build + launch) ✓
- §10 Non-goals — respected (no third-party deps, no font bundle, no animation library) ✓

Placeholder scan: none.

Type consistency check:
- `AppTab` enum used in Task 1 and Task 16 (`.myPlan / .schedule / .catalog / .progress`) ✓
- `DesignTokens.Colors.brandPurple` etc. referenced consistently ✓
- `PlanStore.remainingCourses(in:)` used by Task 17 (MyPlan) and Task 20 (Progress) ✓
- `ProgressRail.init(category:hasCourseOptions:remainingCourseCodes:)` used by Task 17 and 20 ✓
- `ProgressRail.init(fraction:label:)` used by Task 17 completionTile ✓
- `CourseChip.Category` (`.major/.genEd/.elective/.warning`) used by Task 18 ✓
- `StatusPill.Tone` used across Tasks 11, 17, 18, 19, 21 — consistent enum cases ✓
- Button styles `.dtPrimary/.dtSecondary/.dtTertiary/.dtDestructive` defined Task 6, used in 7, 11, 13, 15, 17, 18 ✓

Ambiguity check:
- "Tab crossfade" — implemented via `.easeOut(duration: 0.15)` on `selectedTab` setter. Acceptable interpretation of spec §4.
- Inter font — handled as a documented deviation in DesignTokens.swift + LIMITATIONS.md.

No gaps found.
