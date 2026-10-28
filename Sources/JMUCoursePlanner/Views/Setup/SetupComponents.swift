import AppKit
import SwiftUI
import PlannerCore

// MARK: - Step copy

extension SetupStep {
    /// Short label for the step rail.
    var railTitle: String {
        switch self {
        case .year: "Year in school"
        case .major: "Major"
        case .minor: "Minor"
        case .language: "Language"
        case .transfer: "Prior credit"
        case .transcript: "Transcript"
        case .review: "Review courses"
        case .workload: "Workload"
        }
    }

    var title: String {
        switch self {
        case .year: "Where are you in school?"
        case .major: "Choose your major"
        case .minor: "Add a minor or second major"
        case .language: "Choose your foreign language"
        case .transfer: "Bring in AP and dual enrollment credit"
        case .transcript: "Import your JMU transcript"
        case .review: "Review your courses"
        case .workload: "How full should each semester be?"
        }
    }

    var helper: String {
        switch self {
        case .year:
            "This decides whether we start from a blank slate or from the courses you've already taken."
        case .major:
            "Pick the exact program and degree type. You can change this later from the menu."
        case .minor:
            "Optional. Skip this if you haven't decided yet; you can add one any time."
        case .language:
            "A B.A. requires a foreign language through the intermediate level (232). Your placement decides where the plan starts."
        case .transfer:
            "Optional. Credit you've already earned can clear requirements and unlock prerequisites."
        case .transcript:
            "Use the unofficial transcript PDF from MyMadison. Everything is read on this Mac, and you'll check each course before it counts."
        case .review:
            "Check earned credit and current enrollment. Add anything missed, fix credit amounts or matches, and remove anything detected by mistake."
        case .workload:
            "The generator keeps every semester inside this range while respecting prerequisites and when courses are offered."
        }
    }
}

// MARK: - Selectable option

private struct SetupOptionHighlightedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while a setup option shows its accented outline (hovered, pressed, or
    /// selected). Accent content inside reads this to switch to gold.
    var setupOptionHighlighted: Bool {
        get { self[SetupOptionHighlightedKey.self] }
        set { self[SetupOptionHighlightedKey.self] = newValue }
    }
}

extension Color {
    /// Royal Purple at rest, or readable gold for an accented option.
    static func setupAccent(onPurple: Bool) -> Color {
        onPurple ? DesignTokens.Colors.brandGoldInk : DesignTokens.Colors.brandPurple
    }
}

/// Button style for choosable options in setup: a card (year, workload) or a
/// lighter list row (majors, minors). Hover and selection use a neutral
/// surface with a purple outline and gold accents; press dips the scale.
struct SetupOptionStyle: ButtonStyle {
    enum Chrome { case card, row }
    var isSelected: Bool
    var chrome: Chrome = .card

    func makeBody(configuration: Configuration) -> some View {
        SetupOptionBody(configuration: configuration, isSelected: isSelected, chrome: chrome)
    }
}

private struct SetupOptionBody: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    var configuration: ButtonStyle.Configuration
    var isSelected: Bool
    var chrome: SetupOptionStyle.Chrome

    private var radius: CGFloat { chrome == .card ? DesignTokens.Radius.card : DesignTokens.Radius.button }

    var body: some View {
        let hovering = isHovering && isEnabled
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .environment(\.setupOptionHighlighted, isSelected || hovering || configuration.isPressed)
            .padding(.horizontal, chrome == .card ? DesignTokens.Spacing.l : DesignTokens.Spacing.m)
            .padding(.vertical, chrome == .card ? DesignTokens.Spacing.l : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill(hovering: hovering)))
            .overlay(shape.strokeBorder(stroke(hovering: hovering), lineWidth: isSelected ? 1.5 : 1))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(DesignTokens.Motion.hover, value: hovering)
            .animation(DesignTokens.Motion.press, value: configuration.isPressed)
            .animation(DesignTokens.Motion.hover, value: isSelected)
            .onHover { isHovering = $0 }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func fill(hovering: Bool) -> Color {
        if isSelected { return DesignTokens.Colors.surfaceElevated }
        if hovering { return DesignTokens.Colors.surfaceElevated }
        return chrome == .card ? DesignTokens.Colors.surfaceElevated : .clear
    }

    private func stroke(hovering: Bool) -> Color {
        if isSelected { return DesignTokens.Colors.brandPurple }
        if hovering { return DesignTokens.Colors.brandPurple }
        return chrome == .card ? DesignTokens.Colors.borderSubtle : .clear
    }
}

/// Trailing check that pops in when an option becomes selected. It always
/// matches the selected purple outline with gold content.
struct SetupSelectionCheck: View {
    var isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignTokens.Colors.brandGoldInk)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: 20, height: 20)
        .animation(DesignTokens.Motion.settle, value: isSelected)
        .accessibilityHidden(true)
    }
}

// MARK: - Search field

struct SetupSearchField: View {
    var prompt: String
    @Binding var text: String
    @FocusState private var isFocused: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isFocused ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.textTertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.body)
                .focused($isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
                .fill(DesignTokens.Colors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
                .strokeBorder(
                    isFocused ? DesignTokens.Colors.brandPurple : (isHovering ? DesignTokens.Colors.borderStrong : DesignTokens.Colors.borderSubtle),
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .onHover { isHovering = $0 }
        .animation(DesignTokens.Motion.hover, value: isFocused)
        .animation(DesignTokens.Motion.hover, value: isHovering)
        .animation(DesignTokens.Motion.hover, value: text.isEmpty)
    }
}

/// Small uppercase eyebrow used to label fields and groups in setup.
struct SetupEyebrow: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(DesignTokens.Typography.small)
            .tracking(0.44)
            .textCase(.uppercase)
            .foregroundStyle(DesignTokens.Colors.textTertiary)
    }
}

// MARK: - Step rail

struct SetupStepRail: View {
    var route: [SetupStep]
    var current: SetupStep
    var visited: [SetupStep]
    var onSelect: (SetupStep) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(route.enumerated()), id: \.element) { index, step in
                SetupStepRailRow(
                    number: index + 1,
                    title: step.railTitle,
                    state: state(for: step),
                    isLast: index == route.count - 1,
                    action: { onSelect(step) }
                )
            }
        }
        .animation(DesignTokens.Motion.step, value: route)
        .animation(DesignTokens.Motion.step, value: current)
    }

    private func state(for step: SetupStep) -> SetupStepRailRow.State {
        if step == current { return .current }
        return visited.contains(step) ? .done : .upcoming
    }
}

private struct SetupStepRailRow: View {
    enum State { case done, current, upcoming }
    var number: Int
    var title: String
    var state: State
    var isLast: Bool
    var action: () -> Void
    @SwiftUI.State private var isHovering = false
    @SwiftUI.State private var pushedPointer = false

    private func setPointer(_ pointing: Bool) {
        guard pointing != pushedPointer else { return }
        if pointing { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        pushedPointer = pointing
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
                VStack(spacing: 0) {
                    marker
                    if !isLast {
                        Capsule()
                            .fill(state == .done ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.borderSubtle)
                            .frame(width: 2, height: 12)
                            .padding(.vertical, 3)
                    }
                }
                Text(title)
                    .font(state == .current ? DesignTokens.Typography.bodyEmphasized : DesignTokens.Typography.body)
                    .foregroundStyle(titleColor)
                    .padding(.top, 3)
                    .underline(state == .done && isHovering, color: DesignTokens.Colors.textSecondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not `.disabled`: that would dim the current step's label.
        .allowsHitTesting(state == .done)
        .onHover { hovering in
            isHovering = hovering
            setPointer(hovering && state == .done)
        }
        .onChange(of: state) { _, newState in setPointer(isHovering && newState == .done) }
        .onDisappear { setPointer(false) }
        .accessibilityLabel("Step \(number), \(title)")
        .accessibilityValue(state == .current ? "Current step" : state == .done ? "Completed" : "Not started")
        .accessibilityHint(state == .done ? "Go back to this step" : "")
    }

    private var titleColor: Color {
        switch state {
        case .current: DesignTokens.Colors.textPrimary
        case .done: isHovering ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary
        case .upcoming: DesignTokens.Colors.textTertiary
        }
    }

    private var marker: some View {
        ZStack {
            switch state {
            case .done:
                Circle().fill(DesignTokens.Colors.brandPurple)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            case .current:
                Circle().fill(DesignTokens.Colors.surfaceElevated)
                Circle().strokeBorder(DesignTokens.Colors.brandPurple, lineWidth: 2)
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Colors.brandGoldInk)
            case .upcoming:
                Circle().strokeBorder(DesignTokens.Colors.borderStrong, lineWidth: 1)
                Text("\(number)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .frame(width: 24, height: 24)
        .scaleEffect(isHovering && state == .done ? 1.08 : 1)
        .animation(DesignTokens.Motion.hover, value: isHovering)
    }
}

// MARK: - Live summary

/// "Your plan so far": fills in as the student answers each step, so every
/// choice visibly lands somewhere.
struct SetupSummaryPanel: View {
    @EnvironmentObject private var store: PlanStore
    /// Earned hours from an unconfirmed transcript draft, when one exists.
    var draftEarnedHours: Double?
    var isIncoming: Bool
    /// Workload has a default, so it only appears once the student reaches it.
    var showsWorkload: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            SetupEyebrow("Your plan so far")
            row("person.crop.circle", "Year", value: store.plan.studentYear.map(\.summaryTitle))
            row("graduationcap", "Major", value: store.activeProgram?.title, detail: majorDetail)
            row("square.stack.3d.up", "Minor", value: minorsValue, detail: minorsDetail)
            row("tray.and.arrow.down", isIncoming ? "Prior credit" : "Earned so far", value: creditValue)
            if showsWorkload {
                row("gauge.with.dots.needle.33percent", "Workload", value: store.plan.workload.displayName)
                    .transition(.opacity)
            }
        }
        .animation(DesignTokens.Motion.step, value: store.plan.studentYear)
        .animation(DesignTokens.Motion.step, value: store.plan.programID)
        .animation(DesignTokens.Motion.step, value: store.plan.concentrationID)
        .animation(DesignTokens.Motion.step, value: store.plan.minors.count)
        .animation(DesignTokens.Motion.step, value: store.plan.workload)
        .animation(DesignTokens.Motion.step, value: showsWorkload)
    }

    private var majorDetail: String? {
        guard let program = store.activeProgram else { return nil }
        let concentration = program.concentrations.first { $0.id == store.plan.concentrationID }?.name
        return concentration
    }

    private var minorTitles: [String] {
        store.plan.minors.map { store.catalog?.programsByID[$0.programID]?.title ?? $0.programID }
    }

    private var minorsValue: String? { minorTitles.first }

    private var minorsDetail: String? {
        minorTitles.count > 1 ? "+ \(minorTitles.count - 1) more" : nil
    }

    private var creditValue: String? {
        let hours = draftEarnedHours ?? store.effectiveAcademicHistory.earnedHours
        guard hours > 0 else { return nil }
        return "\(CreditHoursFormatter.string(hours)) credits"
    }

    private func row(_ icon: String, _ label: String, value: String?, detail: String? = nil) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(value == nil ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.brandPurple)
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(value ?? "Not set yet")
                    .font(value == nil ? DesignTokens.Typography.caption : DesignTokens.Typography.label)
                    .foregroundStyle(value == nil ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(2)
                    .contentTransition(.opacity)
                if let detail {
                    Text(detail)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                        .help(detail)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

extension StudentYear {
    /// Compact name for the summary panel and year cards.
    var summaryTitle: String {
        switch self {
        case .enrolledFreshman: "Freshman"
        case .fifthYearOrBeyond: "Fifth year+"
        default: rawValue
        }
    }
}
