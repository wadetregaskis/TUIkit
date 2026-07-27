//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollFollowMarginTests.swift
//
//  ScrollFollowMargin semantics: the resolved-lines math, and the Menu's
//  stateful windowing under each policy — the default is the classic
//  edge-triggered scroll (the window holds still until the selection
//  reaches its edge), .steps(n) starts scrolling n steps early, and
//  .centered keeps the selection centred (the old always-centred
//  behaviour, now opt-in).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("scroll-follow margin")
struct ScrollFollowMarginTests {

    // MARK: Resolution

    @Test("resolvedLines: symbolic values, clamping, and fractions")
    func resolution() {
        #expect(ScrollFollowMargin.none.resolvedLines(viewportLines: 10) == 0)
        #expect(ScrollFollowMargin.steps(2).resolvedLines(viewportLines: 10) == 2)
        #expect(ScrollFollowMargin.steps(3).resolvedLines(viewportLines: 10) == 3)
        #expect(ScrollFollowMargin.fraction(0.25).resolvedLines(viewportLines: 12) == 3)
        // .centered is its own value (carrying a row anchor), distinct from
        // fraction(0.5), but still resolves to half the viewport in line-space so
        // single-line / line-based consumers centre the selection as before.
        #expect(ScrollFollowMargin.centered != ScrollFollowMargin.fraction(0.5))
        #expect(ScrollFollowMargin.centered.centeredAnchor == .center)
        #expect(ScrollFollowMargin.centered(anchor: .top).centeredAnchor == .top)
        #expect(ScrollFollowMargin.centered.resolvedLines(viewportLines: 9) == 4)
        #expect(ScrollFollowMargin.centered.resolvedLines(viewportLines: 10) == 4)
        // Excess margins clamp so a selection can rest strictly inside.
        #expect(ScrollFollowMargin.steps(99).resolvedLines(viewportLines: 8) == 3)
        // Out-of-range inputs are sanitized at construction.
        #expect(ScrollFollowMargin.steps(-5).resolvedLines(viewportLines: 8) == 0)
        #expect(ScrollFollowMargin.fraction(2.0) == ScrollFollowMargin.fraction(0.5))
        #expect(ScrollFollowMargin.fraction(-1) == ScrollFollowMargin.fraction(0))
        // Degenerate viewports never produce a negative margin.
        #expect(ScrollFollowMargin.centered.resolvedLines(viewportLines: 1) == 0)
        #expect(ScrollFollowMargin.steps(1).resolvedLines(viewportLines: 0) == 0)
    }

    // MARK: Menu windowing under each policy

    /// Renders `menu` (35 items, "Item 1"…"Item 35") at height 8 into a
    /// persistent context, walking the selection from `from` to `to` one
    /// step at a time with a re-render per step, and returns for each step
    /// the first visible item number (the window's top row).
    private func walkTops(
        margin: ScrollFollowMargin?, from: Int, to: Int
    ) -> [Int] {
        final class Box { var sel = 0 }
        let box = Box()
        let items = (1...35).map { MenuItem(label: "Item \($0)", shortcut: nil) }
        let tuiContext = TUIContext()

        func frame() -> [String] {
            let menu = Menu(
                items: items,
                selection: Binding(get: { box.sel }, set: { box.sel = $0 }))
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tuiContext)
            if let margin { environment.scrollFollowMargin = margin }
            let context = RenderContext(
                availableWidth: 30, availableHeight: 8,
                environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            let buffer = renderToBuffer(menu, context: context)
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer.lines.map { $0.stripped }
        }

        func topItem(_ lines: [String]) -> Int {
            for line in lines {
                if let range = line.range(of: "Item ") {
                    let digits = line[range.upperBound...].prefix { $0.isNumber }
                    if let n = Int(digits) { return n }
                }
            }
            return -1
        }

        box.sel = from
        _ = frame()
        var tops: [Int] = []
        let step = from <= to ? 1 : -1
        var sel = from
        while sel != to {
            sel += step
            box.sel = sel
            tops.append(topItem(frame()))
        }
        return tops
    }

    @Test("Default (.none): the window holds until the selection hits its edge")
    func edgeTriggeredByDefault() {
        // Height 8 → border eats 2, the ▼ marker 1: five item rows at the
        // top. The window must NOT move while the selection walks strictly
        // inside it (a centring policy moves from the very first step), then
        // advance one per step once the selection rides the bottom edge —
        // with a single one-off 2-row shift allowed at the moment the ▲
        // marker first appears and shrinks the window by a row.
        let tops = walkTops(margin: nil, from: 0, to: 12)
        #expect(tops.first == 1, "the window holds at the top initially: \(tops)")
        #expect(tops == tops.sorted(), "the top only ever advances: \(tops)")
        var bigSteps = 0
        for (a, b) in zip(tops, tops.dropFirst()) {
            #expect(b - a <= 2, "no jumps beyond the marker shrink: \(tops)")
            if b - a > 1 { bigSteps += 1 }
        }
        #expect(bigSteps <= 1, "at most the one marker-appearance shift: \(tops)")
        let holds = tops.prefix { $0 == 1 }.count
        #expect(holds == 4, "the selection walks to the edge before any scroll: \(tops)")
    }

    @Test(".centered keeps the selection centred through the middle")
    func centeredKeepsCentre() {
        let tops = walkTops(margin: .centered, from: 0, to: 20)
        // Mid-list (well clear of both ends) the top must track the
        // selection at a constant offset — the centring invariant.
        let mid = tops[8...14]
        let offsets = Set(zip(mid, 10...16).map { $1 - $0 })
        #expect(offsets.count == 1, "constant selection-to-top offset mid-list: \(tops)")
    }

    @Test(".steps(2) starts scrolling two lines before the edge")
    func linesMarginScrollsEarly() {
        let defaultTops = walkTops(margin: nil, from: 0, to: 10)
        let marginTops = walkTops(margin: .steps(2), from: 0, to: 10)
        let defaultHold = defaultTops.prefix { $0 == 1 }.count
        let marginHold = marginTops.prefix { $0 == 1 }.count
        #expect(
            defaultHold - marginHold == 2,
            "a 2-line margin scrolls exactly 2 steps earlier: default \(defaultTops), margin \(marginTops)")
    }

    // MARK: List cursor + ScrollView reveal under a margin

    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager, height: Int
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 40, availableHeight: height,
            environment: environment, tuiContext: tuiContext)
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    private struct Item: Identifiable {
        let id: Int
        var label: String { "item-\(id)-end" }
    }

    @Test("List cursor with .steps(2) keeps two rows visible beyond it")
    func listCursorMargin() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let items = (0..<30).map { Item(id: $0) }
        let view = List(items, selection: Binding<Int?>.constant(nil)) { item in
            Text(item.label)
        }
        .scrollFollowMargin(.steps(2))
        .frame(height: 10)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 10)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 10)
        // Walk the cursor deep; mid-list the margin must keep 2 rows visible
        // BELOW the cursor (an edge-triggered walk shows the cursor row last).
        for _ in 0..<12 { _ = focusManager.dispatchKeyEvent(KeyEvent(key: .down)) }
        let lines = renderFrame(
            view, tuiContext: tuiContext, focusManager: focusManager, height: 10)
        #expect(lines.contains { $0.contains("item-12-end") }, "cursor visible: \(lines)")
        #expect(
            lines.contains { $0.contains("item-13-end") }
                && lines.contains { $0.contains("item-14-end") },
            "two rows of context visible beyond the cursor: \(lines)")
    }

    @Test("ScrollView reveal with .steps(2) leaves two lines beyond the control")
    func scrollViewRevealMargin() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<20, id: \.self) { i in
                    Button("b\(i)e") {}.focusID("b\(i)")
                }
            }
        }
        .scrollbarVisibility(.visible)
        .scrollFollowMargin(.steps(2))
        .frame(height: 8)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)

        // Reveal downward: b10 lands 2 rows above the last viewport row, so
        // b11 and b12 are visible beyond it.
        focusManager.focus(id: "b10")
        let down = renderFrame(
            view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        #expect(down.contains { $0.contains("b10e") }, "the control is visible: \(down)")
        #expect(down.last?.contains("b12e") == true, "two lines beyond it show: \(down)")

        // And upward: b4 lands 2 rows below the first viewport row.
        focusManager.focus(id: "b4")
        let up = renderFrame(
            view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        #expect(up.first?.contains("b2e") == true, "two lines above it show: \(up)")
    }

    @Test("Walking back up: the default only scrolls at the top edge")
    func edgeTriggeredUpward() {
        // Walk deep, then back. On the way up the window must hold until the
        // selection reaches its TOP edge, then retreat one per step. The
        // fresh menu opens centred (a 4-item window mid-list, selection on
        // its second row), so exactly 2 upward steps pass inside the window
        // before the first scroll.
        let tops = walkTops(margin: nil, from: 20, to: 0)
        #expect(tops == tops.sorted(by: >=), "the top only ever retreats: \(tops)")
        for (a, b) in zip(tops, tops.dropFirst()) {
            #expect(a - b <= 2, "no jumps beyond the marker growth: \(tops)")
        }
        let firstTop = tops.first ?? -1
        let holds = tops.prefix { $0 == firstTop }.count
        #expect(holds == 2, "the selection walks to the top edge before any scroll: \(tops)")
    }
}

/// The sub-row-precise centring the `.centered(anchor:)` margin gives a
/// variable-height-row list (bug: on the fixed-height/hundreds-of-rows Table the
/// whole-row centred margin drifted, since it counts rows not lines).
@MainActor
@Suite("centered follow-margin row anchoring")
struct CenteredAnchorTests {
    /// A line-granularity handler over `heights.count` variable-height rows in a
    /// `viewport`-line content area, centred on `anchor`.
    private func handler(
        heights: [Int], viewport: Int, anchor: ScrollFollowMargin.RowAnchor = .center
    ) -> ItemListHandler<Int> {
        let handler = ItemListHandler<Int>(
            focusID: "list", itemCount: heights.count,
            viewportHeight: viewport, selectionMode: .single)
        handler.contentHeight = viewport
        handler.rowHeight = { heights[$0] }
        handler.followMargin = .centered(anchor: anchor)
        handler.scrollGranularity = .line
        // This harness models the ROW area directly — no "N more" indicator
        // lines are drawn inside `viewport`, so none must be deducted from it.
        handler.drawsScrollIndicators = false
        return handler
    }

    /// The viewport line (0-based) the focused row's anchor line lands on.
    private func anchorViewportLine(
        _ handler: ItemListHandler<Int>, heights: [Int],
        anchor: ScrollFollowMargin.RowAnchor
    ) -> Int {
        let focusedHeight = heights[handler.focusedIndex]
        let anchorLine: Int
        switch anchor {
        case .top: anchorLine = 0
        case .center: anchorLine = focusedHeight / 2
        case .line(let index): anchorLine = max(0, min(focusedHeight - 1, index))
        }
        let absoluteAnchor = heights[0..<handler.focusedIndex].reduce(0, +) + anchorLine
        let absoluteFirstVisible =
            heights[0..<handler.scrollOffset].reduce(0, +) + handler.scrollTopClipLines
        return absoluteAnchor - absoluteFirstVisible
    }

    @Test("A mid-list focused row's centre line lands on the viewport centre")
    func centresMidList() {
        let heights = Array(repeating: 2, count: 20)
        let handler = handler(heights: heights, viewport: 11)  // centre line 5
        handler.focusedIndex = 10
        handler.ensureFocusedItemVisible()
        #expect(anchorViewportLine(handler, heights: heights, anchor: .center) == 5)
    }

    @Test("Variable row heights keep the anchor pinned at the centre line")
    func stableUnderVariableHeights() {
        // Alternating tall/short rows: the whole-row margin drifts as the mix of
        // neighbour heights changes; the line-precise anchor does not.
        let heights = (0..<30).map { $0.isMultiple(of: 2) ? 3 : 1 }
        let handler = handler(heights: heights, viewport: 11)  // centre line 5
        for focus in 8...20 {
            handler.focusedIndex = focus
            handler.ensureFocusedItemVisible()
            #expect(
                anchorViewportLine(handler, heights: heights, anchor: .center) == 5,
                "focus \(focus): centre line held")
        }
    }

    @Test("The .top anchor pins the focused row's FIRST line to the centre")
    func topAnchor() {
        let heights = Array(repeating: 4, count: 20)
        let handler = handler(heights: heights, viewport: 11, anchor: .top)  // centre 5
        handler.focusedIndex = 10
        handler.ensureFocusedItemVisible()
        #expect(anchorViewportLine(handler, heights: heights, anchor: .top) == 5)
    }

    @Test("Near the top the row rests fully against the top edge")
    func restsAtTop() {
        let heights = Array(repeating: 2, count: 20)
        let handler = handler(heights: heights, viewport: 11)
        handler.focusedIndex = 0
        handler.ensureFocusedItemVisible()
        #expect(handler.scrollOffset == 0)
        #expect(handler.scrollTopClipLines == 0, "the first row is fully visible")
    }

    @Test("Near the bottom the offset clamps to the last valid top")
    func restsAtBottom() {
        let heights = Array(repeating: 2, count: 20)
        let handler = handler(heights: heights, viewport: 11)
        handler.focusedIndex = 19
        handler.ensureFocusedItemVisible()
        #expect(handler.scrollOffset == handler.maxOffset, "centring past the end clamps down")
    }

    @Test("Under row granularity the sub-row clip is zeroed (row-precise centring)")
    func rowGranularityZeroesClip() {
        let heights = Array(repeating: 3, count: 20)
        let handler = handler(heights: heights, viewport: 11)
        handler.scrollGranularity = .row  // clampTopClip zeroes the clip here
        handler.focusedIndex = 10
        handler.ensureFocusedItemVisible()
        #expect(handler.scrollTopClipLines == 0, "row granularity forbids a sub-row clip")
    }

    /// An EVEN viewport of EVEN-height rows — the parity every case above
    /// misses, because they all use viewport 11.
    ///
    /// Centring used to be computed as (viewport centre line) − (row centre
    /// line), two independent floors. They agree unless the viewport height and
    /// the row height are both even, where the result is one line short: the
    /// row sits above centre and half a row shows at each edge instead of whole
    /// rows. That is the Multi-line Cells demo exactly — a 6-line content area
    /// of 2-line rows, which fits three whole rows with the focused one in the
    /// middle.
    ///
    /// Asserted on `scrollOffset`/`scrollTopClipLines` directly and NOT through
    /// `anchorViewportLine`: that helper re-derives the anchor as
    /// `focusedHeight / 2`, i.e. it encodes the very definition that was wrong,
    /// so it cannot see this bug.
    @Test("An even-height row in an even viewport centres on whole rows")
    func evenRowInEvenViewportCentresWhole() {
        let heights = Array(repeating: 2, count: 20)
        let handler = handler(heights: heights, viewport: 6)  // exactly three rows
        handler.focusedIndex = 5
        handler.ensureFocusedItemVisible()

        #expect(
            handler.scrollTopClipLines == 0,
            "three 2-line rows fit a 6-line viewport exactly — nothing may be clipped")
        #expect(
            handler.scrollOffset == 4,
            "the focused row is the middle of rows 4/5/6")
    }
}

/// `.steps(n)` means n LINES when the scrollable moves by lines and n ROWS when
/// it moves by rows. Before this the two were separate spellings that resolved
/// through the same arithmetic, so `.rows(2)` and `.lines(2)` behaved
/// identically and picking one made no observable difference.
///
/// The distinction is only visible with MULTI-LINE rows — with single-line rows
/// a row is a line — so these use 3-line rows, where "2 steps of context" is
/// either 2 rows (6 lines) or 2 lines (which does not even clear one row).
@MainActor
@Suite("A step is a line or a row, per the scroll granularity")
struct StepGranularityTests {

    private func handler(granularity: ScrollGranularity, steps: Int) -> ItemListHandler<Int> {
        let heights = Array(repeating: 3, count: 20)
        let handler = ItemListHandler<Int>(
            focusID: "list", itemCount: heights.count,
            viewportHeight: 12, selectionMode: .single)
        handler.contentHeight = 12
        handler.rowHeight = { heights[$0] }
        handler.followMargin = .steps(steps)
        handler.scrollGranularity = granularity
        return handler
    }

    /// Walks the cursor down to `index` and reports the resulting top row.
    private func topAfterWalking(_ handler: ItemListHandler<Int>, to index: Int) -> Int {
        for _ in 0..<index { handler.moveFocus(by: 1, wrap: false) }
        return handler.scrollOffset
    }

    @Test("row granularity keeps whole ROWS of context, line granularity keeps LINES")
    func stepsFollowGranularity() {
        let byRow = handler(granularity: .row, steps: 2)
        let byLine = handler(granularity: .line, steps: 2)
        let rowTop = topAfterWalking(byRow, to: 8)
        let lineTop = topAfterWalking(byLine, to: 8)

        // Two 3-line rows of context is far more than two lines, so the
        // row-granularity window has to start scrolling earlier and therefore
        // sits further down the list.
        #expect(
            rowTop > lineTop,
            """
            .steps(2) must mean 2 ROWS under row granularity and 2 LINES under \
            line granularity — with 3-line rows those cannot coincide. \
            row-granularity top=\(rowTop), line-granularity top=\(lineTop)
            """)
    }

    @Test("with single-line rows the two granularities agree")
    func singleLineRowsCoincide() {
        func flat(_ granularity: ScrollGranularity) -> ItemListHandler<Int> {
            let handler = ItemListHandler<Int>(
                focusID: "list", itemCount: 20, viewportHeight: 8, selectionMode: .single)
            handler.contentHeight = 8
            handler.rowHeight = { _ in 1 }
            handler.followMargin = .steps(2)
            handler.scrollGranularity = granularity
            return handler
        }
        #expect(topAfterWalking(flat(.row), to: 10) == topAfterWalking(flat(.line), to: 10))
    }

    /// The centre must be measured in the lines the ROWS get. Counting the
    /// "N more" indicator lines as part of the area put the row one line low for
    /// each indicator above it — the reported "settles on line 9 of 15".
    @Test("Centring measures the row area, not the whole content height")
    func centringExcludesIndicatorLines() {
        let heights = Array(repeating: 1, count: 40)
        let handler = ItemListHandler<Int>(
            focusID: "list", itemCount: heights.count, viewportHeight: 15,
            selectionMode: .single)
        handler.contentHeight = 17  // 15 for rows, 2 for the indicators
        handler.drawsScrollIndicators = true
        handler.rowHeight = { heights[$0] }
        handler.followMargin = .centered(anchor: .center)
        handler.scrollGranularity = .line

        handler.focusedIndex = 20
        handler.ensureFocusedItemVisible()

        // 1-based line within the 15-line row area: 7 above → line 8, the exact
        // middle (7 above, 7 below).
        let linesAbove = 20 - handler.scrollOffset - handler.scrollTopClipLines
        #expect(
            linesAbove == 7,
            "a one-line row centres on line 8 of 15; got line \(linesAbove + 1)")
    }
}
