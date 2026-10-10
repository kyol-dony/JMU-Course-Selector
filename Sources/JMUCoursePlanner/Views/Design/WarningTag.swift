import SwiftUI

/// Compact one-line warning indicator. A real button, so clicks open its
/// popover and never start a chip drag or open course details.
struct WarningTag<PopoverContent: View>: View {
    var model: WarningTagModel
    @Binding var isPresented: Bool
    @ViewBuilder var popover: () -> PopoverContent

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.tone == .kept ? "checkmark" : "exclamationmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(iconColor))
                Text(model.label)
                    .font(DesignTokens.Typography.small)
                    .foregroundStyle(model.tone == .kept ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.leading, 2)
            .padding(.trailing, 7)
            .padding(.vertical, 1)
            .background(Capsule(style: .continuous).fill(fill))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
        .help(helpText)
        .accessibilityLabel(model.tone == .kept ? "Kept warning: \(model.primary.summary)" : "Warning: \(helpText)")
        .popover(isPresented: $isPresented, arrowEdge: .trailing, content: popover)
    }

    /// A pending prerequisite choice explains itself on hover: which
    /// choices support which later courses.
    private var helpText: String {
        guard model.primary.kind == .pendingPrerequisiteChoice else { return model.primary.summary }
        return "\(model.primary.summary). \(model.primary.detail)"
    }

    private var iconColor: Color {
        switch model.tone {
        case .mustFix: DesignTokens.Colors.danger
        case .worthALook: DesignTokens.Colors.warning
        case .kept: DesignTokens.Colors.borderStrong
        }
    }

    private var fill: Color {
        switch model.tone {
        case .mustFix: DesignTokens.Colors.danger.opacity(0.11)
        case .worthALook: DesignTokens.Colors.warning.opacity(0.13)
        case .kept: DesignTokens.Colors.surface
        }
    }
}
