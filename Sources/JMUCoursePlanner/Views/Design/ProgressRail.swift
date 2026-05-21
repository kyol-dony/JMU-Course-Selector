import SwiftUI
import PlannerCore

struct ProgressRail: View {
    var title: String?
    var completedCredits: Int
    var requiredCredits: Int
    var remainingCourseCodes: [String]
    var hasCourseOptions: Bool
    var isVerified: Bool

    private var fraction: Double {
        guard requiredCredits > 0 else { return 1 }
        return min(Double(completedCredits) / Double(requiredCredits), 1)
    }

    private var fillColor: Color {
        isVerified ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.brandGold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            if title != nil || requiredCredits > 0 {
                HStack(alignment: .firstTextBaseline) {
                    if let title {
                        Text(title)
                            .font(DesignTokens.Typography.bodyEmphasized)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }
                    Spacer(minLength: 0)
                    Text("\(completedCredits)/\(requiredCredits)")
                        .font(DesignTokens.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.rail, style: .continuous)
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 6)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.rail, style: .continuous)
                        .fill(fillColor)
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 6 : 0), height: 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.rail, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                                .blendMode(.multiply)
                        )
                }
                .frame(height: 6)
            }
            .frame(height: 6)

            helperLine
        }
    }

    @ViewBuilder
    private var helperLine: some View {
        if fraction >= 1 {
            Label("Complete", systemImage: "checkmark.circle.fill")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.success)
        } else if !hasCourseOptions {
            Text("\(max(requiredCredits - completedCredits, 0)) credits to plan")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .monospacedDigit()
        } else if remainingCourseCodes.isEmpty {
            Text("\(max(requiredCredits - completedCredits, 0)) credits remaining")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .monospacedDigit()
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(completedCredits) of \(requiredCredits) credits -")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .monospacedDigit()
                Text(stillNeedText)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    private var stillNeedText: String {
        let visible = remainingCourseCodes.prefix(5)
        let extra = remainingCourseCodes.count - visible.count
        if extra > 0 {
            return "Still need: \(visible.joined(separator: ", ")) + \(extra) more"
        }
        return "Still need: \(visible.joined(separator: ", "))"
    }
}

extension ProgressRail {
    init(
        category: CategoryProgress,
        hasCourseOptions: Bool,
        remainingCourseCodes: [String]
    ) {
        self.init(
            title: category.name,
            completedCredits: category.completedCredits,
            requiredCredits: category.requiredCredits,
            remainingCourseCodes: remainingCourseCodes,
            hasCourseOptions: hasCourseOptions,
            isVerified: category.verificationStatus == .verified
        )
    }

    init(fraction: Double, label: String? = nil) {
        let pct = Int((min(max(fraction, 0), 1)) * 100)
        self.init(
            title: label,
            completedCredits: pct,
            requiredCredits: 100,
            remainingCourseCodes: [],
            hasCourseOptions: false,
            isVerified: true
        )
    }
}
