import PlannerCore
import SwiftUI

/// Frames of schedule items, keyed by item ID, in `ScheduleBoardSpace`.
struct ScheduleItemFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Frames of semester columns, in `ScheduleBoardSpace`.
struct ScheduleColumnFramesKey: PreferenceKey {
    static let defaultValue: [SemesterIdentity: CGRect] = [:]

    static func reduce(value: inout [SemesterIdentity: CGRect], nextValue: () -> [SemesterIdentity: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Makes a schedule chip pressable, tappable, and draggable. A press that
/// moves less than the drag threshold is a tap; anything further starts a
/// board drag through the shared controller.
struct DraggableScheduleItem: ViewModifier {
    var itemID: String
    @ObservedObject var drag: ScheduleDragController
    var onTap: () -> Void
    var onBegin: (_ start: CGPoint) -> Void
    var onEnd: (ScheduleDragController.EndResult) -> Void

    @State private var isPressed = false
    @State private var didStartDrag = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !didStartDrag ? 0.98 : 1)
            .animation(DesignTokens.Motion.hover, value: isPressed)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ScheduleItemFramesKey.self,
                        value: [itemID: proxy.frame(in: .named(ScheduleBoardSpace.name))]
                    )
                }
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(ScheduleBoardSpace.name))
                    .onChanged { value in
                        isPressed = true
                        if didStartDrag {
                            drag.update(location: value.location)
                        } else if ScheduleDragGeometry.exceedsDragThreshold(value.translation) {
                            didStartDrag = true
                            onBegin(value.startLocation)
                            drag.update(location: value.location)
                        }
                    }
                    .onEnded { value in
                        isPressed = false
                        if didStartDrag {
                            didStartDrag = false
                            drag.update(location: value.location)
                            onEnd(drag.end(itemID: itemID))
                        } else {
                            onTap()
                        }
                    }
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            .onDisappear { drag.disposeGesture(itemID: itemID) }
    }
}
