import SwiftUI

struct PartialRegenerationStatusView: View {
    let state: PartialRegenerationState
    let onCancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            ProgressView()
            Text("Rebuilding \(state.cutoff.next.displayName) onward").font(.headline)
            Text(state.progress.current == 0 ? "Preparing your remaining requirements…" : state.progress.pathwayName)
                .foregroundStyle(.secondary)
            Button("Cancel", action: onCancel).buttonStyle(.dtSecondary)
        }
        .padding(DesignTokens.Spacing.l)
        .frame(width: 270, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Regenerating semesters after \(state.cutoff.displayName)")
    }
}
