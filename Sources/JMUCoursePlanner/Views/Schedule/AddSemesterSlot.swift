import PlannerCore
import SwiftUI

/// Dashed "add a semester" target: a column after the last semester, or a
/// slim strip between two semesters where terms are missing.
struct AddSemesterSlot: View {
    enum Style {
        /// After the last semester.
        case column
        /// Between two semesters, refilling a skipped term.
        case strip
    }

    var semester: SemesterIdentity
    var style: Style
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(DesignTokens.Colors.brandPurple)
                .frame(width: style == .column ? 150 : 32)
                .frame(minHeight: 540)
                .background(shape.fill(DesignTokens.Colors.brandPurple.opacity(isHovering ? 0.06 : 0)))
                .overlay(
                    shape.strokeBorder(
                        DesignTokens.Colors.brandPurple.opacity(isHovering ? 0.7 : 0.4),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                )
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(DesignTokens.Motion.hover, value: isHovering)
        .help("Add \(semester.displayName)")
        .accessibilityLabel("Add \(semester.displayName)")
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: style == .column ? DesignTokens.Radius.card : DesignTokens.Radius.button,
            style: .continuous
        )
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .column:
            VStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18, weight: .medium))
                Text("Add \(semester.displayName)")
                    .font(DesignTokens.Typography.label)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
        case .strip:
            VStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                // Rotated so the term fits a 32pt strip; the frame is the
                // rotated footprint, not the text's natural width.
                Text(semester.displayName)
                    .font(DesignTokens.Typography.small)
                    .fixedSize()
                    .frame(width: 16, height: 90)
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}
