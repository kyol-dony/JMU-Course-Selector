import SwiftUI
import PlannerCore

struct TranscriptCourseRow: View {
    @Binding var record: AcademicCourseRecord
    var onReplace: () -> Void
    var onRetain: () -> Void
    var onRemove: () -> Void
    /// Briefly outlines the row after a notice link scrolls to it.
    var isFlashed = false
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
                        Text(JMUTranscriptParser.displayCode(record.code)).font(DesignTokens.Typography.bodyEmphasized).foregroundStyle(DesignTokens.Colors.textPrimary)
                        Text(record.title).font(DesignTokens.Typography.caption).foregroundStyle(DesignTokens.Colors.textPrimary)
                        Text(record.source.label + (record.grade.map { " · Grade \($0)" } ?? "")).font(DesignTokens.Typography.caption).foregroundStyle(DesignTokens.Colors.textSecondary)
                        if let term = record.printedTerm { Text(term).font(DesignTokens.Typography.caption).foregroundStyle(DesignTokens.Colors.textSecondary) }
                    }
                    Spacer()
                    Button("Remove", role: .destructive, action: onRemove).buttonStyle(.dtTertiary)
                }
                HStack {
                    Picker("Status", selection: $record.status) {
                        Text("Earned credit").tag(AcademicCourseStatus.earned)
                        Text("In progress").tag(AcademicCourseStatus.inProgress)
                        Text("Excluded").tag(AcademicCourseStatus.excluded)
                        Text("Needs review").tag(AcademicCourseStatus.needsReview)
                    }.frame(maxWidth: 250)
                    TextField("Credits", value: amount, format: .number).textFieldStyle(.roundedBorder).frame(width: 85).accessibilityLabel("Credits for \(record.code)")
                    Text("credits").font(DesignTokens.Typography.caption).foregroundStyle(DesignTokens.Colors.textSecondary)
                    Spacer()
                    Button("Match or replace course", action: onReplace).buttonStyle(.dtTertiary)
                }
                if !record.matchConfirmed && record.status != .excluded {
                    Label("No catalog match. Match a course or keep the printed entry.", systemImage: "exclamationmark.triangle").font(DesignTokens.Typography.caption).foregroundStyle(DesignTokens.Colors.warning)
                    Button(record.status == .inProgress ? "Keep as current enrollment" : "Keep as general credit", action: onRetain).buttonStyle(.dtTertiary)
                } else if record.courseIDs.isEmpty && record.status == .earned {
                    Text("General earned hours; does not satisfy a named course prerequisite.").font(DesignTokens.Typography.caption).foregroundStyle(DesignTokens.Colors.textSecondary)
                } else if record.courseIDs.count > 1 {
                    Text("Awarded equivalents: " + record.courseIDs.joined(separator: ", ")).font(DesignTokens.Typography.caption).foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .strokeBorder(DesignTokens.Colors.danger, lineWidth: 2)
                .opacity(isFlashed ? 1 : 0)
                .allowsHitTesting(false)
        )
        .animation(.easeOut(duration: isFlashed ? 0.15 : 0.6), value: isFlashed)
        .onChange(of: record.status) { old, status in
            if status == .earned && record.earnedCredits == 0 { record.earnedCredits = record.attemptedCredits }
            if status == .inProgress && record.attemptedCredits == 0 { record.attemptedCredits = record.earnedCredits }
        }
    }
}
