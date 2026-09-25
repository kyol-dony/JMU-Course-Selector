import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Schedule drag geometry and controller")
@MainActor
struct ScheduleDragControllerTests {
    static let fall26 = SemesterIdentity(year: 2026, term: .fall)
    static let spring27 = SemesterIdentity(year: 2027, term: .spring)
    static let fall27 = SemesterIdentity(year: 2027, term: .fall)

    /// Fall 2026 holds three items (other than the dragged one); Spring 2027 is empty.
    static let columns = [
        ColumnGeometry(semester: fall26, frame: CGRect(x: 0, y: 0, width: 280, height: 540), itemMidYOffsets: [30, 90, 150]),
        ColumnGeometry(semester: spring27, frame: CGRect(x: 292, y: 0, width: 280, height: 540), itemMidYOffsets: [])
    ]

    static let blocking = DropVerdict(
        level: .blocking,
        headline: "Breaks 1 course",
        reason: "MATH 232 loses its prereq",
        newWarnings: [],
        fixedCount: 0,
        affectedCourseIDs: ["MATH232"]
    )

    @discardableResult
    private func beginDrag(_ controller: ScheduleDragController, itemID: String = "A") -> UUID? {
        controller.begin(
            itemID: itemID,
            origin: Self.fall26,
            originIndex: 0,
            location: CGPoint(x: 100, y: 10),
            grabOffset: CGSize(width: 10, height: 10),
            itemSize: CGSize(width: 256, height: 40),
            columns: Self.columns,
            verdicts: [Self.fall26: .neutral, Self.spring27: Self.blocking]
        )
    }

    // MARK: Geometry

    @Test("points map to a semester and an insertion index")
    func targetMapping() {
        #expect(ScheduleDragGeometry.target(for: CGPoint(x: 100, y: 10), columns: Self.columns) == DropTarget(semester: Self.fall26, index: 0))
        #expect(ScheduleDragGeometry.target(for: CGPoint(x: 100, y: 100), columns: Self.columns) == DropTarget(semester: Self.fall26, index: 2))
        #expect(ScheduleDragGeometry.target(for: CGPoint(x: 100, y: 500), columns: Self.columns) == DropTarget(semester: Self.fall26, index: 3))
    }

    @Test("an empty semester accepts drops at index 0")
    func emptyColumnTarget() {
        #expect(ScheduleDragGeometry.target(for: CGPoint(x: 400, y: 200), columns: Self.columns) == DropTarget(semester: Self.spring27, index: 0))
    }

    @Test("the gap between columns is not a target")
    func gapIsNotATarget() {
        #expect(ScheduleDragGeometry.target(for: CGPoint(x: 286, y: 100), columns: Self.columns) == nil)
    }

    @Test("column geometry skips the dragged item and measures from the column top")
    func columnGeometryBuilder() {
        let pathway = Pathway(id: "p", name: "P", semesters: [
            SemesterPlan(id: Self.fall26, courseIDs: ["A", "B", "C"]),
            SemesterPlan(id: Self.spring27, courseIDs: [])
        ])
        let columns = ScheduleDragGeometry.columns(
            pathway: pathway,
            draggedID: "B",
            columnFrames: [
                Self.fall26: CGRect(x: 0, y: 100, width: 280, height: 540),
                Self.spring27: CGRect(x: 292, y: 100, width: 280, height: 540)
            ],
            itemFrames: [
                "A": CGRect(x: 12, y: 150, width: 256, height: 40),
                "B": CGRect(x: 12, y: 210, width: 256, height: 40),
                "C": CGRect(x: 12, y: 270, width: 256, height: 40)
            ]
        )
        #expect(columns == [
            ColumnGeometry(semester: Self.fall26, frame: CGRect(x: 0, y: 100, width: 280, height: 540), itemMidYOffsets: [70, 190]),
            ColumnGeometry(semester: Self.spring27, frame: CGRect(x: 292, y: 100, width: 280, height: 540), itemMidYOffsets: [])
        ])
    }

    @Test("a drag starts at 4 points of movement")
    func dragThreshold() {
        #expect(!ScheduleDragGeometry.exceedsDragThreshold(CGSize(width: 3, height: 0)))
        #expect(ScheduleDragGeometry.exceedsDragThreshold(CGSize(width: 0, height: 4)))
        #expect(ScheduleDragGeometry.exceedsDragThreshold(CGSize(width: 3, height: 3)))
    }

    @Test("auto-scroll steps toward columns clipped by the edge the cursor is near")
    func autoScroll() {
        let viewport = CGSize(width: 600, height: 600)
        let clipped = [
            ColumnGeometry(semester: Self.fall26, frame: CGRect(x: -100, y: 0, width: 280, height: 540), itemMidYOffsets: []),
            ColumnGeometry(semester: Self.spring27, frame: CGRect(x: 192, y: 0, width: 280, height: 540), itemMidYOffsets: []),
            ColumnGeometry(semester: Self.fall27, frame: CGRect(x: 484, y: 0, width: 280, height: 540), itemMidYOffsets: [])
        ]
        #expect(ScheduleDragGeometry.autoScrollRequest(for: CGPoint(x: 20, y: 200), viewport: viewport, columns: clipped)
            == AutoScrollRequest(semester: Self.fall26, anchor: .leading))
        #expect(ScheduleDragGeometry.autoScrollRequest(for: CGPoint(x: 590, y: 200), viewport: viewport, columns: clipped)
            == AutoScrollRequest(semester: Self.fall27, anchor: .trailing))
        #expect(ScheduleDragGeometry.autoScrollRequest(for: CGPoint(x: 300, y: 200), viewport: viewport, columns: clipped) == nil)
        // Everything visible: nothing to scroll to.
        #expect(ScheduleDragGeometry.autoScrollRequest(for: CGPoint(x: 20, y: 200), viewport: viewport, columns: Self.columns) == nil)
        #expect(ScheduleDragGeometry.autoScrollRequest(for: CGPoint(x: 590, y: 200), viewport: viewport, columns: Self.columns) == nil)
    }

    // MARK: Controller

    @Test("dropping on the origin slot returns home instead of committing")
    func originSlotReturnsHome() {
        let controller = ScheduleDragController()
        let owner = beginDrag(controller)
        controller.update(location: CGPoint(x: 100, y: 10))
        #expect(controller.end(owner: owner) == .returnHome)
        #expect(controller.isReturning)
        #expect(!controller.isDragging)
        #expect(controller.verdicts.isEmpty)
        controller.finishReturn()
        #expect(controller.session == nil)
    }

    @Test("dropping in another semester commits the move")
    func dropCommits() {
        let controller = ScheduleDragController()
        let owner = beginDrag(controller)
        controller.update(location: CGPoint(x: 400, y: 200))
        #expect(controller.end(owner: owner) == .drop(ScheduleDrop(itemID: "A", target: DropTarget(semester: Self.spring27, index: 0))))
        #expect(controller.session == nil)
    }

    @Test("releasing outside every column returns home")
    func outsideReturnsHome() {
        let controller = ScheduleDragController()
        let owner = beginDrag(controller)
        controller.update(location: CGPoint(x: 286, y: 100))
        #expect(controller.end(owner: owner) == .returnHome)
    }

    @Test("red rings follow the hovered column's verdict")
    func affectedFollowsTarget() {
        let controller = ScheduleDragController()
        beginDrag(controller)
        controller.update(location: CGPoint(x: 400, y: 200))
        #expect(controller.affectedCourseIDs == ["MATH232"])
        controller.update(location: CGPoint(x: 100, y: 200))
        #expect(controller.affectedCourseIDs.isEmpty)
    }

    @Test("a cancelled drag ignores the rest of its gesture")
    func cancelIgnoresRestOfGesture() {
        let controller = ScheduleDragController()
        let owner = beginDrag(controller)
        controller.cancel()
        #expect(controller.isReturning)
        #expect(controller.verdicts.isEmpty)
        controller.finishReturn()

        // Mouse still held: that gesture's movement and release do nothing.
        controller.update(location: CGPoint(x: 400, y: 200), owner: owner)
        #expect(controller.session == nil)
        #expect(controller.end(owner: owner) == .ignored)

        // The next gesture starts a fresh drag.
        #expect(beginDrag(controller) != nil)
        #expect(controller.isDragging)
    }

    @Test("an old gesture cannot move, end, or dispose a newer drag")
    func staleGestureIsIgnored() throws {
        let controller = ScheduleDragController()
        let old = beginDrag(controller)
        controller.cancel()
        controller.finishReturn()
        let current = try #require(beginDrag(controller))
        controller.update(location: CGPoint(x: 400, y: 200), owner: current)

        controller.update(location: CGPoint(x: 100, y: 10), owner: old)
        controller.disposeGesture(owner: old)
        controller.cancelGesture(owner: old)
        #expect(controller.end(owner: old) == .ignored)

        #expect(controller.isDragging)
        #expect(controller.session?.target?.semester == Self.spring27)
    }

    @Test("a gesture that vanishes without ending springs its drag back")
    func vanishedGestureReturnsHome() {
        let controller = ScheduleDragController()
        let owner = beginDrag(controller)
        controller.cancelGesture(owner: owner)
        #expect(controller.isReturning)
        #expect(!controller.isDragging)
    }

    @Test("pointer movement within one slot does not republish the session")
    func pointerMovesWithoutSessionChurn() {
        let controller = ScheduleDragController()
        beginDrag(controller)
        controller.update(location: CGPoint(x: 400, y: 200))
        let session = controller.session
        controller.update(location: CGPoint(x: 410, y: 220))
        #expect(controller.session == session)
        #expect(controller.pointer.location == CGPoint(x: 410, y: 220))
    }

    @Test("a late finishReturn does not end a newer drag")
    func finishReturnOnlyWhileReturning() {
        let controller = ScheduleDragController()
        beginDrag(controller, itemID: "B")
        controller.finishReturn()
        #expect(controller.isDragging)
    }

    @Test("new column frames retarget the drag")
    func columnFramesRetarget() {
        let controller = ScheduleDragController()
        beginDrag(controller)
        controller.update(location: CGPoint(x: 400, y: 200))
        #expect(controller.session?.target?.semester == Self.spring27)
        // The board scrolled: Spring 2027 moved right, out from under the cursor.
        controller.updateColumnFrames([Self.spring27: CGRect(x: 600, y: 0, width: 280, height: 540)])
        #expect(controller.session?.target == nil)
    }

    @Test("late verdicts cannot update a newer drag of the same item")
    func staleVerdicts() throws {
        let controller = ScheduleDragController()
        let oldID = try #require(beginDrag(controller))
        controller.cancel()
        controller.finishReturn()
        let newID = try #require(beginDrag(controller))
        controller.applyVerdicts([:], sessionID: oldID)
        #expect(controller.verdicts[Self.spring27] == Self.blocking)
        controller.applyVerdicts([Self.spring27: .neutral], sessionID: newID)
        #expect(controller.verdicts[Self.spring27] == .neutral)
    }

    @Test("removing the owning gesture's view ends its drag")
    func removedGesture() {
        let controller = ScheduleDragController()
        let owner = beginDrag(controller)
        controller.disposeGesture(owner: owner)
        #expect(controller.session == nil)
        beginDrag(controller)
        #expect(controller.isDragging)
        controller.reset()
        #expect(controller.session == nil)
        #expect(controller.verdicts.isEmpty)
    }

    @Test("auto-scroll ignores pointers outside the viewport")
    func outsideViewport() {
        #expect(ScheduleDragGeometry.autoScrollRequest(
            for: CGPoint(x: 599, y: -20), viewport: CGSize(width: 600, height: 600),
            columns: [ColumnGeometry(semester: Self.fall26, frame: CGRect(x: 484, y: 0, width: 280, height: 540), itemMidYOffsets: [])]
        ) == nil)
    }
}
