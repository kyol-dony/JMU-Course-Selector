import SwiftUI
import PlannerCore

struct SetupStepTransfer: View {
    @EnvironmentObject private var store: PlanStore
    var catalog: Catalog
    var onAddAP: ((String, Int) -> Void)? = nil
    var onAddDual: ((String, String, Double) -> Void)? = nil
    var reviewCredits: [TransferCredit]? = nil
    private var addedCredits: [TransferCredit] { reviewCredits ?? store.effectiveAcademicHistory.effectiveCredits }
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

    /// What the chosen exam and score would earn, before the student commits.
    private var apPreview: (earnsCredit: Bool, text: String)? {
        let rules = catalog.apCreditRules.compactMap { rule -> (Int, TransferCreditRule)? in
            guard case .apExam(let name, let minimumScore) = rule.source, name == selectedExam else { return nil }
            return (minimumScore, rule)
        }
        guard let lowest = rules.map(\.0).min() else { return nil }
        let qualifying = rules.filter { $0.0 <= selectedScore }
        guard let best = qualifying.map(\.0).max() else {
            return (false, "JMU awards credit for this exam starting at a score of \(lowest).")
        }
        let codes = Array(Set(qualifying.filter { $0.0 == best }.flatMap { $0.1.awardedCourseIDs })).sorted()
        guard !codes.isEmpty else { return (true, "Earns JMU elective credit.") }
        return (true, "Can earn credit for \(codes.joined(separator: " or ")).")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            apCard
            dualCard
            if !addedCredits.isEmpty {
                addedList
                    .transition(.opacity)
            }
        }
        .animation(DesignTokens.Motion.step, value: addedCredits)
        .onAppear {
            if selectedExam.isEmpty {
                selectedExam = apExamNames.first ?? ""
            }
        }
    }

    private var apCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                cardHeader(icon: "doc.text", title: "AP exam", detail: "Credit depends on the exam and your score.")
                HStack(alignment: .bottom, spacing: DesignTokens.Spacing.l) {
                    field("Exam") {
                        Picker("Exam", selection: $selectedExam) {
                            ForEach(apExamNames, id: \.self) { exam in
                                Text(exam).tag(exam)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                    field("Score") {
                        Picker("Score", selection: $selectedScore) {
                            ForEach(1...5, id: \.self) { score in
                                Text("\(score)").monospacedDigit().tag(score)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    Button {
                        guard !selectedExam.isEmpty else { return }
                        if let onAddAP { onAddAP(selectedExam, selectedScore) }
                        else { store.addAPScore(examName: selectedExam, score: selectedScore) }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.dtSecondary)
                    .disabled(selectedExam.isEmpty)
                }
                if let preview = apPreview {
                    Label(preview.text, systemImage: preview.earnsCredit ? "checkmark.circle" : "info.circle")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(preview.earnsCredit ? DesignTokens.Colors.success : DesignTokens.Colors.textSecondary)
                        .contentTransition(.opacity)
                        .animation(DesignTokens.Motion.hover, value: preview.text)
                }
            }
        }
    }

    private var dualCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                cardHeader(icon: "building.columns", title: "Dual enrollment", detail: "College courses you took in high school. Enter the JMU course they transfer as.")
                HStack(alignment: .bottom, spacing: DesignTokens.Spacing.m) {
                    field("Course you took") {
                        TextField("e.g. ENG 111 at NOVA", text: $dualLabel)
                            .textFieldStyle(.roundedBorder)
                    }
                    field("JMU equivalent") {
                        TextField("e.g. WRTC103", text: $dualCourse)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                    }
                    field("Credits") {
                        Stepper(value: $dualCredits, in: 1...8) {
                            Text("\(dualCredits)")
                                .font(DesignTokens.Typography.bodyEmphasized)
                                .monospacedDigit()
                                .frame(minWidth: 16)
                        }
                        .fixedSize()
                    }
                    Button {
                        let label = dualLabel.isEmpty ? "Dual Enrollment" : dualLabel
                        let code = JMUTranscriptParser.normalizedCode(dualCourse)
                        if let onAddDual { onAddDual(label, code, Double(dualCredits)) }
                        else { store.addDualEnrollment(label: label, courseID: code, credits: dualCredits) }
                        dualLabel = ""
                        dualCourse = ""
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.dtSecondary)
                    .disabled(dualCourse.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var addedList: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack {
                SetupEyebrow("Added so far")
                Spacer()
                Text("\(CreditHoursFormatter.string(addedCredits.reduce(0) { $0 + $1.credits })) credits")
                    .font(DesignTokens.Typography.label)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .contentTransition(.numericText())
            }
            VStack(spacing: 0) {
                ForEach(Array(addedCredits.enumerated()), id: \.element.id) { index, credit in
                    HStack(spacing: DesignTokens.Spacing.m) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(DesignTokens.Colors.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(credit.sourceDescription)
                                .font(DesignTokens.Typography.body)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                            if !credit.courseIDs.isEmpty {
                                Text(credit.courseIDs.joined(separator: ", "))
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                        }
                        Spacer()
                        StatusPill(text: "\(CreditHoursFormatter.string(credit.credits)) cr", tone: .neutral)
                    }
                    .padding(.vertical, DesignTokens.Spacing.s)
                    .padding(.horizontal, DesignTokens.Spacing.m)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    if index < addedCredits.count - 1 {
                        Rectangle().fill(DesignTokens.Colors.borderSubtle).frame(height: 1)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .strokeBorder(DesignTokens.Colors.borderSubtle, lineWidth: 1)
            )
        }
    }

    private func cardHeader(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.brandGoldInk)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
                        .fill(DesignTokens.Colors.brandPurpleSoft)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(detail)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(label)
                .font(DesignTokens.Typography.label)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            content()
        }
    }
}
