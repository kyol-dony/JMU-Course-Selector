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

    /// Non-nil while the user is clicking a semester to anchor "Regenerate after".
    @State private var anchorPick: RegenerationBoundarySelection?
    @State private var hoveredAnchor: SemesterIdentity?
    @State private var regeneration: RegenerationPresentation?
    @State private var regenerationTask: Task<Void, Never>?
    @State private var suffixOpacity = 1.0
    @State private var boardSize = CGSize.zero
    @State private var retainedBoardSize = CGSize.zero
    @State private var completionMessage: String?

    private struct RegenerationPresentation {
        let id = UUID()
        let planID: UUID
        let pathwayID: String
        let cutoff: SemesterIdentity
        var pathway: Pathway
    }
    private var editingLocked: Bool { !store.canEditSchedule || regeneration != nil || anchorPick != nil }
    private var displayedPathway: Pathway? { regeneration?.pathway ?? store.activePathway }

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
        .onChange(of: store.plan.id) { _, _ in anchorPick = nil; cancelRegeneration(); retainedBoardSize = .zero }
        .onChange(of: store.activePathway?.id) { _, _ in anchorPick = nil; cancelRegeneration(); retainedBoardSize = .zero }
        .onChange(of: editingLocked) { _, locked in
            if locked { drag.reset(); presentedWarningID = nil }
        }
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
            cancelRegeneration()
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
                    set: { if !editingLocked { store.plan.activePathwayID = $0 } }
                )
            )
            // Takes space before the spacer, so labels only shorten when the
            // toolbar is genuinely tight.
            .layoutPriority(1)
            .disabled(editingLocked)

            Spacer()

            IssuesButton(issues: issues, catalog: catalog, placeholders: store.activePathway?.placeholders ?? [:]) { warning in
                focus(semester: warning.semester, openingTag: issues.tagID(for: warning))
            }

            if let pathway = store.activePathway {
                let total = pathway.semesters.reduce(0.0) { total, semester in
                    total + AcademicCreditCalculator.hours(in: semester, catalog: catalog)
                }
                StatChip(label: "Pathway", value: "\(CreditHoursFormatter.string(total)) cr")
            }

            if let pick = anchorPick {
                anchorBar(pick)
            } else {
                Button("Regenerate") {
                    Task { await store.generateSchedules() }
                }
                    .buttonStyle(.dtSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(editingLocked)
                Button("Regenerate after…") { startAnchorPick() }
                    .buttonStyle(.dtSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(editingLocked || store.activePathway?.semesters.isEmpty != false)
                    .help("Click the last semester to keep; later semesters are rebuilt")
            }
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
                        (displayedPathway?.semesterGaps ?? []).map { ($0.after, $0) },
                        uniquingKeysWith: { first, _ in first }
                    )
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
                        ForEach(displayedPathway?.semesters ?? []) { semester in
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
                                onEndDrag: handleEnd,
                                anchorPick: anchorContext(for: semester.id)
                            )
                            .id(semester.id)
                            .opacity(isFuture(semester.id) ? suffixOpacity : 1)
                            // Picking keeps columns clickable; their own overlay
                            // routes every click to choosing the anchor.
                            .disabled(editingLocked && anchorPick == nil)
                            .accessibilityHidden(isFuture(semester.id) && suffixOpacity == 0)
                            .overlay(alignment: .topLeading) {
                                if semester.id == firstDisplayedFuture { regenerationStatus }
                            }
                            if let missing = gaps[semester.id]?.missing.first {
                                addSlot(missing, style: .strip)
                                    .opacity(isFuture(missing) ? suffixOpacity : 1)
                            }
                        }
                        if regeneration != nil && firstDisplayedFuture == nil { regenerationStatus }
                        if let message = completionMessage {
                            Text(message).foregroundStyle(.secondary)
                                .padding(DesignTokens.Spacing.l).frame(width: 270)
                        }
                        if let pathway = displayedPathway {
                            addSlot(pathway.nextSemester, style: .column)
                                .opacity(regeneration == nil ? 1 : 0)
                        }
                    }
                    .padding(DesignTokens.Spacing.xl)
                    // Leading layout and retained extent prevent anchor recentering
                    // and scroll clamping when a shorter suffix replaces the old one.
                    .frame(minWidth: max(viewport.size.width, retainedBoardSize.width),
                           minHeight: retainedBoardSize.height, alignment: .topLeading)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: RegenerationBoardSizeKey.self, value: geometry.size)
                    })
                    .animation(reduceMotion || regeneration != nil ? nil : DesignTokens.Motion.settle, value: store.activePathway?.semesters.map(\.id))
                }
                .coordinateSpace(name: ScheduleBoardSpace.name)
                .onPreferenceChange(RegenerationBoardSizeKey.self) { boardSize = $0 }
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

    private func isFuture(_ semester: SemesterIdentity) -> Bool {
        regeneration.map { semester > $0.cutoff } ?? false
    }
    private var firstDisplayedFuture: SemesterIdentity? {
        guard let regeneration else { return nil }
        return regeneration.pathway.semesters.first { $0.id > regeneration.cutoff }?.id
    }
    @ViewBuilder private var regenerationStatus: some View {
        if let regeneration, suffixOpacity == 0 {
            PartialRegenerationStatusView(
                state: store.partialRegeneration ?? .init(
                    operationID: regeneration.id, pathwayID: regeneration.pathwayID, cutoff: regeneration.cutoff,
                    progress: .init(current: 0, total: 1, pathwayName: "Preparing")),
                onCancel: cancelRegeneration)
        }
    }
    private func startAnchorPick() {
        guard let pathway = store.activePathway else { return }
        var pick = RegenerationBoundarySelection(pathway: pathway)
        pick.selected = nil
        hoveredAnchor = nil
        anchorPick = pick
    }

    private func confirmAnchor() {
        guard let pick = anchorPick, let cutoff = pick.selected, pick.canConfirm else { return }
        anchorPick = nil
        hoveredAnchor = nil
        beginRegeneration(after: cutoff)
    }

    private func anchorContext(for semester: SemesterIdentity) -> SemesterColumnView.AnchorPickContext? {
        guard let pick = anchorPick else { return nil }
        return SemesterColumnView.AnchorPickContext(
            role: pick.role(of: semester),
            isPreview: hoveredAnchor == semester,
            onPick: { anchorPick?.toggle(semester) },
            onHover: { inside in
                if inside {
                    hoveredAnchor = semester
                } else if hoveredAnchor == semester {
                    hoveredAnchor = nil
                }
            }
        )
    }

    /// Replaces the Regenerate buttons while picking the anchor semester.
    private func anchorBar(_ pick: RegenerationBoundarySelection) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(pick.canConfirm ? DesignTokens.Colors.success : DesignTokens.Colors.textTertiary)
            Text(pick.prompt)
                .font(DesignTokens.Typography.label)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .fixedSize()
            Button("Cancel") {
                anchorPick = nil
                hoveredAnchor = nil
            }
                .buttonStyle(.dtSecondary)
                .keyboardShortcut(.cancelAction)
            Button("Rebuild") { confirmAnchor() }
                .buttonStyle(.dtPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!pick.canConfirm)
        }
        .accessibilityElement(children: .contain)
    }

    private func beginRegeneration(after cutoff: SemesterIdentity) {
        guard !editingLocked, let source = store.activePathway else { return }
        let originalPlan = store.plan
        let presentation = RegenerationPresentation(planID: originalPlan.id, pathwayID: source.id, cutoff: cutoff, pathway: source)
        completionMessage = nil
        drag.reset()
        retainedBoardSize = boardSize
        regeneration = presentation
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { suffixOpacity = 0 }
        regenerationTask = Task { @MainActor in
            defer {
                if regeneration?.id == presentation.id {
                    regeneration = nil
                    suffixOpacity = 1
                    regenerationTask = nil
                }
            }
            // Finish hiding before dispatch: even a fast result gets a complete
            // fade-out/reveal cycle. Reduce Motion skips this presentation wait.
            if !reduceMotion {
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            }
            guard !Task.isCancelled, store.plan == originalPlan else { return }
            await store.regenerateActivePathway(after: cutoff)
            guard !Task.isCancelled, regeneration?.id == presentation.id,
                  store.plan.id == originalPlan.id, store.activePathway?.id == source.id else { return }
            // Context changes cancel generation. Do not mistake them for a
            // successful no-op or show completion against a different plan.
            var expectedContext = originalPlan
            expectedContext.pathways = store.plan.pathways
            expectedContext.overrides = store.plan.overrides
            guard store.plan == expectedContext else { return }
            regeneration?.pathway = store.activePathway ?? source
            if store.errorMessage == nil, store.activePathway?.semesters.contains(where: { $0.id > cutoff }) == false {
                completionMessage = "No further semesters are needed."
            }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.22)) { suffixOpacity = 1 }
            if !reduceMotion {
                do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            }
            if completionMessage != nil {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4))
                    if store.plan.id == presentation.planID, regeneration == nil { completionMessage = nil }
                }
            }
        }
    }
    private func cancelRegeneration() {
        regenerationTask?.cancel()
        regenerationTask = nil
        store.cancelPartialRegeneration()
        regeneration = nil
        suffixOpacity = 1
        completionMessage = nil
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
        .opacity(drag.isDragging || anchorPick != nil ? 0.35 : 1)
        .allowsHitTesting(!drag.isDragging && !editingLocked)
        .disabled(editingLocked)
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
                if let spec = store.activePathway?.placeholders[session.itemID], let repeated = spec.repeatOf,
                   let course = store.catalog?.coursesByID[repeated] {
                    CourseChip(
                        course: course,
                        creditOverride: spec.credits,
                        accentColor: ScheduleItemLookup.accent(for: course, slots: slots),
                        appearance: appearance,
                        enrollmentLabel: ScheduleItemLookup.enrollmentLabel(for: session.itemID, in: store.activePathway)
                    )
                } else if PathwayPlaceholder.isPlaceholder(session.itemID) {
                    PlaceholderChip(
                        spec: ScheduleItemLookup.placeholderSpec(for: session.itemID, in: store.activePathway),
                        appearance: appearance
                    )
                } else if let course = store.course(forID: session.itemID) {
                    CourseChip(
                        course: course,
                        creditOverride: store.activePathway?.semesters.first { $0.courseIDs.contains(session.itemID) }?.creditOverrides[session.itemID],
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
        guard !editingLocked, let pathway = store.activePathway, let frame = itemFrames[itemID] else { return }
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


private struct RegenerationBoardSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
