import SwiftUI
import PlannerCore

struct SetupStepMajor: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog
    @State private var searchText: String = ""

    private var filtered: [Program] {
        let majors = catalog.programs.filter { $0.kind == .major }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return majors }
        return majors.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
            || $0.college.localizedCaseInsensitiveContains(trimmed)
            || $0.department.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var grouped: [(college: String, departments: [(name: String, programs: [Program])])] {
        let byCollege = Dictionary(grouping: filtered, by: \.college)
        return byCollege.keys.sorted().map { college in
            let byDepartment = Dictionary(grouping: byCollege[college] ?? [], by: \.department)
            let departments = byDepartment.keys.sorted().map { name in
                (name: name, programs: (byDepartment[name] ?? []).sorted { $0.title < $1.title })
            }
            return (college: college, departments: departments)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            SectionHeader(
                "Choose your major",
                helper: "Pick the exact program and degree type. You can change this later from the menu."
            )
            TextField("Search by major, college, or department", text: $searchText)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                    ForEach(grouped, id: \.college) { college, departments in
                        DisclosureGroup {
                            ForEach(departments, id: \.name) { department in
                                DisclosureGroup {
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
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                        }
                    }
                }
                .padding(.trailing, DesignTokens.Spacing.s)
            }
        }
    }

    private func programRow(_ program: Program) -> some View {
        let isSelected = store.plan.programID == program.id
        return Button {
            store.selectProgram(program)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(program.title)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    HStack(spacing: DesignTokens.Spacing.s) {
                        if let degree = program.degreeType {
                            StatusPill(text: degree, tone: .info)
                        }
                        StatusPill(
                            text: program.requirementDataComplete ? "Verified" : "Partial",
                            tone: program.requirementDataComplete ? .success : .warning
                        )
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DesignTokens.Colors.brandPurple)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, DesignTokens.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? DesignTokens.Colors.brandPurpleSoft : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
