import SwiftUI

struct EmptyState: View {
    var systemImage: String
    var title: String
    var message: String
    var actionLabel: String?
    var action: (() -> Void)?

    init(
        systemImage: String,
        title: String,
        body message: String,
        actionLabel: String?,
        action: (() -> Void)?
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DesignTokens.Colors.brandPurple)
                .padding(.bottom, DesignTokens.Spacing.s)
            Text(title)
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.dtPrimary)
                    .padding(.top, DesignTokens.Spacing.s)
            }
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
