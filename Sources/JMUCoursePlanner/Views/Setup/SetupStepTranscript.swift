import SwiftUI
import UniformTypeIdentifiers
import PlannerCore

struct SetupStepTranscript: View {
    @EnvironmentObject private var store: PlanStore
    @ObservedObject var controller: TranscriptImportController
    var onSkip: () -> Void
    @State private var choosingFile = false
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            SectionHeader("Import your JMU transcript", helper: "Upload a text-based unofficial transcript PDF from MyMadison. Processing happens on this Mac. You'll review every detected course before continuing.")
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    if controller.state == .processing {
                        ProgressView("Reading transcript…")
                        Button("Cancel import") { controller.cancel() }.buttonStyle(.dtSecondary)
                    } else {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 32)).foregroundStyle(DesignTokens.Colors.brandPurple)
                        Text("Completed classes, awarded AP/transfer credit, and current enrollment")
                        Text("Scans and screenshots aren't supported. Your original PDF is not saved.").font(DesignTokens.Typography.caption)
                        Button(controller.state == .failed ? "Choose another PDF" : "Choose transcript PDF") { choosingFile = true }.buttonStyle(.dtPrimary)
                    }
                    if let error = controller.errorMessage { Text(error).foregroundStyle(.red) }
                }
            }
            Button("Skip upload / enter manually", action: onSkip).buttonStyle(.dtSecondary)
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                guard let catalog = store.catalog else { return }
                Task {
                    await controller.importPDF(at: url, catalog: catalog, existingRecords: store.plan.academicRecords, existingCredits: store.plan.transferCredits, defaultSemester: store.plan.currentSemester?.id ?? store.plan.planningStart ?? .current())
                }
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
    }
}
