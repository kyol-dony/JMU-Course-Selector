import SwiftUI

struct SectionHeader<Trailing: View>: View {
    var title: String
    var helper: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.heading)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let helper {
                    Text(helper)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, helper: String? = nil) {
        self.init(title: title, helper: helper, trailing: { EmptyView() })
    }
}
