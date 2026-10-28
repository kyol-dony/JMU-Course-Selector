import SwiftUI
import UniformTypeIdentifiers
import PlannerCore

struct SetupStepTranscript: View {
    @EnvironmentObject private var store: PlanStore
    @ObservedObject var controller: TranscriptImportController
    @State private var choosingFile = false
    @State private var isDropTargeted = false
    @State private var isHovering = false
    @State private var dropError: String?

    private var isProcessing: Bool { controller.state == .processing }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            dropZone
            if let error = dropError ?? controller.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            HStack(alignment: .top, spacing: DesignTokens.Spacing.xl) {
                note(icon: "checkmark.seal", title: "What gets imported", text: "Completed classes, awarded AP and transfer credit, and your current enrollment.")
                note(icon: "lock", title: "Stays on this Mac", text: "The PDF is read locally and never saved. Scans and screenshots can't be read.")
            }
        }
        .animation(DesignTokens.Motion.step, value: controller.state)
        .animation(DesignTokens.Motion.hover, value: dropError ?? controller.errorMessage)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): importTranscript(at: url)
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
    }

    private var dropZone: some View {
        let highlighted = (isDropTargeted || isHovering) && !isProcessing
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
        return VStack(spacing: DesignTokens.Spacing.m) {
            if isProcessing {
                ProgressView()
                    .controlSize(.regular)
                Text("Reading your transcript")
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("This usually takes a few seconds.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Button("Cancel") { controller.cancel() }
                    .buttonStyle(.dtTertiary)
            } else {
                Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "doc.text.magnifyingglass")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.brandGoldInk)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(DesignTokens.Colors.surfaceElevated))
                    .overlay(Circle().strokeBorder(DesignTokens.Colors.brandPurple, lineWidth: 1))
                    .scaleEffect(isDropTargeted ? 1.08 : 1)
                Text(isDropTargeted ? "Drop to import" : "Drag your transcript PDF here")
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .contentTransition(.opacity)
                Text("or")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Button(chooseLabel) { choosingFile = true }
                    .buttonStyle(.dtPrimary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.xxl)
        .background(shape.fill(highlighted ? DesignTokens.Colors.surfaceElevated.opacity(isDropTargeted ? 1 : 0.5) : DesignTokens.Colors.surface))
        .overlay(
            shape.strokeBorder(
                highlighted ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.borderStrong,
                style: StrokeStyle(lineWidth: highlighted ? 1.5 : 1, dash: [6, 4])
            )
        )
        .contentShape(shape)
        .onHover { isHovering = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            guard !isProcessing, let url = urls.first else { return false }
            guard url.pathExtension.lowercased() == "pdf" else {
                dropError = "That file isn't a PDF. Download the unofficial transcript from MyMadison as a PDF and try again."
                return false
            }
            importTranscript(at: url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .animation(DesignTokens.Motion.hover, value: highlighted)
        .animation(DesignTokens.Motion.settle, value: isDropTargeted)
    }

    private var chooseLabel: String {
        if controller.draft != nil { return "Replace with another PDF" }
        return controller.state == .failed ? "Choose another PDF" : "Choose transcript PDF"
    }

    private func note(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(text)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func importTranscript(at url: URL) {
        guard let catalog = store.catalog else { return }
        dropError = nil
        Task {
            await controller.importPDF(
                at: url,
                catalog: catalog,
                existingRecords: store.plan.academicRecords,
                existingCredits: store.plan.transferCredits,
                defaultSemester: store.plan.currentSemester?.id ?? store.plan.planningStart ?? .current()
            )
        }
    }
}
