import SwiftUI
import PlannerCore

struct SetupStepMinor: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog
    @State private var searchText: String = ""

    private var candidates: [Program] {
        let pool = catalog.programs
            .filter { $0.kind == .minor || $0.kind == .major }
            .filter { $0.id != store.plan.programID }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return pool }
        return pool.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
            || $0.college.localizedCaseInsensitiveContains(trimmed)
            || $0.department.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            SectionHeader(
                "Add a minor or second major",
                helper: "Optional. You can come back to this later."
            )
            TextField("Search programs", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if !store.plan.minorProgramIDs.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                        Text("Currently added")
                            .font(DesignTokens.Typography.small)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .textCase(.uppercase)
                        ForEach(store.plan.minorProgramIDs, id: \.self) { id in
                            Text(catalog.programsByID[id]?.title ?? id)
                                .font(DesignTokens.Typography.body)
                        }
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(candidates.sorted { $0.title < $1.title }) { program in
                        programRow(program)
                    }
                }
            }
        }
    }

    private func programRow(_ program: Program) -> some View {
        let isAdded = store.plan.minorProgramIDs.contains(program.id)
        return Button {
            store.addMinor(program)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.title)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(program.college)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isAdded ? DesignTokens.Colors.success : DesignTokens.Colors.brandPurple)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, DesignTokens.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
    }
}
