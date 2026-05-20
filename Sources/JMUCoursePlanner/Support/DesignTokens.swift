import AppKit
import SwiftUI

/// Centralized design tokens for the dashboard UI.
enum DesignTokens {
    enum Colors {
        static let surface = dynamic(light: 0xfafafa, dark: 0x0a0a0c)
        static let surfaceElevated = dynamic(light: 0xffffff, dark: 0x15151a)
        static let surfaceTinted = dynamic(light: 0xf4f0fa, dark: 0x1f1530)

        static let borderSubtle = dynamic(light: 0xe4e4e7, dark: 0x2a2a30)
        static let borderStrong = dynamic(light: 0xa1a1aa, dark: 0x52525b)

        static let textPrimary = dynamic(light: 0x0a0a0c, dark: 0xfafafa)
        static let textSecondary = dynamic(light: 0x52525b, dark: 0xa1a1aa)
        static let textTertiary = dynamic(light: 0x71717a, dark: 0x71717a)

        static let brandPurple = dynamic(light: 0x450084, dark: 0x7c3aed)
        static let brandPurpleSoft = dynamic(light: 0xf4f0fa, dark: 0x2a1840)
        static let brandGold = dynamic(light: 0xcbb677, dark: 0xb8a168)

        static let success = dynamic(light: 0x16a34a, dark: 0x22c55e)
        static let warning = dynamic(light: 0xd97706, dark: 0xf59e0b)
        static let danger = dynamic(light: 0xdc2626, dark: 0xef4444)

        static let cardShadowLight = Color.black.opacity(0.06)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Radius {
        static let pill: CGFloat = 999
        static let card: CGFloat = 12
        static let chip: CGFloat = 6
        static let rail: CGFloat = 3
    }

    enum Typography {
        static let display = Font.system(size: 28, weight: .bold)
        static let title = Font.system(size: 22, weight: .semibold)
        static let heading = Font.system(size: 18, weight: .semibold)
        static let body = Font.system(size: 14, weight: .regular)
        static let bodyEmphasized = Font.system(size: 14, weight: .semibold)
        static let label = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 12, weight: .regular)
        static let small = Font.system(size: 11, weight: .medium)
    }

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return nsColor(fromHex: isDark ? dark : light)
        }))
    }

    private static func nsColor(fromHex hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}
