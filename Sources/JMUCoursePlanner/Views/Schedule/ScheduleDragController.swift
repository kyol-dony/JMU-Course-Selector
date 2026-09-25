import AppKit
import PlannerCore
import SwiftUI

/// Where a dragged item would land. `index` is the position in the target
/// semester after the dragged item is removed from its current spot, which is
/// exactly what `PlanStore.moveCourse(_:to:at:)` expects.
struct DropTarget: Equatable {
    var semester: SemesterIdentity
    var index: Int
}

struct ScheduleDrop: Equatable {
    var itemID: String
    var target: DropTarget
}

/// A semester column as the drag sees it. `frame` is live (it moves when the
/// board scrolls); `itemMidYOffsets` are captured when the drag starts,
/// measured from the column's top, so the opening insertion gap cannot feed
/// back into hit-testing.
struct ColumnGeometry: Equatable {
    var semester: SemesterIdentity
    var frame: CGRect
    var itemMidYOffsets: [CGFloat]
}

struct AutoScrollRequest: Equatable {
    var semester: SemesterIdentity
    var anchor: UnitPoint
}

/// Named coordinate space attached to the board's scroll view (viewport space).
enum ScheduleBoardSpace {
    static let name = "scheduleBoard"
}

/// Pure hit-testing and scroll math for board drags.
enum ScheduleDragGeometry {
    static let dragThreshold: CGFloat = 4
    static let autoScrollEdge: CGFloat = 60

    static func exceedsDragThreshold(_ translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) >= dragThreshold
    }

    static func columns(
        pathway: Pathway,
        draggedID: String,
        columnFrames: [SemesterIdentity: CGRect],
        itemFrames: [String: CGRect]
    ) -> [ColumnGeometry] {
        pathway.semesters.compactMap { semester in
            guard let frame = columnFrames[semester.id] else { return nil }
            let offsets = semester.courseIDs
                .filter { $0 != draggedID }
                .compactMap { itemFrames[$0] }
                .map { $0.midY - frame.minY }
            return ColumnGeometry(semester: semester.id, frame: frame, itemMidYOffsets: offsets)
        }
    }

    static func target(for point: CGPoint, columns: [ColumnGeometry]) -> DropTarget? {
        guard let column = columns.first(where: { $0.frame.contains(point) }) else { return nil }
        let localY = point.y - column.frame.minY
        let index = column.itemMidYOffsets.filter { $0 < localY }.count
        return DropTarget(semester: column.semester, index: index)
    }

    /// When the cursor is near the leading or trailing edge, the column to
    /// scroll into view next, or nil if nothing is clipped on that side.
    static func autoScrollRequest(for point: CGPoint, viewport: CGSize, columns: [ColumnGeometry]) -> AutoScrollRequest? {
        guard CGRect(origin: .zero, size: viewport).contains(point) else { return nil }
        let sorted = columns.sorted { $0.frame.minX < $1.frame.minX }
        if point.x < autoScrollEdge {
            guard let column = sorted.last(where: { $0.frame.minX < 0 }) else { return nil }
            return AutoScrollRequest(semester: column.semester, anchor: .leading)
        }
        if point.x > viewport.width - autoScrollEdge {
            guard let column = sorted.first(where: { $0.frame.maxX > viewport.width }) else { return nil }
            return AutoScrollRequest(semester: column.semester, anchor: .trailing)
        }
        return nil
    }
}

/// Cursor position during a drag, split from the session so pointer
/// movement only re-renders the views that follow the cursor.
@MainActor
final class DragPointer: ObservableObject {
    @Published fileprivate(set) var location: CGPoint = .zero
}

/// State machine for dragging a schedule item across the board. Each drag
/// is owned by one gesture, identified by the session ID `begin` returns;
/// gesture callbacks pass that ID so a stale gesture can never drive,
/// end, or dispose a newer drag.
@MainActor
final class ScheduleDragController: ObservableObject {
    struct Session: Equatable {
        let id = UUID()
        var itemID: String
        var origin: SemesterIdentity
        /// Index of the item in its semester's full list when the drag began.
        var originIndex: Int
        /// Cursor offset from the item's top-left corner.
        var grabOffset: CGSize
        var itemSize: CGSize
        var target: DropTarget?
    }

    enum EndResult: Equatable {
        case drop(ScheduleDrop)
        /// Released on its own slot or outside every column: animate back.
        case returnHome
        /// The gesture belonged to a cancelled or rejected drag.
        case ignored
    }

    @Published private(set) var session: Session?
    @Published private(set) var verdicts: [SemesterIdentity: DropVerdict] = [:]
    /// True while the floating item animates back to its slot.
    @Published private(set) var isReturning = false

    /// Cursor position in `ScheduleBoardSpace`.
    let pointer = DragPointer()
    private var columns: [ColumnGeometry] = []
    private var escapeMonitor: Any?

    var isDragging: Bool { session != nil && !isReturning }

    /// Courses that dropping on the hovered column would break.
    var affectedCourseIDs: Set<String> {
        guard isDragging, let target = session?.target else { return [] }
        return verdicts[target.semester]?.affectedCourseIDs ?? []
    }

    /// Starts a drag and returns its session ID, or nil when another drag
    /// (or a spring-back) is still in progress.
    @discardableResult
    func begin(
        itemID: String,
        origin: SemesterIdentity,
        originIndex: Int,
        location: CGPoint,
        grabOffset: CGSize,
        itemSize: CGSize,
        columns: [ColumnGeometry],
        verdicts: [SemesterIdentity: DropVerdict]
    ) -> UUID? {
        guard session == nil else { return nil }
        self.columns = columns
        self.verdicts = verdicts
        pointer.location = location
        let session = Session(
            itemID: itemID,
            origin: origin,
            originIndex: originIndex,
            grabOffset: grabOffset,
            itemSize: itemSize,
            target: ScheduleDragGeometry.target(for: location, columns: columns)
        )
        self.session = session
        return session.id
    }

    /// Moves the live drag, whichever gesture owns it (column-frame updates, tests).
    func update(location: CGPoint) {
        guard isDragging, let session else { return }
        pointer.location = location
        let target = ScheduleDragGeometry.target(for: location, columns: columns)
        // Publish the session only when the drop target changes.
        if target != session.target {
            self.session?.target = target
        }
    }

    /// Moves the drag only if `owner` is the gesture that started it.
    func update(location: CGPoint, owner: UUID?) {
        guard let owner, session?.id == owner else { return }
        update(location: location)
    }

    /// Async calculations belong to one gesture, never merely to an item ID.
    func applyVerdicts(_ verdicts: [SemesterIdentity: DropVerdict], sessionID: UUID) {
        guard isDragging, session?.id == sessionID else { return }
        self.verdicts = verdicts
    }

    /// The owning gesture's view went away (so it can never deliver
    /// onEnded): drop its drag immediately.
    func disposeGesture(owner: UUID?) {
        guard let owner, session?.id == owner else { return }
        clear()
    }

    /// The owning gesture was cancelled by the system without onEnded:
    /// spring the item back rather than leave the drag live.
    func cancelGesture(owner: UUID?) {
        guard let owner, session?.id == owner, !isReturning else { return }
        startReturn()
    }

    func reset() {
        clear()
        setEscapeMonitoring(false)
    }

    /// Live column frames from the board (they move when it scrolls).
    func updateColumnFrames(_ frames: [SemesterIdentity: CGRect]) {
        guard isDragging else { return }
        for index in columns.indices {
            if let frame = frames[columns[index].semester] {
                columns[index].frame = frame
            }
        }
        if session != nil {
            update(location: pointer.location)
        }
    }

    /// Release by the owning gesture: commit, or spring back when the drop
    /// would land on the item's own slot or outside every column.
    func end(owner: UUID?) -> EndResult {
        guard let owner, let session, session.id == owner, !isReturning else { return .ignored }
        if let target = session.target,
           !(target.semester == session.origin && target.index == session.originIndex) {
            clear()
            return .drop(ScheduleDrop(itemID: session.itemID, target: target))
        }
        startReturn()
        return .returnHome
    }

    /// Stops a live drag without committing (Esc, or the plan changed
    /// underneath). The still-held gesture's later callbacks find a
    /// returning or cleared session and are ignored.
    func cancel() {
        guard session != nil, !isReturning else { return }
        startReturn()
    }

    /// Moves the floating item during the return animation.
    func moveReturningItem(to location: CGPoint) {
        guard isReturning, session != nil else { return }
        pointer.location = location
    }

    func finishReturn() {
        guard isReturning else { return }
        clear()
    }

    /// Esc cancels a drag. Installed only while dragging.
    func setEscapeMonitoring(_ enabled: Bool) {
        if enabled, escapeMonitor == nil {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event } // Esc
                MainActor.assumeIsolated { self?.cancel() }
                return nil
            }
        } else if !enabled, let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    private func startReturn() {
        session?.target = nil
        verdicts = [:]
        isReturning = true
        setEscapeMonitoring(false)
    }

    private func clear() {
        setEscapeMonitoring(false)
        session = nil
        verdicts = [:]
        isReturning = false
        columns = []
    }
}
