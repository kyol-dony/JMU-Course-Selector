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
                helper: "Optional. Pick a pathway for any minor that offers tracks or options."
            )
            TextField("Search programs", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if !store.plan.minors.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                        Text("Currently added")
                            .font(DesignTokens.Typography.small)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .textCase(.uppercase)
                        ForEach(store.plan.minors) { selection in
                            addedMinorRow(selection)
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

    @ViewBuilder
    private func addedMinorRow(_ selection: MinorSelection) -> some View {
        let program = catalog.programsByID[selection.programID]
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.s) {
                Text(program?.title ?? selection.programID)
                    .font(DesignTokens.Typography.body)
                Spacer(minLength: 0)
                Button {
                    store.removeMinor(programID: selection.programID)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(DesignTokens.Colors.danger)
                }
                .buttonStyle(.plain)
            }
            if let program, !program.concentrations.isEmpty {
                concentrationPicker(for: program, selection: selection)
            }
        }
        .padding(.vertical, 4)
    }

    private func concentrationPicker(for program: Program, selection: MinorSelection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pathway")
                .font(DesignTokens.Typography.small)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .textCase(.uppercase)
            Picker("Pathway", selection: Binding(
                get: { selection.concentrationID ?? "" },
                set: { newValue in
                    store.selectMinorConcentration(
                        minorProgramID: selection.programID,
                        concentrationID: newValue.isEmpty ? nil : newValue
                    )
                }
            )) {
                Text("Select pathway").tag("")
                ForEach(program.concentrations) { concentration in
                    Text(concentration.name).tag(concentration.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            if selection.concentrationID == nil {
                Text("This minor offers multiple pathways. Pick one so its requirements count toward your plan.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.warning)
            }
        }
    }

    private func programRow(_ program: Program) -> some View {
        let isAdded = store.plan.minors.contains { $0.programID == program.id }
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
