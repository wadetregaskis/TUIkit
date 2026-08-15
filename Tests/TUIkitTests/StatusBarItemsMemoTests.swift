//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StatusBarItemsMemoTests.swift
//
//  Regression test for `.statusBarItems` interacting with the render memos.
//  The status bar's section items are cleared and rebuilt every render pass,
//  so a subtree served from the cache never re-registers and its items
//  silently vanish from the bar. The modifier adds no hit region and reads no
//  volatile value, so every other cache gate let it through — it has to
//  declare the side effect, exactly as the preference and onKeyPress
//  modifiers do.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Status bar items through the render memos")
struct StatusBarItemsMemoTests {
    /// One live-loop-shaped frame, returning the items the bar would show.
    private func renderFrame<V: View>(_ view: V, tuiContext: TUIContext) -> [String] {
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        // A status bar of this frame's own: the environment no longer
        // hands out a shared instance, which is what let a parallel
        // neighbour's items be read back as this test's.
        environment.statusBar = StatusBarState()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.activeFocusSectionID = "section"
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10,
            environment: environment, tuiContext: tuiContext)

        environment.statusBar?.clearSectionItems()
        // The bar derives its active section from the focus manager, exactly
        // as `RenderLoop.beginRenderPass` wires it.
        environment.statusBar?.focusManager = focusManager
        focusManager.registerSection(id: "section")
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return environment.statusBar?.currentUserItems.map(\.shortcut) ?? []
    }

    @Test("A memoized row's status bar items survive a cache-hit frame")
    func itemsSurviveRowMemo() {
        let tuiContext = TUIContext()
        // An `Equatable` element auto-wires `_MemoizedRow`, so the second
        // frame is a cache hit on an unchanged row — which is exactly when
        // the registration used to be skipped.
        let view = VStack {
            ForEach(["row"], id: \.self) { name in
                Text(name).statusBarItems {
                    StatusBarItem(shortcut: "h", label: "help")
                }
            }
        }

        #expect(renderFrame(view, tuiContext: tuiContext).contains("h"))
        // Frame 2: the row's element is unchanged, so the memo may serve it.
        #expect(
            renderFrame(view, tuiContext: tuiContext).contains("h"),
            "the cache-hit frame dropped the row's status bar items")
    }

    @Test("An .equatable() subtree's status bar items survive a cache-hit frame")
    func itemsSurviveEquatableView() {
        struct Panel: View, Equatable {
            var body: some View {
                Text("panel").statusBarItems {
                    StatusBarItem(shortcut: "p", label: "panel")
                }
            }
        }
        let tuiContext = TUIContext()
        let view = VStack { Panel().equatable() }

        #expect(renderFrame(view, tuiContext: tuiContext).contains("p"))
        #expect(
            renderFrame(view, tuiContext: tuiContext).contains("p"),
            "the cache-hit frame dropped the subtree's status bar items")
    }
}
