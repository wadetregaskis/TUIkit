//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DragLiftTests.swift
//
//  The picture of a dragged row leaves the row it came from rather than
//  appearing over the pointer already carrying it. These measure the flight,
//  and the two things it must NOT disturb: the anchor math a drop reports, and
//  the walk home a cancel starts.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Drag lift")
struct DragLiftTests {

    private typealias Lift = DragAndDropSession.ActiveDrag

    /// A session with a drag opened from a press at `press` and the cursor
    /// since moved to `cursor`.
    private func dragging(
        press: (x: Int, y: Int), cursor: (x: Int, y: Int)
    ) -> DragAndDropSession {
        let session = DragAndDropSession()
        session.beginFrame()
        // The dispatcher normally stamps these; here the two positions ARE the
        // fixture — the press is where the row was, the drag is where the
        // pointer has got to.
        session.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .pressed, x: press.x, y: press.y)
        session.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: cursor.x, y: cursor.y)
        session.begin(
            payload: "row", preview: FrameBuffer(lines: ["ROW"]), grabX: 0, grabY: 0)
        return session
    }

    @Test("The picture starts where the row was and ends under the cursor")
    func theLiftTravels() {
        let session = dragging(press: (x: 2, y: 3), cursor: (x: 20, y: 9))
        // Before anything drives it, the picture is at the row's own place —
        // which is the hole the list has just opened where the row was.
        #expect(session.liftedPreviewFrame().map { ($0.x, $0.y) } ?? (-1, -1) == (2, 3))

        session.driveLift(nowNanos: 0)
        session.driveLift(nowNanos: Lift.liftDurationNanos / 2)
        let midway = session.liftedPreviewFrame()!
        #expect(midway.x > 2 && midway.x < 20, "halfway is between: \(midway)")
        #expect(midway.y > 3 && midway.y < 9, "halfway is between: \(midway)")

        session.driveLift(nowNanos: Lift.liftDurationNanos)
        #expect(session.liftedPreviewFrame().map { ($0.x, $0.y) } ?? (-1, -1) == (20, 9))
    }

    @Test("The lift asks for frames only while it is running")
    func theLiftStopsAskingForFrames() {
        // The loop is demand-driven: a flight that kept saying yes would hold
        // the app at 30 fps for the whole drag, and one that never said yes
        // would draw a single frame and freeze.
        let session = dragging(press: (x: 2, y: 3), cursor: (x: 20, y: 9))
        #expect(session.driveLift(nowNanos: 0), "the first frame anchors and continues")
        #expect(session.driveLift(nowNanos: Lift.liftDurationNanos / 2))
        #expect(!session.driveLift(nowNanos: Lift.liftDurationNanos))
        #expect(!session.driveLift(nowNanos: Lift.liftDurationNanos * 4), "and stays stopped")
    }

    @Test("The lift does not touch the anchor math a drop reports")
    func theAnchorMathIsUnchanged() {
        // `previewFrame()` is what a drop reports through `DropInfo` and what a
        // cancel measures its walk home from. It answers where the DRAG is; the
        // lift is about where its picture has got to, and the two must not be
        // the same number.
        let session = dragging(press: (x: 2, y: 3), cursor: (x: 20, y: 9))
        let before = session.previewFrame()
        session.driveLift(nowNanos: 0)
        session.driveLift(nowNanos: Lift.liftDurationNanos / 3)
        let during = session.previewFrame()
        #expect(before?.x == during?.x && before?.y == during?.y)
        #expect(during?.x == 20 && during?.y == 9, "the cursor, not the picture: \(during!)")
    }

    @Test("A drag that never moves has nowhere to lift to")
    func aMotionlessDragDoesNotTravel() {
        let session = dragging(press: (x: 5, y: 5), cursor: (x: 5, y: 5))
        session.driveLift(nowNanos: 0)
        session.driveLift(nowNanos: Lift.liftDurationNanos / 2)
        #expect(session.liftedPreviewFrame().map { ($0.x, $0.y) } ?? (-1, -1) == (5, 5))
    }
}
