import SwiftUI
import PlannerCore

struct GraduationProgressView: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog

    var body: some View {
        if let progress = store.progress, let program = store.activeProgram {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                    donut(progress: progress)
                    categoryList(progress: progress, program: store.effectiveActiveProgram ?? program)
                }
                .padding(DesignTokens.Spacing.xl)
                .frame(maxWidth: 980, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        } else {
            EmptyState(
                systemImage: "chart.bar.xaxis",
                title: "No progress to show",
                body: "Generate a pathway from setup to see live graduation tracking.",
                actionLabel: "Open setup",
                action: { store.setupSheetPresented = true }
            )
        }
    }

    private func donut(progress: GraduationProgress) -> some View {
        Card {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.xl) {
                ZStack {
                    Circle()
                        .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: CGFloat(progress.overallFraction))
                        .stroke(
                            DesignTokens.Colors.brandPurple,
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int(progress.overallFraction * 100))%")
                            .font(.system(size: 36, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(DesignTokens.Colors.brandPurple)
                        Text("complete")
                            .font(DesignTokens.Typography.small)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
                .frame(width: 180, height: 180)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                    Text("Graduation tracker")
                        .font(DesignTokens.Typography.heading)
                    Text("\(progress.overallCompletedCredits) of \(progress.overallRequiredCredits) credits planned")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .monospacedDigit()
                    if let target = progress.projectedGraduation {
                        Text("Projected: \(target.displayName)")
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func categoryList(progress: GraduationProgress, program: Program) -> some View {
        // Defensive uniquing: requirement IDs SHOULD be unique within a program
        // but parser regressions or appended Gen Ed clusters could collide;
        // keep the first occurrence rather than crashing the whole tab.
        let requirementsByID = Dictionary(
            program.requirements.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            SectionHeader("By category")
            ForEach(progress.categories) { category in
                let requirement = requirementsByID[category.id]
                let hasOptions = !(requirement?.courseOptions.isEmpty ?? true)
                Card {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(category.name)
                                .font(DesignTokens.Typography.bodyEmphasized)
                            if category.verificationStatus != .verified {
                                StatusPill(text: "Partial", tone: .warning)
                            }
                            Spacer()
                        }
                        ProgressRail(
                            category: category,
                            hasCourseOptions: hasOptions,
                            remainingCourseCodes: remainingCodes(for: requirement, fallback: category)
                        )
                        if let note = requirement?.note, !hasOptions {
                            Text(note)
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                        contributionList(for: requirement)
                    }
                }
            }
        }
    }

    private func remainingCodes(for requirement: RequirementCategory?, fallback: CategoryProgress) -> [String] {
        if let requirement {
            if let key = store.majorRequirementSelectionKey(for: requirement) {
                return store.remainingCourses(in: requirement, selectionKey: key)
            }
            return store.remainingCourses(in: requirement)
        }
        let fallbackRequirement = RequirementCategory(
            id: fallback.id,
            name: fallback.name,
            requiredCredits: fallback.requiredCredits,
            courseOptions: []
        )
        if let key = store.majorRequirementSelectionKey(for: fallbackRequirement) {
            return store.remainingCourses(in: fallbackRequirement, selectionKey: key)
        }
        return store.remainingCourses(in: fallbackRequirement)
    }

    @ViewBuilder
    private func contributionList(for requirement: RequirementCategory?) -> some View {
        let rows = contributions(for: requirement)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Contributing courses")
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                ForEach(rows) { row in
                    HStack {
                        Text(row.code)
                            .font(DesignTokens.Typography.caption)
                            .monospacedDigit()
                        Spacer()
                        StatusPill(text: row.source, tone: row.isTransfer ? .info : .neutral)
                    }
                }
            }
        }
    }

    private func contributions(for requirement: RequirementCategory?) -> [CourseContribution] {
        guard let requirement else { return [] }
        let transferIDs = Set(store.plan.transferCredits.flatMap(\.courseIDs))
        // If a course shows up in more than one semester of the pathway (e.g.,
        // after a manual drag that introduced a duplicate), keep the earliest
        // placement rather than crashing with a duplicate-key precondition.
        let scheduled = Dictionary(
            (store.activePathway?.semesters ?? [])
                .sorted { $0.id < $1.id }
                .flatMap { semester in semester.courseIDs.map { ($0, semester.id.displayName) } },
            uniquingKeysWith: { first, _ in first }
        )
        return requirement.courseOptions.compactMap { option in
            if let transferID = option.first(where: transferIDs.contains),
               let course = catalog.coursesByID[transferID] {
                return CourseContribution(code: course.code, source: "Transfer", isTransfer: true)
            }
            if let scheduledID = option.first(where: { scheduled[$0] != nil }),
               let course = catalog.coursesByID[scheduledID],
               let semester = scheduled[scheduledID] {
                return CourseContribution(code: course.code, source: semester, isTransfer: false)
            }
            return nil
        }
    }
}

private struct CourseContribution: Identifiable {
    var id: String { "\(code)-\(source)" }
    var code: String
    var source: String
    var isTransfer: Bool
}
