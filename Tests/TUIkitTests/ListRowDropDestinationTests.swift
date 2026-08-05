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

    /// The list the drag STARTED in, which the test above deliberately isn't.
    ///
    /// `DraggableModifier` renders the source view blank while it is carried —
    /// right on its own terms, since the view owns that space in the layout and
    /// a list closing up under the pointer would move the rows the drop is aimed
    /// between. Inside a list that is ALSO opening a landing slot for the same
    /// drag it is one line too many: the blank where the row *was*, plus the gap
    /// where it would *go*. The list grew by a line for the duration of every
    /// same-list drag, which is what "an errant blank line" was.
    ///
    /// `.onMove`'s own reorder has always drawn this as N−1 rows plus one slot.
    /// This is that rule reaching the `.draggable` + `ForEach.dropDestination`
    /// pair, which is how a row that can also change LISTS is written.
    @Test("A row dragged within its own list collapses; the slot is the only gap")
    func aRowDraggedWithinItsOwnListLeavesNoExtraLine() {
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
            availableWidth: 20, availableHeight: 12, environment: env, tuiContext: tui)

        func render() -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let view = List {
                ForEach(["AAA", "BBB", "CCC"], id: \.self) { name in
                    // The demo's shape: the Spacer makes the whole row width
                    // draggable rather than just the label.
                    HStack(spacing: 1) {
                        Text(name)
                        Spacer()
                    }
                    .draggable(name)
                }
                .dropDestination(for: String.self) { index, values in
                    log.inserted.append((index, values))
                }
            }
            .frame(height: 9)
            var inner = context
            inner.hasExplicitHeight = true
            let buffer = renderToBuffer(view, context: inner)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        func lineOf(_ name: String, in buffer: FrameBuffer) -> Int? {
            buffer.lines.firstIndex { $0.stripped.contains(name) }
        }

        let atRest = render()
        guard let restA = lineOf("AAA", in: atRest), let restB = lineOf("BBB", in: atRest),
            let restC = lineOf("CCC", in: atRest)
        else {
            Issue.record("the three rows are drawn at rest: \(atRest.lines.map(\.stripped))")
            return
        }
        #expect(restB == restA + 1 && restC == restB + 1, "one row per line at rest")

        // Grab AAA and drag it down onto CCC. A real press through the
        // dispatcher, not a synthetic `begin`: the whole point is that the
        // session knows WHICH view started this, and only the modifier's own
        // path records that.
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: restA))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 2, y: restC))

        let during = render()
        #expect(
            lineOf("AAA", in: during) == nil,
            "the carried row is not drawn in place: \(during.lines.map(\.stripped))")
        #expect(
            lineOf("BBB", in: during) == restA,
            """
            BBB closed up over the vacated line — it did not, so the blank and \
            the slot are both taking a line: \(during.lines.map(\.stripped))
            """)
        #expect(
            lineOf("CCC", in: during) == restC,
            "and CCC held its line: one row out, one slot in, no net change")
        // The gap is where the pointer is, immediately above CCC.
        #expect(
            during.lines[restC - 1].stripped.allSatisfy { " │".contains($0) },
            "the slot itself holds nothing: \(during.lines[restC - 1].stripped.debugDescription)")

        // Dropping still reports the index counted against the list's DATA, so
        // an app compensating for its own row (the row-transfer demo's
        // `from < index ? index - 1 : index`) keeps landing it in the same place.
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: restC))
        #expect(log.inserted.count == 1, "the drop was taken")
        #expect(log.inserted.first?.0 == 2, "before CCC, by data offset: \(log.inserted)")
        #expect(log.inserted.first?.1 == ["AAA"])
    }

    /// The other half of the rule above, and the reason it cannot simply drop
    /// "whichever row looks blank": a drag that came from ANOTHER list takes no
    /// row out of this one, so every row of ours stays drawn and the slot is a
    /// genuine extra line. Matching the drag's source by identity is what tells
    /// the two apart.
    @Test("A drag from another list still opens a gap without losing a row")
    func aDragFromAnotherListKeepsEveryRow() {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
        tui.mouseEventDispatcher.setActiveSupport(.full)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12, environment: env, tuiContext: tui)

        // Two lists side by side, both of draggable rows — the row-transfer
        // demo in miniature.
        func render() -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.dragAndDropSession.beginFrame()
            let view = HStack(alignment: .top, spacing: 2) {
                sideList(["AAA", "BBB"])
                sideList(["YYY", "ZZZ"])
            }
            var inner = context
            inner.hasExplicitHeight = true
            let buffer = renderToBuffer(view, context: inner)
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        let atRest = render()
        let restY = atRest.lines.firstIndex { $0.stripped.contains("YYY") } ?? -1
        let restZ = atRest.lines.firstIndex { $0.stripped.contains("ZZZ") } ?? -1
        #expect(restY >= 0 && restZ == restY + 1, "the right-hand list is drawn")

        // Press AAA in the LEFT list, drag over YYY in the right one.
        let restA = atRest.lines.firstIndex { $0.stripped.contains("AAA") } ?? -1
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 2, y: restA))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 24, y: restY))

        let during = render()
        #expect(
            during.lines.firstIndex { $0.stripped.contains("YYY") } == restY + 1,
            """
            the right list opened a gap and kept both its rows: \
            \(during.lines.map(\.stripped))
            """)
        #expect(
            during.lines.firstIndex { $0.stripped.contains("ZZZ") } == restZ + 1,
            "including the one below the gap")
        // And the list the row CAME from holds its shape: no slot is open there
        // — the pointer is elsewhere — so the blank `.draggable` leaves behind
        // is the only thing marking the row, and the rows below it stay put.
        // Collapsing here instead would shuffle the whole list up the moment the
        // pointer crossed out of it and back down when it returned.
        #expect(
            !during.lines.contains { $0.stripped.contains("AAA") },
            "the carried row is gone from the list it came from")
        #expect(
            during.lines.firstIndex { $0.stripped.contains("BBB") } == restA + 1,
            "but that list does not close up: with no slot of its own, nothing moves")

        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 24, y: restY))
    }

    /// One list of draggable rows that also accepts them — used twice by the
    /// cross-list test above, where the two must be separate `List`s (and so
    /// separate identities) for the source match to mean anything.
    @ViewBuilder private func sideList(_ names: [String]) -> some View {
        List {
            ForEach(names, id: \.self) { name in
                HStack(spacing: 1) {
                    Text(name)
                    Spacer()
                }
                .draggable(name)
            }
            .dropDestination(for: String.self) { _, _ in }
        }
        .frame(width: 14, height: 8)
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
