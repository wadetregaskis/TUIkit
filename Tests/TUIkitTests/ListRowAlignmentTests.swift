//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowAlignmentTests.swift
//
//  A List carries each visible row's own payload — its hit regions, its
//  overlays, its opacity claims — up into its buffer by pairing the frame's row
//  ranges with the rows they were drawn from. Two things drop ranges off the
//  FRONT without dropping the rows: a reorder frame's overrun, clipped away
//  from the slot, and a push past the bottom, which slides the top rows out.
//  After either, every row carried the payload of a row above it. And a row the
//  frame rendered but did not draw still owes the root the dialog it presents.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A List row's own payload stays on its row")
struct ListRowAlignmentTests {

    /// Labels of three different widths, so a claim or a region that lands a row
    /// or two off lands on a label it does not fit. No label is part of another,
    /// so `contains` finds exactly one row's.
    private static let labels = (0..<30).map { "row\($0)" + String(repeating: "-", count: $0 % 3) }

    // MARK: - Claims and regions

    /// A block of three rows picked up at the top and moved to the end. The slot is
    /// as tall as the block, but once the rows have scrolled away only one line is
    /// reserved for it, so the frame overruns by two and is clipped from the FRONT,
    /// away from the slot.
    @Test(
        "A reorder overrun clipped from the front leaves each row's claims on it",
        arguments: ScrollIndicatorStyle.allCases)
    func reorderOverrunKeepsClaimsOnTheirRows(style: ScrollIndicatorStyle) {
        let fixture = ListReorderFixture(items: Self.labels, feedback: .dimmed)
        fixture.selection = Set(Self.labels.prefix(3))
        fixture.env.palette = FadedInk()
        fixture.env.scrollIndicatorStyle = style
        let held = heldBlockMovedToTheEnd(fixture)

        #expect(fixture.handler?.reorder?.held.count == 3, "the whole block is in hand")
        #expect(fixture.handler?.showsScrollbar == (style == .scrollbar), "drawn by the \(style) composer")
        expectInkOnLabelsOnly(held)
    }

    /// Pushed past its bottom, a list slides its rows up into the allowance and the
    /// top rows slide out. Both composers slide, so both run.
    @Test("A push past the bottom leaves each row's claims on it", arguments: ScrollIndicatorStyle.allCases)
    func overscrollKeepsClaimsOnTheirRows(style: ScrollIndicatorStyle) {
        let ctx = pushableContext(palette: FadedInk(), style: style)
        let view = List(selection: .constant(Int?.none)) {
            ForEach(Self.labels.indices, id: \.self) { Text(Self.labels[$0]) }
        }
        let pushed = pushedPastTheBottom(view, context: ctx)

        let handler = ctx.environment.focusManager?.currentFocused as? ItemListHandler<Int>
        #expect(handler?.overscrollState.excursion == 2, "pushed the whole allowance")
        #expect(handler?.showsScrollbar == (style == .scrollbar), "drawn by the \(style) composer")
        expectInkOnLabelsOnly(pushed)
    }

    /// The same drop, felt by the pointer: a row's own interactive children are
    /// carried up the same way as its claims.
    @Test("A push past the bottom leaves each row's button on it", arguments: ScrollIndicatorStyle.allCases)
    func overscrollKeepsButtonsOnTheirRows(style: ScrollIndicatorStyle) {
        final class Box { var value: Int? }
        let tapped = Box()
        let ctx = pushableContext(palette: EnvironmentValues().palette, style: style)
        let view = List(selection: .constant(Int?.none)) {
            ForEach(Self.labels.indices, id: \.self) { index in
                Button(Self.labels[index]) { tapped.value = index }
            }
        }
        let pushed = pushedPastTheBottom(view, context: ctx)
        let handler = ctx.environment.focusManager?.currentFocused as? ItemListHandler<Int>
        #expect(handler?.showsScrollbar == (style == .scrollbar), "drawn by the \(style) composer")
        let screen = pushed.lines.map(\.stripped)
        let last = Self.labels.count - 1
        guard let row = screen.firstIndex(where: { $0.contains(Self.labels[last]) }) else {
            Issue.record("the last row is not on screen:\n\(screen.joined(separator: "\n"))")
            return
        }

        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setRegions(pushed.hitTestRegions)
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: row))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: row))
        #expect(
            tapped.value == last,
            """
            clicking where \(Self.labels[last]) is drawn tapped \
            \(tapped.value.map { Self.labels[$0] } ?? "nothing"):
            \(screen.joined(separator: "\n"))
            """)
    }

    // MARK: - The cursor's reveal region

    /// The one-line region an enclosing scroller follows to keep the cursor on
    /// screen. Paired with the wrong row, it sat on another row's line, or was
    /// missing whenever the cursor row fell past the end of the pairing.
    ///
    /// The cursor moves BEFORE the push: moving it is a reveal, and a reveal drops
    /// any excursion. Two rows above the end is still on screen after the push, and
    /// its region used to sit two lines low; at the end there was no region at all.
    @Test(
        "A push past the bottom leaves the cursor's reveal region on the cursor row",
        arguments: ScrollIndicatorStyle.allCases, [0, 2])
    func overscrollKeepsTheCursorRegionOnItsRow(style: ScrollIndicatorStyle, rowsAboveEnd: Int) throws {
        let ctx = pushableContext(palette: EnvironmentValues().palette, style: style)
        let view = List(selection: .constant(Int?.none)) {
            ForEach(Self.labels.indices, id: \.self) { Text(Self.labels[$0]) }
        }
        _ = renderToBuffer(view, context: ctx)
        _ = ctx.environment.focusManager?.dispatchKeyEvent(KeyEvent(key: .end))
        _ = renderToBuffer(view, context: ctx)
        for _ in 0..<rowsAboveEnd {
            _ = ctx.environment.focusManager?.dispatchKeyEvent(KeyEvent(key: .up))
            _ = renderToBuffer(view, context: ctx)
        }
        let pushed = pushedPastTheBottom(view, context: ctx)

        let handler = try #require(ctx.environment.focusManager?.currentFocused as? ItemListHandler<Int>)
        let cursor = Self.labels.count - 1 - rowsAboveEnd
        #expect(handler.focusedIndex == cursor)
        #expect(handler.overscrollState.excursion == 2, "pushed the whole allowance")
        #expect(handler.showsScrollbar == (style == .scrollbar), "drawn by the \(style) composer")
        let screen = pushed.lines.map(\.stripped)
        let line = try #require(
            screen.firstIndex(where: { $0.contains(Self.labels[cursor]) }),
            "the cursor row slid off:\n\(screen.joined(separator: "\n"))")
        let region = pushed.revealTarget(focusID: handler.focusID, wholeControl: false)
        #expect(
            region?.top == line && region?.height == 1,
            "the cursor's region is \(String(describing: region)); its row is drawn on line \(line)")
    }

    // MARK: - Dialogs

    /// A dialog is a screen-level layer: it needs no line of its row's, only for
    /// the list to carry it up. The last row of a list pushed past its bottom is
    /// still drawn, but it fell past the end of the positional pairing, and its
    /// dialog went with it.
    @Test("A push past the bottom keeps the dialog of the last row, which is still drawn")
    func overscrollKeepsTheLastRowsDialog() throws {
        let box = PresenterBox()
        let ctx = pushableContext(palette: EnvironmentValues().palette)
        let view = presentingList(box)
        let pushed = pushedPastTheBottom(view, context: ctx)
        let handler = try #require(ctx.environment.focusManager?.currentFocused as? ItemListHandler<Int>)
        let last = Self.labels.count - 1
        try #require(drawnRows(pushed).last == last, "the last row is drawn")

        let presented = frame(presentingFrom: last, in: box, view, context: ctx)
        #expect(handler.overscrollState.excursion == 2, "still pushed when the dialog appeared")
        #expect(presented.overlays.contains { $0.level == .modal }, "the last row's dialog was dropped")
    }

    /// And the dialog of a row the push slid off the top. That row drew nothing, but
    /// it was rendered, so its dialog already holds the keyboard. The positional
    /// pairing kept this one by accident, carrying the first rows' payloads to other
    /// rows' lines; pairing by row has to keep it on purpose, by keeping the rows it
    /// no longer pairs.
    @Test("A push past the bottom keeps the dialog of a row it slid off the top")
    func overscrollKeepsTheDialogOfARowSlidOffTheTop() throws {
        let box = PresenterBox()
        let ctx = pushableContext(palette: EnvironmentValues().palette)
        let view = presentingList(box)
        let pushed = pushedPastTheBottom(view, context: ctx)
        let handler = try #require(ctx.environment.focusManager?.currentFocused as? ItemListHandler<Int>)
        // The window's first row: the slide took `excursion` one-line rows off the
        // top, and the window still holds them.
        let firstDrawn = try #require(drawnRows(pushed).first)
        let slidOff = firstDrawn - handler.overscrollState.excursion

        let presented = frame(presentingFrom: slidOff, in: box, view, context: ctx)
        #expect(handler.overscrollState.excursion == 2, "still pushed when the dialog appeared")
        #expect(!drawnRows(presented).contains(slidOff), "the presenting row is not drawn")
        #expect(presented.overlays.contains { $0.level == .modal }, "the slid-off row's dialog was dropped")
    }

    /// The mirror at the other end: pulled past its top, a list slides its last rows
    /// off the bottom. The positional pairing never reached those rows — `zip` stops
    /// at the shorter array — so their dialogs were dropped. Kept after the paired
    /// rows, they are carried now.
    @Test("A pull past the top keeps the dialog of a row it slid off the bottom")
    func overscrollKeepsTheDialogOfARowSlidOffTheBottom() throws {
        let box = PresenterBox()
        let ctx = pushableContext(palette: EnvironmentValues().palette, top: .rows(2), bottom: .none)
        let view = presentingList(box)
        let dispatcher = ctx.environment.mouseEventDispatcher!
        let resting = renderToBuffer(view, context: ctx)
        let lastDrawn = try #require(drawnRows(resting).last)
        // At offset 0 there is nowhere to scroll, so the tick has only the allowance
        // to spend (as `ListTableOverscrollTests.pushingUp` relies on).
        dispatcher.setRegions(resting.hitTestRegions)
        _ = dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .scrolled, x: 2, y: 2))
        let pulled = renderToBuffer(view, context: ctx)
        let handler = try #require(ctx.environment.focusManager?.currentFocused as? ItemListHandler<Int>)
        #expect(handler.overscrollState.excursion < 0, "pulled past the top")
        try #require(!drawnRows(pulled).contains(lastDrawn), "the slide took the row off")

        let presented = frame(presentingFrom: lastDrawn, in: box, view, context: ctx)
        #expect(presented.overlays.contains { $0.level == .modal }, "the slid-off row's dialog was dropped")
    }

    // MARK: - Helpers

    /// A 24×8 context whose lists may be pushed past their ends by the given
    /// allowances (two lines past the bottom unless told otherwise), under `style`,
    /// with `palette`. The terminal is sized to match, as the modal suites size it,
    /// so a dialog a row presents has a screen to size itself to.
    private func pushableContext(
        palette: any Palette, style: ScrollIndicatorStyle = .text,
        top: ScrollOverscroll = .none, bottom: ScrollOverscroll = .rows(2)
    ) -> RenderContext {
        makeRenderContext(width: 24, height: 8) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
            environment.scrollOverscrollTop = top
            environment.scrollOverscrollBottom = bottom
            environment.scrollIndicatorStyle = style
            environment.palette = palette
            environment.terminalWidth = 24
            environment.terminalHeight = 8
        }
    }

    /// Scrolls `view` to its bottom and on into its allowance, a wheel tick at a
    /// time, re-rendering between: the allowance is resolved as part of rendering.
    /// The wheel rather than End, so the keyboard cursor stays where it was.
    private func pushedPastTheBottom(_ view: some View, context ctx: RenderContext) -> FrameBuffer {
        let dispatcher = ctx.environment.mouseEventDispatcher!
        var latest = renderToBuffer(view, context: ctx)
        for _ in 0..<(Self.labels.count + 4) {
            dispatcher.setRegions(latest.hitTestRegions)
            _ = dispatcher.dispatch(MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 2))
            latest = renderToBuffer(view, context: ctx)
        }
        return latest
    }

    /// Picks up the fixture's selection with Ctrl-R and moves it to the end,
    /// rendering after each key, and returns the held frame.
    private func heldBlockMovedToTheEnd(_ fixture: ListReorderFixture) -> FrameBuffer {
        fixture.render()
        _ = fixture.env.focusManager?.dispatchKeyEvent(
            KeyEvent(key: .character("r"), ctrl: true))
        fixture.render()
        _ = fixture.env.focusManager?.dispatchKeyEvent(KeyEvent(key: .end))
        return fixture.render()
    }

    /// Which row presents its dialog, if any.
    private final class PresenterBox {
        var presenting: Int?
    }

    /// A list whose every row can present a dialog, and the one `box.presenting`
    /// names does.
    private func presentingList(_ box: PresenterBox) -> some View {
        List(selection: .constant(Int?.none)) {
            ForEach(Self.labels.indices, id: \.self) { index in
                Text(Self.labels[index])
                    .modal(isPresented: Binding(get: { box.presenting == index }, set: { _ in })) {
                        Text("MODAL BODY")
                    }
            }
        }
    }

    /// The frame on which `row` presents its dialog, with no input since the last.
    /// The render memo is dropped first: presenting changes nothing it keys on, so
    /// it could serve the row as it was.
    private func frame(
        presentingFrom row: Int, in box: PresenterBox, _ view: some View, context ctx: RenderContext
    ) -> FrameBuffer {
        box.presenting = row
        ctx.renderCache?.clearAll()
        return renderToBuffer(view, context: ctx)
    }

    /// The rows whose labels `frame` draws, in index order.
    private func drawnRows(_ frame: FrameBuffer) -> [Int] {
        let screen = frame.lines.map(\.stripped)
        return Self.labels.indices.filter { index in screen.contains { $0.contains(Self.labels[index]) } }
    }

    /// Every cell of a row's label owes the label's faded ink, and no other cell of
    /// the frame owes any. Columns are characters of the stripped line, which are
    /// cells here: every glyph drawn is one cell wide.
    private func expectInkOnLabelsOnly(
        _ frame: FrameBuffer, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let faded = owed(FadedInk().foreground)
        let screen = frame.lines.map(\.stripped)
        var wrong: [String] = []
        for (row, line) in screen.enumerated() {
            let label = line.range(of: "row[0-9]+-*", options: .regularExpression).map {
                line.distance(from: line.startIndex, to: $0.lowerBound)
                    ..< line.distance(from: line.startIndex, to: $0.upperBound)
            }
            for column in 0..<line.count {
                let ink = owed(atColumn: column, row: row, in: frame).ink
                let expected = label?.contains(column) == true ? faded : 1
                if ink != expected { wrong.append("(\(column), \(row)): \(ink)") }
            }
        }
        #expect(
            wrong.isEmpty,
            """
            cells owing the wrong ink, \(wrong.count) of them: \(wrong.prefix(10))
            \(screen.joined(separator: "\n"))
            """,
            sourceLocation: sourceLocation)
    }
}

/// Only the rows' ink faded — `foreground`, which `Text` draws in — with the
/// quieter rungs pinned opaque, since they default to `foreground` and the "N more"
/// line and the scrollbar's track are drawn in them: so the rows claim, and nothing
/// else in the list does.
private struct FadedInk: Palette {
    let id = "faded-ink"
    let name = "Faded ink"
    let background = Color.rgb(10, 10, 20)
    let foreground = Color.rgb(230, 230, 240).opacity(0.5)
    let foregroundSecondary = Color.rgb(200, 200, 210)
    let foregroundTertiary = Color.rgb(150, 150, 160)
    let foregroundQuaternary = Color.rgb(110, 110, 120)
    let accent = Color.rgb(0, 180, 200)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}
