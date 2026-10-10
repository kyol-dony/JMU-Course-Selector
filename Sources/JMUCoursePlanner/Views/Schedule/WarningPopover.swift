import PlannerCore
import SwiftUI

/// Detail for one chip's or semester's warnings: explanation, caveats, a
/// one-click fix for the worst active course warning, and Keep controls.
struct WarningPopover: View {
    @EnvironmentObject private var store: PlanStore
    var warnings: [ConflictWarning]
    var onClose: () -> Void
    var onJumpToCourse: (String) -> Void

    @State private var suggestions: [FixSuggestion]?

    private struct LoadKey: Hashable {
        var warningID: String?
        var revision: UUID
    }

    /// The worst active course-level warning gets the fix row. A pending
    /// prerequisite choice is settled in the picker, not by a move.
    private var fixTarget: ConflictWarning? {
        warnings.first { !$0.isSemesterLevel && !$0.isOverridden && $0.kind != .pendingPrerequisiteChoice }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            ForEach(Array(warnings.enumerated()), id: \.element.id) { index, warning in
                if index > 0 { Divider() }
                section(warning)
            }
        }
        .padding(DesignTokens.Spacing.m)
        .frame(width: 280, alignment: .leading)
        .task(id: LoadKey(warningID: fixTarget?.id, revision: store.verdictRevision)) {
            suggestions = nil
            guard let target = fixTarget else { return }
            let result = await store.fixSuggestions(for: target)
            guard !Task.isCancelled else { return }
            suggestions = result
        }
    }

    @ViewBuilder
    private func section(_ warning: ConflictWarning) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack(spacing: 6) {
                Image(systemName: warning.isOverridden ? "checkmark" : "exclamationmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(color(for: warning)))
                Text(warning.isOverridden ? "\(warning.kind.title) (kept)" : warning.kind.title)
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            Text(warning.detail)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if warning.id == fixTarget?.id {
                fixRow
            }
            if !warning.notes.isEmpty {
                Divider().opacity(0.5)
                ForEach(warning.notes, id: \.self) { note in
                    Text(note)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // A pending choice belongs to a placeholder, not a course, and is
            // an explanation rather than a conflict to keep.
            if warning.kind != .pendingPrerequisiteChoice {
                actions(for: warning)
            }
        }
    }

    @ViewBuilder
    private func actions(for warning: ConflictWarning) -> some View {
        HStack(spacing: DesignTokens.Spacing.m) {
            if warning.isOverridden {
                Button("Stop keeping") { store.removeOverride(warning) }
                    .buttonStyle(.dtTertiary)
            } else {
                Button("Keep anyway") { store.override(warning) }
                    .buttonStyle(.dtTertiary)
            }
            if !warning.isSemesterLevel {
                Button("View course") {
                    onClose()
                    store.showCourse(warning.courseID)
                }
                .buttonStyle(.dtTertiary)
            }
        }
    }

    @ViewBuilder
    private var fixRow: some View {
        switch suggestions {
        case nil:
            Text("Finding a better semester…")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        case let suggestions?:
            let moves = suggestions.compactMap { suggestion -> (String, SemesterIdentity)? in
                if case .move(let courseID, let semester) = suggestion { return (courseID, semester) }
                return nil
            }
            if !moves.isEmpty {
                // One fix per line: side by side, two "Move to <Term> <Year>"
                // buttons do not fit the popover and truncate the year.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fits in:")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    ForEach(moves, id: \.1) { courseID, semester in
                        Button(moveTitle(courseID, to: semester)) {
                            onClose()
                            store.moveCourse(courseID, to: semester)
                        }
                        .buttonStyle(.dtTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if case .moveEarlier(let courseID)? = suggestions.first {
                Button("Move \(store.course(forID: courseID)?.code ?? courseID) earlier") {
                    onClose()
                    onJumpToCourse(courseID)
                }
                .buttonStyle(.dtTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Says so when a fix trades this warning for others (e.g. a light load).
    private func moveTitle(_ courseID: String, to semester: SemesterIdentity) -> String {
        let added = store.newWarningCount(moving: courseID, to: semester) ?? 0
        guard added > 0 else { return "Move to \(semester.displayName)" }
        return "Move to \(semester.displayName) (\(added) new warning\(added == 1 ? "" : "s"))"
    }

    private func color(for warning: ConflictWarning) -> Color {
        if warning.isOverridden { return DesignTokens.Colors.borderStrong }
        return warning.kind.severity == .mustFix ? DesignTokens.Colors.danger : DesignTokens.Colors.warning
    }
}
