import SwiftUI
import PlannerCore

struct CatalogView: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog
    @State private var searchText: String = ""
    @State private var selectedEntryID: String?
    @State private var concentrationID: String?

    private var filteredPrograms: [Program] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return catalog.programs }
        return catalog.programs.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
            || $0.college.localizedCaseInsensitiveContains(trimmed)
            || $0.department.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var grouped: [(college: String, departments: [(name: String, programs: [Program])])] {
        let byCollege = Dictionary(grouping: filteredPrograms, by: \.college)
        return byCollege.keys.sorted().map { college in
            let byDepartment = Dictionary(grouping: byCollege[college] ?? [], by: \.department)
            let departments = byDepartment.keys.sorted().map { name in
                (name: name, programs: (byDepartment[name] ?? []).sorted { $0.title < $1.title })
            }
            return (college: college, departments: departments)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            leftRail
            Divider()
            detail
        }
        .onAppear {
            if store.catalogSelectedProgramID == nil {
                store.catalogSelectedProgramID = store.plan.programID ?? catalog.programs.first?.id
            }
            resetSelection()
        }
        .onChange(of: store.catalogSelectedProgramID) { _, _ in resetSelection() }
        .onChange(of: concentrationID) { _, _ in
            guard let outline = selectedProgram.map({ CatalogOutline(program: $0, concentrationID: concentrationID) }) else { return }
            if !outline.sections.contains(where: { $0.entries.contains { $0.id == selectedEntryID } }) {
                selectedEntryID = outline.firstEntryID
            }
        }
    }

    private var selectedProgram: Program? {
        store.catalogSelectedProgramID.flatMap { catalog.programsByID[$0] }
    }

    /// A newly chosen program starts on its default concentration and its
    /// first requirement.
    private func resetSelection() {
        guard let program = selectedProgram else {
            concentrationID = nil
            selectedEntryID = nil
            return
        }
        concentrationID = CatalogOutline.defaultConcentrationID(for: program)
        selectedEntryID = CatalogOutline(program: program, concentrationID: concentrationID).firstEntryID
    }

    private var leftRail: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            TextField("Search programs", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, DesignTokens.Spacing.l)
                .padding(.top, DesignTokens.Spacing.l)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(grouped, id: \.college) { college, departments in
                        InteractiveDisclosureGroup {
                            ForEach(departments, id: \.name) { department in
                                InteractiveDisclosureGroup {
                                    ForEach(department.programs) { program in
                                        programRow(program)
                                    }
                                } label: {
                                    Text(department.name)
                                        .font(DesignTokens.Typography.label)
                                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                                }
                            }
                        } label: {
                            Text(college)
                                .font(DesignTokens.Typography.bodyEmphasized)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.l)
            }
        }
        .frame(width: 320)
        .background(DesignTokens.Colors.surface)
    }

    private func programRow(_ program: Program) -> some View {
        let isSelected = store.catalogSelectedProgramID == program.id
        return Button {
            store.catalogSelectedProgramID = program.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.title)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(program.department)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                Spacer(minLength: 0)
                if !program.requirementDataComplete {
                    Circle()
                        .fill(DesignTokens.Colors.warning)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, DesignTokens.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? DesignTokens.Colors.brandPurpleSoft : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        if let program = selectedProgram {
            let outline = CatalogOutline(program: program, concentrationID: concentrationID)
            VStack(alignment: .leading, spacing: 0) {
                programHeader(program)
                Divider()
                HStack(spacing: 0) {
                    RequirementIndexView(
                        program: program,
                        outline: outline,
                        concentrationID: $concentrationID,
                        selectedEntryID: $selectedEntryID
                    )
                    Divider()
                    if let entry = outline.sections.lazy.flatMap(\.entries).first(where: { $0.id == selectedEntryID }) {
                        RequirementDetailView(entry: entry, catalog: catalog, slotMap: slotMap(for: program))
                    } else {
                        EmptyState(
                            systemImage: "list.bullet.rectangle",
                            title: "No requirements listed",
                            body: "The catalog page for this program didn't list requirements the app could read.",
                            actionLabel: nil,
                            action: nil
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyState(
                systemImage: "book.closed",
                title: "Browse JMU programs",
                body: "Pick a program from the list to see its requirement breakdown.",
                actionLabel: nil,
                action: nil
            )
        }
    }

    private func programHeader(_ program: Program) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.s) {
                Text(program.title)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let degree = program.degreeType {
                    StatusPill(text: degree, tone: .info)
                }
                StatusPill(
                    text: program.requirementDataComplete ? "Verified" : "Partial",
                    tone: program.requirementDataComplete ? .success : .warning
                )
            }
            Text(([program.college, program.department] + (program.totalCredits.map { ["\($0) credits"] } ?? [])).joined(separator: " · "))
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.l)
    }

    /// One subject color per subject across the whole program, so a subject
    /// keeps its color from requirement to requirement.
    private func slotMap(for program: Program) -> [String: Int] {
        let categories = program.requirements + program.concentrations.flatMap(\.requirements)
        let codes = categories.flatMap { $0.choices.flatMap { $0 } + $0.courseOptions.flatMap { $0 } }
            .map { catalog.coursesByID[$0]?.code ?? $0 }
        return CourseClassificationPalette.slotMap(for: codes.map(CourseClassificationPalette.classification(forCode:)))
    }
}
