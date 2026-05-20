import SwiftUI
import PlannerCore

struct SetupSheet: View {
    @EnvironmentObject private var store: PlanStore
    @Environment(\.dismiss) private var dismiss
    var catalog: Catalog
    @State private var step: Int = 0

    private let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            stepContent
                .padding(DesignTokens.Spacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider().opacity(0.5)
            footer
        }
        .frame(minWidth: 640, minHeight: 560)
        .background(DesignTokens.Colors.surface)
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.m) {
            Text("Build your plan")
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Circle()
                        .fill(index <= step ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.borderSubtle)
                        .frame(width: 8, height: 8)
                }
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.l)
    }

    private var stepContent: some View {
        ScrollView {
            Group {
                switch step {
                case 0: SetupStepMajor(catalog: catalog)
                case 1: SetupStepMinor(catalog: catalog)
                case 2: SetupStepTransfer(catalog: catalog)
                default: SetupStepWorkload()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            Button("Back") {
                if step > 0 { step -= 1 }
            }
            .buttonStyle(.dtSecondary)
            .disabled(step == 0)

            Spacer()

            if step == 1 || step == 2 {
                Button("Skip") {
                    advance()
                }
                .buttonStyle(.dtTertiary)
            }

            if step < stepCount - 1 {
                Button("Next") {
                    advance()
                }
                .buttonStyle(.dtPrimary)
                .disabled(step == 0 && !store.majorSelectionComplete)
            } else {
                Button("Generate Plan") {
                    store.generateSchedules()
                    if store.errorMessage == nil {
                        dismiss()
                    }
                }
                .buttonStyle(.dtPrimary)
                .disabled(!store.majorSelectionComplete)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.l)
    }

    private func advance() {
        if step < stepCount - 1 {
            step += 1
        }
    }
}
