import SwiftUI

/// Shared chrome for the DT button styles: hover tracking, pressed scale, and
/// a dimmed, non-hovering disabled state so a blocked action never looks live.
private struct DTButtonBody<Background: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    var configuration: ButtonStyle.Configuration
    var font: Font
    /// Given (isHovering, isPressed).
    var foreground: (Bool, Bool) -> Color
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    @ViewBuilder var background: (_ isHovering: Bool, _ isPressed: Bool) -> Background

    var body: some View {
        let hovering = isHovering && isEnabled
        configuration.label
            .font(font)
            .foregroundStyle(foreground(hovering, configuration.isPressed))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(background(hovering, configuration.isPressed))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(DesignTokens.Motion.hover, value: hovering)
            .animation(DesignTokens.Motion.press, value: configuration.isPressed)
            .animation(DesignTokens.Motion.hover, value: isEnabled)
            .onHover { isHovering = $0 }
    }
}

struct DTPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DTButtonBody(
            configuration: configuration,
            font: DesignTokens.Typography.bodyEmphasized,
            foreground: { _, _ in .white },
            horizontalPadding: DesignTokens.Spacing.l,
            verticalPadding: DesignTokens.Spacing.m
        ) { hovering, pressed in
            RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
                .fill(DesignTokens.Colors.brandPurple)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
                        .fill(Color.white.opacity(hovering && !pressed ? 0.1 : 0))
                )
                .opacity(pressed ? 0.85 : 1)
        }
    }
}

struct DTSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DTButtonBody(
            configuration: configuration,
            font: DesignTokens.Typography.bodyEmphasized,
            foreground: { _, _ in DesignTokens.Colors.textPrimary },
            horizontalPadding: DesignTokens.Spacing.l,
            verticalPadding: DesignTokens.Spacing.m
        ) { hovering, pressed in
            RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
                .fill(pressed ? DesignTokens.Colors.surface : DesignTokens.Colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
                        .stroke(hovering ? DesignTokens.Colors.borderStrong : DesignTokens.Colors.borderSubtle, lineWidth: 1)
                )
        }
    }
}

/// Text-weight action. A `.destructive` role swaps Royal Purple for Hard Stop Red.
/// Gold text and a purple hover outline match the top navigation tabs.
struct DTTertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive
        return DTButtonBody(
            configuration: configuration,
            font: DesignTokens.Typography.label,
            foreground: { hovering, pressed in
                destructive ? DesignTokens.Colors.danger
                    : DesignTokens.Colors.brandGoldInk
            },
            horizontalPadding: DesignTokens.Spacing.s,
            verticalPadding: DesignTokens.Spacing.xs
        ) { hovering, pressed in
            RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                .fill(destructive
                    ? DesignTokens.Colors.danger.opacity(pressed ? 0.15 : hovering ? 0.08 : 0)
                    : DesignTokens.Colors.surfaceElevated.opacity(pressed ? 1 : hovering ? 0.7 : 0))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                    .strokeBorder(!destructive && (hovering || pressed) ? DesignTokens.Colors.brandPurple : .clear, lineWidth: 1))
        }
    }
}

struct DTDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DTButtonBody(
            configuration: configuration,
            font: DesignTokens.Typography.bodyEmphasized,
            foreground: { _, _ in DesignTokens.Colors.danger },
            horizontalPadding: DesignTokens.Spacing.l,
            verticalPadding: DesignTokens.Spacing.m
        ) { hovering, pressed in
            RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
                .fill(DesignTokens.Colors.danger.opacity(pressed ? 0.15 : hovering ? 0.07 : 0))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
                        .stroke(DesignTokens.Colors.danger.opacity(0.5), lineWidth: 1)
                )
        }
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
