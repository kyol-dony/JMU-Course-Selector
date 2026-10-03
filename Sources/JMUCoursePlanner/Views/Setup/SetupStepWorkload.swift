import SwiftUI
import PlannerCore

struct SetupStepWorkload: View {
    @EnvironmentObject private var store: PlanStore

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
                ForEach(WorkloadPreference.allCases, id: \.self) { workload in
                    workloadCard(workload)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Label("Graduating in four years takes 120 credits over 8 semesters, about 15 per semester.", systemImage: "info.circle")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }

    private func workloadCard(_ workload: WorkloadPreference) -> some View {
        let isSelected = store.plan.workload == workload
        return Button {
            withAnimation(DesignTokens.Motion.step) {
                store.setWorkload(workload)
            }
        } label: {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                HStack {
                    Text(workload.rawValue)
                        .font(DesignTokens.Typography.heading)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Spacer(minLength: 0)
                    SetupSelectionCheck(isSelected: isSelected)
                }
                Text("\(workload.creditRange.lowerBound)\u{2013}\(workload.creditRange.upperBound) credits")
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? DesignTokens.Colors.brandGoldInk : DesignTokens.Colors.textSecondary)
                CreditRangeScale(range: workload.creditRange, isSelected: isSelected)
                Text(workload.blurb)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .buttonStyle(SetupOptionStyle(isSelected: isSelected))
        .accessibilityLabel(workload.displayName)
    }
}

/// A 12 to 19 credit scale with the workload's range filled in, so the three
/// options read as positions on one ruler rather than three unrelated labels.
private struct CreditRangeScale: View {
    var range: ClosedRange<Int>
    var isSelected: Bool
    private let scale = 12...19

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(scale), id: \.self) { credit in
                Capsule()
                    .fill(range.contains(credit) ? fill : DesignTokens.Colors.borderSubtle)
                    .frame(height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private var fill: Color {
        isSelected ? DesignTokens.Colors.brandGoldInk : DesignTokens.Colors.borderStrong
    }
}

private extension WorkloadPreference {
    var blurb: String {
        switch self {
        case .light: "Room for a job, a heavy lab, or settling in. May add a semester or summer classes."
        case .standard: "The usual full-time pace. Keeps most students on track for four years."
        case .heavy: "Finish sooner or fit in a second major or minor. Expect busier weeks."
        }
    }
}
