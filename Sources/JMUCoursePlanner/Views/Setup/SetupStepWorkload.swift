import SwiftUI
import PlannerCore

struct SetupStepWorkload: View {
    @EnvironmentObject private var store: PlanStore

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            SectionHeader(
                "Workload preference",
                helper: "The generator stays inside this range while respecting prerequisites and semester availability."
            )
            VStack(spacing: DesignTokens.Spacing.m) {
                ForEach(WorkloadPreference.allCases, id: \.self) { workload in
                    workloadRow(workload)
                }
            }
        }
    }

    private func workloadRow(_ workload: WorkloadPreference) -> some View {
        let isSelected = store.plan.workload == workload
        return Button {
            store.setWorkload(workload)
        } label: {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? DesignTokens.Colors.brandGold : DesignTokens.Colors.borderStrong)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text(workload.rawValue)
                        .font(DesignTokens.Typography.bodyEmphasized)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(workload.displayName)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(DesignTokens.Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(isSelected ? DesignTokens.Colors.brandPurpleSoft : DesignTokens.Colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .stroke(
                        isSelected ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.borderSubtle,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
