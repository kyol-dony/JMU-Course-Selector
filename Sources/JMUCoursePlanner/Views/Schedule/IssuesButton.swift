import PlannerCore
import SwiftUI

/// Toolbar summary of the pathway's warnings. Opens a list grouped by
/// severity; choosing a row jumps to it on the board.
struct IssuesButton: View {
    var issues: ScheduleIssues
    var catalog: Catalog
    /// The pathway's placeholder definitions, so a placeholder's issue reads
    /// as its requirement rather than its internal ID.
    var placeholders: [String: PlaceholderSpec] = [:]
    var onSelect: (ConflictWarning) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: issues.worstActive == nil ? "checkmark" : "exclamationmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(tint))
                Text(issues.buttonTitle)
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.08)))
            .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(issues.buttonTitle)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { list }
    }

    private var tint: Color {
        switch issues.worstActive {
        case .mustFix: DesignTokens.Colors.danger
        case .worthALook: DesignTokens.Colors.warning
        case .hidden, nil: DesignTokens.Colors.success
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if issues.activeCount == 0 {
                    Text("Nothing needs attention.")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .padding(DesignTokens.Spacing.s)
                }
                group("Must fix", issues.mustFix)
                group("Worth a look", issues.worthALook)
                if !issues.kept.isEmpty {
                    InteractiveDisclosureGroup(contentIndent: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(issues.kept) { row($0) }
                        }
                    } label: {
                        Text("Kept (\(issues.kept.count))")
                            .font(DesignTokens.Typography.label)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            }
            .padding(DesignTokens.Spacing.s)
        }
        .frame(width: 320)
        .frame(maxHeight: 420)
    }

    @ViewBuilder
    private func group(_ title: String, _ warnings: [ConflictWarning]) -> some View {
        if !warnings.isEmpty {
            HStack {
                Text(title.uppercased())
                    .font(DesignTokens.Typography.small)
                    .tracking(0.44)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer()
                Text("\(warnings.count)")
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.top, DesignTokens.Spacing.s)
            .padding(.bottom, 2)
            ForEach(warnings) { row($0) }
        }
    }

    private func row(_ warning: ConflictWarning) -> some View {
        Button {
            isPresented = false
            onSelect(warning)
        } label: {
            HStack(spacing: DesignTokens.Spacing.s) {
                Circle()
                    .fill(color(for: warning))
                    .frame(width: 8, height: 8)
                Text(subject(for: warning))
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 84, alignment: .leading)
                Text(warning.summary)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: DesignTokens.Spacing.s)
                if !warning.isSemesterLevel {
                    Text(warning.semester.displayName)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(subject(for: warning)): \(warning.summary), \(warning.semester.displayName)")
    }

    private func subject(for warning: ConflictWarning) -> String {
        if warning.isSemesterLevel { return warning.semester.displayName }
        if let repeated = placeholders[warning.courseID]?.repeatOf {
            return catalog.coursesByID[repeated]?.code ?? repeated
        }
        if PathwayPlaceholder.isPlaceholder(warning.courseID) {
            return placeholders[warning.courseID]?.categoryName ?? "Placeholder"
        }
        return catalog.coursesByID[warning.courseID]?.code ?? warning.courseID
    }

    private func color(for warning: ConflictWarning) -> Color {
        if warning.isOverridden { return DesignTokens.Colors.borderStrong }
        return warning.kind.severity == .mustFix ? DesignTokens.Colors.danger : DesignTokens.Colors.warning
    }
}
