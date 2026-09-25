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
    /// Only called into, never observed: pointer movement must not re-render every chip.
    let drag: ScheduleDragController
    var onTap: () -> Void
    var onBegin: (_ start: CGPoint) -> Void
    var onEnd: (ScheduleDragController.EndResult) -> Void

    @State private var isPressed = false
    @State private var didStartDrag = false
    /// Session ID of the drag this gesture started, if the controller accepted it.
    @State private var owner: UUID?
    @GestureState private var isGestureActive = false

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
                    .updating($isGestureActive) { _, active, _ in active = true }
                    .onChanged { value in
                        isPressed = true
                        if didStartDrag {
                            drag.update(location: value.location, owner: owner)
                        } else if ScheduleDragGeometry.exceedsDragThreshold(value.translation) {
                            didStartDrag = true
                            onBegin(value.startLocation)
                            if let session = drag.session, session.itemID == itemID, drag.isDragging {
                                owner = session.id
                            }
                            drag.update(location: value.location, owner: owner)
                        }
                    }
                    .onEnded { value in
                        isPressed = false
                        if didStartDrag {
                            didStartDrag = false
                            let ended = owner
                            owner = nil
                            drag.update(location: value.location, owner: ended)
                            onEnd(drag.end(owner: ended))
                        } else {
                            onTap()
                        }
                    }
            )
            .onChange(of: isGestureActive) { _, active in
                guard !active else { return }
                // The gesture is over. onEnded normally cleans up first; if the
                // system cancelled the gesture without it, spring the drag back.
                Task { @MainActor in
                    isPressed = false
                    guard didStartDrag else { return }
                    didStartDrag = false
                    drag.cancelGesture(owner: owner)
                    owner = nil
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            .onDisappear { drag.disposeGesture(owner: owner) }
    }
}
