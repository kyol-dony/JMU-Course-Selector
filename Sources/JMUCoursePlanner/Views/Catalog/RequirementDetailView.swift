import SwiftUI
import PlannerCore

/// The selected requirement on the catalog tab: its name, rule, credits and
/// catalog description, then a two-column grid of course blocks. General
/// Education shows each area as its own titled group.
struct RequirementDetailView: View {
    var entry: CatalogOutline.Entry
    var catalog: Catalog
    var slotMap: [String: Int]

    private let columns = [
        GridItem(.flexible(), spacing: 10, alignment: .top),
        GridItem(.flexible(), spacing: 10, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                switch entry.content {
                case .requirement(let category):
                    header(category, font: DesignTokens.Typography.heading)
                    courses(category)
                case .generalEducation(let areas):
                    Text(entry.name)
                        .font(DesignTokens.Typography.heading)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("Every JMU student completes these areas, whatever the major.")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    ForEach(areas) { area in
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                            header(area, font: DesignTokens.Typography.bodyEmphasized)
                            courses(area)
                        }
                        .padding(.top, DesignTokens.Spacing.s)
                    }
                case .degree(let requirement):
                    degreeDetail(requirement)
                }
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(entry.id)
    }

    /// A degree requirement has no fixed course list: its rule, the
    /// Registrar's eligibility in words, and the program's footnote.
    private func degreeDetail(_ requirement: DegreeRequirement) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Text(entry.name)
                .font(DesignTokens.Typography.heading)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            HStack(spacing: DesignTokens.Spacing.s) {
                Text(DegreeRequirementText.rule(for: requirement))
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(DesignTokens.Colors.brandPurple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(DesignTokens.Colors.brandPurpleSoft))
                Text(requirement.kind == .foreignLanguage ? "\(requirement.creditsText) credits, by placement" : "\(requirement.creditsText) credits")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .monospacedDigit()
            }
            Text(DegreeRequirementText.eligibility(for: requirement.kind))
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note = requirement.note, !note.isEmpty {
                Text(note)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private func header(_ category: RequirementCategory, font: Font) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Text(category.name)
                .font(font)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DesignTokens.Spacing.s) {
                Text(RequirementRuleText.label(for: category))
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(DesignTokens.Colors.brandPurple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(DesignTokens.Colors.brandPurpleSoft))
                Text(summary(category))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .monospacedDigit()
            }
            if let description = category.catalogDescription, !description.isEmpty {
                Text(description)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let note = category.note, !note.isEmpty {
                Text(note)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func courses(_ category: RequirementCategory) -> some View {
        let blocks = Self.blocks(for: category)
        if blocks.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Colors.warning)
                Text("The catalog doesn't give a fixed course list for this requirement.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(blocks, id: \.self) { block in
                    CatalogCourseBlock(
                        courseIDs: block.courseIDs,
                        isAlternatives: block.isAlternatives,
                        catalog: catalog,
                        remarks: category.courseRemarks,
                        slotMap: slotMap
                    )
                }
            }
        }
    }

    /// "9 credits · 4 options"; all-required lists count courses instead.
    private func summary(_ category: RequirementCategory) -> String {
        let count = Self.blocks(for: category).count
        let credits = "\(category.requiredCredits) credit\(category.requiredCredits == 1 ? "" : "s")"
        guard count > 0 else { return credits }
        if case .allRequired = category.selection {
            return "\(credits) · \(count) course\(count == 1 ? "" : "s")"
        }
        return "\(credits) · \(count) option\(count == 1 ? "" : "s")"
    }

    /// The blocks to show. An all-required list follows its slots, so the
    /// catalog's "A or B" stays one block; other rules show the parsed groups
    /// (a pair taken together is one block). Requirements parsed before
    /// groups existed show each distinct course on its own, since a legacy
    /// slot lists alternatives, not courses taken together.
    nonisolated static func blocks(for category: RequirementCategory) -> [CatalogBlockGroup] {
        if case .allRequired = category.selection, !category.courseOptions.isEmpty {
            return category.courseOptions.map { CatalogBlockGroup(courseIDs: $0, isAlternatives: $0.count > 1) }
        }
        if !category.choices.isEmpty {
            return category.choices.map { CatalogBlockGroup(courseIDs: $0, isAlternatives: false) }
        }
        var seen: Set<String> = []
        return category.courseOptions.flatMap { $0 }.filter { seen.insert($0).inserted }
            .map { CatalogBlockGroup(courseIDs: [$0], isAlternatives: false) }
    }
}

/// One course block's courses: taken together ("PSYC 210 & PSYC 211") or,
/// for an all-required slot, interchangeable ("SCOM 461 or SCOM 462").
struct CatalogBlockGroup: Hashable {
    var courseIDs: [String]
    var isAlternatives: Bool
}
