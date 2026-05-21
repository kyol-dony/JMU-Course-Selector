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
                Text("\(program.college) · \(program.department)")
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
            HStack(alignment: .top, spacing: DesignTokens.Spacing.l) {
                completionTile(progress: progress)
                graduationTile(progress: progress)
            }
        }
    }

    private func completionTile(progress: GraduationProgress) -> some View {
        let pct = Int(progress.overallFraction * 100)
        let fraction = min(max(progress.overallFraction, 0), 1)
        let remaining = max(progress.overallRequiredCredits - progress.overallCompletedCredits, 0)
        return Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("Completion")
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                    .padding(.bottom, DesignTokens.Spacing.xs)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(pct)")
                        .font(DesignTokens.Typography.display)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Colors.brandPurple)
                    Text("%")
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(DesignTokens.Colors.brandPurple.opacity(0.6))
                }
                .padding(.bottom, DesignTokens.Spacing.s)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.rail, style: .continuous)
                        .fill(DesignTokens.Colors.borderSubtle)
                        .frame(height: 6)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.rail, style: .continuous)
                            .fill(DesignTokens.Colors.brandGold)
                            .frame(width: max(geo.size.width * fraction, fraction > 0 ? 6 : 0), height: 6)
                    }
                    .frame(height: 6)
                }
                .frame(height: 6)
                .padding(.bottom, DesignTokens.Spacing.s)
                Text(
                    remaining == 0
                        ? "\(progress.overallCompletedCredits) of \(progress.overallRequiredCredits) credits planned"
                        : "\(progress.overallCompletedCredits) of \(progress.overallRequiredCredits) credits planned · \(remaining) to go"
                )
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func graduationTile(progress: GraduationProgress) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("Projected graduation")
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                    .padding(.bottom, DesignTokens.Spacing.xs)
                Text(progress.projectedGraduation?.displayName ?? "Not yet")
                    .font(DesignTokens.Typography.display)
                    .monospacedDigit()
                    .foregroundStyle(
                        progress.projectedGraduation == nil
                            ? DesignTokens.Colors.textTertiary
                            : DesignTokens.Colors.textPrimary
                    )
                    .padding(.bottom, DesignTokens.Spacing.s + 6 + DesignTokens.Spacing.s)
                Text(semestersAwayText(progress: progress))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            let requirementProgram = store.effectiveActiveProgram ?? program
            let lookup = Dictionary(
                requirementProgram.requirements.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            Card {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                    SectionHeader("Requirement progress")
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                        ForEach(progress.categories) { category in
                            let requirement = lookup[category.id]
                            requirementProgressRow(category: category, requirement: requirement)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func requirementProgressRow(category: CategoryProgress, requirement: RequirementCategory?) -> some View {
        RequirementProgressRow(
            category: category,
            requirement: requirement,
            remainingCourseCodes: remainingCodes(for: requirement),
            onTap: {
                store.scheduleCategoryFilter = category.id
                withAnimation(.easeOut(duration: 0.15)) {
                    store.selectedTab = .schedule
                }
            }
        )
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

private struct RequirementProgressRow: View {
    var category: CategoryProgress
    var requirement: RequirementCategory?
    var remainingCourseCodes: [String]
    var onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            ProgressRail(
                category: category,
                hasCourseOptions: !(requirement?.courseOptions.isEmpty ?? true),
                remainingCourseCodes: remainingCourseCodes
            )
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                    .fill(isHovering ? DesignTokens.Colors.brandPurpleSoft : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}
