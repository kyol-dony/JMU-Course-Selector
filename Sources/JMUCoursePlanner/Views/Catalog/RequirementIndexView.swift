import SwiftUI
import PlannerCore

/// The catalog tab's section index: a concentration menu (when the program
/// has concentrations), then the outline's sections with one row per
/// requirement.
struct RequirementIndexView: View {
    var program: Program
    var outline: CatalogOutline
    @Binding var concentrationID: String?
    @Binding var selectedEntryID: String?

    @State private var hoveredEntryID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                if !program.concentrations.isEmpty {
                    ConcentrationMenu(concentrations: program.concentrations, selection: $concentrationID)
                }
                ForEach(outline.sections) { section in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title.uppercased())
                            .font(DesignTokens.Typography.small)
                            .tracking(0.6)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.horizontal, DesignTokens.Spacing.s)
                            .padding(.bottom, 2)
                        ForEach(section.entries) { entry in
                            row(entry)
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.m)
        }
        .frame(width: 220)
    }

    private func row(_ entry: CatalogOutline.Entry) -> some View {
        let isSelected = entry.id == selectedEntryID
        let isHovered = entry.id == hoveredEntryID
        return Button {
            selectedEntryID = entry.id
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.s) {
                Text(entry.name)
                    .font(isSelected ? DesignTokens.Typography.label : DesignTokens.Typography.body)
                    .foregroundStyle(isSelected ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !entry.hasCourseList {
                    Circle()
                        .fill(DesignTokens.Colors.warning)
                        .frame(width: 6, height: 6)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                }
                Text(entry.creditsText)
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(isSelected ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.textTertiary)
                    .monospacedDigit()
                    .fixedSize()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, DesignTokens.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                    .fill(isSelected
                          ? DesignTokens.Colors.brandPurpleSoft
                          : isHovered ? DesignTokens.Colors.borderSubtle.opacity(0.45) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredEntryID = entry.id
            } else if hoveredEntryID == entry.id {
                hoveredEntryID = nil
            }
        }
        .animation(DesignTokens.Motion.hover, value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(entry.hasCourseList ? "" : "No fixed course list")
    }
}

/// A bordered button naming the shown concentration; it opens a popover
/// listing "None" and each concentration.
private struct ConcentrationMenu: View {
    var concentrations: [Concentration]
    @Binding var selection: String?

    @State private var isOpen = false
    @State private var isHovering = false
    @State private var hoveredID: String??

    private var selectedName: String {
        concentrations.first { $0.id == selection }?.name ?? "None"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
        Button {
            isOpen.toggle()
        } label: {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("CONCENTRATION")
                        .font(DesignTokens.Typography.small)
                        .tracking(0.6)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text(selectedName)
                        .font(DesignTokens.Typography.label)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, DesignTokens.Spacing.s)
            .background(shape.fill(DesignTokens.Colors.surfaceElevated))
            .overlay(shape.strokeBorder(isHovering || isOpen ? DesignTokens.Colors.borderStrong : DesignTokens.Colors.borderSubtle, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(DesignTokens.Motion.hover, value: isHovering)
        .accessibilityLabel("Concentration: \(selectedName)")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                option(id: nil, name: "None")
                ForEach(concentrations) { concentration in
                    option(id: concentration.id, name: concentration.name)
                }
            }
            .padding(6)
            .frame(width: 280)
        }
    }

    private func option(id: String?, name: String) -> some View {
        let isSelected = selection == id
        let isHovered = hoveredID == .some(id)
        return Button {
            selection = id
            isOpen = false
        } label: {
            HStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.brandPurple)
                    .opacity(isSelected ? 1 : 0)
                Text(name)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(isSelected ? DesignTokens.Colors.brandPurple : DesignTokens.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, DesignTokens.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
                    .fill(isSelected ? DesignTokens.Colors.brandPurpleSoft
                          : isHovered ? DesignTokens.Colors.borderSubtle.opacity(0.45) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredID = .some(id)
            } else if hoveredID == .some(id) {
                hoveredID = nil
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
