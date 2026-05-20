import SwiftUI
import PlannerCore

struct CourseChip: View {
    var course: Course
    var accentColor: Color
    var isHighlighted: Bool = false
    var onTap: () -> Void = {}
    var onRemove: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
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
                if isHovering {
                    HStack(spacing: 3) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        if let onRemove {
                            Button {
                                onRemove()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(DesignTokens.Colors.danger)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(5)
                    .background(.regularMaterial, in: Capsule())
                    .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.01 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
    }
}
