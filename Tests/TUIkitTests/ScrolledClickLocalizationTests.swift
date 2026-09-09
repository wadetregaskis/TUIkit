//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrolledClickLocalizationTests.swift
//
//  A control scrolled partly off the top of an enclosing ScrollView keeps its
//  full coordinate space — the rows above the fold still exist, they are just
//  not drawn. The dispatcher hands handlers region-LOCAL coordinates, so that
//  localisation has to be measured from where the control begins, not from
//  where the viewport cut it. Getting it wrong shifts every click inside the
//  control up by exactly the number of clipped rows, which is invisible until
//  something in the control cares about y — a Table row, a List row, a text
//  cursor.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Clicks inside a scrolled-off control localise to the control")
struct ScrolledClickLocalizationTests {

    // MARK: - The seam itself

    /// The dispatcher's contract in isolation: `topClip` records how far above
    /// its clipped top the region really starts, so a click's local y must be
    /// measured from there.
    @Test("A clipped region localises against its unclipped origin")
    func clippedRegionLocalisesAgainstOrigin() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var seen: [Int] = []
        let id = dispatcher.register { event in
            seen.append(event.y)
            return true
        }

        // A 20-row control whose first 5 rows have been scrolled off the top:
        // rows 5..<20 of the control are drawn at screen rows 0..<15.
        var region = HitTestRegion(
            offsetX: 0, offsetY: 0, width: 10, height: 15, handlerID: id)
        region.topClip = 5
        dispatcher.setRegions([region])

        #expect(dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 0)))
        #expect(dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 10)))
        #expect(
            seen == [5, 15],
            "screen rows 0 and 10 are the control's own rows 5 and 15; got \(seen)")
    }

    /// The same for the drag-capture path: once a press is claimed every later
    /// event routes back to that handler using the captured offset, which has
    /// to be the same unclipped origin or a drag jumps the moment it starts.
    @Test("A captured drag keeps localising against the unclipped origin")
    func capturedDragLocalisesAgainstOrigin() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var seen: [Int] = []
        let id = dispatcher.register { event in
            seen.append(event.y)
            return true
        }
        var region = HitTestRegion(
            offsetX: 0, offsetY: 0, width: 10, height: 15, handlerID: id)
        region.topClip = 4
        dispatcher.setRegions([region])

        #expect(dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 1, y: 2)))
        #expect(dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: 1, y: 6)))
        #expect(dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 1, y: 6)))
        #expect(
            seen == [6, 10, 10],
            "the whole gesture is measured from the control's own top; got \(seen)")
    }

    /// And for the pass-through path a speculative claimant uses to hand the
    /// click on to whatever it was sitting on.
    @Test("A click passed through to the region behind localises against its origin")
    func regionBehindLocalisesAgainstOrigin() {
        let dispatcher = MouseEventDispatcher()
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var seen: [Int] = []
        let front = dispatcher.register { _ in false }
        let back = dispatcher.register { event in
            seen.append(event.y)
            return true
        }
        var behind = HitTestRegion(
            offsetX: 0, offsetY: 0, width: 10, height: 15, handlerID: back)
        behind.topClip = 3
        dispatcher.setRegions([
            behind,
            HitTestRegion(offsetX: 0, offsetY: 0, width: 10, height: 15, handlerID: front),
        ])

        // Screen row 7, in the (unclipped) front region's local space.
        #expect(
            dispatcher.passClickThrough(
                from: front, event: MouseEvent(button: .left, phase: .pressed, x: 1, y: 7)))
        #expect(
            seen == [10, 10],
            "screen row 7 is the back control's own row 10, for press and release; got \(seen)")
    }

    // MARK: - App-shaped

    private struct Item: Identifiable, Sendable {
        let id: Int
        let name: String
    }

    /// The reported bug: a Table on a scrollable page. Once the page has been
    /// scrolled far enough to push the table's header off the top, clicking a
    /// row selected one that many rows higher up.
    @Test("Clicking a row of a scrolled-off Table selects the row that was clicked")
    func tableRowClickSurvivesOuterScroll() {
        final class Box { var selection: Int? }
        let box = Box()
        let items = (1...40).map { Item(id: $0, name: "row-\($0)") }

        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(1...6, id: \.self) { index in
                    Text("filler-\(index)")
                }
                Table(
                    items,
                    selection: Binding(get: { box.selection }, set: { box.selection = $0 })
                ) {
                    TableColumn("Name", value: \Item.name)
                }
                .frame(height: 44)
            }
        }
        .frame(height: 12)

        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        let focusManager = FocusManager()

        func frame() -> FrameBuffer {
            dispatcher.beginRenderPass()
            var env = EnvironmentValues()
            env.mouseEventDispatcher = dispatcher
            env.focusManager = focusManager
            let context = RenderContext(
                availableWidth: 30, availableHeight: 12, environment: env, tuiContext: tui)
            let buffer = renderToBuffer(view, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        _ = frame()
        // Scroll the PAGE (not the table) until the filler above the table has
        // gone: enough ticks that the table's own top sits above the viewport.
        for _ in 0..<8 {
            _ = dispatcher.dispatch(
                MouseEvent(button: .scrollDown, phase: .scrolled, x: 5, y: 6))
            _ = frame()
        }
        let buffer = frame()
        #expect(
            !buffer.lines.contains { $0.stripped.contains("filler-1") },
            "the page really scrolled: \(buffer.lines.map(\.stripped))")

        // Click whatever row is drawn a few lines down — located by reading the
        // screen, so the test asserts agreement between what is drawn and what
        // is selected rather than any particular geometry.
        guard
            let (y, label) = buffer.lines.enumerated().compactMap({ index, line -> (Int, String)? in
                guard index >= 4 else { return nil }
                guard let name = line.stripped.split(separator: " ").first(where: {
                    $0.hasPrefix("row-")
                }) else { return nil }
                return (index, String(name))
            }).first
        else {
            Issue.record("no row drawn: \(buffer.lines.map(\.stripped))")
            return
        }

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 4, y: y))

        let expected = Int(label.dropFirst("row-".count))
        #expect(
            box.selection == expected,
            "clicked \(label) on screen row \(y) but selected row-\(box.selection.map(String.init) ?? "nil")")
    }

    /// The List twin of the same bug — same dispatcher seam, different view.
    @Test("Clicking a row of a scrolled-off List selects the row that was clicked")
    func listRowClickSurvivesOuterScroll() {
        final class Box { var selection: String? }
        let box = Box()
        let items = (1...40).map { "row-\($0)" }

        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(1...6, id: \.self) { index in
                    Text("filler-\(index)")
                }
                List(selection: Binding(get: { box.selection }, set: { box.selection = $0 })) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                    }
                }
                .frame(height: 42)
            }
        }
        .frame(height: 12)

        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        let focusManager = FocusManager()

        func frame() -> FrameBuffer {
            dispatcher.beginRenderPass()
            var env = EnvironmentValues()
            env.mouseEventDispatcher = dispatcher
            env.focusManager = focusManager
            let context = RenderContext(
                availableWidth: 30, availableHeight: 12, environment: env, tuiContext: tui)
            let buffer = renderToBuffer(view, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        _ = frame()
        for _ in 0..<8 {
            _ = dispatcher.dispatch(
                MouseEvent(button: .scrollDown, phase: .scrolled, x: 5, y: 6))
            _ = frame()
        }
        let buffer = frame()
        #expect(
            !buffer.lines.contains { $0.stripped.contains("filler-1") },
            "the page really scrolled: \(buffer.lines.map(\.stripped))")

        guard
            let (y, label) = buffer.lines.enumerated().compactMap({ index, line -> (Int, String)? in
                guard index >= 4 else { return nil }
                guard let name = line.stripped.split(separator: " ").first(where: {
                    $0.hasPrefix("row-")
                }) else { return nil }
                return (index, String(name))
            }).first
        else {
            Issue.record("no row drawn: \(buffer.lines.map(\.stripped))")
            return
        }

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 4, y: y))

        #expect(
            box.selection == label,
            "clicked \(label) on screen row \(y) but selected \(box.selection ?? "nil")")
    }

    /// The List's OWN top clip, not an enclosing scroller's. With line
    /// granularity (the default) the wheel leaves the top row drawn from its
    /// fourth line down, and the region `_ListCore` merges for a control
    /// spanning that row has to say how many lines were cut — otherwise the
    /// dispatcher localises every click inside the control that far too high.
    @Test("A control in a List row clipped by the list's own top localises to the row")
    func rowChildRegionCarriesTheListsOwnTopClip() {
        final class Box { var seen: [Int] = [] }
        let box = Box()

        let view = List(selection: .constant(String?.none)) {
            ForEach(["A", "B", "C", "D"], id: \.self) { item in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(1...5, id: \.self) { line in
                        Text("\(item)-\(line)")
                    }
                }
                .onMouseEvent { event in
                    guard event.button == .left, event.phase == .pressed else { return false }
                    box.seen.append(event.y)
                    return true
                }
            }
        }
        .frame(height: 8)

        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        let focusManager = FocusManager()

        func frame() -> FrameBuffer {
            dispatcher.beginRenderPass()
            var env = EnvironmentValues()
            env.mouseEventDispatcher = dispatcher
            env.focusManager = focusManager
            let context = RenderContext(
                availableWidth: 30, availableHeight: 8, environment: env, tuiContext: tui)
            let buffer = renderToBuffer(view, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        _ = frame()
        // One tick is `ViewConstants.mouseWheelScrollLines` = 3 lines, and the
        // rows are 5 lines tall: the list rests at row 0 with a 3-line top clip.
        _ = dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: 5, y: 3))
        let buffer = frame()

        #expect(
            !buffer.lines.contains { $0.stripped.contains("A-3") },
            "the list clipped 3 lines off its top row: \(buffer.lines.map(\.stripped))")
        guard let y = buffer.lines.firstIndex(where: { $0.stripped.contains("A-5") }) else {
            Issue.record("row A's fifth line is not drawn: \(buffer.lines.map(\.stripped))")
            return
        }
        #expect(
            buffer.hitTestRegions.contains { $0.topClip == 3 },
            "the merged region records the cut lines: \(buffer.hitTestRegions)")

        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: y))
        #expect(
            box.seen == [4],
            "'A-5' is the control's own line 4; got \(box.seen) (short by the 3 clipped lines)")
    }
}
