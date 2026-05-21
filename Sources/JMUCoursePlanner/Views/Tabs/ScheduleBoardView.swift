import SwiftUI
import PlannerCore

struct ScheduleBoardView: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog

    var body: some View {
        if store.plan.pathways.isEmpty {
            EmptyState(
                systemImage: "calendar.badge.plus",
                title: "No pathways yet",
                body: "Pick a major and generate pathways to see your semester plan.",
                actionLabel: "Open setup",
                action: { store.setupSheetPresented = true }
            )
        } else {
            VStack(spacing: 0) {
                subToolbar
                Divider().opacity(0.5)
                warningsBanner
                board
            }
        }
    }

    private var subToolbar: some View {
        HStack(spacing: DesignTokens.Spacing.m) {
            Picker("Pathway", selection: Binding(
                get: { store.plan.activePathwayID ?? store.plan.pathways.first?.id ?? "" },
                set: { store.plan.activePathwayID = $0 }
            )) {
                ForEach(store.plan.pathways) { pathway in
                    Text(pathway.name).tag(pathway.id)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Spacer()

            if let pathway = store.activePathway {
                let total = pathway.semesters.flatMap(\.courseIDs)
                    .compactMap { catalog.coursesByID[$0]?.credits }
                    .reduce(0, +)
                StatChip(label: "Pathway", value: "\(total) cr")
            }

            Button("Regenerate") { store.generateSchedules() }
                .buttonStyle(.dtSecondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.m)
    }

    @ViewBuilder
    private var warningsBanner: some View {
        let active = visibleWarnings.filter { !$0.isOverridden }
        if !active.isEmpty {
            HStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.Colors.warning)
                Text("\(active.count) warning\(active.count == 1 ? "" : "s") in this pathway")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.s)
            .background(DesignTokens.Colors.warning.opacity(0.1))
        }
    }

    private var board: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
                if let pathway = store.activePathway {
                    let classifications = pathway.semesters
                        .flatMap(\.courseIDs)
                        .compactMap { catalog.coursesByID[$0]?.code }
                        .map(CourseClassificationPalette.classification)
                    let classificationSlots = CourseClassificationPalette.slotMap(for: classifications)
                    ForEach(pathway.semesters) { semester in
                        SemesterColumn(
                            semester: semester,
                            catalog: catalog,
                            visibleWarnings: visibleWarnings,
                            classificationSlots: classificationSlots,
                            highlightedCategoryID: store.scheduleCategoryFilter
                        )
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
    }

    private var visibleWarnings: [ConflictWarning] {
        store.warnings.filter { $0.kind != .unknownAvailability }
    }
}

private struct SemesterColumn: View {
    @EnvironmentObject private var store: PlanStore
    var semester: SemesterPlan
    var catalog: Catalog
    var visibleWarnings: [ConflictWarning]
    var classificationSlots: [String: Int]
    var highlightedCategoryID: String?

    private var totalCredits: Int {
        semester.courseIDs.compactMap { store.course(forID: $0)?.credits }.reduce(0, +)
    }

    var body: some View {
        Card(padding: DesignTokens.Spacing.m) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                header
                Divider().opacity(0.5)
                ForEach(semester.courseIDs, id: \.self) { id in
                    if PathwayPlaceholder.isPlaceholder(id),
                       let spec = store.activePathway?.placeholders[id] {
                        placeholderChip(id: id, spec: spec)
                    } else if let course = store.course(forID: id) {
                        let warnings = visibleWarnings.filter { $0.courseID == id && $0.semester == semester.id }
                        let classification = CourseClassificationPalette.classification(forCode: course.code)
                        CourseChip(
                            course: course,
                            accentColor: CourseClassificationPalette.color(
                                for: classification,
                                slotMap: classificationSlots
                            ),
                            isHighlighted: isHighlighted(courseID: id),
                            onTap: { store.showCourse(id) },
                            onRemove: { store.removeCourse(id) }
                        )
                        .draggable(id)
                        ForEach(warnings) { warning in
                            warningStrip(warning)
                        }
                    }
                }
                Spacer(minLength: 0)
                addCourseMenu
            }
        }
        .frame(width: 280)
        .frame(minHeight: 540, alignment: .top)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first else { return false }
            store.moveCourse(id, to: semester.id)
            return true
        }
    }

    /// Dashed-outline chip rendered for unfilled multi-alternate requirement
    /// options. Tap to pick a course from the option's alternates.
    private func placeholderChip(id: String, spec: PlaceholderSpec) -> some View {
        Menu {
            ForEach(spec.alternates, id: \.self) { altID in
                let label = catalog.coursesByID[altID].map { "\($0.code) - \($0.title)" } ?? altID
                Button(label) { store.resolvePlaceholder(id, with: altID) }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.s) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(DesignTokens.Colors.brandPurple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose course")
                        .font(DesignTokens.Typography.bodyEmphasized)
                        .foregroundStyle(DesignTokens.Colors.brandPurple)
                    Text(spec.categoryName)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text("\(spec.credits) cr")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .monospacedDigit()
            }
            .padding(DesignTokens.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(DesignTokens.Colors.brandPurple)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(semester.id.displayName)
                    .font(DesignTokens.Typography.bodyEmphasized)
                Text("\(totalCredits) credits")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .monospacedDigit()
            }
            Spacer()
            StatusPill(text: "\(semester.courseIDs.count)", tone: .neutral)
        }
    }

    private func warningStrip(_ warning: ConflictWarning) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: iconName(for: warning.kind))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(warning.isOverridden ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.warning)
            Text(warning.message)
                .font(DesignTokens.Typography.caption)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(warning.isOverridden ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.warning)
            Spacer(minLength: 0)
            if !warning.isOverridden {
                Button("Keep") { store.override(warning) }
                    .buttonStyle(.dtTertiary)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(warning.isOverridden ? DesignTokens.Colors.surface : DesignTokens.Colors.warning.opacity(0.12))
        )
    }

    private func iconName(for kind: ConflictKind) -> String {
        switch kind {
        case .missingCorequisite:
            return "arrow.left.arrow.right.circle.fill"
        case .missingPrerequisite, .unavailableSemester, .unknownAvailability:
            return "exclamationmark.triangle.fill"
        }
    }

    private var addCourseMenu: some View {
        Menu {
            ForEach(catalog.courses.sorted { $0.code < $1.code }) { course in
                Button("\(course.code) - \(course.title)") {
                    store.moveCourse(course.id, to: semester.id)
                }
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add course")
                    .font(DesignTokens.Typography.label)
            }
            .foregroundStyle(DesignTokens.Colors.brandPurple)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DesignTokens.Colors.brandPurpleSoft)
            )
        }
        .menuStyle(.borderlessButton)
    }

    private func isHighlighted(courseID: String) -> Bool {
        guard let categoryID = highlightedCategoryID else { return false }
        guard let program = store.effectiveActiveProgram else { return false }
        guard let category = program.requirements.first(where: { $0.id == categoryID }) else { return false }
        return store.courseIDsForRequirementHighlight(in: category).contains(courseID)
    }
}
