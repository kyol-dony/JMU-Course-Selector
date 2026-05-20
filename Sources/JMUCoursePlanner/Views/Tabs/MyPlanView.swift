import SwiftUI
import PlannerCore

struct MyPlanView: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog

    var body: some View {
        if let program = store.activeProgram {
            content(program: program)
        } else {
            EmptyState(
                systemImage: "graduationcap",
                title: "Let's build your plan",
                body: "Choose your major, add any transfer credit, pick a workload, and the planner will draft pathways you can edit.",
                actionLabel: "Start setup",
                action: { store.setupSheetPresented = true }
            )
        }
    }

    private func content(program: Program) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                hero(program: program)
                stats
                categoryBreakdown
                footerActions
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func hero(program: Program) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.s) {
                    Text(program.title)
                        .font(DesignTokens.Typography.display)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    if let degree = program.degreeType {
                        StatusPill(text: degree, tone: .info)
                    }
                    StatusPill(
                        text: program.requirementDataComplete ? "Verified" : "Partial",
                        tone: program.requirementDataComplete ? .success : .warning,
                        systemImage: program.requirementDataComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                }
                Text("\(program.college) - \(program.department)")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                if !program.requirementDataComplete {
                    Text(program.sourceNote)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.top, DesignTokens.Spacing.s)
                }
            }
        }
    }

    @ViewBuilder
    private var stats: some View {
        if let progress = store.progress {
            HStack(spacing: DesignTokens.Spacing.l) {
                completionTile(progress: progress)
                graduationTile(progress: progress)
            }
        }
    }

    private func completionTile(progress: GraduationProgress) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Text("Completion")
                .font(DesignTokens.Typography.small)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .textCase(.uppercase)
            Text("\(Int(progress.overallFraction * 100))%")
                .font(.system(size: 44, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Colors.brandPurple)
            ProgressRail(fraction: progress.overallFraction)
            Text("\(progress.overallCompletedCredits) of \(progress.overallRequiredCredits) credits")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .monospacedDigit()
        }
        .padding(DesignTokens.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [DesignTokens.Colors.brandPurpleSoft, DesignTokens.Colors.surfaceElevated],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 1)
        )
    }

    private func graduationTile(progress: GraduationProgress) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                Text("Projected graduation")
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                Text(progress.projectedGraduation?.displayName ?? "-")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(semestersAwayText(progress: progress))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func semestersAwayText(progress: GraduationProgress) -> String {
        guard let target = progress.projectedGraduation else { return "Generate a pathway to project a date" }
        let currentYear = Calendar.current.component(.year, from: Date())
        let monthsAway = max((target.year - currentYear) * 12, 0)
        let semesters = max(monthsAway / 6, 1)
        return "About \(semesters) semester\(semesters == 1 ? "" : "s") from now"
    }

    @ViewBuilder
    private var categoryBreakdown: some View {
        if let progress = store.progress, let program = store.activeProgram {
            let lookup = Dictionary(uniqueKeysWithValues: program.requirements.map { ($0.id, $0) })
            Card {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                    SectionHeader("Requirement progress")
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                        ForEach(progress.categories) { category in
                            let requirement = lookup[category.id]
                            Button {
                                store.scheduleCategoryFilter = category.id
                                withAnimation(.easeOut(duration: 0.15)) {
                                    store.selectedTab = .schedule
                                }
                            } label: {
                                ProgressRail(
                                    category: category,
                                    hasCourseOptions: !(requirement?.courseOptions.isEmpty ?? true),
                                    remainingCourseCodes: remainingCodes(for: requirement)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func remainingCodes(for category: RequirementCategory?) -> [String] {
        guard let category else { return [] }
        return store.remainingCourses(in: category)
    }

    private var footerActions: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Button("Edit setup") { store.setupSheetPresented = true }
                .buttonStyle(.dtSecondary)
            Button("Regenerate pathways") { store.generateSchedules() }
                .buttonStyle(.dtTertiary)
            Spacer()
        }
    }
}
