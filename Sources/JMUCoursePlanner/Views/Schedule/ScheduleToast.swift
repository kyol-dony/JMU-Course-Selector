import SwiftUI

/// Bottom-of-board confirmation after a schedule edit, with Undo. Dismisses
/// itself after 4 seconds unless hovered; a newer change replaces it.
struct ScheduleToast: View {
    @EnvironmentObject private var store: PlanStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private struct DismissKey: Hashable {
        var changeID: UUID
        var isHovering: Bool
    }

    var body: some View {
        if let change = store.lastScheduleChange {
            let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
            HStack(spacing: DesignTokens.Spacing.m) {
                Text(Self.text(for: change))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .monospacedDigit()
                Button("Undo") { store.undoLastScheduleChange() }
                    .buttonStyle(.dtTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, DesignTokens.Spacing.s)
            .background(shape.fill(DesignTokens.Colors.surfaceElevated))
            .overlay(shape.strokeBorder(DesignTokens.Colors.borderSubtle, lineWidth: 1))
            .shadow(color: DesignTokens.Colors.cardShadowLight, radius: 8, x: 0, y: 4)
            .onHover { isHovering = $0 }
            .task(id: DismissKey(changeID: change.id, isHovering: isHovering)) {
                guard !isHovering else { return }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, store.lastScheduleChange?.id == change.id else { return }
                store.lastScheduleChange = nil
            }
            .padding(.bottom, DesignTokens.Spacing.l)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    static func text(for change: ScheduleChange) -> String {
        guard change.newWarningCount > 0 else { return change.message }
        let noun = change.newWarningCount == 1 ? "warning" : "warnings"
        return "\(change.message) · \(change.newWarningCount) new \(noun)"
    }
}
