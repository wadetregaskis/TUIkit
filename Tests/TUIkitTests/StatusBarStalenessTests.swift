//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarStalenessTests.swift
//
//  A page's shortcuts leave with the page. They did not: pressing Escape back
//  to the Example's menu left every shortcut of the page just left sitting on
//  the bar, because a `.statusBarItems` OUTSIDE a focus section wrote straight
//  into the app's standing global set and nothing cleared it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("A page's status items leave with the page")
struct StatusBarStalenessTests {

    /// One frame, as the loop runs it: clear what the tree declared last time,
    /// render, and read the bar.
    private func frame<V: View>(_ view: V, bar: StatusBarState, tui: TUIContext) -> [String] {
        var environment = EnvironmentValues()
        environment.statusBar = bar
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10, environment: environment, tuiContext: tui)
        bar.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        return bar.currentUserItems.map(\.shortcut)
    }

    @Test("Items declared by a view that has gone are gone with it")
    func aDepartedPageTakesItsShortcuts() {
        let bar = StatusBarState()
        let tui = TUIContext()
        let page = Text("page").statusBarItems {
            StatusBarItem(shortcut: "c", label: "chars")
            StatusBarItem(shortcut: "m", label: "colour")
        }
        #expect(frame(page, bar: bar, tui: tui) == ["c", "m"])
        // The page is gone; so are its shortcuts.
        #expect(frame(Text("menu"), bar: bar, tui: tui).isEmpty)
        // And it can come back.
        #expect(frame(page, bar: bar, tui: tui) == ["c", "m"])
    }

    @Test("An app's own standing items are not swept away with them")
    func imperativeItemsSurvive() {
        // `setItems(_:)` is the app saying so once, not the tree saying so this
        // frame — the pass clear must not touch it.
        let bar = StatusBarState()
        let tui = TUIContext()
        bar.setItems([StatusBarItem(shortcut: "?", label: "help")])
        #expect(frame(Text("menu"), bar: bar, tui: tui) == ["?"])

        // A page's declaration takes precedence while the page is there, which
        // is what writing into the same property used to do…
        let page = Text("page").statusBarItems { StatusBarItem(shortcut: "c", label: "chars") }
        #expect(frame(page, bar: bar, tui: tui) == ["c"])
        // …and the standing set comes back when it leaves.
        #expect(frame(Text("menu"), bar: bar, tui: tui) == ["?"])
    }
}
