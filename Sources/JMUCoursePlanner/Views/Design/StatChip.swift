import SwiftUI

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
            Text(value)
                .font(DesignTokens.Typography.bodyEmphasized)
                .monospacedDigit()
                .foregroundStyle(emphasized ? DesignTokens.Colors.brandGold : DesignTokens.Colors.textPrimary)
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
