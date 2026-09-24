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

    // MARK: - The list's own claims at a back clip

    /// A press on the row straddling the bottom. During a hold the per-row budget
    /// clip stands down for `clipReorderOverrun`, which cuts the straddling row's
    /// lower lines from the BACK — `.live` draws no slot, so nothing else decides the
    /// end. That row is the cursor row, focused and not selected, so the list paints
    /// its focus wash on every line of it; and the wash's claims on the lines cut
    /// stayed behind, past the rows, on the "N more below" line and the border (§54).
    ///
    /// Under `.rowSelectionIndicator(.hidden)`: there the cursor row holds the plain
    /// wash, which is translucent here and so claims. Anywhere else it breathes, or
    /// holds the breath's bottom in an inactive window, and both spend the wash's alpha
    /// against the page and claim nothing (`Palette.focusWashPulse()`) — true, and no
    /// test of the clip.
    @Test("A reorder frame clipped from the back takes the cut lines' claims with it")
    func backClipTakesTheListsOwnClaims() throws {
        let fixture = ListReorderFixture(items: (0..<12).map { "row\($0)" }, feedback: .live)
        fixture.tallRows = ["row5": 3]
        fixture.env.palette = FadedFocus()
        fixture.env.rowSelectionIndicator = .hidden
        let resting = fixture.render()
        let line = fixture.rowY(resting, "row5")
        try #require(line >= 0, "the tall row is on screen: \(resting.lines.map(\.stripped))")
        fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: line))
        let pressed = fixture.render()
        defer {
            fixture.dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 2, y: line))
        }

        let lines = pressed.lines.map(\.stripped)
        #expect(fixture.handler?.reorder != nil, "the press began a hold")
        #expect(lines.filter { $0.contains("row5") }.count == 1, "row5 still straddles the bottom: \(lines)")
        #expect(!pressed.opacityRegions.isEmpty, "the cursor row's wash claims")
        let strays = pressed.opacityRegions.flatMap { claim in
            (claim.offsetY..<(claim.offsetY + claim.height)).filter {
                !(lines.indices.contains($0)
                    && lines[$0].range(of: "row[0-9]", options: .regularExpression) != nil)
            }
        }
        #expect(
            strays.isEmpty,
            """
            claims on lines \(strays), which show no row:
            \(lines.joined(separator: "\n"))
            """)
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

    // MARK: - Within a row cut through its top

    /// Which line's button answered a click.
    private final class TapBox {
        var label: String?
    }

    /// The selection a reorder picks up, boxed so the binding outlives the expression
    /// that made it.
    private final class SelectionBox {
        var rows: Set<Int> = []
    }

    /// The lines a row can draw, each its own button and every label distinct: a
    /// payload placed from the row's own top rather than from its first DRAWN line
    /// lands on another line of the SAME row, which a click then names. How many a row
    /// draws is each test's to choose, because what cuts a row through differs — the
    /// slide engages only on a row-aligned bottom, and the reorder overrun lands
    /// mid-row only at some row heights.
    private static let lineLabels = (0..<8).map { row in
        ["a", "bb", "ccc"].map { "r\(row)\($0)" }
    }

    private func rows(_ tapped: TapBox, lines: Int) -> some View {
        List(selection: .constant(Int?.none)) {
            ForEach(Self.lineLabels.indices, id: \.self) { row in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(Self.lineLabels[row].prefix(lines)), id: \.self) { label in
                        Button(label) { tapped.label = label }
                    }
                }
            }
        }
    }

    /// Every line of every row the frame drew, with the label drawn on it.
    private func drawnLineLabels(_ frame: FrameBuffer) -> [(y: Int, label: String)] {
        let all = Self.lineLabels.flatMap { $0 }
        return frame.lines.enumerated().compactMap { y, line in
            let stripped = line.stripped
            guard let label = all.first(where: { stripped.contains($0) }) else { return nil }
            return (y, label)
        }
    }

    /// Clicks every drawn line and reports which label answered, so a payload one line
    /// off its own content shows up as another line of the same row answering.
    private func labelsAnsweringAClick(
        _ frame: FrameBuffer, _ tapped: TapBox, context ctx: RenderContext
    ) -> [(drawn: String, answered: String?)] {
        let dispatcher = ctx.environment.mouseEventDispatcher!
        dispatcher.setRegions(frame.hitTestRegions)
        return drawnLineLabels(frame).map { line in
            tapped.label = nil
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: line.y))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: line.y))
            return (line.label, tapped.label)
        }
    }

    /// A push past the bottom slides the top row out through its own lines: it keeps
    /// drawing its last line, and that line's own button must be the one a click
    /// reaches. Read from the row's top instead, the region of the line the slide cut
    /// away sat on it.
    @Test("A push past the bottom leaves a cut row's buttons on their own lines")
    func overscrollKeepsCutRowsButtonsOnTheirLines() throws {
        let tapped = TapBox()
        // A push is a step the edge BLOCKED, so it engages only where the resting
        // bottom is row-aligned: two-line rows, an eight-line viewport, and a bar
        // rather than the "N more" lines, which would take one of them. Off that
        // lattice every tick still has a line of the top row to give, the allowance is
        // never reached — and that is why the suite's other push cases, on single-line
        // rows, cut no row through.
        let ctx = pushableContext(
            palette: EnvironmentValues().palette, style: .scrollbar, bottom: .rows(1))
        let pushed = pushedPastTheBottom(rows(tapped, lines: 2), context: ctx)
        let handler = ctx.environment.focusManager?.currentFocused as? ItemListHandler<Int>
        #expect(handler?.overscrollState.excursion == 1, "pushed the whole allowance")
        let screen = pushed.lines.map(\.stripped)
        let answers = labelsAnsweringAClick(pushed, tapped, context: ctx)
        let top = try #require(
            answers.first, "no row line is drawn:\n\(screen.joined(separator: "\n"))")
        #expect(
            top.drawn.hasSuffix("bb"),
            "the premise: the slide cut the top row through, leaving its last line — \(top.drawn)")
        for answer in answers {
            #expect(
                answer.answered == answer.drawn,
                """
                clicking the line drawn as \(answer.drawn) tapped \(answer.answered ?? "nothing")
                \(screen.joined(separator: "\n"))
                """)
        }
    }

    /// The same cut from the other path: a reorder frame that overruns is clipped from
    /// the front, away from the slot, and the first row to survive is cut through its
    /// own lines.
    @Test("A reorder overrun clipped from the front leaves a cut row's buttons on their lines")
    func reorderOverrunKeepsCutRowsButtonsOnTheirLines() throws {
        let tapped = TapBox()
        let selection = SelectionBox()
        selection.rows = [0, 1, 2]
        let ctx = pushableContext(palette: EnvironmentValues().palette)
        // Three lines a row: the overrun a three-row block leaves lands inside a row at
        // this height, and on a row boundary at two.
        let view = List(
            selection: Binding(get: { selection.rows }, set: { selection.rows = $0 })
        ) {
            ForEach(Self.lineLabels.indices, id: \.self) { row in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.lineLabels[row], id: \.self) { label in
                        Button(label) { tapped.label = label }
                    }
                }
            }
            .onMove { _, _ in }
        }
        _ = renderToBuffer(view, context: ctx)
        _ = ctx.environment.focusManager?.dispatchKeyEvent(
            KeyEvent(key: .character("r"), ctrl: true))
        _ = renderToBuffer(view, context: ctx)
        _ = ctx.environment.focusManager?.dispatchKeyEvent(KeyEvent(key: .end))
        let held = renderToBuffer(view, context: ctx)

        let screen = held.lines.map(\.stripped)
        let handler = ctx.environment.focusManager?.currentFocused as? ItemListHandler<Int>
        #expect(handler?.reorder?.held.count == 3, "the whole block is in hand")
        let answers = labelsAnsweringAClick(held, tapped, context: ctx)
        let top = try #require(
            answers.first, "no row line is drawn:\n\(screen.joined(separator: "\n"))")
        #expect(
            !top.drawn.hasSuffix("a"),
            "the premise: the overrun cut the top row through — \(top.drawn)")
        for answer in answers {
            #expect(
                answer.answered == answer.drawn,
                """
                clicking the line drawn as \(answer.drawn) tapped \(answer.answered ?? "nothing")
                \(screen.joined(separator: "\n"))
                """)
        }
    }

    /// The rows whose labels `frame` draws, in index order.
    private func drawnRows(_ frame: FrameBuffer) -> [Int] {
        let screen = frame.lines.map(\.stripped)
        return Self.labels.indices.filter { index in screen.contains { $0.contains(Self.labels[index]) } }
    }
}

/// Opaque everywhere but the focus wash, which a custom palette may set to anything:
/// the default derives it with `opacity(_:over:)`, which spends the alpha, so only a
/// palette that states its own reaches a translucent one. It is the one claim a List
/// paints on EVERY line of a row, so the one a back clip can cut.
private struct FadedFocus: Palette {
    let id = "faded-focus"
    let name = "Faded focus"
    let background = Color.rgb(10, 10, 20)
    let foreground = Color.rgb(230, 230, 240)
    let accent = Color.rgb(0, 180, 200)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
    let focusBackground = Color.rgb(60, 60, 200).opacity(0.5)
}
