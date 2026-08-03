//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListTableOverscrollTests.swift
//
//  §1.5 overscroll on the ROW-based scrollables.
//
//  `ScrollView` gets its slide from `replacingLines` on the finished viewport
//  buffer, because it appends its scrollbar as a whole column afterwards.
//  `List` and `Table` merge a bar cell into each line as they build it and stitch
//  the "N more" indicators in at top and bottom, so the same trick would carry
//  the chrome along with the content. These tests pin the distinction: the rows
//  move, the bar and the indicators do not.
//
//  Every case is written for BOTH views. Sharing `ItemListHandler` is not
//  sharing behaviour when each view wires its own per-frame inputs — that is
//  what `017683fa` found the hard way with the row anchor.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("List and Table can be pushed past their edges")
struct ListTableOverscrollTests {

    private struct Item: Identifiable {
        let id: Int
        var name: String { "row \(id)" }
        /// Three lines, so the visible-ROW count and the viewport's LINE count
        /// diverge — which is what `.viewport(minus:)` used to be resolved against.
        var detail: String { "row \(id)\nline b\nline c" }
    }

    private static let items = (0..<40).map(Item.init(id:))

    private func context(
        width: Int = 28, height: Int = 8, top: ScrollOverscroll = .none,
        bar: ScrollbarVisibility = .hidden
    ) -> RenderContext {
        makeRenderContext(width: width, height: height) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
            environment.scrollOverscrollTop = top
            environment.scrollbarVisibility = bar
        }
    }

    private func list(_ selection: Binding<Int?> = .constant(nil)) -> some View {
        List(selection: selection) {
            ForEach(Self.items) { Text($0.name) }
        }
    }

    private func table() -> some View {
        Table(Self.items, selection: .constant(nil)) {
            TableColumn("Name", value: \Item.name)
        }
    }

    /// Renders, pushes one wheel tick UP over the view, and returns the screens
    /// before and after. At offset 0 there is nowhere to scroll, so the tick has
    /// only the allowance to spend — no graze step to consume first.
    private func pushingUp(
        _ view: some View, context ctx: RenderContext, ticks: Int = 1
    ) -> (before: [String], after: [String]) {
        let dispatcher = ctx.environment.mouseEventDispatcher!
        let first = renderToBuffer(view, context: ctx)
        var latest = first
        // A re-render between events is required: the allowance is resolved as
        // part of rendering, so a second tick only sees a settled bound once the
        // first tick's frame has been drawn.
        for _ in 0..<ticks {
            dispatcher.setRegions(latest.hitTestRegions)
            _ = dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .scrolled, x: 2, y: 2))
            latest = renderToBuffer(view, context: ctx)
        }
        return (first.lines.map(\.stripped), latest.lines.map(\.stripped))
    }

    @Test("A multi-line Table's viewport allowance is measured in lines, not rows")
    func multiLineTableViewportAllowanceIsLineBased() {
        // 15 available lines − 3 chrome (top border, header, bottom border) = 12
        // content lines; one goes to the "N more" indicator, so the viewport the
        // allowance is relative to is 11 LINES, and .viewport(minus: 8) is 3.
        // The visible-ROW count here is far smaller (3-line rows), so resolving
        // against rows yielded max(0, rows − 8) == 0: no allowance at all, and
        // the view could not be pushed past its edge by even one line.
        let ctx = context(width: 28, height: 15, top: .viewport(minus: 8))
        let view = Table(Self.items, selection: .constant(Int?.none)) {
            TableColumn("Name", value: \Item.detail).lineLimit(3)
        }
        let (before, after) = pushingUp(view, context: ctx, ticks: 2)
        #expect(
            slide(before, after) == 3,
            "the excursion caps at the LINE-based allowance:\n\(after.joined(separator: "\n"))")
    }

    /// The screen line the given row is drawn on. A "blank" line still carries
    /// the list's border glyphs, so counting empty strings would find none —
    /// the row's own position is the honest measure of how far it slid.
    private func lineOf(_ text: String, in screen: [String]) -> Int? {
        screen.firstIndex { $0.contains(text) }
    }

    /// How far the first row moved down between the two screens.
    private func slide(_ before: [String], _ after: [String], row: String = "row 0") -> Int? {
        guard let a = lineOf(row, in: before), let b = lineOf(row, in: after) else { return nil }
        return b - a
    }

    // MARK: - The rows move

    @Test("A List can be pushed past its top")
    func listPushesPastTop() {
        let ctx = context(top: .rows(2))
        let (before, after) = pushingUp(list(), context: ctx)
        #expect(
            slide(before, after) == 2,
            """
            the rows slid down by the 2-row allowance, opening blank space above:
            \(after.joined(separator: "\n"))
            """)
    }

    @Test("A Table can be pushed past its top")
    func tablePushesPastTop() {
        let ctx = context(top: .rows(2))
        let (before, after) = pushingUp(table(), context: ctx)
        #expect(
            slide(before, after) == 2,
            """
            the rows slid down by the 2-row allowance, opening blank space above:
            \(after.joined(separator: "\n"))
            """)
    }

    // MARK: - The chrome does not

    /// The trailing column of each line — where a scrollbar lives.
    private func lastColumn(_ screen: [String]) -> [Character] {
        screen.map { $0.last ?? " " }
    }

    @Test("A List's scrollbar stays put while the rows slide")
    func listScrollbarDoesNotSlide() {
        let ctx = context(top: .rows(2), bar: .visible)
        let (before, after) = pushingUp(list(), context: ctx)
        #expect(
            slide(before, after) == 2,
            "the rows did move:\n\(after.joined(separator: "\n"))")
        #expect(
            lastColumn(before) == lastColumn(after),
            """
            …but the bar did not. It describes where the content SITS; sliding \
            the finished lines (the ScrollView technique) would carry it along, \
            which is exactly why the row views build their rows separately.
            before: \(String(lastColumn(before)))
            after:  \(String(lastColumn(after)))
            """)
    }

    @Test("A Table's scrollbar stays put while the rows slide")
    func tableScrollbarDoesNotSlide() {
        let ctx = context(top: .rows(2), bar: .visible)
        let (before, after) = pushingUp(table(), context: ctx)
        #expect(
            slide(before, after) == 2,
            "the rows did move:\n\(after.joined(separator: "\n"))")
        #expect(
            lastColumn(before) == lastColumn(after),
            """
            …but the bar did not.
            before: \(String(lastColumn(before)))
            after:  \(String(lastColumn(after)))
            """)
    }

    @Test("The 'N more below' indicator stays on its own line", arguments: [true, false])
    func indicatorDoesNotSlide(_ isList: Bool) {
        let ctx = context(top: .rows(2))
        let (before, after) =
            isList ? pushingUp(list(), context: ctx) : pushingUp(table(), context: ctx)
        func indicatorRow(_ screen: [String]) -> Int? {
            screen.lastIndex { $0.contains("more") }
        }
        #expect(
            indicatorRow(before) != nil,
            "the control case has an indicator:\n\(before.joined(separator: "\n"))")
        #expect(
            indicatorRow(before) == indicatorRow(after),
            """
            the indicator counts CONTENT, so it neither moves nor changes when \
            the view is pushed past an edge:
            \(after.joined(separator: "\n"))
            """)
    }

    // MARK: - Clicks follow the rows

    @Test("Clicking a slid row selects that row, not the one that was there")
    func rowHitRegionsSlide() {
        final class Box { var value: Int? }
        let selected = Box()
        let ctx = context(top: .rows(2))
        let dispatcher = ctx.environment.mouseEventDispatcher!
        let view = list(Binding(get: { selected.value }, set: { selected.value = $0 }))

        let first = renderToBuffer(view, context: ctx)
        dispatcher.setRegions(first.hitTestRegions)
        _ = dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .scrolled, x: 2, y: 2))

        let pushed = renderToBuffer(view, context: ctx)
        dispatcher.setRegions(pushed.hitTestRegions)
        let screen = pushed.lines.map(\.stripped)
        guard let row = screen.firstIndex(where: { $0.contains("row 1") }) else {
            Issue.record("row 1 is not on screen:\n\(screen.joined(separator: "\n"))")
            return
        }
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: row))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: row))
        #expect(
            selected.value == 1,
            """
            the row ranges slid with the rows — clicking where "row 1" is DRAWN \
            selects row 1, got \(selected.value.map(String.init) ?? "nil"):
            \(screen.joined(separator: "\n"))
            """)
    }

    /// The Table twin. Its click path recomputes the row from `visibleRange`
    /// rather than publishing pre-slid ranges like the List, so it needs its
    /// own excursion compensation — uncompensated, a click under a 2-row push
    /// selected the row 2 PAST the one under the pointer (and its published
    /// bands slid the wrong way entirely: `+excursion` where drawn rows sit at
    /// `−excursion`, putting bands 2×excursion from the rows they named).
    @Test("Clicking a slid Table row selects that row too")
    func tableRowClicksSlide() {
        final class Box { var value: Int? }
        let selected = Box()
        let ctx = context(top: .rows(2))
        let dispatcher = ctx.environment.mouseEventDispatcher!
        let view = Table(
            Self.items,
            selection: Binding(get: { selected.value }, set: { selected.value = $0 })
        ) {
            TableColumn("Name", value: \Item.name)
        }

        let first = renderToBuffer(view, context: ctx)
        dispatcher.setRegions(first.hitTestRegions)
        _ = dispatcher.dispatch(MouseEvent(button: .scrollUp, phase: .scrolled, x: 2, y: 2))

        let pushed = renderToBuffer(view, context: ctx)
        dispatcher.setRegions(pushed.hitTestRegions)
        let screen = pushed.lines.map(\.stripped)
        guard let row = screen.firstIndex(where: { $0.contains("row 1") }) else {
            Issue.record("row 1 is not on screen:\n\(screen.joined(separator: "\n"))")
            return
        }
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: row))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: row))
        #expect(
            selected.value == 1,
            """
            clicking where "row 1" is DRAWN selects row 1, \
            got \(selected.value.map(String.init) ?? "nil"):
            \(screen.joined(separator: "\n"))
            """)
    }

    // MARK: - Inert by default

    @Test("Without an allowance neither view moves at all", arguments: [true, false])
    func inertWithoutAnAllowance(_ isList: Bool) {
        let ctx = context()  // no allowance
        let (before, after) =
            isList ? pushingUp(list(), context: ctx) : pushingUp(table(), context: ctx)
        #expect(
            before == after,
            """
            a scrollable that opted into nothing is byte-for-byte unchanged by a \
            tick at its edge:
            \(after.joined(separator: "\n"))
            """)
    }
}
