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
//  The X axis is the same seam with `leftClip` / `localOriginX` in place of
//  `topClip` / `localOriginY`, and the two cases at the end of this file are
//  its halves: the point a drop destination is handed, and a reorder drag's
//  "is the cursor over the rows at all" column test inside a horizontal
//  ScrollView, where measuring from the clipped left edge made the leftmost
//  visible content column read as off the rows.
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

    // MARK: - The other axis

    /// The seam itself, on X: `leftClip` records how far left of its clipped
    /// left edge a region really starts, so a point handed to a drop
    /// destination has to be measured from there. `hovering` took its y from
    /// the unclipped origin and its x from the clipped one, so the two halves
    /// of one point disagreed.
    @Test("A clipped region's hover point is measured from its unclipped origin")
    func clippedRegionHoverPointLocalisesAgainstOrigin() {
        let dispatcher = MouseEventDispatcher()
        let session = DragAndDropSession()
        // `DragAndDropSession.dispatcher` is weak (TUIContext owns it in
        // production), so the local has to outlive the last direct use of it
        // below — see the `withExtendedLifetime` at the end.
        session.dispatcher = dispatcher
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        let id = dispatcher.register { _ in false }

        // A destination scrolled 4 columns off the left and 3 rows off the top:
        // its own cell (4, 3) is the one screen cell (0, 0) draws.
        var region = HitTestRegion(
            offsetX: 0, offsetY: 0, width: 10, height: 6, handlerID: id)
        region.leftClip = 4
        region.topClip = 3
        dispatcher.setRegions([region])

        var seen: [(x: Int, y: Int)] = []
        session.registerTarget(
            DragAndDropSession.Target(
                handlerID: id, accepts: { _ in true }, perform: { _, _ in true },
                setTargeted: { _ in }, hovering: { x, y in seen.append((x: x, y: y)) }))

        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .pressed, x: 2, y: 1)
        session.begin(payload: "x", preview: FrameBuffer(text: "x"))
        session.lastAbsoluteEvent = MouseEvent(button: .left, phase: .dragged, x: 2, y: 1)
        session.dragMoved()

        // TWO hovers, not one: `begin(payload:preview:)` resolves targeting
        // immediately and ends by calling `dragMoved()` itself, so the press
        // reports a point before the explicit move does. Both are the same
        // point here, which is what makes asserting on every entry the right
        // shape — the count is incidental, the coordinates are the subject.
        #expect(seen.count == 2, "begin() hovers once and dragMoved() again: \(seen)")
        #expect(
            seen.allSatisfy { $0.x == 6 },
            "screen column 2 is the destination's own column 6; got \(seen)")
        #expect(
            seen.allSatisfy { $0.y == 4 },
            "screen row 1 is the destination's own row 4; got \(seen)")
        withExtendedLifetime(dispatcher) {}
    }

    /// The live half, app-shaped: a reorder drag inside a horizontally scrolled
    /// `ScrollView`. `DragAndDropSession.contentY(in:)` decides whether the
    /// cursor is over the rows by testing the control's own content columns, so
    /// the column it tests must be measured from the control's true left edge.
    /// Measured from the clipped one every column read `leftClip` too low, and
    /// the leftmost visible column — a genuine interior cell — fell out of
    /// `contentColumns` and reported "off the rows".
    @Test("A reorder drag in a horizontally scrolled List still lands on the rows")
    func reorderSurvivesHorizontalClip() {
        let fixture = ListReorderFixture(horizontalViewport: 12)
        // Row positions off the UNSCROLLED frame, where the labels are still
        // drawn: a horizontal scroll moves no rows.
        let unscrolled = fixture.render()
        let ySource = fixture.rowY(unscrolled, "a")
        let yTarget = fixture.rowY(unscrolled, "c")
        #expect(ySource >= 0, "precondition: row a is drawn")
        #expect(yTarget > ySource, "precondition: row c is drawn below it")

        fixture.scrollHorizontally(by: 5)
        let scrolled = fixture.render()
        #expect(
            scrolled.hitTestRegions.contains { $0.leftClip == 5 },
            "precondition: the list's region is clipped 5 columns from the left")

        // Absolute column 0 is the list's own column 5 — four columns right of
        // its border, as interior as a cell gets.
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .pressed, x: 0, y: ySource))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .dragged, x: 0, y: yTarget))
        fixture.render()
        fixture.dispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 0, y: yTarget))
        fixture.render()
        #expect(
            fixture.items == ["b", "c", "a", "d", "e"],
            "a dropped after c, exactly as it does unscrolled")
    }
}
