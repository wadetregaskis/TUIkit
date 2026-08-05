//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListRowDropDestinationTests.swift
//
//  `ForEach.dropDestination(for:action:)` — a drop that lands BETWEEN rows
//  rather than on a view. The list opens a landing slot under the pointer
//  while a compatible drag hovers, reports the index that slot sits at, and
//  keeps taking drops when it is empty or its scrolling is disabled.
//
//  The view-level modifier of the same name is `DragAndDropTests`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("List row drop destinations", .serialized)
struct ListRowDropDestinationTests {

    /// `ForEach.dropDestination(for:action:)` — the index-reporting sibling of
    /// the view-level modifier. A view destination only knows that something
    /// was dropped on it; this one knows between which rows, so the list can
    /// open a landing slot while the pointer moves.
    @Test("A drag over a list's rows opens a gap and lands at that index")
    func rowDropDestinationOpensAGapAndReportsTheIndex() {
        final class Log: @unchecked Sendable {
            var inserted: [(Int, [String])] = []
        }
        let log = Log()
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        tui.mouseEventDispatcher.setActiveSupport(.full)
        let context = RenderContext(
            availableWidth: 20, availableHeight: 10, environment: env, tuiContext: tui)

        let rows = ["a", "b", "c", "d"]
        func render() -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let view = List {
                ForEach(rows, id: \.self) { Text($0) }
                    .dropDestination(for: String.self) { index, values in
                        log.inserted.append((index, values))
                    }
            }
            .frame(height: 8)
            var inner = context
            inner.hasExplicitHeight = true
            let buffer = renderToBuffer(view, context: inner)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        let buffer = render()
        let rowY = buffer.lines.firstIndex { $0.stripped.contains("c") } ?? -1
        #expect(rowY > 0, "found row c")

        // A drag from somewhere else, hovering over row "c".
        tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 2, y: rowY)
        tui.dragAndDropSession.begin(payload: "zzz", preview: FrameBuffer(text: "zzz"))
        let hovering = render()
        let movedTo = hovering.lines.firstIndex { $0.stripped.contains("c") } ?? -1
        #expect(
            movedTo == rowY + 1,
            "a gap opened at the pointer, pushing row c down one: \(rowY) → \(movedTo)")
        #expect(
            !hovering.lines[rowY].stripped.contains { !" │".contains($0) },
            "and the gap itself holds nothing: \(hovering.lines[rowY].stripped.debugDescription)")

        // The pointer has not moved, but the frame it is over HAS: the gap is
        // now the line under it. Every later mouse report re-resolves the slot
        // against that frame, and the answer has to be the same one — the slot
        // used to read as "off the rows", jump to the end of the list, and come
        // back on the report after that.
        tui.dragAndDropSession.dragMoved()
        let steady = render()
        #expect(
            steady.lines.firstIndex { $0.stripped.contains("c") } == rowY + 1,
            "the gap stays where the pointer is")

        // And one line DOWN moves it one line down — not "nowhere", and not
        // stuck one row above the cursor.
        tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 2, y: rowY + 1)
        tui.dragAndDropSession.dragMoved()
        let lower = render()
        #expect(
            lower.lines.firstIndex { $0.stripped.contains("c") } == rowY,
            "row c is back above the gap: the gap followed the pointer down")

        tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 2, y: rowY)
        tui.dragAndDropSession.dragMoved()
        _ = render()
        _ = tui.dragAndDropSession.performDrop()
        #expect(log.inserted.count == 1, "the drop was taken")
        #expect(log.inserted.first?.0 == 2, "at row c's index: \(log.inserted)")
        #expect(log.inserted.first?.1 == ["zzz"])
    }

    /// Emptying a list used to make it permanently unfillable: the empty branch
    /// returned before ANY interaction was wired, so the list contributed no hit
    /// region and no drop target, and a drag over it resolved nothing and flew
    /// home. Empty is a state, not an absence.
    @Test("An empty list still takes a drop, at index 0")
    func emptyListStillAcceptsDrops() {
        final class Log: @unchecked Sendable {
            var inserted: [(Int, [String])] = []
        }
        let log = Log()
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        tui.mouseEventDispatcher.setActiveSupport(.full)
        let context = RenderContext(
            availableWidth: 20, availableHeight: 10, environment: env, tuiContext: tui)

        let rows: [String] = []
        func render() -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let view = List {
                ForEach(rows, id: \.self) { Text($0) }
                    .dropDestination(for: String.self) { index, values in
                        log.inserted.append((index, values))
                    }
            }
            .frame(height: 6)
            var inner = context
            inner.hasExplicitHeight = true
            let buffer = renderToBuffer(view, context: inner)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        let buffer = render()
        #expect(!buffer.hitTestRegions.isEmpty, "an empty list is still on screen and clickable")

        tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 3, y: 2)
        tui.dragAndDropSession.begin(payload: "zzz", preview: FrameBuffer(text: "zzz"))
        _ = render()
        #expect(tui.dragAndDropSession.performDrop(), "the empty list takes it")
        #expect(log.inserted.first?.0 == 0, "at the only index there is: \(log.inserted)")
        #expect(log.inserted.first?.1 == ["zzz"])
    }

    /// The List side of the rule the Table twin pins in
    /// `TableReorderDragTests.scrollDisabledTableStillAcceptsDrops`: a drop is
    /// not a scroll, so `.scrollDisabled` never withholds the drop target.
    @Test("A scroll-disabled list still takes a drop")
    func scrollDisabledListStillAcceptsDrops() {
        final class Log: @unchecked Sendable {
            var inserted: [(Int, [String])] = []
        }
        let log = Log()
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        tui.mouseEventDispatcher.setActiveSupport(.full)
        let context = RenderContext(
            availableWidth: 20, availableHeight: 10, environment: env, tuiContext: tui)

        func render() -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let view = List {
                ForEach(["a", "b", "c"], id: \.self) { Text($0) }
                    .dropDestination(for: String.self) { index, values in
                        log.inserted.append((index, values))
                    }
            }
            .scrollDisabled(true)
            .frame(height: 7)
            var inner = context
            inner.hasExplicitHeight = true
            let buffer = renderToBuffer(view, context: inner)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        _ = render()
        tui.dragAndDropSession.lastAbsoluteEvent = MouseEvent(
            button: .left, phase: .dragged, x: 3, y: 2)
        tui.dragAndDropSession.begin(payload: "zzz", preview: FrameBuffer(text: "zzz"))
        _ = render()
        #expect(tui.dragAndDropSession.performDrop(), "the pinned list takes it")
        #expect(log.inserted.count == 1)
        #expect(log.inserted.first?.1 == ["zzz"])
    }
}
