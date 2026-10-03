import SwiftUI
import PlannerCore

struct SetupSheet: View {
    @EnvironmentObject private var store: PlanStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var catalog: Catalog?
    @State private var flow: SetupFlow
    @StateObject private var importController = TranscriptImportController()
    /// Direction of the last step change; steers the slide-in edge.
    @State private var movingForward = true
    @State private var yearAdvanceTask: Task<Void, Never>?
    @State private var reviewError: String?

    init(catalog: Catalog?, flow: SetupFlow = SetupFlow()) {
        self.catalog = catalog
        _flow = State(initialValue: flow)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(width: 1)
            VStack(spacing: 0) {
                topBar
                stepContainer
                Rectangle()
                    .fill(DesignTokens.Colors.borderSubtle)
                    .frame(height: 1)
                footer
            }
            .background(DesignTokens.Colors.surfaceElevated)
        }
        .frame(minWidth: 880, idealWidth: 920, minHeight: 640, idealHeight: 680)
        .background(DesignTokens.Colors.surface)
        .onAppear { if let year = store.plan.studentYear { flow.selectYear(year) } }
        .onDisappear {
            importController.cancel()
            yearAdvanceTask?.cancel()
        }
        .onChange(of: importController.state) { _, state in
            if state == .reviewing { navigate { $0.importReady() } }
        }
        // The sheet sits above the dashboard, so the dashboard's overlay is
        // hidden while setup is up. Repeat it here so setup-triggered
        // generation shows the same progress modal.
        .overlay {
            if let progress = store.scheduleGenerationProgress {
                ScheduleGenerationOverlay(progress: progress)
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.scheduleGenerationProgress)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        // Short windows with the six-step route scroll instead of clipping.
        ViewThatFits(in: .vertical) {
            sidebarContent
            ScrollView { sidebarContent }
        }
        .frame(width: 248)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                SetupEyebrow("Plan setup")
                Text("Build your plan")
                    .font(DesignTokens.Typography.heading)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            SetupStepRail(route: flow.route, current: flow.step, visited: flow.visited) { step in
                navigate { $0.jumpBack(to: step) }
            }
            Spacer(minLength: DesignTokens.Spacing.l)
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(height: 1)
            SetupSummaryPanel(
                draftEarnedHours: draftEarnedHours,
                isIncoming: flow.year == .incomingFreshman,
                showsWorkload: flow.step == .workload
            )
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: 248, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var draftEarnedHours: Double? {
        guard let draft = importController.draft else { return nil }
        return EffectiveCreditBuilder.build(records: draft.records, legacyCredits: []).earnedHours
    }

    // MARK: Main pane

    private var topBar: some View {
        HStack {
            Text("Step \(flow.position) of \(flow.route.count)")
                .font(DesignTokens.Typography.small)
                .tracking(0.44)
                .textCase(.uppercase)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(DesignTokens.Motion.step, value: flow.position)
            Spacer()
            CloseButton { dismiss() }
        }
        .padding(.leading, DesignTokens.Spacing.xxl)
        .padding(.trailing, DesignTokens.Spacing.l)
        .padding(.top, DesignTokens.Spacing.l)
    }

    private var stepContainer: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                    Text(flow.step.title)
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(flow.step.helper)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineSpacing(2)
                        .frame(maxWidth: 560, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, DesignTokens.Spacing.xxl)
                stepBody
            }
            .padding(.top, DesignTokens.Spacing.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(flow.step)
            .transition(stepTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var stepTransition: AnyTransition {
        let fadeOut = AnyTransition.opacity.animation(.easeOut(duration: 0.12))
        guard !reduceMotion else { return .asymmetric(insertion: .opacity, removal: fadeOut) }
        return .asymmetric(
            insertion: .offset(x: movingForward ? 32 : -32).combined(with: .opacity),
            removal: fadeOut
        )
    }

    @ViewBuilder
    private var stepBody: some View {
        if flow.step == .year {
            scrolling {
                SetupStepYear(selection: flow.year, onSelect: selectYear)
            }
        } else if let catalog {
            switch flow.step {
            case .major:
                SetupStepMajor(catalog: catalog)
                    .padding(.horizontal, DesignTokens.Spacing.xxl)
            case .minor:
                SetupStepMinor(catalog: catalog)
                    .padding(.horizontal, DesignTokens.Spacing.xxl)
            case .transfer:
                scrolling { SetupStepTransfer(catalog: catalog) }
            case .transcript:
                scrolling { SetupStepTranscript(controller: importController) }
            case .review:
                ScrollViewReader { proxy in
                    scrolling {
                        SetupStepCourseReview(controller: importController, catalog: catalog) { recordID in
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                                proxy.scrollTo(recordID, anchor: .center)
                            }
                        }
                    }
                }
            case .workload:
                scrolling { SetupStepWorkload() }
            case .year:
                EmptyView()
            }
        } else {
            VStack(spacing: DesignTokens.Spacing.l) {
                ProgressView()
                    .controlSize(.small)
                Text(store.statusMessage)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                if store.errorMessage != nil {
                    Button("Retry") { Task { await store.load() } }
                        .buttonStyle(.dtSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func scrolling<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, DesignTokens.Spacing.xxl)
                .padding(.bottom, DesignTokens.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: DesignTokens.Spacing.m) {
            Button {
                navigate { $0.back() }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.dtSecondary)
            .disabled(flow.visited.isEmpty)
            .keyboardShortcut("[", modifiers: .command)

            Spacer(minLength: DesignTokens.Spacing.m)

            if let message = footerMessage {
                Label(message.text, systemImage: message.isError ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(message.isError ? DesignTokens.Colors.danger : DesignTokens.Colors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .transition(.opacity)
            }

            if showsSkip {
                Button("Skip") { navigate { $0.advance(majorSelectionComplete: store.majorSelectionComplete) } }
                    .buttonStyle(.dtTertiary)
                    .transition(.opacity)
            }

            primaryButton
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.l)
        .animation(DesignTokens.Motion.hover, value: footerMessage?.text)
        .animation(DesignTokens.Motion.hover, value: showsSkip)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch flow.step {
        case .transcript:
            Button(importController.draft == nil ? "Enter courses manually" : "Resume course review") {
                startManualReview()
            }
            .buttonStyle(.dtSecondary)
            .disabled(catalog == nil || importController.state == .processing)
        case .review:
            Button("Confirm courses") { confirmReview() }
                .buttonStyle(.dtPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(importController.draft == nil || reviewHasBlockingIssues)
        case .workload:
            Button {
                Task {
                    await store.generateSchedules()
                    if store.errorMessage == nil { dismiss() }
                }
            } label: {
                Label("Generate plan", systemImage: "wand.and.stars")
            }
            .buttonStyle(.dtPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(!store.majorSelectionComplete || !store.canEditSchedule)
        default:
            Button {
                navigate { $0.advance(majorSelectionComplete: store.majorSelectionComplete) }
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text("Continue")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(.dtPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(!canContinue)
        }
    }

    private var canContinue: Bool {
        switch flow.step {
        case .year: flow.year != nil
        case .major: catalog != nil && store.majorSelectionComplete
        default: catalog != nil
        }
    }

    private var showsSkip: Bool {
        switch flow.step {
        case .minor: store.plan.minors.isEmpty
        case .transfer: store.effectiveAcademicHistory.effectiveCredits.isEmpty
        default: false
        }
    }

    private var reviewHasBlockingIssues: Bool {
        guard let draft = importController.draft, let catalog else { return false }
        return TranscriptReconciler.validate(draft, catalog: catalog).contains { $0.isBlocking }
    }

    /// Says why the primary action is blocked, or surfaces the latest error,
    /// so a disabled button never reads as an unresponsive one.
    private var footerMessage: (text: String, isError: Bool)? {
        if let error = reviewError ?? store.errorMessage { return (error, true) }
        switch flow.step {
        case .year where flow.year == nil:
            return ("Choose a year to continue", false)
        case .major where store.activeProgram == nil:
            return ("Choose a major to continue", false)
        case .major where !store.majorSelectionComplete:
            return ("Choose a concentration to continue", false)
        case .review where reviewHasBlockingIssues:
            return ("Resolve the flagged rows to continue", false)
        default:
            return nil
        }
    }

    // MARK: Actions

    private func navigate(_ change: (inout SetupFlow) -> Void) {
        var next = flow
        change(&next)
        guard next.step != flow.step || next.route != flow.route || next.year != flow.year else { return }
        movingForward = next.position >= flow.position
        reviewError = nil
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DesignTokens.Motion.step) {
            flow = next
        }
    }

    /// Selecting a year highlights the card, holds a beat so the choice
    /// registers, then moves on.
    private func selectYear(_ year: StudentYear) {
        store.plan.studentYear = year
        navigate { $0.selectYear(year) }
        yearAdvanceTask?.cancel()
        yearAdvanceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, flow.step == .year, flow.year == year else { return }
            navigate { $0.advance(majorSelectionComplete: store.majorSelectionComplete) }
        }
    }

    private func startManualReview() {
        guard let catalog else { return }
        importController.beginManual(
            catalog: catalog,
            existingRecords: store.plan.academicRecords,
            existingCredits: store.plan.transferCredits,
            defaultSemester: store.plan.currentSemester?.id ?? store.plan.planningStart ?? .current()
        )
        navigate { $0.skipUpload() }
    }

    private func confirmReview() {
        guard let draft = importController.draft, let catalog else { return }
        do {
            let history = try TranscriptReconciler.confirm(draft, catalog: catalog)
            try store.confirmAcademicHistory(history)
            reviewError = nil
            navigate { $0.reviewConfirmed() }
        } catch {
            reviewError = error.localizedDescription
        }
    }
}

private struct CloseButton: View {
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovering ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(isHovering ? DesignTokens.Colors.borderSubtle : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(DesignTokens.Motion.hover, value: isHovering)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Close setup")
        .help("Close setup")
    }
}
