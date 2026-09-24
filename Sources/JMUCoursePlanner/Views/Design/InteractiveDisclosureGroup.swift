import SwiftUI

/// Disclosure row with a full-width hit target. Native macOS disclosure groups
/// only toggle reliably from the chevron, which makes text labels feel inert.
struct InteractiveDisclosureGroup<Label: View, Content: View>: View {
    @State private var isExpanded = false
    @State private var isHovering = false

    private let contentIndent: CGFloat
    private let label: () -> Label
    private let content: () -> Content

    init(
        contentIndent: CGFloat = DesignTokens.Spacing.l,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.contentIndent = contentIndent
        self.content = content
        self.label = label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? DesignTokens.Spacing.xs : 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.s) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    label()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DesignTokens.Spacing.s)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                        .fill(isHovering ? DesignTokens.Colors.brandPurpleSoft : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }

            if isExpanded {
                content()
                    .padding(.leading, contentIndent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
