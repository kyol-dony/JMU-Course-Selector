import SwiftUI
import PlannerCore

struct SetupStepMinor: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog
    @State private var searchText: String = ""

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }

    private var candidates: [Program] {
        let pool = catalog.programs
            .filter { $0.kind == .minor || $0.kind == .major }
            .filter { $0.id != store.plan.programID }
        guard !trimmedSearch.isEmpty else { return pool.sorted { $0.title < $1.title } }
        return pool.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedSearch)
            || $0.college.localizedCaseInsensitiveContains(trimmedSearch)
            || $0.department.localizedCaseInsensitiveContains(trimmedSearch)
        }
        .sorted { $0.title < $1.title }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            if !store.plan.minors.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                    SetupEyebrow("Added")
                    ForEach(store.plan.minors) { selection in
                        addedMinorCard(selection)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            SetupSearchField(prompt: "Search minors and majors", text: $searchText)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let results = candidates
                    if !trimmedSearch.isEmpty {
                        Text(results.count == 1 ? "1 program" : "\(results.count) programs")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .monospacedDigit()
                            .padding(.horizontal, DesignTokens.Spacing.s)
                            .padding(.bottom, DesignTokens.Spacing.xs)
                        if results.isEmpty {
                            SetupNoResults(query: trimmedSearch, noun: "programs")
                        }
                    }
                    ForEach(results) { program in
                        programRow(program)
                    }
                }
                .padding(.bottom, DesignTokens.Spacing.xl)
            }
        }
        .animation(DesignTokens.Motion.step, value: store.plan.minors)
    }

    private func addedMinorCard(_ selection: MinorSelection) -> some View {
        let program = catalog.programsByID[selection.programID]
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack(spacing: DesignTokens.Spacing.m) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(DesignTokens.Colors.brandGoldInk)
                VStack(alignment: .leading, spacing: 2) {
                    Text(program?.title ?? selection.programID)
                        .font(DesignTokens.Typography.bodyEmphasized)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    if let program {
                        Text(kindLabel(program))
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                RemoveButton(label: "Remove \(program?.title ?? selection.programID)") {
                    store.removeMinor(programID: selection.programID)
                }
            }
            if let program, !program.concentrations.isEmpty {
                concentrationPicker(for: program, selection: selection)
                    .padding(.leading, 28)
            }
        }
        .padding(DesignTokens.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Colors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .strokeBorder(DesignTokens.Colors.brandPurple.opacity(0.35), lineWidth: 1)
        )
    }

    private func concentrationPicker(for program: Program, selection: MinorSelection) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.m) {
                Text(program.concentrationSelectionRequired ? "Pathway" : "Pathway (optional)")
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Picker("Pathway", selection: Binding(
                    get: { selection.concentrationID ?? "" },
                    set: { newValue in
                        store.selectMinorConcentration(
                            minorProgramID: selection.programID,
                            concentrationID: newValue.isEmpty ? nil : newValue
                        )
                    }
                )) {
                    if program.concentrationSelectionRequired {
                        Text("Select pathway").tag("")
                    } else {
                        Text("Standard \(program.kind == .major ? "major" : "minor") / No pathway").tag("")
                    }
                    ForEach(program.concentrations) { concentration in
                        Text(concentration.name).tag(concentration.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            if program.concentrationSelectionRequired, selection.concentrationID == nil {
                Label("This program offers several pathways. Pick one so its requirements count toward your plan.", systemImage: "exclamationmark.circle")
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
            HStack(spacing: DesignTokens.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.title)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("\(kindLabel(program)), \(program.college)")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isAdded {
                    StatusPill(text: "Added", tone: .success, systemImage: "checkmark")
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else {
                    AddGlyph()
                }
            }
        }
        .buttonStyle(SetupOptionStyle(isSelected: false, chrome: .row))
        .disabled(isAdded)
        .accessibilityLabel(isAdded ? "\(program.title), added" : "Add \(program.title)")
    }

    private func kindLabel(_ program: Program) -> String {
        program.kind == .major ? "Second major" : "Minor"
    }
}

private struct AddGlyph: View {
    @Environment(\.setupOptionHighlighted) private var onPurple

    var body: some View {
        Image(systemName: "plus.circle")
            .font(.system(size: 17))
            .foregroundStyle(Color.setupAccent(onPurple: onPurple))
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}

private struct RemoveButton: View {
    var label: String
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isHovering ? DesignTokens.Colors.danger : DesignTokens.Colors.textTertiary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(isHovering ? DesignTokens.Colors.danger.opacity(0.12) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(DesignTokens.Motion.hover, value: isHovering)
        .accessibilityLabel(label)
        .help(label)
    }
}
