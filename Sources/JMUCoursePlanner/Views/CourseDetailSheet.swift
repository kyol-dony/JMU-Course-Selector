import SwiftUI
import PlannerCore

struct CourseDetailSheet: View {
    @EnvironmentObject private var store: PlanStore
    @Environment(\.dismiss) private var dismiss
    var course: Course
    var catalog: Catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                    descriptionSection
                    availabilitySection
                    prereqSection
                    professorSection
                    linksSection
                }
                .padding(DesignTokens.Spacing.xl)
            }
        }
        .frame(width: 480)
        .frame(maxHeight: .infinity)
        .background(DesignTokens.Colors.surface)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.code)
                    .font(DesignTokens.Typography.display)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(course.title)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                HStack(spacing: DesignTokens.Spacing.s) {
                    StatusPill(text: "\(course.credits) credits", tone: .info)
                    if let availability = course.availability, !availability.isEmpty {
                        StatusPill(
                            text: availability.map(\.rawValue).sorted().joined(separator: " / "),
                            tone: .neutral
                        )
                    } else {
                        StatusPill(text: "Availability unknown", tone: .warning)
                    }
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignTokens.Spacing.xl)
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            SectionHeader("Description")
            if let detail = store.courseDetail, detail.course.id == course.id, let description = detail.description {
                Text(description)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            } else if let detail = store.courseDetail, detail.course.id == course.id {
                Text(detail.descriptionStatus)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            } else {
                Text("Loading official course details...")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
    }

    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            SectionHeader("Semester availability")
            if let availability = course.availability, !availability.isEmpty {
                Text("Typically offered: \(availability.map(\.rawValue).sorted().joined(separator: " and "))")
                    .font(DesignTokens.Typography.body)
            } else {
                Text("Availability is not verified in the local catalog. Confirm with the registrar before placing this course.")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.warning)
            }
            Text("If you move this course into a term where it is not typically offered, the warning stays visible until you change it.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private var prereqSection: some View {
        let prerequisiteExpr = displayedPrerequisiteExpr
        if prerequisiteExpr != .empty {
            requirementExpressionSection(
                title: "Prereqs",
                expr: prerequisiteExpr,
                showsUnknownNote: course.hasUnknownPrereqTokens
            )
        }

        if course.corequisiteExpr != .empty {
            requirementExpressionSection(
                title: "Coreqs",
                expr: course.corequisiteExpr,
                showsUnknownNote: false
            )
        }
    }

    private var displayedPrerequisiteExpr: PrereqExpr {
        if course.prerequisiteExpr != .empty {
            return course.prerequisiteExpr
        }
        switch course.prerequisites.count {
        case 0:
            return .empty
        case 1:
            return .course(course.prerequisites[0])
        default:
            return .all(course.prerequisites.map(PrereqExpr.course))
        }
    }

    private func requirementExpressionSection(title: String, expr: PrereqExpr, showsUnknownNote: Bool) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(DesignTokens.Typography.small)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .textCase(.uppercase)
            Text(expr.displayString(coursesByID: catalog.coursesByID))
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            if showsUnknownNote {
                Text("Some terms couldn't be parsed. See JMU catalog.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
    }

    private var professorSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            SectionHeader("Difficulty and professors")
            let detail = store.courseDetail?.course.id == course.id ? store.courseDetail : nil
            Text(detail?.rmpStatus ?? "Loading professor data...")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            if let url = detail?.rmpSearchURL {
                Link("Search JMU professors on Rate My Professors", destination: url)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.brandPurple)
            }

            if let professors = detail?.professors, !professors.isEmpty {
                ForEach(professors) { professor in
                    HStack {
                        Text(professor.name)
                            .font(DesignTokens.Typography.body)
                        Spacer()
                        Text(professor.rating.map { String(format: "%.1f", $0) } ?? "No reviews yet")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var linksSection: some View {
        if let url = course.registrarURL {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                SectionHeader("Links")
                Link("Open JMU registrar page", destination: url)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.brandPurple)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                width = max(width, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        totalHeight += rowHeight
        width = max(width, rowWidth)
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x - bounds.minX + size.width > maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
