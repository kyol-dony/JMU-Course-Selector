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
                hero(program: program, badge: nil, concentrationName: store.activeConcentration?.name)
                ForEach(secondaryHeroEntries(), id: \.program.id) { entry in
                    hero(program: entry.program, badge: entry.badge, concentrationName: entry.concentrationName)
                }
                stats
                categoryBreakdown
                footerActions
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private struct SecondaryHeroEntry {
        var program: Program
        var badge: String
        var concentrationName: String?
    }

    /// Build a hero entry per added minor / second major. Uses the raw catalog
    /// program (not the gen-ed-stripped effective form) so the title/college
    /// match what the user picked in setup, and surfaces the picked
    /// concentration name if any.
    private func secondaryHeroEntries() -> [SecondaryHeroEntry] {
        store.plan.minors.compactMap { selection -> SecondaryHeroEntry? in
            guard let program = catalog.programsByID[selection.programID] else { return nil }
            let badge = program.kind == .major ? "Second major" : "Minor"
            let concentrationName = selection.concentrationID.flatMap { id in
                program.concentrations.first(where: { $0.id == id })?.name
            }
            return SecondaryHeroEntry(program: program, badge: badge, concentrationName: concentrationName)
        }
    }

    private func hero(program: Program, badge: String?, concentrationName: String?) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.s) {
                    Text(program.title)
                        .font(DesignTokens.Typography.display)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    if let badge {
                        StatusPill(text: badge, tone: .info)
                    }
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
                if let concentrationName {
                    Text("Concentration: \(concentrationName)")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
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
            HStack(alignment: .center, spacing: DesignTokens.Spacing.m) {
                ZStack {
                    Circle()
                        .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: CGFloat(fraction))
                        .stroke(
                            DesignTokens.Colors.brandGold,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(pct)%")
                            .font(DesignTokens.Typography.title)
                            .monospacedDigit()
                            .foregroundStyle(DesignTokens.Colors.brandPurple)
                        Text("complete")
                            .font(DesignTokens.Typography.small)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
                .frame(width: 90, height: 90)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Completion")
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .textCase(.uppercase)
                    Text("\(progress.overallCompletedCredits) of \(progress.overallRequiredCredits) credits")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .monospacedDigit()
                    if remaining > 0 {
                        Text("\(remaining) credits to go")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func graduationTile(progress: GraduationProgress) -> some View {
        let upcoming = nextUpcomingSemester()
        return Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                Text("Projected graduation")
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                Text(progress.projectedGraduation?.displayName ?? "Not yet")
                    .font(DesignTokens.Typography.display)
                    .monospacedDigit()
                    .foregroundStyle(
                        progress.projectedGraduation == nil
                            ? DesignTokens.Colors.textTertiary
                            : DesignTokens.Colors.textPrimary
                    )
                Text(semestersAwayText(progress: progress))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .monospacedDigit()
                nextTermButton(upcoming)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func nextUpcomingSemester() -> SemesterPlan? {
        guard let semesters = store.activePathway?.semesters else { return nil }
        let month = Calendar.current.component(.month, from: Date())
        let year = Calendar.current.component(.year, from: Date())
        let currentTerm: SemesterTerm = month >= 7 ? .fall : .spring
        let nowID = SemesterIdentity(year: year, term: currentTerm)
        return semesters.sorted { $0.id < $1.id }.first { $0.id >= nowID }
    }

    @ViewBuilder
    private func nextTermButton(_ semester: SemesterPlan?) -> some View {
        if let semester {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    store.selectedTab = .schedule
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next term")
                            .font(DesignTokens.Typography.small)
                            .foregroundStyle(DesignTokens.Colors.brandGold.opacity(0.75))
                            .textCase(.uppercase)
                        Text("\(semester.id.displayName) · \(semester.courseIDs.count) course\(semester.courseIDs.count == 1 ? "" : "s")")
                            .font(DesignTokens.Typography.bodyEmphasized)
                            .foregroundStyle(DesignTokens.Colors.brandGold)
                            .monospacedDigit()
                    }
                    Spacer(minLength: DesignTokens.Spacing.s)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.brandGold)
                }
                .padding(.horizontal, DesignTokens.Spacing.m)
                .padding(.vertical, DesignTokens.Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                        .fill(DesignTokens.Colors.brandPurpleSoft)
                )
            }
            .buttonStyle(.plain)
        }
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
            let lookup = requirementLookup(primary: requirementProgram)
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

    /// Mirror ProgressCalculator's "{programID}::{categoryID}" prefix for
    /// second-major / minor categories so their requirement lookup resolves
    /// and the schedule-filter tap targets the right id.
    private func requirementLookup(primary: Program) -> [String: RequirementCategory] {
        var pairs: [(String, RequirementCategory)] = primary.requirements.map { ($0.id, $0) }
        for extra in store.selectedMinorPrograms() {
            for category in extra.requirements {
                pairs.append(("\(extra.id)::\(category.id)", category))
            }
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    private func remainingCodes(for category: RequirementCategory?) -> [String] {
        guard let category else { return [] }
        return store.remainingCourses(in: category)
    }

    @ViewBuilder
    private func contributionList(rows: [MyPlanCourseContribution]) -> some View {
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

    /// Walk the pathway's `resolvedPlaceholders` map for entries whose key
    /// matches an Open Elective slot.
    private func openElectiveContributions() -> [MyPlanCourseContribution] {
        guard let pathway = store.activePathway else { return [] }
        let openElectivePrefix = PathwayPlaceholder.id(
            categoryID: ScheduleGenerator.openElectiveCategoryID,
            optionIndex: 0
        ).split(separator: "::").dropLast().joined(separator: "::") + "::"
        let scheduled = Dictionary(
            pathway.semesters
                .sorted { $0.id < $1.id }
                .flatMap { semester in semester.courseIDs.map { ($0, semester.id.displayName) } },
            uniquingKeysWith: { first, _ in first }
        )
        return pathway.resolvedPlaceholders.compactMap { placeholderID, courseID in
            guard placeholderID.hasPrefix(openElectivePrefix) else { return nil }
            guard let course = catalog.coursesByID[courseID] else { return nil }
            let source = scheduled[courseID] ?? "Scheduled"
            return MyPlanCourseContribution(code: course.code, source: source, isTransfer: false)
        }
        .sorted { $0.code < $1.code }
    }

    private func contributions(for requirement: RequirementCategory?) -> [MyPlanCourseContribution] {
        guard let requirement else { return [] }
        let transferIDs = Set(store.plan.transferCredits.flatMap(\.courseIDs))
        let scheduled = Dictionary(
            (store.activePathway?.semesters ?? [])
                .sorted { $0.id < $1.id }
                .flatMap { semester in semester.courseIDs.map { ($0, semester.id.displayName) } },
            uniquingKeysWith: { first, _ in first }
        )
        return requirement.courseOptions.compactMap { option in
            if let transferID = option.first(where: transferIDs.contains),
               let course = catalog.coursesByID[transferID] {
                return MyPlanCourseContribution(code: course.code, source: "Transfer", isTransfer: true)
            }
            if let scheduledID = option.first(where: { scheduled[$0] != nil }),
               let course = catalog.coursesByID[scheduledID],
               let semester = scheduled[scheduledID] {
                return MyPlanCourseContribution(code: course.code, source: semester, isTransfer: false)
            }
            return nil
        }
    }

    private var footerActions: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Button("Edit setup") { store.setupSheetPresented = true }
                .buttonStyle(.dtSecondary)
            Button("Regenerate pathways") { store.generateSchedules() }
                .buttonStyle(.dtTertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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

private struct MyPlanCourseContribution: Identifiable {
    var id: String { "\(code)-\(source)" }
    var code: String
    var source: String
    var isTransfer: Bool
}
