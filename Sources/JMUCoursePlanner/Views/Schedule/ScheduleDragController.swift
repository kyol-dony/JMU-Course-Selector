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

/// State machine for dragging a schedule item across the board.
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
        /// Cursor position in `ScheduleBoardSpace`.
        var location: CGPoint
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

    private var columns: [ColumnGeometry] = []
    private var suppressedItemID: String?
    private var escapeMonitor: Any?

    var isDragging: Bool { session != nil && !isReturning }

    /// Courses that dropping on the hovered column would break.
    var affectedCourseIDs: Set<String> {
        guard isDragging, let target = session?.target else { return [] }
        return verdicts[target.semester]?.affectedCourseIDs ?? []
    }

    func begin(
        itemID: String,
        origin: SemesterIdentity,
        originIndex: Int,
        location: CGPoint,
        grabOffset: CGSize,
        itemSize: CGSize,
        columns: [ColumnGeometry],
        verdicts: [SemesterIdentity: DropVerdict]
    ) {
        guard session == nil, suppressedItemID != itemID else { return }
        self.columns = columns
        self.verdicts = verdicts
        session = Session(
            itemID: itemID,
            origin: origin,
            originIndex: originIndex,
            grabOffset: grabOffset,
            itemSize: itemSize,
            location: location,
            target: ScheduleDragGeometry.target(for: location, columns: columns)
        )
    }

    func update(location: CGPoint) {
        guard isDragging, var session else { return }
        session.location = location
        session.target = ScheduleDragGeometry.target(for: location, columns: columns)
        self.session = session
    }

    /// Async calculations belong to one gesture, never merely to an item ID.
    func applyVerdicts(_ verdicts: [SemesterIdentity: DropVerdict], sessionID: UUID) {
        guard isDragging, session?.id == sessionID else { return }
        self.verdicts = verdicts
    }

    /// A removed chip cannot deliver onEnded. Dispose that gesture's latch.
    func disposeGesture(itemID: String) {
        if session?.itemID == itemID {
            clear()
            setEscapeMonitoring(false)
        }
        if suppressedItemID == itemID { suppressedItemID = nil }
    }

    func reset() {
        clear()
        suppressedItemID = nil
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
        if let location = session?.location {
            update(location: location)
        }
    }

    func end(itemID: String) -> EndResult {
        if suppressedItemID == itemID {
            suppressedItemID = nil
            return .ignored
        }
        guard let session, session.itemID == itemID, !isReturning else { return .ignored }
        if let target = session.target,
           !(target.semester == session.origin && target.index == session.originIndex) {
            clear()
            return .drop(ScheduleDrop(itemID: itemID, target: target))
        }
        startReturn()
        return .returnHome
    }

    /// Stops a live drag without committing (Esc, or the plan changed
    /// underneath). The rest of that item's gesture is ignored until it ends.
    func cancel() {
        guard let session, !isReturning else { return }
        suppressedItemID = session.itemID
        startReturn()
    }

    /// Moves the floating item during the return animation.
    func moveReturningItem(to location: CGPoint) {
        guard isReturning, var session else { return }
        session.location = location
        self.session = session
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
