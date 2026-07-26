//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabStripRowNavigationTests.swift
//
//  Up/down navigation across the rows of a wrapped tab strip.
//
//  The strip floats the active row to the BOTTOM — it abuts and connects to the
//  content — so the rendered geometry the handler navigates always has the
//  current row LAST. Reading "the row below" out of that geometry as `row + 1`
//  is therefore always out of bounds, and Down could never move at all. The
//  strip is a ring: the row after the bottom one is the top one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

private final class IntBox {
    var value: Int
    init(_ v: Int) { value = v }
    var binding: Binding<Int> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
@Suite("Tab strip row navigation")
struct TabStripRowNavigationTests {

    /// A handler over `count` tabs, wired to `selection`.
    private func handler(count: Int, selection: IntBox) -> TabStripHandler {
        TabStripHandler(
            focusID: "t",
            selection: Binding(
                get: { AnyHashable(selection.value) },
                set: { selection.value = ($0.base as? Int) ?? selection.value }),
            values: Array(0..<count).map { AnyHashable($0) })
    }

    // MARK: - The handler in isolation

    @Test("Up and down step between rows by nearest centre, treating the strip as a ring")
    func verticalRowNavigation() {
        let sel = IntBox(4)
        let strip = handler(count: 6, selection: sel)
        // Two tabs per row, aligned in two columns.
        strip.centers = [0: 2, 1: 8, 2: 2, 3: 8, 4: 2, 5: 8]
        // As rendered: the active row (tab 4's) is floated last.
        strip.rows = [[0, 1], [2, 3], [4, 5]]

        // Up → the row above, nearest centre → tab 2.
        #expect(strip.handleKeyEvent(KeyEvent(key: .up)) == true)
        #expect(sel.value == 2)

        // The next render floats tab 2's row to the bottom, rotating the rest.
        strip.rows = [[4, 5], [0, 1], [2, 3]]

        // Down → back where we came from. Up and down are inverses.
        #expect(strip.handleKeyEvent(KeyEvent(key: .down)) == true)
        #expect(sel.value == 4)
    }

    @Test("Down moves the other way around the ring from up")
    func downIsTheOppositeDirection() {
        let sel = IntBox(4)
        let strip = handler(count: 6, selection: sel)
        strip.centers = [0: 2, 1: 8, 2: 2, 3: 8, 4: 2, 5: 8]
        strip.rows = [[0, 1], [2, 3], [4, 5]]

        // Up from tab 4's row reaches tab 2's; down must reach the *other*
        // neighbour, tab 0's row, not the same one.
        #expect(strip.handleKeyEvent(KeyEvent(key: .down)) == true)
        #expect(sel.value == 0, "down went to the row up would not have, got \(sel.value)")
    }

    @Test("A single-row strip passes up and down through, so focus can leave it")
    func singleRowBubbles() {
        let sel = IntBox(1)
        let strip = handler(count: 3, selection: sel)
        strip.rows = [[0, 1, 2]]
        strip.centers = [0: 2, 1: 8, 2: 14]

        #expect(strip.handleKeyEvent(KeyEvent(key: .up)) == false)
        #expect(strip.handleKeyEvent(KeyEvent(key: .down)) == false)
        #expect(sel.value == 1, "an unhandled key must not disturb the selection")
    }

    @Test("A strip that has never been laid out passes the keys through")
    func unrenderedStripBubbles() {
        let sel = IntBox(0)
        let strip = handler(count: 3, selection: sel)
        #expect(strip.handleKeyEvent(KeyEvent(key: .up)) == false)
        #expect(strip.handleKeyEvent(KeyEvent(key: .down)) == false)
    }

    // MARK: - Through a real render

    /// Six tabs in a strip too narrow for one row: three rows of two, so the row
    /// of tab `n` is `n / 2`.
    private func wrappedStrip(_ sel: IntBox) -> some View {
        TabView(selection: sel.binding) {
            ForEach(0..<6) { i in Tab("T\(i)", value: i) { Text("c\(i)") } }
        }
        .tabViewStyle(.compact)
    }

    @Test("A focused wrapped strip moves the selection to another row on up")
    func upMovesBetweenRowsInRender() {
        let sel = IntBox(0)
        let ctx = makeRenderContext(width: 14, height: 14)
        let fm = ctx.environment.focusManager!
        _ = renderToBuffer(wrappedStrip(sel), context: ctx)  // registers handler + geometry
        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))         // focus the strip
        #expect(fm.dispatchKeyEvent(KeyEvent(key: .up)), "there is a row above the active one")
        #expect(sel.value / 2 != 0, "the selection left row 0, landing on tab \(sel.value)")
    }

    @Test("A focused wrapped strip moves the selection to another row on down")
    func downMovesBetweenRowsInRender() {
        let sel = IntBox(0)
        let ctx = makeRenderContext(width: 14, height: 14)
        let fm = ctx.environment.focusManager!
        _ = renderToBuffer(wrappedStrip(sel), context: ctx)
        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))
        #expect(
            fm.dispatchKeyEvent(KeyEvent(key: .down)),
            """
            Down is handled. The active row is floated to the bottom of the strip, \
            so there is never a row literally below it — but the strip is a ring, \
            and down steps around it.
            """)
        #expect(sel.value / 2 != 0, "the selection left row 0, landing on tab \(sel.value)")
    }

    @Test("Repeated up cycles through every row of a wrapped strip")
    func upReachesEveryRow() {
        #expect(rowsVisited(pressing: .up) == 3, "up walks all three rows")
    }

    @Test("Repeated down cycles through every row of a wrapped strip")
    func downReachesEveryRow() {
        #expect(rowsVisited(pressing: .down) == 3, "down walks all three rows")
    }

    /// Presses `key` six times on a focused three-row strip, re-rendering between
    /// presses so the handler sees the rotated geometry the user is looking at,
    /// and reports how many distinct rows the selection visited.
    private func rowsVisited(pressing key: Key) -> Int {
        let sel = IntBox(0)
        let ctx = makeRenderContext(width: 14, height: 14)
        let fm = ctx.environment.focusManager!
        let view = wrappedStrip(sel)
        _ = renderToBuffer(view, context: ctx)
        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))  // focus the strip
        var seen: Set<Int> = [sel.value / 2]
        for _ in 0..<6 {
            _ = renderToBuffer(view, context: ctx)  // refresh the row geometry
            _ = fm.dispatchKeyEvent(KeyEvent(key: key))
            seen.insert(sel.value / 2)
        }
        return seen.count
    }
}
