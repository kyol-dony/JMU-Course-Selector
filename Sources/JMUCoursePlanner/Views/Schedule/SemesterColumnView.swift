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

    /// "2nd time" for a repeat slot; nil for anything else.
    static func enrollmentLabel(for id: String, in pathway: Pathway?) -> String? {
        guard let number = pathway?.enrollmentNumber(of: id) else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return "\(formatter.string(from: NSNumber(value: number)) ?? "\(number)") time"
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
    var issues: ScheduleIssues
    @Binding var presentedWarningID: String?
    var isHighlighted: Bool
    var onJumpToCourse: (String) -> Void
    var classificationSlots: [String: Int]
    var highlightedCategoryID: String?
    var onBeginDrag: (_ itemID: String, _ semester: SemesterIdentity, _ index: Int, _ start: CGPoint) -> Void
    var onEndDrag: (ScheduleDragController.EndResult) -> Void
    /// Set while the board is picking the anchor for "Regenerate after".
    var anchorPick: AnchorPickContext? = nil

    struct AnchorPickContext {
        /// Nil until an anchor is picked.
        var role: RegenerationBoundarySelection.Role?
        /// The pointer is over this column.
        var isPreview: Bool
        var onPick: () -> Void
        var onHover: (Bool) -> Void
    }

    private var totalCredits: Double {
        semester.courseIDs.reduce(0.0) { total, id in
            if PathwayPlaceholder.isPlaceholder(id) {
                return total + (store.activePathway?.placeholders[id]?.credits ?? 0)
            }
            return total + (semester.creditOverrides[id] ?? Double(store.course(forID: id)?.credits ?? 0))
        }
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
        .opacity(anchorPick?.role == .rebuilt ? 0.45 : 1)
        .overlay { verdictOverlay }
        .overlay { anchorPreviewOverlay }
        .overlay { anchorPickTarget }
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
        .animation(reduceMotion ? nil : DesignTokens.Motion.hover, value: issues.worstActive(in: semester.id))
        .animation(reduceMotion ? nil : DesignTokens.Motion.hover, value: isHighlighted)
        .animation(reduceMotion ? nil : DesignTokens.Motion.hover, value: anchorPick?.role)
        .animation(reduceMotion ? nil : DesignTokens.Motion.hover, value: anchorPick?.isPreview)
        .onChange(of: store.activePathway) { _, pathway in
            // A slot that's been chosen, removed or replaced elsewhere (undo,
            // regeneration) closes its picker instead of offering stale advice.
            guard let slot = coursePickerRequest?.placeholderID,
                  !(pathway?.semesters.contains { $0.courseIDs.contains(slot) } ?? false)
            else { return }
            coursePickerRequest = nil
        }
        .sheet(item: $coursePickerRequest) { request in
            CoursePickerSheet(
                title: request.title,
                courses: request.courses,
                // Read from the store on every render, so an open picker
                // follows edits rather than the labels it opened with.
                dependencyPresentation: request.placeholderID.flatMap(store.placeholderDependencyPresentation(for:))
            ) { course in
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
                    HStack(spacing: 6) {
                        Text("\(CreditHoursFormatter.string(totalCredits)) credits")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .monospacedDigit()
                        if let model = WarningTagModel(warnings: issues.semesterWarnings(in: semester.id)) {
                            warningTag(model)
                        }
                    }
                    // Load tags are short; show them in full ("Heavy load (19 cr)")
                    // and let the count pill give up the width instead.
                    .fixedSize()
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
        if anchorPick?.role == .anchor {
            StatusPill(text: "Keep through", tone: .success, systemImage: "lock.fill")
        } else if anchorPick?.role == .rebuilt {
            StatusPill(text: "Rebuild", tone: .neutral, systemImage: "arrow.triangle.2.circlepath")
        } else if anchorPick != nil {
            StatusPill(text: "\(semester.courseIDs.count)", tone: .neutral)
        } else if isOriginColumn {
            StatusPill(text: "Current spot", tone: .neutral)
        } else if let verdict, let headline = verdict.headline {
            StatusPill(text: headline, tone: Self.tone(for: verdict), systemImage: Self.icon(for: verdict))
        } else if drag.isDragging && verdict == nil {
            StatusPill(text: "Checking…", tone: .neutral)
        } else if !drag.isDragging && store.canDeleteSemester(semester.id) {
            deleteSemesterButton
        } else {
            StatusPill(text: "\(semester.courseIDs.count)", tone: .neutral)
        }
    }

    /// Shown in place of the "0" count on an empty semester.
    private var deleteSemesterButton: some View {
        Button {
            store.deleteSemester(semester.id)
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.danger)
                .frame(width: 20, height: 20)
                .background(Circle().fill(DesignTokens.Colors.surfaceElevated))
                .overlay(Circle().strokeBorder(DesignTokens.Colors.borderSubtle, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Delete \(semester.id.displayName)")
        .accessibilityLabel("Delete \(semester.id.displayName)")
    }

    // MARK: Verdict styling

    @ViewBuilder
    private var verdictOverlay: some View {
        if let style = overlayStyle {
            let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
            ZStack {
                shape.fill(style.color.opacity(style.fill))
                shape.strokeBorder(style.color.opacity(style.stroke), lineWidth: isTarget || anchorPick?.role == .anchor ? 2 : 1)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private var overlayStyle: (color: Color, stroke: Double, fill: Double)? {
        if let anchorPick {
            // Keep/rebuild picture only; warning outlines are hidden while picking.
            switch anchorPick.role {
            case .anchor: return (DesignTokens.Colors.success, 0.9, 0.06)
            case .kept: return (DesignTokens.Colors.success, 0.4, 0)
            case .rebuilt, nil: return nil
            }
        }
        guard drag.isDragging else {
            if isHighlighted { return (DesignTokens.Colors.brandPurple, 0.6, 0) }
            switch issues.worstActive(in: semester.id) {
            case .mustFix: return (DesignTokens.Colors.danger, 0.4, 0)
            case .worthALook: return (DesignTokens.Colors.warning, 0.45, 0)
            case .hidden, nil: return nil
            }
        }
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

    /// Dashed green preview of the anchor under the pointer.
    @ViewBuilder
    private var anchorPreviewOverlay: some View {
        if let anchorPick, anchorPick.isPreview, anchorPick.role != .anchor {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .strokeBorder(DesignTokens.Colors.success.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// While picking, the whole column is one click target, so clicking a
    /// course inside it picks the semester instead of opening the course.
    @ViewBuilder
    private var anchorPickTarget: some View {
        if let anchorPick {
            Color.clear
                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
                .onTapGesture(perform: anchorPick.onPick)
                .onHover(perform: anchorPick.onHover)
                .accessibilityElement()
                .accessibilityLabel(anchorPick.role == .anchor
                    ? "Clear Keep through \(semester.id.displayName)"
                    : "Keep through \(semester.id.displayName)")
                .accessibilityAddTraits(anchorPick.role == .anchor ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { anchorPick.onPick() }
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
        if let spec = store.activePathway?.placeholders[id], let repeated = spec.repeatOf,
           let course = catalog.coursesByID[repeated] {
            // A later enrollment of a course taken more than once: that
            // course again, with nothing to choose.
            let label = ScheduleItemLookup.enrollmentLabel(for: id, in: store.activePathway)
            CourseChip(
                course: course,
                creditOverride: spec.credits,
                accentColor: ScheduleItemLookup.accent(for: course, slots: classificationSlots),
                isHighlighted: isHighlighted(courseID: repeated),
                isAffected: drag.affectedCourseIDs.contains(id),
                appearance: appearance,
                onRemove: { store.removeCourse(id) },
                accessory: chipTag(for: id),
                enrollmentLabel: label
            )
            .modifier(dragModifier(id: id, index: index) { store.showCourse(repeated) })
            .contextMenu {
                MoveToMenu(itemID: id, currentSemester: semester.id)
                Divider()
                Button("Remove \(course.code)\(label.map { " (\($0))" } ?? "")", role: .destructive) { store.removeCourse(id) }
            }
            .accessibilityActions { moveActions(for: id) }
            .onContinuousHover { phase in
                if case .active = phase { store.prefetchDropVerdicts(for: id) }
            }
        } else if PathwayPlaceholder.isPlaceholder(id) {
            let spec = ScheduleItemLookup.placeholderSpec(for: id, in: store.activePathway)
            PlaceholderChip(spec: spec, appearance: appearance, accessory: chipTag(for: id))
                .modifier(dragModifier(id: id, index: index) { openPlaceholderPicker(id: id, spec: spec) })
                .contextMenu { MoveToMenu(itemID: id, currentSemester: semester.id) }
                .accessibilityActions { moveActions(for: id) }
                .onContinuousHover { phase in
                    if case .active = phase { store.prefetchDropVerdicts(for: id) }
                }
        } else if let course = store.course(forID: id) {
            CourseChip(
                course: course,
                creditOverride: semester.creditOverrides[id],
                accentColor: ScheduleItemLookup.accent(for: course, slots: classificationSlots),
                isHighlighted: isHighlighted(courseID: id),
                isAffected: drag.affectedCourseIDs.contains(id),
                appearance: appearance,
                onRemove: { store.removeCourse(id) },
                accessory: chipTag(for: id)
            )
            .modifier(dragModifier(id: id, index: index) { store.showCourse(id) })
            .contextMenu {
                MoveToMenu(itemID: id, currentSemester: semester.id)
                Divider()
                Button("Remove \(course.code)", role: .destructive) { store.removeCourse(id) }
            }
            .accessibilityActions { moveActions(for: id) }
            .onContinuousHover { phase in
                    if case .active = phase { store.prefetchDropVerdicts(for: id) }
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

    private func chipTag(for courseID: String) -> AnyView? {
        guard let model = WarningTagModel(warnings: issues.warnings(for: courseID, in: semester.id)) else { return nil }
        return AnyView(warningTag(model))
    }

    private func warningTag(_ model: WarningTagModel) -> some View {
        WarningTag(
            model: model,
            isPresented: Binding(
                get: { presentedWarningID == model.key },
                set: { presentedWarningID = $0 ? model.key : nil }
            )
        ) {
            WarningPopover(
                warnings: model.warnings,
                onClose: { presentedWarningID = nil },
                onJumpToCourse: onJumpToCourse
            )
            .environmentObject(store)
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
            .foregroundStyle(DesignTokens.Colors.brandGoldInk)
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
        // second-major / minor categories; an option row covers its parts.
        return store.courseIDsForRequirementHighlight(rowID: categoryID).contains(courseID)
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

    var placeholderID: String? {
        if case .resolvePlaceholder(let id) = action { return id }
        return nil
    }
}
