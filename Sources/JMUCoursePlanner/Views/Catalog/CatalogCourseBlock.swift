import SwiftUI
import PlannerCore

/// One option of a requirement on the catalog tab: a single course, or a
/// group taken together ("PSYC 210 & PSYC 211"). Styled like the Schedule
/// tab's `CourseChip` at rest and on hover; clicking a course opens its
/// detail sheet.
struct CatalogCourseBlock: View {
    @EnvironmentObject private var store: PlanStore
    var courseIDs: [String]
    var catalog: Catalog
    var remarks: [String: [String]]
    var slotMap: [String: Int]

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
    }

    private var codes: [String] { courseIDs.map(code(for:)) }

    private var accentColor: Color {
        let classification = CourseClassificationPalette.classification(forCode: codes.first ?? "")
        return CourseClassificationPalette.color(for: classification, slotMap: slotMap)
    }

    private var creditsText: String? {
        let known = courseIDs.compactMap { catalog.coursesByID[$0]?.credits }
        guard !known.isEmpty else { return nil }
        return "\(known.reduce(0, +)) cr"
    }

    private var blockRemarks: [String] {
        var seen: Set<String> = []
        return courseIDs.flatMap { remarks[$0] ?? [] }.filter { seen.insert($0).inserted }
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(codes.joined(separator: " & "))
                        .font(DesignTokens.Typography.bodyEmphasized)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .monospacedDigit()
                    Spacer(minLength: DesignTokens.Spacing.s)
                    if let creditsText {
                        Text(creditsText)
                            .font(DesignTokens.Typography.small)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .monospacedDigit()
                    }
                }
                ForEach(courseIDs, id: \.self) { courseID in
                    titleRow(courseID)
                }
                if !blockRemarks.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(blockRemarks, id: \.self, content: remarkTag)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, DesignTokens.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(
            ZStack {
                shape.fill(DesignTokens.Colors.surfaceElevated)
                shape.fill(accentColor.opacity(isHovering ? 0.07 : 0))
            }
        )
        .clipShape(shape)
        .overlay(shape.strokeBorder(isHovering ? accentColor.opacity(0.35) : DesignTokens.Colors.borderSubtle, lineWidth: 1))
        .shadow(color: isHovering ? accentColor.opacity(0.45) : .clear, radius: isHovering ? 5 : 0, x: 0, y: isHovering ? 3 : 0)
        .offset(y: isHovering && !reduceMotion ? -1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { if let first = courseIDs.first { store.showCourse(first) } }
        .onHover { isHovering = $0 }
        .animation(DesignTokens.Motion.hover, value: isHovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(codes.joined(separator: " and "))
    }

    /// A course's title; in a group each title opens its own course.
    private func titleRow(_ courseID: String) -> some View {
        let title = catalog.coursesByID[courseID]?.title ?? "Title not in the catalog"
        return Button {
            store.showCourse(courseID)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if courseIDs.count > 1 {
                    Text(code(for: courseID))
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .monospacedDigit()
                }
                Text(title)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(code(for: courseID))")
    }

    private func remarkTag(_ remark: String) -> some View {
        Text(remark)
            .font(DesignTokens.Typography.small)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                    .fill(DesignTokens.Colors.borderSubtle.opacity(0.5))
            )
    }

    /// The catalog code, or one rebuilt from the ID ("PSYC210" → "PSYC 210")
    /// when the course is missing from the catalog.
    private func code(for courseID: String) -> String {
        if let code = catalog.coursesByID[courseID]?.code { return code }
        guard let digit = courseID.firstIndex(where: \.isNumber), digit != courseID.startIndex else { return courseID }
        return "\(courseID[..<digit]) \(courseID[digit...])"
    }
}
