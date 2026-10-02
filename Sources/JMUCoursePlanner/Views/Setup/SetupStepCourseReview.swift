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
    var onConfirm: (AcademicHistory) -> Void
    @State private var picker: TranscriptPickerRequest?
    @State private var confirmationError: String?
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            SectionHeader("Review your courses", helper: "Check earned credit and current enrollment. Add anything missed, correct amounts or matches, and remove incorrect detections.")
            if let draft = controller.draft {
                let earned = EffectiveCreditBuilder.build(records: draft.records, legacyCredits: []).earnedHours
                let current = draft.records.filter { $0.status == .inProgress }.reduce(0.0) { $0 + $1.attemptedCredits }
                HStack {
                    StatusPill(text: "\(CreditHoursFormatter.string(earned)) earned hours", tone: .neutral)
                    StatusPill(text: "\(CreditHoursFormatter.string(current)) current hours", tone: .neutral)
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Current semester").font(DesignTokens.Typography.bodyEmphasized)
                        HStack {
                            Picker("Term", selection: currentTerm) { ForEach(SemesterTerm.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 200)
                            Stepper("Year \(currentYear.wrappedValue.formatted(.number.grouping(.never)))", value: currentYear, in: 1900...2200)
                            Button("Confirm semester") { controller.draft?.setCurrentSemester(draft.currentSemester) }
                        }
                        Text("These courses stay exactly in this semester. New courses will be planned afterward.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !issues.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Review notices").font(DesignTokens.Typography.bodyEmphasized)
                            ForEach(issues) { issue in
                                HStack(alignment: .top) {
                                    Text(issue.message).font(.caption).foregroundStyle(issue.isBlocking ? .red : .secondary)
                                    if issue.recordID == nil && issue.kind == .malformedRow {
                                        Button("Reviewed") { controller.draft?.dismissedIssueIDs.insert(issue.id) }.buttonStyle(.borderless)
                                    }
                                }
                            }
                        }
                    }
                }
                group("Earned credit", status: .earned)
                group("In progress", status: .inProgress)
                DisclosureGroup("Excluded attempts / uncertain rows") {
                    rows(draft.records.filter { $0.status == .excluded || $0.status == .needsReview })
                }
                DisclosureGroup("Add AP or dual-enrollment credit manually") {
                    SetupStepTransfer(catalog: catalog, onAddAP: { exam, score in
                        controller.draft?.addAPScore(examName: exam, score: score, catalog: catalog, program: store.effectiveActiveProgram)
                    }, onAddDual: { label, code, credits in
                        controller.draft?.records.append(.init(code: code, title: label, courseIDs: catalog.coursesByID[code] == nil ? [] : [code], earnedCredits: credits, status: .earned, source: .manual, matchConfirmed: catalog.coursesByID[code] != nil))
                    }, reviewCredits: EffectiveCreditBuilder.build(records: draft.records, legacyCredits: []).credits)
                }
                if let error = confirmationError { Text(error).foregroundStyle(.red) }
                Button("Confirm courses and continue") {
                    do { onConfirm(try TranscriptReconciler.confirm(draft, catalog: catalog)); confirmationError = nil }
                    catch { confirmationError = error.localizedDescription }
                }.buttonStyle(.dtPrimary).disabled(issues.contains { $0.isBlocking })
            } else {
                Text("Choose a transcript or manual entry to begin review.")
            }
        }
        .sheet(item: $picker) { request in
            CoursePickerSheet(title: request.recordID == nil ? "Add a course" : "Match a detected course", courses: catalog.courses) { course in
                if let id = request.recordID { controller.draft?.replace(recordID: id, with: course) }
                else { controller.draft?.add(course: course, status: request.status) }
            }
        }
    }
    private func group(_ title: String, status: AcademicCourseStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(DesignTokens.Typography.heading)
                Spacer()
                Button("Add course") { picker = .init(status: status) }.buttonStyle(.dtSecondary)
            }
            let records = controller.draft?.records.filter { $0.status == status } ?? []
            if records.isEmpty { Text("No courses in this group.").font(.caption).foregroundStyle(.secondary) }
            rows(records)
        }
    }
    private func rows(_ records: [AcademicCourseRecord]) -> some View {
        ForEach(records) { row in
            let binding = Binding<AcademicCourseRecord>(get: { controller.draft?.records.first { $0.id == row.id } ?? row }, set: { controller.draft?.update(record: $0) })
            TranscriptCourseRow(record: binding, onReplace: { picker = .init(recordID: row.id, status: row.status) }, onRetain: {
                if row.status == .inProgress { controller.draft?.retainUnmatchedEnrollment(recordID: row.id) }
                else { controller.draft?.retainAsGeneralCredit(recordID: row.id) }
            }, onRemove: { controller.draft?.remove(recordID: row.id) })
        }
    }
}
