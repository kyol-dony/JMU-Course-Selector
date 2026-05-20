import SwiftUI
import PlannerCore

struct CatalogView: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog
    @State private var searchText: String = ""

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
        }
    }

    private var leftRail: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            TextField("Search programs", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, DesignTokens.Spacing.l)
                .padding(.top, DesignTokens.Spacing.l)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
        if let id = store.catalogSelectedProgramID, let program = catalog.programsByID[id] {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                    detailHero(program)
                    ForEach(program.requirements) { requirement in
                        requirementCard(requirement)
                    }
                }
                .padding(DesignTokens.Spacing.xl)
                .frame(maxWidth: 980, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
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

    private func detailHero(_ program: Program) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
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
                Text("\(program.college) - \(program.department)")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text(program.sourceNote)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
    }

    private func requirementCard(_ requirement: RequirementCategory) -> some View {
        Card {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                    if let note = requirement.note {
                        Text(note)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                    ForEach(requirement.courseOptions.indices, id: \.self) { index in
                        let alternatives = requirement.courseOptions[index]
                        HStack(spacing: 6) {
                            Image(systemName: "circle")
                                .font(.system(size: 9))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text(alternatives.compactMap { catalog.coursesByID[$0]?.code }.joined(separator: " or "))
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .onTapGesture {
                                    if let firstID = alternatives.first {
                                        store.showCourse(firstID)
                                    }
                                }
                        }
                    }
                }
                .padding(.top, DesignTokens.Spacing.s)
            } label: {
                ProgressRail(
                    title: requirement.name,
                    completedCredits: 0,
                    requiredCredits: requirement.requiredCredits,
                    remainingCourseCodes: requirement.courseOptions.compactMap { option in
                        option.first.flatMap { catalog.coursesByID[$0]?.code }
                    },
                    hasCourseOptions: !requirement.courseOptions.isEmpty,
                    isVerified: requirement.verificationStatus == .verified
                )
            }
        }
    }
}
