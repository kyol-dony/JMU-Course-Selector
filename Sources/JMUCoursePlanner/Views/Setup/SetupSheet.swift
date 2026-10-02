import SwiftUI
import PlannerCore

struct SetupSheet: View {
    @EnvironmentObject private var store: PlanStore
    @Environment(\.dismiss) private var dismiss
    var catalog: Catalog?
    @State private var flow = SetupFlow()
    @StateObject private var importController = TranscriptImportController()

    private var stepCount: Int { flow.route.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            stepContent
                .padding(DesignTokens.Spacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider().opacity(0.5)
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal) }
            footer
        }
        .frame(minWidth: 640, minHeight: 560)
        .background(DesignTokens.Colors.surface)
        .onAppear { if let year = store.plan.studentYear { flow.selectYear(year) } }
        .onDisappear { importController.cancel() }
        .onChange(of: importController.state) { _, state in if state == .reviewing { flow.importReady() } }
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

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.m) {
            Text("Build your plan")
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Circle()
                        .fill(index <= (flow.route.firstIndex(of: flow.step) ?? 0) ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.borderSubtle)
                        .frame(width: 8, height: 8)
                }
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.l)
    }

    private var stepContent: some View {
        ScrollView {
            Group {
                if flow.step == .year {
                    SetupStepYear(selection: flow.year) { year in
                        store.plan.studentYear = year
                        flow.selectYear(year)
                        advance()
                    }
                } else if let catalog {
                    switch flow.step {
                    case .major: SetupStepMajor(catalog: catalog)
                    case .minor: SetupStepMinor(catalog: catalog)
                    case .transfer: SetupStepTransfer(catalog: catalog)
                    case .transcript:
                        SetupStepTranscript(controller: importController) {
                            importController.beginManual(catalog: catalog, existingRecords: store.plan.academicRecords, existingCredits: store.plan.transferCredits, defaultSemester: store.plan.currentSemester?.id ?? store.plan.planningStart ?? .current())
                            flow.skipUpload()
                        }
                    case .review:
                        SetupStepCourseReview(controller: importController, catalog: catalog) { history in
                            do { try store.confirmAcademicHistory(history); flow.reviewConfirmed() }
                            catch { store.errorMessage = error.localizedDescription }
                        }
                    case .workload: SetupStepWorkload()
                    case .year: EmptyView()
                    }
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text(store.statusMessage)
                        if store.errorMessage != nil { Button("Retry") { Task { await store.load() } } }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            Button("Back") {
                flow.back()
            }
            .buttonStyle(.dtSecondary)
            .disabled(flow.visited.isEmpty)

            Spacer()

            if flow.step == .minor || flow.step == .transfer {
                Button("Skip") {
                    advance()
                }
                .buttonStyle(.dtTertiary)
            }

            if flow.step == .transcript || flow.step == .review {
                EmptyView()
            } else if flow.step != .workload {
                Button("Next") {
                    advance()
                }
                .buttonStyle(.dtPrimary)
                .disabled((flow.step == .year && flow.year == nil)
                    || (flow.step == .major && !store.majorSelectionComplete)
                    || (flow.step != .year && catalog == nil)
                    || flow.step == .transcript || flow.step == .review)
            } else {
                Button("Generate Plan") {
                    Task {
                        await store.generateSchedules()
                        if store.errorMessage == nil {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.dtPrimary)
                .disabled(!store.majorSelectionComplete || store.scheduleGenerationProgress != nil)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.l)
    }

    private func advance() {
        flow.advance(majorSelectionComplete: store.majorSelectionComplete)
    }
}
