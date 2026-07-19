import SwiftUI

/// Full-screen modal shown while pathway generation runs off-main. Dims and
/// blocks the UI behind it so the app reads as "working," not frozen.
struct ScheduleGenerationOverlay: View {
    var progress: ScheduleGenerationProgress

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}

            Card {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                    Text("Generating pathways")
                        .font(DesignTokens.Typography.heading)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(subtitle)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .monospacedDigit()
                    ProgressView(value: Double(progress.current), total: Double(max(progress.total, 1)))
                        .tint(DesignTokens.Colors.brandGold)
                }
                .padding(DesignTokens.Spacing.s)
            }
            .frame(width: 360)
        }
        .transition(.opacity)
    }

    private var subtitle: String {
        if progress.current == 0 {
            return "Preparing course requirements..."
        }
        return "Building pathway \(progress.current) of \(progress.total) — \(progress.pathwayName)"
    }
}
