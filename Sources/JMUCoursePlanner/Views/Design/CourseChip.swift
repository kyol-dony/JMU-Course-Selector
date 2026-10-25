import SwiftUI
import PlannerCore

struct CourseChip: View {
    enum Appearance: Equatable {
        case normal
        /// Dimmed stand-in left in the origin slot while the item is dragged.
        case ghost
        /// The floating copy that follows the cursor.
        case lifted
    }

    var course: Course
    var creditOverride: Double? = nil
    var accentColor: Color
    var isHighlighted: Bool = false
    /// Would lose a prereq or coreq if the current drag dropped here.
    var isAffected: Bool = false
    var appearance: Appearance = .normal
    var onRemove: (() -> Void)?
    /// Optional content under the title, such as a warning tag.
    var accessory: AnyView? = nil
    /// "2nd time" on a later enrollment of a course taken more than once.
    var enrollmentLabel: String? = nil

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isHoverActive: Bool { isHovering && appearance == .normal }
    private var isTinted: Bool { isHoverActive || appearance == .lifted }
    private var isLiftedMotion: Bool { appearance == .lifted && !reduceMotion }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(course.code)
                        .font(DesignTokens.Typography.bodyEmphasized)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .monospacedDigit()
                    if let enrollmentLabel {
                        Text(enrollmentLabel)
                            .font(DesignTokens.Typography.small)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text("\(CreditHoursFormatter.string(creditOverride ?? Double(course.credits))) cr")
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .monospacedDigit()
                }
                Text(course.title)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let accessory {
                    accessory.padding(.top, 3)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, DesignTokens.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(
            ZStack {
                shape.fill(DesignTokens.Colors.surfaceElevated)
                shape.fill(accentColor.opacity(isTinted ? 0.07 : 0))
            }
        )
        .clipShape(shape)
        .overlay(border)
        .overlay(alignment: .topTrailing) { removeButton }
        .opacity(appearance == .ghost ? 0.35 : 1)
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        .scaleEffect(isLiftedMotion ? 1.03 : 1)
        .rotationEffect(.degrees(isLiftedMotion ? -1.5 : 0))
        .offset(y: isHoverActive && !reduceMotion ? -1 : 0)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(DesignTokens.Motion.hover, value: isHovering)
        .animation(DesignTokens.Motion.hover, value: appearance)
        .animation(DesignTokens.Motion.hover, value: isAffected)
    }

    @ViewBuilder
    private var border: some View {
        if isAffected {
            shape.strokeBorder(DesignTokens.Colors.danger.opacity(0.45), lineWidth: 2)
        } else if isHighlighted {
            shape.strokeBorder(DesignTokens.Colors.brandPurple, lineWidth: 2)
        } else if appearance == .ghost {
            shape.strokeBorder(DesignTokens.Colors.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else {
            shape.strokeBorder(isTinted ? accentColor.opacity(0.35) : DesignTokens.Colors.borderSubtle, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var removeButton: some View {
        if isHoverActive, let onRemove {
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.danger)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(DesignTokens.Colors.surfaceElevated))
                    .overlay(Circle().strokeBorder(DesignTokens.Colors.borderSubtle, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Remove \(course.code)")
            .padding(4)
            .transition(.opacity)
        }
    }

    private var shadowColor: Color {
        switch appearance {
        case .lifted: DesignTokens.Colors.dragShadow
        case .normal: isHoverActive ? accentColor.opacity(0.45) : .clear
        case .ghost: .clear
        }
    }

    private var shadowRadius: CGFloat {
        switch appearance {
        case .lifted: 12
        case .normal: isHoverActive ? 5 : 0
        case .ghost: 0
        }
    }

    private var shadowY: CGFloat {
        switch appearance {
        case .lifted: 12
        case .normal: isHoverActive ? 3 : 0
        case .ghost: 0
        }
    }
}
