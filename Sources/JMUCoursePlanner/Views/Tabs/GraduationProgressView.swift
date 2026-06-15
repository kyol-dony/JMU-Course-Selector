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
        let creditsLeft = max(progress.overallRequiredCredits - progress.overallCompletedCredits, 0)
        let categoriesDone = progress.categories.filter { $0.remainingCredits == 0 }.count
        let categoriesTotal = progress.categories.count
        let semestersLeft = computeSemestersLeft(target: progress.projectedGraduation)
        let upcoming = nextUpcomingSemester()

        return Card {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.xl) {
                ZStack {
                    Circle()
                        .stroke(DesignTokens.Colors.borderSubtle, lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: CGFloat(progress.overallFraction))
                        .stroke(
                            DesignTokens.Colors.brandGold,
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
                .frame(minWidth: 200, alignment: .leading)

                Spacer(minLength: DesignTokens.Spacing.l)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                    Text("At a glance")
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .textCase(.uppercase)
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.l) {
                        miniStat(value: "\(creditsLeft)", label: "credits left")
                        miniStat(value: "\(categoriesDone)/\(categoriesTotal)", label: "categories")
                        miniStat(
                            value: semestersLeft.map(String.init) ?? "—",
                            label: semestersLeft == 1 ? "semester" : "semesters"
                        )
                    }
                    nextTermButton(upcoming)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DesignTokens.Typography.title)
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text(label)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
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

    private func computeSemestersLeft(target: SemesterIdentity?) -> Int? {
        guard let target else { return nil }
        let currentYear = Calendar.current.component(.year, from: Date())
        let monthsAway = max((target.year - currentYear) * 12, 0)
        return max(monthsAway / 6, 1)
    }

    private func nextUpcomingSemester() -> SemesterPlan? {
        guard let semesters = store.activePathway?.semesters else { return nil }
        let month = Calendar.current.component(.month, from: Date())
        let year = Calendar.current.component(.year, from: Date())
        let currentTerm: SemesterTerm = month >= 7 ? .fall : .spring
        let nowID = SemesterIdentity(year: year, term: currentTerm)
        return semesters.sorted { $0.id < $1.id }.first { $0.id >= nowID }
    }

    private func categoryList(progress: GraduationProgress, program: Program) -> some View {
        // Defensive uniquing: requirement IDs SHOULD be unique within a program
        // but parser regressions or appended Gen Ed clusters could collide;
        // keep the first occurrence rather than crashing the whole tab.
        // Second-major / minor categories are added by ProgressCalculator with
        // id "{programID}::{categoryID}" — mirror that prefix here so their
        // contributing-courses lookup hits, not just the primary major's.
        var pairs: [(String, RequirementCategory)] = program.requirements.map { ($0.id, $0) }
        for extra in store.selectedMinorPrograms() {
            for category in extra.requirements {
                pairs.append(("\(extra.id)::\(category.id)", category))
            }
        }
        let requirementsByID = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            SectionHeader("By category")
            ForEach(progress.categories) { category in
                let requirement = requirementsByID[category.id]
                let isOpenElective = category.id == ScheduleGenerator.openElectiveCategoryID
                let hasOptions = isOpenElective || !(requirement?.courseOptions.isEmpty ?? true)
                Card {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.s) {
                            Text(category.name)
                                .font(DesignTokens.Typography.bodyEmphasized)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                            if category.remainingCredits == 0 {
                                StatusPill(text: "Complete", tone: .success, systemImage: "checkmark.circle.fill")
                            } else if category.verificationStatus != .verified {
                                StatusPill(text: "Partial", tone: .warning)
                            }
                            Spacer(minLength: DesignTokens.Spacing.s)
                            Text("\(category.completedCredits)/\(category.requiredCredits)")
                                .font(DesignTokens.Typography.caption)
                                .monospacedDigit()
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        ProgressRail(
                            category: category,
                            hasCourseOptions: hasOptions,
                            remainingCourseCodes: remainingCodes(for: requirement, fallback: category),
                            showHeader: false
                        )
                        if let note = requirement?.note, !hasOptions {
                            Text(note)
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                        if isOpenElective {
                            contributionList(rows: openElectiveContributions())
                        } else {
                            contributionList(rows: contributions(for: requirement))
                        }
                    }
                }
            }
        }
    }

    private func remainingCodes(for requirement: RequirementCategory?, fallback: CategoryProgress) -> [String] {
        if let requirement {
            return store.remainingCourses(in: requirement)
        }
        let fallbackRequirement = RequirementCategory(
            id: fallback.id,
            name: fallback.name,
            requiredCredits: fallback.requiredCredits,
            courseOptions: []
        )
        return store.remainingCourses(in: fallbackRequirement)
    }

    @ViewBuilder
    private func contributionList(rows: [CourseContribution]) -> some View {
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
    /// matches an Open Elective slot. Each entry tells us which real course
    /// the student picked for that slot and which semester it landed in.
    private func openElectiveContributions() -> [CourseContribution] {
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
            return CourseContribution(code: course.code, source: source, isTransfer: false)
        }
        .sorted { $0.code < $1.code }
    }

    private func contributions(for requirement: RequirementCategory?) -> [CourseContribution] {
        guard let requirement else { return [] }
        // If a course shows up in more than one semester of the pathway (e.g.,
        // after a manual drag that introduced a duplicate), keep the earliest
        // placement rather than crashing with a duplicate-key precondition.
        let scheduled = Dictionary(
            (store.activePathway?.semesters ?? [])
                .sorted { $0.id < $1.id }
                .flatMap { semester in semester.courseIDs.map { ($0, semester.id.displayName) } },
            uniquingKeysWith: { first, _ in first }
        )
        return ProgressContributionBuilder.contributions(
            for: requirement,
            transferCredits: store.plan.transferCredits,
            scheduled: scheduled,
            coursesByID: catalog.coursesByID
        )
    }
}

struct ProgressContributionBuilder {
    static func contributions(
        for requirement: RequirementCategory,
        transferCredits: [TransferCredit],
        scheduled: [String: String],
        coursesByID: [String: Course]
    ) -> [CourseContribution] {
        let transferIDs = Set(transferCredits.flatMap(\.courseIDs))
        let rows = requirement.courseOptions.compactMap { option in
            if let transferID = option.first(where: transferIDs.contains),
               let course = coursesByID[transferID] {
                return CourseContribution(code: course.code, source: "Transfer", isTransfer: true)
            }
            if let scheduledID = option.first(where: { scheduled[$0] != nil }),
               let course = coursesByID[scheduledID],
               let semester = scheduled[scheduledID] {
                return CourseContribution(code: course.code, source: semester, isTransfer: false)
            }
            return nil
        }
        if !rows.isEmpty { return rows }
        guard let apLit = apLiteratureContribution(for: requirement, transferCredits: transferCredits) else {
            return []
        }
        return [apLit]
    }

    private static func apLiteratureContribution(
        for requirement: RequirementCategory,
        transferCredits: [TransferCredit]
    ) -> CourseContribution? {
        guard requirement.name.contains("[C2L]") else { return nil }
        let apLitGNEDIDs: Set<String> = ["GNED123", "GNED124", "GNED129"]
        guard transferCredits.contains(where: { credit in
            !apLitGNEDIDs.isDisjoint(with: credit.courseIDs)
                && credit.sourceDescription.localizedCaseInsensitiveContains("English Literature")
        }) else {
            return nil
        }
        return CourseContribution(code: "AP English Literature & Composition", source: "Transfer", isTransfer: true)
    }
}

struct CourseContribution: Identifiable, Equatable {
    var id: String { "\(code)-\(source)" }
    var code: String
    var source: String
    var isTransfer: Bool
}
