import SwiftUI
import PlannerCore

private struct TranscriptPickerRequest: Identifiable {
    let id = UUID()
    var recordID: UUID?
    var status: AcademicCourseStatus
}
struct SetupStepCourseReview: View {
    @EnvironmentObject private var store: PlanStore
    @ObservedObject var controller: TranscriptImportController
    var catalog: Catalog
    /// Scrolls the enclosing scroll view to a course row by record ID.
    var scrollToRow: (UUID) -> Void = { _ in }
    @State private var picker: TranscriptPickerRequest?
    @State private var showsUncertainRows = false
    @State private var flashedRecordID: UUID?
    @State private var flashTask: Task<Void, Never>?
    private static let rowLinkScheme = "jmu-review-row"
    private var issues: [TranscriptIssue] { controller.draft.map { TranscriptReconciler.validate($0, catalog: catalog) } ?? [] }
    private var currentTerm: Binding<SemesterTerm> {
        Binding(get: { controller.draft?.currentSemester.term ?? .fall }, set: { term in
            guard let year = controller.draft?.currentSemester.year else { return }
            controller.draft?.setCurrentSemester(.init(year: year, term: term))
        })
    }
    private var currentYear: Binding<Int> {
        Binding(get: { controller.draft?.currentSemester.year ?? 2026 }, set: { year in
            guard let term = controller.draft?.currentSemester.term else { return }
            controller.draft?.setCurrentSemester(.init(year: year, term: term))
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            if let draft = controller.draft {
                let earned = EffectiveCreditBuilder.build(records: draft.records, legacyCredits: []).earnedHours
                let current = draft.records.filter { $0.status == .inProgress }.reduce(0.0) { $0 + $1.attemptedCredits }
                HStack(spacing: DesignTokens.Spacing.s) {
                    StatChip(label: "Earned", value: "\(CreditHoursFormatter.string(earned)) cr")
                    StatChip(label: "This semester", value: "\(CreditHoursFormatter.string(current)) cr")
                }
                .contentTransition(.numericText())
                .animation(DesignTokens.Motion.hover, value: earned)
                .animation(DesignTokens.Motion.hover, value: current)
                let currentIssues = issues
                if !currentIssues.isEmpty {
                    noticesCard(currentIssues)
                }
                Card {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                        Text("Current semester").font(DesignTokens.Typography.bodyEmphasized)
                        HStack(spacing: DesignTokens.Spacing.m) {
                            Picker("Term", selection: currentTerm) { ForEach(SemesterTerm.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 200)
                            Stepper("Year \(currentYear.wrappedValue.formatted(.number.grouping(.never)))", value: currentYear, in: 1900...2200)
                                .monospacedDigit()
                            Button("Confirm semester") { controller.draft?.setCurrentSemester(draft.currentSemester) }
                                .buttonStyle(.dtTertiary)
                        }
                        Text("These courses stay exactly in this semester. New courses will be planned afterward.")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
                group("Earned credit", status: .earned)
                group("In progress", status: .inProgress)
                InteractiveDisclosureGroup(isExpanded: $showsUncertainRows) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                        rows(draft.records.filter { $0.status == .excluded || $0.status == .needsReview })
                    }
                    .padding(.top, DesignTokens.Spacing.s)
                } label: {
                    Text("Excluded attempts and uncertain rows")
                        .font(DesignTokens.Typography.bodyEmphasized)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                InteractiveDisclosureGroup {
                    SetupStepTransfer(catalog: catalog, onAddAP: { exam, score in
                        controller.draft?.addAPScore(examName: exam, score: score, catalog: catalog, program: store.effectiveActiveProgram)
                    }, onAddDual: { label, code, credits in
                        controller.draft?.records.append(.init(code: code, title: label, courseIDs: catalog.coursesByID[code] == nil ? [] : [code], earnedCredits: credits, status: .earned, source: .manual, matchConfirmed: catalog.coursesByID[code] != nil))
                    }, reviewCredits: EffectiveCreditBuilder.build(records: draft.records, legacyCredits: []).credits)
                    .padding(.top, DesignTokens.Spacing.s)
                } label: {
                    Text("Add AP or dual enrollment credit by hand")
                        .font(DesignTokens.Typography.bodyEmphasized)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
            } else {
                Text("Choose a transcript or manual entry to begin review.")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .onDisappear { flashTask?.cancel() }
        .sheet(item: $picker) { request in
            CoursePickerSheet(title: request.recordID == nil ? "Add a course" : "Match a detected course", courses: catalog.courses) { course in
                if let id = request.recordID { controller.draft?.replace(recordID: id, with: course) }
                else { controller.draft?.add(course: course, status: request.status) }
            }
        }
    }
    private func noticesCard(_ issues: [TranscriptIssue]) -> some View {
        let blocking = issues.contains { $0.isBlocking }
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Label(blocking ? "Fix these before continuing" : "Worth a look", systemImage: blocking ? "exclamationmark.octagon" : "exclamationmark.triangle")
                .font(DesignTokens.Typography.bodyEmphasized)
                .foregroundStyle(blocking ? DesignTokens.Colors.danger : DesignTokens.Colors.warning)
            ForEach(issues) { issue in
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.s) {
                    Circle()
                        .fill(issue.isBlocking ? DesignTokens.Colors.danger : DesignTokens.Colors.warning)
                        .frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    issueText(issue)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .tint(issue.isBlocking ? DesignTokens.Colors.danger : DesignTokens.Colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if issue.recordID == nil && issue.kind == .malformedRow {
                        Button("Mark reviewed") { controller.draft?.dismissedIssueIDs.insert(issue.id) }
                            .buttonStyle(.dtTertiary)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill((blocking ? DesignTokens.Colors.danger : DesignTokens.Colors.warning).opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .strokeBorder((blocking ? DesignTokens.Colors.danger : DesignTokens.Colors.warning).opacity(0.4), lineWidth: 1)
        )
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == Self.rowLinkScheme, let id = url.host.flatMap(UUID.init(uuidString:)) else { return .systemAction }
            jump(to: id)
            return .handled
        })
    }
    /// Names the course an issue belongs to so the student knows which row to
    /// fix: "CS OOO: Match this course...". The code is a link (colored by the
    /// caller's tint) that scrolls to that row.
    private func issueText(_ issue: TranscriptIssue) -> Text {
        guard let recordID = issue.recordID,
              let record = controller.draft?.records.first(where: { $0.id == recordID }) else {
            return Text(issue.message)
        }
        var code = AttributedString(JMUTranscriptParser.displayCode(record.code))
        code.link = URL(string: "\(Self.rowLinkScheme)://\(recordID.uuidString)")
        code.inlinePresentationIntent = .stronglyEmphasized
        code.underlineStyle = .single
        return Text(code + AttributedString(": \(issue.message)"))
    }

    /// Scrolls to a row and outlines it briefly, opening the uncertain-rows
    /// group first when the row lives inside it.
    private func jump(to recordID: UUID) {
        guard let record = controller.draft?.records.first(where: { $0.id == recordID }) else { return }
        let needsExpand = (record.status == .excluded || record.status == .needsReview) && !showsUncertainRows
        if needsExpand {
            withAnimation(.easeOut(duration: 0.15)) { showsUncertainRows = true }
        }
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            // Give a freshly opened group a moment to lay out its rows.
            if needsExpand { try? await Task.sleep(for: .milliseconds(80)) }
            scrollToRow(recordID)
            flashedRecordID = recordID
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            flashedRecordID = nil
        }
    }
    private func group(_ title: String, status: AcademicCourseStatus) -> some View {
        let records = controller.draft?.records.filter { $0.status == status } ?? []
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            HStack {
                Text(title).font(DesignTokens.Typography.heading)
                Text("\(records.count)")
                    .font(DesignTokens.Typography.label)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer()
                Button { picker = .init(status: status) } label: { Label("Add course", systemImage: "plus") }
                    .buttonStyle(.dtSecondary)
            }
            if records.isEmpty {
                Text("No courses in this group yet.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            rows(records)
        }
    }
    private func rows(_ records: [AcademicCourseRecord]) -> some View {
        ForEach(records) { row in
            let binding = Binding<AcademicCourseRecord>(get: { controller.draft?.records.first { $0.id == row.id } ?? row }, set: { controller.draft?.update(record: $0) })
            TranscriptCourseRow(record: binding, onReplace: { picker = .init(recordID: row.id, status: row.status) }, onRetain: {
                if row.status == .inProgress { controller.draft?.retainUnmatchedEnrollment(recordID: row.id) }
                else { controller.draft?.retainAsGeneralCredit(recordID: row.id) }
            }, onRemove: { controller.draft?.remove(recordID: row.id) }, isFlashed: flashedRecordID == row.id)
            .id(row.id)
        }
    }
}
