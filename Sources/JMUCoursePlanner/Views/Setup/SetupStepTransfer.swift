import SwiftUI
import PlannerCore

struct SetupStepTransfer: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog
    @State private var selectedExam: String = ""
    @State private var selectedScore: Int = 5
    @State private var dualLabel: String = ""
    @State private var dualCourse: String = ""
    @State private var dualCredits: Int = 3

    private var apExamNames: [String] {
        Array(Set(catalog.apCreditRules.compactMap { rule in
            if case .apExam(let name, _) = rule.source { return name }
            return nil
        })).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            SectionHeader(
                "Transfer credit",
                helper: "Optional. Add AP scores and dual enrollment courses you have completed."
            )

            Card {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                    Text("AP exam")
                        .font(DesignTokens.Typography.bodyEmphasized)
                    HStack(spacing: DesignTokens.Spacing.s) {
                        Picker("Exam", selection: $selectedExam) {
                            ForEach(apExamNames, id: \.self) { exam in
                                Text(exam).tag(exam)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        Stepper("Score \(selectedScore)", value: $selectedScore, in: 1...5)
                            .frame(width: 130)
                        Button("Add") {
                            guard !selectedExam.isEmpty else { return }
                            store.addAPScore(examName: selectedExam, score: selectedScore)
                        }
                        .buttonStyle(.dtSecondary)
                        .disabled(selectedExam.isEmpty)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                    Text("Dual enrollment")
                        .font(DesignTokens.Typography.bodyEmphasized)
                    Grid(alignment: .leading, horizontalSpacing: DesignTokens.Spacing.s, verticalSpacing: DesignTokens.Spacing.s) {
                        GridRow {
                            TextField("Source course", text: $dualLabel)
                            TextField("JMU course code, e.g. WRTC103", text: $dualCourse)
                        }
                        GridRow {
                            Stepper("\(dualCredits) credits", value: $dualCredits, in: 1...8)
                            Button("Add") {
                                store.addDualEnrollment(
                                    label: dualLabel.isEmpty ? "Dual Enrollment" : dualLabel,
                                    courseID: dualCourse.replacingOccurrences(of: " ", with: "").uppercased(),
                                    credits: dualCredits
                                )
                                dualLabel = ""
                                dualCourse = ""
                            }
                            .buttonStyle(.dtSecondary)
                            .disabled(dualCourse.isEmpty)
                        }
                    }
                }
            }

            if !store.plan.transferCredits.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                        Text("Added so far")
                            .font(DesignTokens.Typography.small)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .textCase(.uppercase)
                        ForEach(store.plan.transferCredits) { credit in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(credit.sourceDescription)
                                        .font(DesignTokens.Typography.body)
                                    Text(credit.courseIDs.joined(separator: ", "))
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                                }
                                Spacer()
                                StatusPill(text: "\(credit.credits) cr", tone: .neutral)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .onAppear {
            if selectedExam.isEmpty {
                selectedExam = apExamNames.first ?? ""
            }
        }
    }
}
