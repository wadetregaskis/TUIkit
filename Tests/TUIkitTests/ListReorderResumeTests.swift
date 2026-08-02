//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListReorderResumeTests.swift
//
//  A reorder that leaves its page mid-gesture and comes back. What makes this
//  different from every other reorder suite is the STATE PASS: these renders
//  drive `StateStorage`'s pass boundaries the way the run loop does, so a list
//  that stops rendering really does lose its handler and really does come back
//  as a new one — which is the whole situation under test.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Counts `onMove` calls from outside the view's own state, so a move that
/// lands somewhere nothing reads is still visible to the test.
@MainActor
private final class MoveLog {
    private(set) var moves = 0
    func record() { moves += 1 }
}

/// The page under test. Its row order is `@State`, deliberately: that is what
/// makes leaving destructive — the departed page's box is pruned, so a drop
/// committed by the orphaned handler writes where nothing will ever read it,
/// which is precisely the failure this suite is about.
private struct ReorderPage: View {
    let log: MoveLog
    @State private var items = ["a", "b", "c", "d", "e"]

    var body: some View {
        List(selection: .constant(String?.none)) {
            ForEach(items, id: \.self) { Text($0) }
                .onMove { offsets, destination in
                    log.record()
                    items.move(fromOffsets: offsets, toOffset: destination)
                }
        }
        .frame(height: 9)
    }
}

/// A page that shows either the reorderable list or something else entirely,
/// rendered through real render passes so leaving prunes the list's state.
@MainActor
private final class ReorderPageFixture {
    let log = MoveLog()
    var moves: Int { log.moves }
    let tui = TUIContext()
    var env = EnvironmentValues()

    init(feedback: RowReorderFeedback = .dimmed) {
        env.focusManager = FocusManager()
        env.rowReorderFeedback = feedback
        env.applyRuntimeServices(from: tui)
        tui.mouseEventDispatcher.setActiveSupport(.full)
    }

    var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }
    var session: DragAndDropSession? { tui.dragAndDropSession }

    /// One frame, with the same begin/end bracketing the run loop uses.
    @discardableResult
    func render(showsList: Bool) -> FrameBuffer {
        dispatcher.beginRenderPass()
        session?.beginFrame()
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }

        let view: AnyView =
            showsList ? AnyView(ReorderPage(log: log)) : AnyView(Text("another page"))

        var context = RenderContext(
            availableWidth: 20, availableHeight: 11, environment: env, tuiContext: tui)
        context.hasExplicitHeight = true
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)
        return buffer
    }

    /// The row labels in the order they are drawn.
    func rows(_ buffer: FrameBuffer) -> [String] {
        buffer.lines.compactMap { line in
            ["a", "b", "c", "d", "e"].first { line.stripped.contains($0) }
        }
    }

    func rowY(_ buffer: FrameBuffer, _ label: String) -> Int {
        buffer.lines.firstIndex { $0.stripped.contains(label) } ?? -1
    }

    func press(_ buffer: FrameBuffer, on label: String) {
        dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: rowY(buffer, label)))
    }

    func drag(_ buffer: FrameBuffer, to label: String) {
        dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: rowY(buffer, label)))
    }

    func release(_ buffer: FrameBuffer, on label: String) {
        dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: rowY(buffer, label)))
    }
}

@Suite("List reorder across pages")
@MainActor
struct ListReorderResumeTests {
    @Test("A reorder survives leaving the page and coming back")
    func reorderResumesAfterPageChange() {
        let fixture = ReorderPageFixture()
        let first = fixture.render(showsList: true)
        fixture.press(first, on: "a")
        fixture.drag(first, to: "c")
        let started = fixture.session?.reorderHandler

        // Away, and back: the list stops rendering, so its `StateStorage` box is
        // pruned and the handler holding the rows is orphaned. Returning builds a
        // brand-new one — the object the drop has to run against, because it is
        // the only one drawing anything or holding a live `onMove`.
        fixture.render(showsList: false)
        let resumed = fixture.render(showsList: true)
        let carrying = fixture.session?.reorderHandler
        #expect(started != nil)
        // The premise of the whole test: a different object came back. Without
        // this the rest proves nothing.
        #expect(started !== carrying)
        #expect(carrying?.isReordering == true)

        fixture.release(resumed, on: "c")
        #expect(fixture.moves == 1)
        // Read off the SCREEN, not off a counter: the move has to land in the
        // state the visible list draws from, which is the half an orphaned
        // handler gets wrong while still reporting that it moved something.
        #expect(fixture.rows(fixture.render(showsList: true)) == ["b", "c", "a", "d", "e"])
    }

    @Test("Releasing while the list is off the page moves nothing")
    func releaseAwayFromTheListCancels() {
        let fixture = ReorderPageFixture()
        let first = fixture.render(showsList: true)
        fixture.press(first, on: "a")
        fixture.drag(first, to: "c")

        // Released somewhere the rows are not: nothing on screen can take them,
        // so the gesture ends as a cancel rather than landing unseen.
        let away = fixture.render(showsList: false)
        fixture.release(away, on: "another")
        #expect(fixture.moves == 0)

        // And the gesture is over: coming back and releasing again must not
        // resurrect it.
        let back = fixture.render(showsList: true)
        fixture.release(back, on: "c")
        #expect(fixture.moves == 0)
        #expect(fixture.rows(fixture.render(showsList: true)) == ["a", "b", "c", "d", "e"])
    }

    /// Leave TWICE. The first departure orphans the press-captured handler and
    /// the return adopts the reorder onto a replacement; the second departure
    /// frees that replacement too (the session holds it weakly), so at release
    /// there is neither a host on screen nor a live orphan. That release still
    /// has to END the gesture: it used to return `false`, leaving the session's
    /// drag active — the floating row stayed painted at the last cursor
    /// position for the rest of the session (nothing ends a drag but a new one)
    /// — and then fall through to the click path, mutating an off-screen list's
    /// selection through press-frame geometry.
    @Test("Releasing after the resumed list is freed ends the drag, not a click")
    func releaseAfterAdoptedHandlerIsFreed() {
        let fixture = ReorderPageFixture(feedback: .cursor)
        let first = fixture.render(showsList: true)
        fixture.press(first, on: "a")
        fixture.drag(first, to: "c")
        #expect(fixture.session?.active != nil, "a `.cursor` drag floats the row")

        // Away, back (adoption), and away again (the adopted handler is freed).
        fixture.render(showsList: false)
        fixture.render(showsList: true)
        fixture.render(showsList: false)
        let away = fixture.render(showsList: false)
        #expect(
            fixture.session?.reorderHandler == nil,
            "the adopted handler really was freed — the premise of this test")

        fixture.release(away, on: "another")
        #expect(fixture.moves == 0, "nothing was moved")
        #expect(
            fixture.session?.active == nil,
            "the drag ended: no preview left painted over every later frame")

        // And the gesture is over for good — coming back must not resurrect it.
        let back = fixture.render(showsList: true)
        fixture.release(back, on: "c")
        #expect(fixture.moves == 0)
        #expect(fixture.rows(fixture.render(showsList: true)) == ["a", "b", "c", "d", "e"])
    }

    @Test("A reorder that never leaves its page still drops where it points")
    func plainReorderIsUnchanged() {
        let fixture = ReorderPageFixture()
        let buffer = fixture.render(showsList: true)
        fixture.press(buffer, on: "a")
        fixture.drag(buffer, to: "c")
        fixture.release(buffer, on: "c")
        #expect(fixture.moves == 1)
        #expect(fixture.rows(fixture.render(showsList: true)) == ["b", "c", "a", "d", "e"])
    }
}
