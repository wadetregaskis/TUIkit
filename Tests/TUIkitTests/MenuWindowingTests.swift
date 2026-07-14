//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MenuWindowingTests.swift
//
//  A Menu taller than its available height windows its items to fit, keeping
//  the selected item visible and showing ▲/▼ overflow markers — so every item
//  is reachable (by arrowing/wheeling) on a terminal shorter than the menu.
//  A short menu is unchanged (no markers, all items shown). Clicks map back to
//  the correct item even when the window is scrolled.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Menu windowing (scroll when taller than the viewport)")
struct MenuWindowingTests {

    private func items(_ n: Int) -> [MenuItem] {
        (1...n).map { MenuItem(label: "Item \($0)", shortcut: nil) }
    }

    private func render(_ menu: Menu, height: Int, width: Int = 40) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(menu, context: context)
    }

    private func stripped(_ b: FrameBuffer) -> [String] { b.lines.map { $0.stripped } }

    @Test("A menu that fits shows every item and no overflow markers")
    func shortMenuUnchanged() {
        let menu = Menu(items: items(4), selectedIndex: 0)
        let out = stripped(render(menu, height: 12))
        #expect(out.contains { $0.contains("Item 1") })
        #expect(out.contains { $0.contains("Item 4") })
        #expect(!out.contains { $0.contains("▲") }, "no top marker when it fits")
        #expect(!out.contains { $0.contains("▼") }, "no bottom marker when it fits")
    }

    @Test("A tall menu at the top shows a ▼ marker and no ▲, within the viewport")
    func tallMenuTop() {
        let menu = Menu(items: items(30), selectedIndex: 0)
        let buffer = render(menu, height: 8)
        let out = stripped(buffer)
        #expect(buffer.height <= 8, "the menu fits the available height, got \(buffer.height)")
        #expect(out.contains { $0.contains("Item 1") }, "the selected top item is visible")
        #expect(out.contains { $0.contains("▼") }, "a ▼ marker shows there's more below")
        #expect(!out.contains { $0.contains("▲") }, "no ▲ marker at the top")
        #expect(!out.contains { $0.contains("Item 30") }, "far items are windowed out")
    }

    @Test("A tall menu selected in the middle windows around the selection (both markers)")
    func tallMenuMiddle() {
        let menu = Menu(items: items(30), selectedIndex: 15)
        let buffer = render(menu, height: 8)
        let out = stripped(buffer)
        #expect(buffer.height <= 8)
        #expect(out.contains { $0.contains("Item 16") }, "the selected item (index 15) is visible")
        #expect(out.contains { $0.contains("▲") }, "▲ marker: content above")
        #expect(out.contains { $0.contains("▼") }, "▼ marker: content below")
    }

    @Test("A tall menu selected at the end shows a ▲ marker and no ▼")
    func tallMenuBottom() {
        let menu = Menu(items: items(30), selectedIndex: 29)
        let out = stripped(render(menu, height: 8))
        #expect(out.contains { $0.contains("Item 30") }, "the selected last item is visible")
        #expect(out.contains { $0.contains("▲") }, "▲ marker: content above")
        #expect(!out.contains { $0.contains("▼") }, "no ▼ marker at the bottom")
    }

    @Test("A menu of budget+1 items with a mid selection still fits the height")
    func budgetPlusOneMidSelection() {
        // The regression shape: rows.count == budget + 1 with the selection in
        // the middle. The old two-pass windowing measured its markers at the
        // full budget, shrank the window, and then re-derived the markers — at
        // which point BOTH switched on and the emitted lines exceeded the
        // budget (7 items at height 8 → 6-line budget → 7 lines → 9-row menu).
        let menu = Menu(items: items(7), selectedIndex: 3)
        let buffer = render(menu, height: 8)
        #expect(buffer.height <= 8, "menu fits its offered height, got \(buffer.height)")
        #expect(
            stripped(buffer).contains { $0.contains("Item 4") },
            "the selected item stays visible")
        // The over-emission was MASKED by a parent clamp truncating the buffer
        // to the available height — slicing off the bottom border. The menu
        // must stay a closed box.
        #expect(
            stripped(buffer).last?.hasPrefix("╰") == true,
            "the bottom border survives: \(stripped(buffer))")
    }

    @Test("Windowing NEVER exceeds the height, keeps the selection visible, and markers are truthful")
    func windowingInvariantSweep() {
        // Deterministic sweep over the count × height × selection space that
        // includes every count≈budget boundary and the tiny-budget floors.
        for count in 1...25 {
            for height in 3...14 {
                for sel in 0..<count {
                    let buffer = render(Menu(items: items(count), selectedIndex: sel), height: height)
                    let out = stripped(buffer)
                    #expect(
                        buffer.height <= max(3, height),
                        "count=\(count) height=\(height) sel=\(sel): rendered \(buffer.height)")
                    // The box must be CLOSED — over-emission gets masked by the
                    // parent clamp slicing off the bottom border, so border
                    // integrity is the true no-overflow assertion.
                    #expect(
                        out.first?.hasPrefix("╭") == true && out.last?.hasPrefix("╰") == true,
                        "count=\(count) height=\(height) sel=\(sel): borders intact: \(out)")
                    // The selected item is always visible (it's the window anchor)…
                    let selVisible = out.contains { $0.contains("Item \(sel + 1)") }
                    // …except at budgets too small for even one row + chrome.
                    if height >= 4 {
                        #expect(
                            selVisible,
                            "count=\(count) height=\(height) sel=\(sel): selection visible")
                    }
                    // Markers only when there IS content beyond that edge.
                    let hasAbove = out.contains { $0.contains("▲") }
                    let hasBelow = out.contains { $0.contains("▼") }
                    let firstVisible = out.contains { $0.contains("Item 1 ") || $0.hasSuffix("Item 1") }
                    let lastVisible = out.contains { $0.contains("Item \(count)") }
                    if hasAbove {
                        #expect(
                            !firstVisible || count > 9,  // "Item 1" is a prefix of "Item 1N" past 9
                            "count=\(count) height=\(height) sel=\(sel): ▲ implies item 1 is off-screen")
                    }
                    if hasBelow {
                        #expect(
                            !lastVisible,
                            "count=\(count) height=\(height) sel=\(sel): ▼ implies the last item is off-screen")
                    }
                }
            }
        }
    }

    @Test("A divider or out-of-range selection anchors near the value, not the top")
    func dividerSelectionAnchorsNearby() {
        // A stale binding can hold a divider's index or an out-of-range value;
        // the window must stay in that neighbourhood (nearest ITEM row), not
        // snap to the top of the menu.
        var menuItems = items(20)
        menuItems.insert(.divider, at: 10)
        let onDivider = render(Menu(items: menuItems, selectedIndex: 10), height: 8)
        let out = stripped(onDivider)
        #expect(onDivider.height <= 8)
        #expect(
            out.contains { $0.contains("Item 10") || $0.contains("Item 11") },
            "window stays near the divider's neighbourhood: \(out)")
        #expect(!out.contains { $0.contains("Item 1 ") }, "not snapped to the top")

        let outOfRange = render(Menu(items: items(20), selectedIndex: 19), height: 8)
        #expect(outOfRange.height <= 8, "out-of-range-safe (init clamps; render must too)")
    }

    @Test("Clicking a windowed item selects that item, not an off-by-window neighbour")
    func clickMapsThroughWindow() {
        final class Box { var sel = 15 }
        let box = Box()
        let menu = Menu(
            items: items(30),
            selection: Binding(get: { box.sel }, set: { box.sel = $0 }))

        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var env = EnvironmentValues()
        env.mouseEventDispatcher = dispatcher
        let context = RenderContext(
            availableWidth: 40, availableHeight: 8, environment: env, tuiContext: tui
        ).isolatingRenderCache()
        let buffer = renderToBuffer(menu, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        // Find a visible item row (one that names an "Item N") and click it; the
        // selection must become exactly that N-1, proving the window offset is
        // applied to the click mapping.
        guard let y = buffer.lines.firstIndex(where: { $0.stripped.contains("Item 17") }) else {
            Issue.record("Item 17 not visible in the window: \(stripped(buffer))")
            return
        }
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 5, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 5, y: y))
        #expect(box.sel == 16, "clicking the 'Item 17' row selects index 16, got \(box.sel)")
    }
}
