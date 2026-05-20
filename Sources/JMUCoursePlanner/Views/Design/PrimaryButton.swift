import SwiftUI

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
