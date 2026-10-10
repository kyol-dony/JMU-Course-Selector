import Foundation
import PlannerCore
import SwiftUI

struct CoursePickerEntry: Identifiable {
    let course: Course
    let searchKey: String

    var id: String { course.id }
}

struct CoursePickerIndex {
    let entries: [CoursePickerEntry]

    init(courses: [Course]) {
        entries = courses
            .sorted { lhs, rhs in
                let codeOrder = lhs.code.localizedStandardCompare(rhs.code)
                if codeOrder != .orderedSame {
                    return codeOrder == .orderedAscending
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            .map { course in
                CoursePickerEntry(
                    course: course,
                    searchKey: Self.normalize("\(course.code) \(course.title)")
                )
            }
    }

    func entries(matching query: String) -> [CoursePickerEntry] {
        let terms = Self.normalize(query).split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return entries }
        return entries.filter { entry in
            terms.allSatisfy { entry.searchKey.contains($0) }
        }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

enum PlaceholderCoursePickerPolicy {
    /// The slot's menu, from the same domain prerequisite analysis reasons
    /// over, so a highlighted choice is always one the picker offers.
    static func eligibleCourses(for spec: PlaceholderSpec, catalog: Catalog) -> [Course] {
        let coursesByID = catalog.coursesByID
        return PlaceholderCourseDomain.eligibleCourseIDs(for: spec, catalog: catalog).compactMap { coursesByID[$0] }
    }
}

struct CoursePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var index: CoursePickerIndex

    private let title: String
    /// Why this placeholder matters to later courses, and which choices
    /// support them. Marks rows only; every course stays selectable.
    private let dependencyPresentation: PlaceholderDependencyPresentation?
    private let onSelect: (Course) -> Void

    init(
        title: String,
        courses: [Course],
        dependencyPresentation: PlaceholderDependencyPresentation? = nil,
        onSelect: @escaping (Course) -> Void
    ) {
        self.title = title
        _index = State(initialValue: CoursePickerIndex(courses: courses))
        self.dependencyPresentation = dependencyPresentation
        self.onSelect = onSelect
    }

    var body: some View {
        let results = index.entries(matching: query)
        VStack(spacing: 0) {
            header(resultCount: results.count)
            Divider()
            courseList(results: results)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 500, idealHeight: 620)
        .background(DesignTokens.Colors.surface)
    }

    private func header(resultCount: Int) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignTokens.Typography.heading)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("\(resultCount) course\(resultCount == 1 ? "" : "s")")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close")
            }

            if let dependencyPresentation {
                dependencyNotice(dependencyPresentation)
            }

            HStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                TextField("Search by course code or title", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .stroke(DesignTokens.Colors.borderSubtle)
            )
        }
        .padding(DesignTokens.Spacing.l)
    }

    private func dependencyNotice(_ presentation: PlaceholderDependencyPresentation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.Colors.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.summary)
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(presentation.detail + " Any course here can still be chosen.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignTokens.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                .fill(DesignTokens.Colors.warning.opacity(0.13))
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func courseList(results: [CoursePickerEntry]) -> some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(results) { entry in
                Button {
                    onSelect(entry.course)
                    dismiss()
                } label: {
                    HStack(spacing: DesignTokens.Spacing.m) {
                        Text(entry.course.code)
                            .font(DesignTokens.Typography.bodyEmphasized)
                            .foregroundStyle(DesignTokens.Colors.brandPurple)
                            .frame(width: 90, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.course.title)
                                .font(DesignTokens.Typography.body)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .lineLimit(2)
                            if let support = dependencyPresentation?.labelsByCourseID[entry.course.id] {
                                Label(support, systemImage: "arrow.turn.down.right")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: DesignTokens.Spacing.m)
                        Text("\(entry.course.credits) cr")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rowAccessibilityLabel(entry.course))
            }
            .listStyle(.inset)
        }
    }

    private func rowAccessibilityLabel(_ course: Course) -> String {
        let base = "\(course.code), \(course.title), \(course.credits) credits"
        guard let support = dependencyPresentation?.labelsByCourseID[course.id] else { return base }
        return "\(base). \(support)"
    }
}
