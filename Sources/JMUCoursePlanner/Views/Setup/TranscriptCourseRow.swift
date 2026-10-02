import SwiftUI
import PlannerCore

struct TranscriptCourseRow: View {
    @Binding var record: AcademicCourseRecord
    var onReplace: () -> Void
    var onRetain: () -> Void
    var onRemove: () -> Void
    private var amount: Binding<Double> {
        Binding(get: { record.status == .inProgress ? record.attemptedCredits : record.earnedCredits }, set: { value in
            if record.status == .inProgress { record.attemptedCredits = value } else { record.earnedCredits = value }
        })
    }
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.code).font(DesignTokens.Typography.bodyEmphasized)
                        Text(record.title).font(DesignTokens.Typography.caption)
                        Text(record.source.label + (record.grade.map { " · Grade \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                        if let term = record.printedTerm { Text(term).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("Remove", action: onRemove).buttonStyle(.borderless)
                }
                HStack {
                    Picker("Status", selection: $record.status) {
                        Text("Earned credit").tag(AcademicCourseStatus.earned)
                        Text("In progress").tag(AcademicCourseStatus.inProgress)
                        Text("Excluded").tag(AcademicCourseStatus.excluded)
                        Text("Needs review").tag(AcademicCourseStatus.needsReview)
                    }.frame(maxWidth: 250)
                    TextField("Credits", value: amount, format: .number).textFieldStyle(.roundedBorder).frame(width: 85).accessibilityLabel("Credits for \(record.code)")
                    Text("credits").font(.caption)
                    Spacer()
                    Button("Match / replace course", action: onReplace).buttonStyle(.borderless)
                }
                if !record.matchConfirmed && record.status != .excluded {
                    Text("No catalog match. Match a course or retain the printed entry.").font(.caption).foregroundStyle(.orange)
                    Button(record.status == .inProgress ? "Keep as current enrollment" : "Keep as general credit", action: onRetain).buttonStyle(.borderless)
                } else if record.courseIDs.isEmpty && record.status == .earned {
                    Text("General earned hours; does not satisfy a named course prerequisite.").font(.caption).foregroundStyle(.secondary)
                } else if record.courseIDs.count > 1 {
                    Text("Awarded equivalents: " + record.courseIDs.joined(separator: ", ")).font(.caption)
                }
            }
        }
        .onChange(of: record.status) { old, status in
            if status == .earned && record.earnedCredits == 0 { record.earnedCredits = record.attemptedCredits }
            if status == .inProgress && record.attemptedCredits == 0 { record.attemptedCredits = record.earnedCredits }
        }
    }
}
