import SwiftUI
import PlannerCore

struct TransferCreditView: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog
    @State private var selectedExam = "Computer Science A"
    @State private var selectedScore = 5
    @State private var dualLabel = ""
    @State private var dualCourse = ""
    @State private var dualCredits = 3

    private var apExamNames: [String] {
        Array(Set(catalog.apCreditRules.compactMap { rule in
            if case .apExam(let name, _) = rule.source { return name }
            return nil
        })).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transfer credit")
                .font(.headline)
            Text("AP rules use the JMU catalog chart entries that are present in this seed. Dual enrollment entries are stored as student-entered credit until an official transfer equivalency is verified.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Picker("AP Exam", selection: $selectedExam) {
                    ForEach(apExamNames, id: \.self) { Text($0).tag($0) }
                }
                Stepper("Score \(selectedScore)", value: $selectedScore, in: 1...5)
                Button("Add AP Credit") {
                    store.addAPScore(examName: selectedExam, score: selectedScore)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    TextField("Dual enrollment course name", text: $dualLabel)
                    TextField("JMU course code, e.g. WRTC103", text: $dualCourse)
                    Stepper("\(dualCredits) credits", value: $dualCredits, in: 1...8)
                    Button("Add") {
                        store.addDualEnrollment(label: dualLabel.isEmpty ? "Dual Enrollment" : dualLabel, courseID: dualCourse.replacingOccurrences(of: " ", with: "").uppercased(), credits: dualCredits)
                        dualLabel = ""
                        dualCourse = ""
                    }
                    .disabled(dualCourse.isEmpty)
                }
            }

            if !store.plan.transferCredits.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.plan.transferCredits) { credit in
                        Text("\(credit.sourceDescription): \(credit.courseIDs.joined(separator: ", ")) (\(credit.credits) credits)")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
    }
}
