import SwiftUI

struct SetupStepYear: View {
    var selection: StudentYear?
    var onSelect: (StudentYear) -> Void

    private let continuing: [StudentYear] = [.enrolledFreshman, .sophomore, .junior, .senior, .fifthYearOrBeyond]
    private let columns = [
        GridItem(.flexible(), spacing: DesignTokens.Spacing.m),
        GridItem(.flexible(), spacing: DesignTokens.Spacing.m)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                SetupEyebrow("New to JMU")
                card(.incomingFreshman)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                SetupEyebrow("Already at JMU")
                LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.m) {
                    ForEach(continuing, id: \.self) { year in
                        card(year)
                    }
                }
                Text("Next you'll import your unofficial transcript, so finished and current courses are already in place.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding(.top, DesignTokens.Spacing.xs)
            }
        }
    }

    private func card(_ year: StudentYear) -> some View {
        let isSelected = selection == year
        return Button { onSelect(year) } label: {
            HStack(spacing: DesignTokens.Spacing.m) {
                Text(year.badge)
                    .font(.system(size: year == .incomingFreshman ? 11 : 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? DesignTokens.Colors.brandGold : DesignTokens.Colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
                            .fill(isSelected ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
                            .strokeBorder(isSelected ? .clear : DesignTokens.Colors.borderSubtle, lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(year.summaryTitle)
                        .font(DesignTokens.Typography.bodyEmphasized)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(year.subtitle)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                SetupSelectionCheck(isSelected: isSelected)
            }
        }
        .buttonStyle(SetupOptionStyle(isSelected: isSelected))
        .accessibilityLabel(year.rawValue)
    }
}

private extension StudentYear {
    var badge: String {
        switch self {
        case .incomingFreshman: "NEW"
        case .enrolledFreshman: "1"
        case .sophomore: "2"
        case .junior: "3"
        case .senior: "4"
        case .fifthYearOrBeyond: "5+"
        }
    }

    var subtitle: String {
        switch self {
        case .incomingFreshman: "Starting your first JMU semester soon. Start from a blank plan and add any AP or dual enrollment credit."
        case .enrolledFreshman: "In your first year now"
        case .sophomore: "In your second year"
        case .junior: "In your third year"
        case .senior: "In your fourth year"
        case .fifthYearOrBeyond: "Fifth year or later"
        }
    }
}
