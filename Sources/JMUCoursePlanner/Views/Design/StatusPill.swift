import SwiftUI

struct StatusPill: View {
    enum Tone {
        case success
        case warning
        case danger
        case info
        case neutral
    }

    var text: String
    var tone: Tone = .neutral
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(DesignTokens.Typography.small)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, DesignTokens.Spacing.s)
        .padding(.vertical, 3)
        .background(Capsule(style: .continuous).fill(background))
    }

    private var foreground: Color {
        switch tone {
        case .success: DesignTokens.Colors.success
        case .warning: DesignTokens.Colors.warning
        case .danger: DesignTokens.Colors.danger
        case .info: DesignTokens.Colors.brandPurple
        case .neutral: DesignTokens.Colors.textSecondary
        }
    }

    private var background: Color {
        switch tone {
        case .success: DesignTokens.Colors.success.opacity(0.15)
        case .warning: DesignTokens.Colors.warning.opacity(0.15)
        case .danger: DesignTokens.Colors.danger.opacity(0.15)
        case .info: DesignTokens.Colors.brandPurpleSoft
        case .neutral: DesignTokens.Colors.borderSubtle.opacity(0.5)
        }
    }
}
