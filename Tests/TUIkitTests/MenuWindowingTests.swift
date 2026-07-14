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
