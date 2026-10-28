import SwiftUI
import PlannerCore

struct SetupStepMajor: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog
    @State private var searchText: String = ""

    private var majors: [Program] { catalog.programs.filter { $0.kind == .major } }

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }

    private var filtered: [Program] {
        guard !trimmedSearch.isEmpty else { return majors }
        return majors.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedSearch)
            || $0.college.localizedCaseInsensitiveContains(trimmedSearch)
            || $0.department.localizedCaseInsensitiveContains(trimmedSearch)
        }
        .sorted { $0.title < $1.title }
    }

    private var grouped: [(college: String, departments: [(name: String, programs: [Program])])] {
        let byCollege = Dictionary(grouping: majors, by: \.college)
        return byCollege.keys.sorted().map { college in
            let byDepartment = Dictionary(grouping: byCollege[college] ?? [], by: \.department)
            let departments = byDepartment.keys.sorted().map { name in
                (name: name, programs: (byDepartment[name] ?? []).sorted { $0.title < $1.title })
            }
            return (college: college, departments: departments)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            if let program = store.activeProgram {
                selectedCard(program)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            SetupSearchField(prompt: "Search by major, college, or department", text: $searchText)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if trimmedSearch.isEmpty {
                        browseList
                    } else {
                        searchResults
                    }
                }
                .padding(.bottom, DesignTokens.Spacing.xl)
            }
            .scrollIndicators(.automatic)
        }
        .animation(DesignTokens.Motion.step, value: store.plan.programID)
    }

    // MARK: Selected major

    private func selectedCard(_ program: Program) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignTokens.Colors.brandGoldInk)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    SetupEyebrow("Your major")
                    Text(program.title)
                        .font(DesignTokens.Typography.bodyEmphasized)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(program.college)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                programPills(program, includesConcentration: false)
            }
            if !program.concentrations.isEmpty {
                concentrationPicker(for: program)
                    .padding(.leading, 30)
            }
        }
        .padding(DesignTokens.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Colors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .strokeBorder(DesignTokens.Colors.brandPurple.opacity(0.35), lineWidth: 1)
        )
        .id(program.id)
    }

    private func concentrationPicker(for program: Program) -> some View {
        let needsChoice = program.concentrationSelectionRequired && store.plan.concentrationID == nil
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.m) {
                Text(program.concentrationSelectionRequired ? "Concentration" : "Concentration (optional)")
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Picker("Concentration", selection: Binding(
                    get: { store.plan.concentrationID ?? "" },
                    set: { id in
                        withAnimation(DesignTokens.Motion.step) {
                            store.selectConcentration(id: id.isEmpty ? nil : id)
                        }
                    }
                )) {
                    if program.concentrationSelectionRequired {
                        Text("Select concentration").tag("")
                    } else {
                        Text("Standard major / No concentration").tag("")
                    }
                    ForEach(program.concentrations) { concentration in
                        Text(concentration.name).tag(concentration.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            if needsChoice {
                Label("This major requires a concentration. Pick one to continue.", systemImage: "exclamationmark.circle")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.warning)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Lists

    @ViewBuilder
    private var browseList: some View {
        ForEach(grouped, id: \.college) { college, departments in
            let containsSelection = departments.contains { $0.programs.contains { $0.id == store.plan.programID } }
            InteractiveDisclosureGroup(initiallyExpanded: containsSelection) {
                ForEach(departments, id: \.name) { department in
                    let departmentHasSelection = department.programs.contains { $0.id == store.plan.programID }
                    InteractiveDisclosureGroup(initiallyExpanded: departmentHasSelection) {
                        ForEach(department.programs) { program in
                            programRow(program, showsCollege: false)
                        }
                    } label: {
                        groupLabel(department.name, count: department.programs.count, font: DesignTokens.Typography.label, color: DesignTokens.Colors.textSecondary)
                    }
                }
            } label: {
                groupLabel(college, count: departments.reduce(0) { $0 + $1.programs.count }, font: DesignTokens.Typography.bodyEmphasized, color: DesignTokens.Colors.textPrimary)
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = filtered
        Text(results.count == 1 ? "1 major" : "\(results.count) majors")
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.textTertiary)
            .monospacedDigit()
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.bottom, DesignTokens.Spacing.xs)
        if results.isEmpty {
            SetupNoResults(query: trimmedSearch, noun: "majors")
        }
        ForEach(results) { program in
            programRow(program, showsCollege: true)
        }
    }

    private func groupLabel(_ text: String, count: Int, font: Font, color: Color) -> some View {
        HStack {
            Text(text)
                .font(font)
                .foregroundStyle(color)
            Spacer(minLength: DesignTokens.Spacing.s)
            Text("\(count)")
                .font(DesignTokens.Typography.caption)
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    private func programRow(_ program: Program, showsCollege: Bool) -> some View {
        let isSelected = store.plan.programID == program.id
        return Button {
            withAnimation(DesignTokens.Motion.step) {
                store.selectProgram(program)
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.m) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text(program.title)
                        .font(isSelected ? DesignTokens.Typography.bodyEmphasized : DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    if showsCollege {
                        Text("\(program.department), \(program.college)")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .lineLimit(1)
                    }
                    programPills(program)
                }
                Spacer(minLength: 0)
                SetupSelectionCheck(isSelected: isSelected)
            }
        }
        .buttonStyle(SetupOptionStyle(isSelected: isSelected, chrome: .row))
    }

    private func programPills(_ program: Program, includesConcentration: Bool = true) -> some View {
        // Pills never wrap their text. When the row is too narrow for all of
        // them, the concentration pill drops to its own line instead of
        // squeezing onto two.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Spacing.s) {
                statusPills(program)
                concentrationPill(program, includesConcentration: includesConcentration)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.s) {
                    statusPills(program)
                }
                concentrationPill(program, includesConcentration: includesConcentration)
            }
        }
    }

    @ViewBuilder
    private func statusPills(_ program: Program) -> some View {
        if let degree = program.degreeType {
            StatusPill(text: degree, tone: .info)
                .fixedSize()
        }
        StatusPill(
            text: program.requirementDataComplete ? "Verified" : "Partial",
            tone: program.requirementDataComplete ? .success : .warning
        )
        .fixedSize()
    }

    @ViewBuilder
    private func concentrationPill(_ program: Program, includesConcentration: Bool) -> some View {
        if !includesConcentration {
            EmptyView()
        } else if program.concentrationSelectionRequired && !program.concentrations.isEmpty {
            StatusPill(text: "Concentration required", tone: .warning)
                .fixedSize()
        } else if !program.concentrations.isEmpty {
            StatusPill(text: "Optional concentration", tone: .info)
                .fixedSize()
        }
    }
}

/// Empty search state shared by the major and minor steps.
struct SetupNoResults: View {
    var query: String
    var noun: String

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("No \(noun) match \u{201C}\(query)\u{201D}")
                .font(DesignTokens.Typography.bodyEmphasized)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text("Try a shorter word, a department name, or a college.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.xxl)
    }
}
