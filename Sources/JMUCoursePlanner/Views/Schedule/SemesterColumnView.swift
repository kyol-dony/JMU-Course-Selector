import PlannerCore
import SwiftUI

/// Lookups shared by semester columns and the board's floating drag preview.
enum ScheduleItemLookup {
    /// A missing spec (stale persisted pathway) falls back to an
    /// open-elective-style full-catalog picker rather than dropping the slot.
    static func placeholderSpec(for id: String, in pathway: Pathway?) -> PlaceholderSpec {
        pathway?.placeholders[id] ?? PlaceholderSpec(
            categoryID: ScheduleGenerator.openElectiveCategoryID,
            categoryName: "Choose a course",
            alternates: [],
            credits: 3
        )
    }

    static func accent(for course: Course, slots: [String: Int]) -> Color {
        CourseClassificationPalette.color(
            for: CourseClassificationPalette.classification(forCode: course.code),
            slotMap: slots
        )
    }
}

struct SemesterColumnView: View {
    @EnvironmentObject private var store: PlanStore
    @ObservedObject var drag: ScheduleDragController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var coursePickerRequest: CoursePickerRequest?
    var semester: SemesterPlan
    var catalog: Catalog
    var visibleWarnings: [ConflictWarning]
    var classificationSlots: [String: Int]
    var highlightedCategoryID: String?
    var onBeginDrag: (_ itemID: String, _ semester: SemesterIdentity, _ index: Int, _ start: CGPoint) -> Void
    var onEndDrag: (ScheduleDragController.EndResult) -> Void

    private var totalCredits: Int {
        semester.courseIDs.compactMap { store.course(forID: $0)?.credits }.reduce(0, +)
    }

    private var session: ScheduleDragController.Session? { drag.session }
    /// This column holds the item being dragged.
    private var isOriginColumn: Bool { drag.isDragging && session?.origin == semester.id }
    /// The cursor is over this column.
    private var isTarget: Bool { drag.isDragging && session?.target?.semester == semester.id }
    private var verdict: DropVerdict? {
        guard drag.isDragging, !isOriginColumn else { return nil }
        return drag.verdicts[semester.id]
    }

    /// Where the insertion gap goes, counted among the items other than the
    /// dragged one. Nil when the drop would land back on the item's own
    /// slot, since the ghost already marks that spot.
    private var gapIndex: Int? {
        guard isTarget, let session, let target = session.target else { return nil }
        if isOriginColumn, target.index == session.originIndex { return nil }
        return target.index
    }

    var body: some View {
        Card(padding: DesignTokens.Spacing.m) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                header
                Divider().opacity(0.5)
                items
                Spacer(minLength: 0)
                addCourseButton
            }
        }
        .frame(width: 280)
        .frame(minHeight: 540, alignment: .top)
        .overlay { verdictOverlay }
        .shadow(color: isTarget ? DesignTokens.Colors.targetShadow : .clear, radius: 9, x: 0, y: 6)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ScheduleColumnFramesKey.self,
                    value: [semester.id: proxy.frame(in: .named(ScheduleBoardSpace.name))]
                )
            }
        )
        .animation(DesignTokens.Motion.hover, value: verdict)
        .animation(DesignTokens.Motion.hover, value: isTarget)
        .animation(DesignTokens.Motion.hover, value: drag.isDragging)
        .sheet(item: $coursePickerRequest) { request in
            CoursePickerSheet(title: request.title, courses: request.courses) { course in
                switch request.action {
                case .resolvePlaceholder(let placeholderID):
                    store.resolvePlaceholder(placeholderID, with: course.id)
                case .addCourse:
                    store.moveCourse(course.id, to: semester.id)
                }
            }
        }
    }

    // MARK: Header (fixed height so drag geometry stays valid)

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(semester.id.displayName)
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let verdict, let reason = verdict.reason {
                    Text(reason)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(Self.color(for: verdict))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(reason)
                } else {
                    Text("\(totalCredits) credits")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: DesignTokens.Spacing.s)
            headerPill
                .lineLimit(1)
                .frame(maxWidth: 130, alignment: .trailing)
                .help(verdict?.headline ?? "")
        }
    }

    @ViewBuilder
    private var headerPill: some View {
        if isOriginColumn {
            StatusPill(text: "Current spot", tone: .neutral)
        } else if let verdict, let headline = verdict.headline {
            StatusPill(text: headline, tone: Self.tone(for: verdict), systemImage: Self.icon(for: verdict))
        } else if drag.isDragging && verdict == nil {
            StatusPill(text: "Checking…", tone: .neutral)
        } else {
            StatusPill(text: "\(semester.courseIDs.count)", tone: .neutral)
        }
    }

    // MARK: Verdict styling

    @ViewBuilder
    private var verdictOverlay: some View {
        if let style = overlayStyle {
            let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
            ZStack {
                shape.fill(style.color.opacity(style.fill))
                shape.strokeBorder(style.color.opacity(style.stroke), lineWidth: isTarget ? 2 : 1)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private var overlayStyle: (color: Color, stroke: Double, fill: Double)? {
        guard drag.isDragging else { return nil }
        if isOriginColumn {
            return isTarget ? (DesignTokens.Colors.brandPurple, 0.6, 0) : nil
        }
        switch verdict?.level {
        case .blocking: return (DesignTokens.Colors.danger, 0.4, 0.04)
        case .caution: return (DesignTokens.Colors.warning, 0.45, 0.04)
        case .clear: return (DesignTokens.Colors.success, 0.4, 0)
        case nil: return nil
        }
    }

    static func tone(for verdict: DropVerdict) -> StatusPill.Tone {
        switch verdict.level {
        case .blocking: .danger
        case .caution: .warning
        case .clear: .success
        }
    }

    static func icon(for verdict: DropVerdict) -> String {
        switch verdict.level {
        case .blocking: "xmark"
        case .caution: "exclamationmark.triangle.fill"
        case .clear: "checkmark"
        }
    }

    static func color(for verdict: DropVerdict) -> Color {
        switch verdict.level {
        case .blocking: DesignTokens.Colors.danger
        case .caution: DesignTokens.Colors.warning
        case .clear: DesignTokens.Colors.success
        }
    }

    // MARK: Items

    private var items: some View {
        let draggedID = drag.isDragging ? session?.itemID : nil
        let others = semester.courseIDs.filter { $0 != draggedID }
        let gap = gapIndex
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            ForEach(Array(semester.courseIDs.enumerated()), id: \.element) { index, id in
                if let gap, others.firstIndex(of: id) == gap {
                    if !reduceMotion { insertionGap }
                }
                item(id: id, index: index)
                    .overlay(alignment: .top) {
                        if reduceMotion, let gap, others.firstIndex(of: id) == gap {
                            insertionLine.offset(y: -4)
                        }
                    }
            }
            if let gap, gap >= others.count, !reduceMotion {
                insertionGap
            }
        }
        .overlay(alignment: .bottom) {
            if reduceMotion, let gap, gap >= others.count {
                insertionLine.offset(y: 4)
            }
        }
        .animation(reduceMotion ? nil : DesignTokens.Motion.settle, value: gap)
    }

    private var insertionLine: some View {
        HStack(spacing: 0) {
            Circle().fill(DesignTokens.Colors.brandPurple).frame(width: 8, height: 8)
            Rectangle().fill(DesignTokens.Colors.brandPurple).frame(height: 3)
        }
        .frame(height: 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var insertionGap: some View {
        let height = max(session?.itemSize.height ?? 8, 8)
        return VStack(spacing: 0) {
            insertionLine
            Spacer(minLength: 0)
        }
        .frame(height: height)
        .transition(.opacity)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func item(id: String, index: Int) -> some View {
        let appearance: CourseChip.Appearance = session?.itemID == id ? .ghost : .normal
        if PathwayPlaceholder.isPlaceholder(id) {
            let spec = ScheduleItemLookup.placeholderSpec(for: id, in: store.activePathway)
            PlaceholderChip(spec: spec, appearance: appearance)
                .modifier(dragModifier(id: id, index: index) { openPlaceholderPicker(id: id, spec: spec) })
                .contextMenu { MoveToMenu(itemID: id, currentSemester: semester.id) }
                .accessibilityActions { moveActions(for: id) }
                .onHover { if $0 { store.prefetchDropVerdicts(for: id) } }
        } else if let course = store.course(forID: id) {
            CourseChip(
                course: course,
                accentColor: ScheduleItemLookup.accent(for: course, slots: classificationSlots),
                isHighlighted: isHighlighted(courseID: id),
                isAffected: drag.affectedCourseIDs.contains(id),
                appearance: appearance,
                onRemove: { store.removeCourse(id) }
            )
            .modifier(dragModifier(id: id, index: index) { store.showCourse(id) })
            .contextMenu {
                MoveToMenu(itemID: id, currentSemester: semester.id)
                Divider()
                Button("Remove \(course.code)", role: .destructive) { store.removeCourse(id) }
            }
            .accessibilityActions { moveActions(for: id) }
            .onHover { if $0 { store.prefetchDropVerdicts(for: id) } }
            ForEach(visibleWarnings.filter { $0.courseID == id && $0.semester == semester.id }) { warning in
                warningStrip(warning)
            }
        }
    }

    /// VoiceOver equivalents of dragging: one action per other semester.
    @ViewBuilder
    private func moveActions(for id: String) -> some View {
        let targets = (store.activePathway?.semesters ?? []).filter { $0.id != semester.id }
        ForEach(targets) { target in
            Button("Move to \(target.id.displayName)") {
                store.moveCourse(id, to: target.id)
            }
        }
    }

    private func dragModifier(id: String, index: Int, onTap: @escaping () -> Void) -> DraggableScheduleItem {
        DraggableScheduleItem(
            itemID: id,
            drag: drag,
            onTap: onTap,
            onBegin: { start in onBeginDrag(id, semester.id, index, start) },
            onEnd: onEndDrag
        )
    }

    /// Every placeholder opens the searchable course picker. Empty
    /// alternates mean any catalog course; otherwise results stay restricted
    /// to the requirement's parsed alternatives.
    private func openPlaceholderPicker(id: String, spec: PlaceholderSpec) {
        coursePickerRequest = CoursePickerRequest(
            id: id,
            title: "Choose \(spec.categoryName)",
            courses: PlaceholderCoursePickerPolicy.eligibleCourses(for: spec, catalog: catalog),
            action: .resolvePlaceholder(id)
        )
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

    private var addCourseButton: some View {
        Button {
            coursePickerRequest = CoursePickerRequest(
                id: "add::\(semester.id.year)::\(semester.id.term.rawValue)",
                title: "Add course to \(semester.id.displayName)",
                courses: catalog.courses,
                action: .addCourse
            )
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add course")
                    .font(DesignTokens.Typography.label)
            }
            .foregroundStyle(DesignTokens.Colors.brandGold)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DesignTokens.Colors.brandPurpleSoft)
            )
        }
        .buttonStyle(.plain)
    }

    private func isHighlighted(courseID: String) -> Bool {
        guard let categoryID = highlightedCategoryID else { return false }
        // Filter id is either the primary major's raw category id or the
        // ProgressCalculator-prefixed "{programID}::{categoryID}" form used for
        // second-major / minor categories. Search both spaces.
        if let program = store.effectiveActiveProgram,
           let category = program.requirements.first(where: { $0.id == categoryID }) {
            return store.courseIDsForRequirementHighlight(in: category).contains(courseID)
        }
        for extra in store.selectedMinorPrograms() {
            for category in extra.requirements where "\(extra.id)::\(category.id)" == categoryID {
                return store.courseIDsForRequirementHighlight(in: category).contains(courseID)
            }
        }
        return false
    }
}

private struct CoursePickerRequest: Identifiable {
    enum Action {
        case resolvePlaceholder(String)
        case addCourse
    }

    let id: String
    let title: String
    let courses: [Course]
    let action: Action
}
