import PlannerCore
import SwiftUI

struct ScheduleBoardView: View {
    @EnvironmentObject private var store: PlanStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    @StateObject private var drag = ScheduleDragController()
    @State private var itemFrames: [String: CGRect] = [:]
    @State private var columnFrames: [SemesterIdentity: CGRect] = [:]
    @State private var lastAutoScroll = Date.distantPast
    @State private var presentedWarningID: String?
    @State private var highlightedSemester: SemesterIdentity?
    @State private var scrollRequest: ScrollRequest?

    private struct ScrollRequest: Equatable {
        let id = UUID()
        var semester: SemesterIdentity
    }
    var catalog: Catalog

    var body: some View {
        let issues = ScheduleIssues(store.warnings, catalog: catalog)
        Group {
            if store.plan.pathways.isEmpty {
                EmptyState(
                    systemImage: "calendar.badge.plus", title: "No pathways yet",
                    body: "Pick a major and generate pathways to see your semester plan.",
                    actionLabel: "Open setup", action: { store.setupSheetPresented = true }
                )
            } else {
                VStack(spacing: 0) {
                    subToolbar(issues)
                    Divider().opacity(0.5)
                    board(issues)
                }
            }
        }
        .overlay(alignment: .bottom) { ScheduleToast() }
        .animation(DesignTokens.Motion.hover, value: store.lastScheduleChange)
        .onAppear { store.undoManager = undoManager }
        .onChange(of: undoManager) { _, newValue in store.undoManager = newValue }
        .onChange(of: store.verdictRevision) { _, _ in
            if drag.isDragging {
                drag.cancel()
                drag.finishReturn()
            }
        }
        .onChange(of: issues) { _, current in
            // A tag that disappeared must not leave its popover armed to
            // reopen when a later edit brings the same warnings back.
            if let key = presentedWarningID, !current.containsTag(key) {
                presentedWarningID = nil
            }
        }
        .onChange(of: drag.isDragging) { _, dragging in
            drag.setEscapeMonitoring(dragging)
            if dragging { presentedWarningID = nil }
        }
        .task(id: drag.isReturning ? drag.session?.id : nil) {
            if drag.isReturning { await animateReturnHome() }
        }
        .task(id: drag.isDragging ? drag.session?.id : nil) {
            guard drag.isDragging, let session = drag.session,
                  let verdicts = await store.loadDropVerdicts(for: session.itemID),
                  !Task.isCancelled else { return }
            withAnimation(DesignTokens.Motion.hover) {
                drag.applyVerdicts(verdicts, sessionID: session.id)
            }
        }
        .onDisappear {
            drag.reset()
            // A toast left over from another visit could offer Undo for a
            // change that is no longer on top of the undo stack.
            store.lastScheduleChange = nil
        }
    }

    private func subToolbar(_ issues: ScheduleIssues) -> some View {
        HStack(spacing: DesignTokens.Spacing.m) {
            PathwaySelector(
                pathways: store.plan.pathways,
                selection: Binding(
                    get: { store.plan.activePathwayID ?? store.plan.pathways.first?.id ?? "" },
                    set: { store.plan.activePathwayID = $0 }
                )
            )
            // Takes space before the spacer, so labels only shorten when the
            // toolbar is genuinely tight.
            .layoutPriority(1)

            Spacer()

            IssuesButton(issues: issues, catalog: catalog) { warning in
                focus(semester: warning.semester, openingTag: issues.tagID(for: warning))
            }

            if let pathway = store.activePathway {
                let total = pathway.semesters.flatMap(\.courseIDs)
                    .compactMap { catalog.coursesByID[$0]?.credits }
                    .reduce(0, +)
                StatChip(label: "Pathway", value: "\(total) cr")
            }

            Button("Regenerate") {
                Task { await store.generateSchedules() }
            }
                .buttonStyle(.dtSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(store.scheduleGenerationProgress != nil)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.m)
    }

    private var classificationSlots: [String: Int] {
        let classifications = (store.activePathway?.semesters ?? [])
            .flatMap(\.courseIDs)
            .compactMap { catalog.coursesByID[$0]?.code }
            .map(CourseClassificationPalette.classification)
        return CourseClassificationPalette.slotMap(for: classifications)
    }

    private func board(_ issues: ScheduleIssues) -> some View {
        let slots = classificationSlots
        return GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    let gaps = Dictionary(
                        (store.activePathway?.semesterGaps ?? []).map { ($0.after, $0) },
                        uniquingKeysWith: { first, _ in first }
                    )
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
                        ForEach(store.activePathway?.semesters ?? []) { semester in
                            SemesterColumnView(
                                drag: drag,
                                semester: semester,
                                catalog: catalog,
                                issues: issues,
                                presentedWarningID: $presentedWarningID,
                                isHighlighted: highlightedSemester == semester.id,
                                onJumpToCourse: jumpToCourse,
                                classificationSlots: slots,
                                highlightedCategoryID: store.scheduleCategoryFilter,
                                onBeginDrag: beginDrag,
                                onEndDrag: handleEnd
                            )
                            .id(semester.id)
                            if let missing = gaps[semester.id]?.missing.first {
                                addSlot(missing, style: .strip)
                            }
                        }
                        if let pathway = store.activePathway {
                            addSlot(pathway.nextSemester, style: .column)
                        }
                    }
                    .padding(DesignTokens.Spacing.xl)
                    // Centered when the semesters fit the window; scrolls
                    // from the leading edge when they don't.
                    .frame(minWidth: viewport.size.width, alignment: .center)
                    .animation(reduceMotion ? nil : DesignTokens.Motion.settle, value: store.activePathway?.semesters.map(\.id))
                }
                .coordinateSpace(name: ScheduleBoardSpace.name)
                .onPreferenceChange(ScheduleItemFramesKey.self) { frames in
                    itemFrames = frames
                }
                .onPreferenceChange(ScheduleColumnFramesKey.self) { frames in
                    columnFrames = frames
                    drag.updateColumnFrames(frames)
                }
                .overlay(alignment: .topLeading) {
                    floatingItem(slots: slots)
                }
                .onReceive(drag.pointer.$location) { location in
                    autoScroll(location: location, viewport: viewport.size, proxy: proxy)
                }
                .onChange(of: scrollRequest) { _, request in
                    guard let request else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                        proxy.scrollTo(request.semester, anchor: .center)
                    }
                }
                .task(id: drag.isDragging) {
                    guard drag.isDragging else { return }
                    while !Task.isCancelled {
                        autoScroll(location: drag.pointer.location, viewport: viewport.size, proxy: proxy)
                        do { try await Task.sleep(for: .milliseconds(350)) }
                        catch { return }
                    }
                }
            }
        }
    }

    /// Add controls stay in the layout while dragging (so columns never shift
    /// under the cursor) but fade and ignore clicks.
    private func addSlot(_ semester: SemesterIdentity, style: AddSemesterSlot.Style) -> some View {
        AddSemesterSlot(semester: semester, style: style) {
            store.addSemester(semester)
            Task { @MainActor in
                await Task.yield()
                scrollRequest = ScrollRequest(semester: semester)
            }
        }
        .opacity(drag.isDragging ? 0.35 : 1)
        .allowsHitTesting(!drag.isDragging)
        .transition(.opacity)
    }

    /// Scrolls to a semester, pulses its outline, then opens a tag's popover.
    func focus(semester: SemesterIdentity, openingTag tagID: String? = nil) {
        presentedWarningID = nil
        scrollRequest = ScrollRequest(semester: semester)
        if !reduceMotion { highlightedSemester = semester }
        Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(250)) }
            presentedWarningID = tagID
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(750))
            if highlightedSemester == semester { highlightedSemester = nil }
        }
    }

    /// "Move <CODE> earlier": show where that course sits.
    func jumpToCourse(_ courseID: String) {
        guard let semester = store.activePathway?.semesters.first(where: { $0.courseIDs.contains(courseID) })?.id else { return }
        focus(semester: semester)
    }

    /// The copy of the dragged item that follows the cursor.
    @ViewBuilder
    private func floatingItem(slots: [String: Int]) -> some View {
        if let session = drag.session {
            let appearance: CourseChip.Appearance = drag.isReturning ? .normal : .lifted
            Group {
                if PathwayPlaceholder.isPlaceholder(session.itemID) {
                    PlaceholderChip(
                        spec: ScheduleItemLookup.placeholderSpec(for: session.itemID, in: store.activePathway),
                        appearance: appearance
                    )
                } else if let course = store.course(forID: session.itemID) {
                    CourseChip(
                        course: course,
                        accentColor: ScheduleItemLookup.accent(for: course, slots: slots),
                        appearance: appearance
                    )
                }
            }
            .frame(width: session.itemSize.width)
            .modifier(FollowPointer(pointer: drag.pointer, grabOffset: session.grabOffset))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }

    private func beginDrag(itemID: String, semester: SemesterIdentity, index: Int, start: CGPoint) {
        guard let pathway = store.activePathway, let frame = itemFrames[itemID] else { return }
        drag.begin(
            itemID: itemID,
            origin: semester,
            originIndex: index,
            location: start,
            grabOffset: CGSize(width: start.x - frame.minX, height: start.y - frame.minY),
            itemSize: frame.size,
            columns: ScheduleDragGeometry.columns(
                pathway: pathway,
                draggedID: itemID,
                columnFrames: columnFrames,
                itemFrames: itemFrames
            ),
            verdicts: [:]
        )
    }

    /// `.returnHome` is animated from `onChange(of: drag.isReturning)` so Esc
    /// cancels share the same path.
    private func handleEnd(_ result: ScheduleDragController.EndResult) {
        guard case .drop(let drop) = result else { return }
        withAnimation(reduceMotion ? nil : DesignTokens.Motion.settle) {
            store.moveCourse(drop.itemID, to: drop.target.semester, at: drop.target.index)
        }
    }

    private func animateReturnHome() async {
        guard !reduceMotion else { drag.finishReturn(); return }
        let drag = self.drag
        guard let session = drag.session, let home = itemFrames[session.itemID] else {
            drag.finishReturn()
            return
        }
        let homeLocation = CGPoint(
            x: home.minX + session.grabOffset.width,
            y: home.minY + session.grabOffset.height
        )
        withAnimation(reduceMotion ? DesignTokens.Motion.hover : DesignTokens.Motion.settle) {
            drag.moveReturningItem(to: homeLocation)
        }
        do { try await Task.sleep(for: .milliseconds(250)) }
        catch { return }
        guard !Task.isCancelled, drag.session?.id == session.id else { return }
        drag.finishReturn()
    }

    private func autoScroll(location: CGPoint?, viewport: CGSize, proxy: ScrollViewProxy) {
        guard let location, drag.isDragging,
              Date().timeIntervalSince(lastAutoScroll) > 0.35
        else { return }
        let columns = columnFrames.map { ColumnGeometry(semester: $0.key, frame: $0.value, itemMidYOffsets: []) }
        guard let request = ScheduleDragGeometry.autoScrollRequest(for: location, viewport: viewport, columns: columns) else { return }
        lastAutoScroll = Date()
        // Choose the vertical anchor that keeps this column at its current Y.
        // A plain .leading/.trailing anchor would also center it vertically.
        let frame = columnFrames[request.semester] ?? .zero
        let difference = viewport.height - frame.height
        let verticalAnchor = abs(difference) > 1 ? frame.minY / difference : 0.5
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
            proxy.scrollTo(request.semester, anchor: UnitPoint(x: request.anchor.x, y: verticalAnchor))
        }
    }
}

/// Offsets the floating chip to the cursor. The only view that observes
/// pointer movement, so the board and columns re-render only when the drop
/// target changes.
private struct FollowPointer: ViewModifier {
    @ObservedObject var pointer: DragPointer
    var grabOffset: CGSize

    func body(content: Content) -> some View {
        content.offset(
            x: pointer.location.x - grabOffset.width,
            y: pointer.location.y - grabOffset.height
        )
    }
}
