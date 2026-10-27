import SwiftUI
import PlannerCore

/// A "Choose one of the following options" requirement as side-by-side
/// columns, one per option. Pure, so the catalog tab's layout is testable
/// without a view.
struct OptionColumns: Equatable {
    struct Part: Equatable {
        enum Kind: Equatable {
            /// "6 credits" of an elective pool, with the pool's rule in words.
            case pool(credits: Int, rule: String)
            case choose(count: Int)
            case required
        }

        var kind: Kind
        var title: String
        var blocks: [CatalogBlockGroup]
        /// "Or take both": these courses together instead of choosing.
        var alternative: CatalogBlockGroup?
        var remarks: [String: [String]] = [:]
    }

    struct Column: Equatable {
        var optionID: String
        var label: String
        var parts: [Part]
        var state: State
    }

    /// `browsing`: the program is not in the student's plan.
    enum State: Equatable { case browsing, inPlan, available }

    let columns: [Column]

    /// A nil `chosenOptionID` puts every column in `.browsing`.
    init(category: RequirementCategory, chosenOptionID: String?) {
        columns = (category.options ?? []).map { option in
            Column(
                optionID: option.id,
                label: option.label,
                parts: option.parts.map(Self.part),
                state: chosenOptionID == nil ? .browsing : (option.id == chosenOptionID ? .inPlan : .available)
            )
        }
    }

    private static func part(_ part: RequirementCategory) -> Part {
        let alternative = (part.alternativeGroup?.isEmpty == false)
            ? part.alternativeGroup.map { CatalogBlockGroup(courseIDs: $0, isAlternatives: false) }
            : nil
        func built(_ kind: Part.Kind, title: String, blocks: [CatalogBlockGroup]) -> Part {
            Part(kind: kind, title: title, blocks: blocks, alternative: alternative, remarks: part.courseRemarks)
        }

        if let rule = poolRule(of: part) {
            return built(.pool(credits: part.requiredCredits, rule: rule), title: "\(part.requiredCredits) credits", blocks: [])
        }
        let blocks = RequirementDetailView.blocks(for: part)
        switch part.selection {
        case .chooseCourses(let count), .chooseGroups(let count):
            return built(.choose(count: count), title: "Choose \(numberWord(count))", blocks: blocks)
        case .allRequired:
            // One slot with several courses is "pick one of these", whatever
            // the catalog's wording: show each course as its own block.
            if part.courseOptions.count == 1, let slot = part.courseOptions.first, slot.count > 1 {
                return built(.choose(count: 1), title: "Choose one",
                             blocks: slot.map { CatalogBlockGroup(courseIDs: [$0], isAlternatives: false) })
            }
            return built(.required, title: part.name, blocks: blocks)
        case .chooseCredits, .unknown:
            return built(.required, title: RequirementRuleText.label(for: part), blocks: blocks)
        }
    }

    /// The pool's rule ("MATH electives at MATH 310 or above") when the part
    /// is an elective pool: its name drops the leading "6 credits of", else
    /// the rule is read back from the pool token.
    private static func poolRule(of part: RequirementCategory) -> String? {
        let token = part.courseOptions.lazy.compactMap(\.first).first(where: ElectivePool.isToken)
        guard token != nil || part.electivePoolSlots?.isEmpty == false else { return nil }
        if let match = part.name.range(of: #"(?i)^\s*\d+\s+credits?\s+of\s+"#, options: .regularExpression) {
            let rule = part.name[match.upperBound...].trimmingCharacters(in: .whitespaces)
            if !rule.isEmpty { return rule }
        }
        if let token, let rule = rule(fromToken: token) { return rule }
        return part.name
    }

    /// "pool:MATH:310" -> "MATH electives at MATH 310 or above"; a pool that
    /// stops below the graduate range names both ends.
    private static func rule(fromToken token: String) -> String? {
        let fields = token.split(separator: ":").map(String.init)
        guard fields.count >= 3, let minimum = Int(fields[2]) else { return nil }
        let subject = fields[1]
        if fields.count > 3, let maximum = Int(fields[3]), maximum < ElectivePool.maximumNumber {
            return "\(subject) electives from \(subject) \(minimum) to \(maximum)"
        }
        return "\(subject) electives at \(subject) \(minimum) or above"
    }

    private static func numberWord(_ count: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return words.indices.contains(count) ? words[count] : "\(count)"
    }
}

/// The columns on screen. The chosen option is outlined in Royal Purple and
/// labelled "In your plan"; the others offer "Use this option".
struct OptionColumnsView: View {
    @EnvironmentObject private var store: PlanStore
    var category: RequirementCategory
    var chosenOptionID: String?
    /// Switch the plan to an option; nil when the program isn't in the plan.
    var onUse: ((String) -> Void)?
    var catalog: Catalog
    var slotMap: [String: Int]

    private let blockColumns = [
        GridItem(.flexible(), spacing: 6, alignment: .top),
        GridItem(.flexible(), spacing: 6, alignment: .top)
    ]

    var body: some View {
        let model = OptionColumns(category: category, chosenOptionID: chosenOptionID)
        HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
            ForEach(model.columns, id: \.optionID) { column in
                columnView(column)
            }
        }
    }

    private func columnView(_ column: OptionColumns.Column) -> some View {
        let isChosen = column.state == .inPlan
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.s) {
                Text(column.label)
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer(minLength: DesignTokens.Spacing.s)
                switch column.state {
                case .inPlan:
                    Text("In your plan")
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DesignTokens.Colors.brandPurple))
                case .available:
                    if let onUse {
                        Button("Use this option") { onUse(column.optionID) }
                            .buttonStyle(.dtSecondary)
                            .disabled(!store.canEditSchedule)
                    }
                case .browsing:
                    EmptyView()
                }
            }
            ForEach(Array(column.parts.enumerated()), id: \.offset) { _, part in
                partView(part)
            }
        }
        .padding(DesignTokens.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(shape.fill(isChosen ? DesignTokens.Colors.brandPurpleSoft : DesignTokens.Colors.surfaceElevated))
        .overlay(shape.strokeBorder(isChosen ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.borderSubtle, lineWidth: isChosen ? 1.5 : 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isChosen ? "\(column.label), in your plan" : column.label)
    }

    private func partView(_ part: OptionColumns.Part) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(DesignTokens.Colors.borderSubtle)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(part.title)
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                if case .pool(_, let rule) = part.kind {
                    Text(rule)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.brandPurple)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                                .strokeBorder(DesignTokens.Colors.brandPurple.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                } else {
                    if !part.blocks.isEmpty {
                        LazyVGrid(columns: blockColumns, alignment: .leading, spacing: 6) {
                            ForEach(part.blocks, id: \.self) { block in
                                courseBlock(block, remarks: part.remarks)
                            }
                        }
                    }
                }
                if let alternative = part.alternative {
                    Text("— or take both —")
                        .font(DesignTokens.Typography.small)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                    courseBlock(alternative, remarks: part.remarks)
                }
            }
        }
    }

    private func courseBlock(_ block: CatalogBlockGroup, remarks: [String: [String]]) -> some View {
        CatalogCourseBlock(
            courseIDs: block.courseIDs,
            isAlternatives: block.isAlternatives,
            catalog: catalog,
            remarks: remarks,
            slotMap: slotMap
        )
    }
}
