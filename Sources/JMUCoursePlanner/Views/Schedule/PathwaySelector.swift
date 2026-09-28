import PlannerCore
import SwiftUI

/// Shorter forms of a pathway name for narrow toolbars, longest first:
/// "Gen Ed-First Path" → "Gen Ed-First" → "Gen Ed".
enum PathwayLabel {
    static func levels(for name: String) -> [String] {
        var levels = [name]
        var current = name
        for suffix in [" Path", "-First"] where current.hasSuffix(suffix) {
            current = String(current.dropLast(suffix.count))
            levels.append(current)
        }
        return levels
    }

    /// The name at a shortening step; past its shortest form, the shortest form.
    static func label(for name: String, level: Int) -> String {
        let levels = levels(for: name)
        return levels[min(level, levels.count - 1)]
    }
}

/// Schedule toolbar pathway switcher. Same trough as the top-bar tabs but
/// quieter: the selected pathway is a raised Card Paper segment, no purple.
/// When space runs short, every label shortens one step together, never
/// truncating with an ellipsis.
struct PathwaySelector: View {
    var pathways: [Pathway]
    @Binding var selection: String

    @Namespace private var selectionNamespace
    @State private var hoveredID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            segments(level: 0)
            segments(level: 1)
            segments(level: 2)
        }
    }

    private func segments(level: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.button, style: .continuous)
        return HStack(spacing: 4) {
            ForEach(pathways) { pathway in
                segment(pathway, level: level)
            }
        }
        .padding(4)
        .background(shape.fill(DesignTokens.Colors.borderSubtle.opacity(0.45)))
        .overlay(shape.strokeBorder(DesignTokens.Colors.borderSubtle, lineWidth: 1))
        .fixedSize()
    }

    private func segment(_ pathway: Pathway, level: Int) -> some View {
        let isSelected = pathway.id == selection
        let isHovered = hoveredID == pathway.id
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.chip, style: .continuous)
        return Button {
            withAnimation(reduceMotion ? nil : DesignTokens.Motion.hover) {
                selection = pathway.id
            }
        } label: {
            Text(PathwayLabel.label(for: pathway.name, level: level))
                .font(DesignTokens.Typography.label)
                .foregroundStyle(isSelected || isHovered ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background {
                    if isSelected {
                        shape
                            .fill(DesignTokens.Colors.surfaceElevated)
                            .overlay(shape.strokeBorder(DesignTokens.Colors.borderSubtle, lineWidth: 1))
                            .shadow(color: DesignTokens.Colors.cardShadowLight, radius: 1, x: 0, y: 1)
                            // One id per shortening step: ViewThatFits builds every
                            // step, and a shared id would clash between them.
                            .matchedGeometryEffect(id: "selection-\(level)", in: selectionNamespace)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredID = pathway.id
            } else if hoveredID == pathway.id {
                hoveredID = nil
            }
        }
        .animation(DesignTokens.Motion.hover, value: isHovered)
        .help(pathway.name)
        .accessibilityLabel(pathway.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
