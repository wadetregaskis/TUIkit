//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollFollowMarginTests.swift
//
//  ScrollFollowMargin semantics: the resolved-lines math, and the Menu's
//  stateful windowing under each policy — the default is the classic
//  edge-triggered scroll (the window holds still until the selection
//  reaches its edge), .lines(n) starts scrolling n lines early, and
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
        #expect(ScrollFollowMargin.lines(2).resolvedLines(viewportLines: 10) == 2)
        #expect(ScrollFollowMargin.rows(3).resolvedLines(viewportLines: 10) == 3)
        #expect(ScrollFollowMargin.fraction(0.25).resolvedLines(viewportLines: 12) == 3)
        // centered == fraction(0.5), clamped to (viewport - 1) / 2.
        #expect(ScrollFollowMargin.centered == ScrollFollowMargin.fraction(0.5))
        #expect(ScrollFollowMargin.centered.resolvedLines(viewportLines: 9) == 4)
        #expect(ScrollFollowMargin.centered.resolvedLines(viewportLines: 10) == 4)
        // Excess margins clamp so a selection can rest strictly inside.
        #expect(ScrollFollowMargin.lines(99).resolvedLines(viewportLines: 8) == 3)
        // Out-of-range inputs are sanitized at construction.
        #expect(ScrollFollowMargin.lines(-5).resolvedLines(viewportLines: 8) == 0)
        #expect(ScrollFollowMargin.fraction(2.0) == ScrollFollowMargin.fraction(0.5))
        #expect(ScrollFollowMargin.fraction(-1) == ScrollFollowMargin.fraction(0))
        // Degenerate viewports never produce a negative margin.
        #expect(ScrollFollowMargin.centered.resolvedLines(viewportLines: 1) == 0)
        #expect(ScrollFollowMargin.lines(1).resolvedLines(viewportLines: 0) == 0)
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

    @Test(".lines(2) starts scrolling two lines before the edge")
    func linesMarginScrollsEarly() {
        let defaultTops = walkTops(margin: nil, from: 0, to: 10)
        let marginTops = walkTops(margin: .lines(2), from: 0, to: 10)
        let defaultHold = defaultTops.prefix { $0 == 1 }.count
        let marginHold = marginTops.prefix { $0 == 1 }.count
        #expect(
            defaultHold - marginHold == 2,
            "a 2-line margin scrolls exactly 2 steps earlier: default \(defaultTops), margin \(marginTops)")
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
