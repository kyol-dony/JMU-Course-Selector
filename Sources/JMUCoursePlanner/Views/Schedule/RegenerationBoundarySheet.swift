import PlannerCore
import SwiftUI

struct RegenerationBoundarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: RegenerationBoundarySelection
    let pathway: Pathway
    let onConfirm: (SemesterIdentity) -> Void

    init(pathway: Pathway, onConfirm: @escaping (SemesterIdentity) -> Void) {
        self.pathway = pathway
        self.onConfirm = onConfirm
        _selection = State(initialValue: .init(pathway: pathway))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            Text("Regenerate later semesters").font(.title2.bold())
            Text(pathway.name).font(.headline).foregroundStyle(.secondary)
            Picker("Last semester to preserve", selection: $selection.selected) {
                ForEach(selection.semesters, id: \.self) { semester in
                    Text(semester.displayName).tag(Optional(semester))
                }
            }
            Text(selection.summary).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text("The selected semester and all earlier semesters stay exactly as you arranged them. Later course and elective choices in this pathway will be replaced. You can undo the regeneration.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Regenerate later semesters") {
                    guard let cutoff = selection.selected, selection.canConfirm else { return }
                    dismiss()
                    onConfirm(cutoff)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!selection.canConfirm)
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: 480)
    }
}
