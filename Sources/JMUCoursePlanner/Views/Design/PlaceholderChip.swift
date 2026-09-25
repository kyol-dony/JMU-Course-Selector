import PlannerCore
import SwiftUI

/// Dashed-outline chip for an unfilled requirement slot. Mirrors CourseChip's
/// hover, ghost, and lifted treatments with a Royal Purple tint.
struct PlaceholderChip: View {
    var spec: PlaceholderSpec
    var appearance: CourseChip.Appearance = .normal

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isHoverActive: Bool { isHovering && appearance == .normal }
    private var isTinted: Bool { isHoverActive || appearance == .lifted }
    private var isLiftedMotion: Bool { appearance == .lifted && !reduceMotion }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.s) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(DesignTokens.Colors.brandPurple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose course")
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .foregroundStyle(DesignTokens.Colors.brandPurple)
                Text(spec.categoryName)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text("\(spec.credits) cr")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .monospacedDigit()
        }
        .padding(DesignTokens.Spacing.s)
        .background(
            ZStack {
                shape.fill(appearance == .lifted ? DesignTokens.Colors.surfaceElevated : Color.clear)
                shape.fill(DesignTokens.Colors.brandPurple.opacity(isTinted ? 0.06 : 0))
            }
        )
        .overlay(
            shape.strokeBorder(DesignTokens.Colors.brandPurple, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .opacity(appearance == .ghost ? 0.35 : 1)
        .shadow(
            color: appearance == .lifted ? DesignTokens.Colors.dragShadow : (isHoverActive ? DesignTokens.Colors.brandPurple.opacity(0.3) : .clear),
            radius: appearance == .lifted ? 12 : (isHoverActive ? 5 : 0),
            x: 0,
            y: appearance == .lifted ? 12 : (isHoverActive ? 3 : 0)
        )
        .scaleEffect(isLiftedMotion ? 1.03 : 1)
        .rotationEffect(.degrees(isLiftedMotion ? -1.5 : 0))
        .offset(y: isHoverActive && !reduceMotion ? -1 : 0)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(DesignTokens.Motion.hover, value: isHovering)
        .animation(DesignTokens.Motion.hover, value: appearance)
    }
}
