import SwiftUI

struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = DesignTokens.Spacing.l
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 1)
            )
            .shadow(
                color: scheme == .light ? DesignTokens.Colors.cardShadowLight : .clear,
                radius: 2,
                x: 0,
                y: 1
            )
    }
}
