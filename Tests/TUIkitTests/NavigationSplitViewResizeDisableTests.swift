//  🖥️ TUIKit — Terminal UI Kit for Swift
//  NavigationSplitViewResizeDisableTests.swift
//
//  When a split view isn't resizable — either via navigationSplitViewResizable(false)
//  or because its style sizes columns to fit content every frame — the divider
//  must draw no grip dots and register no focus section. A size-to-fit split has
//  no persisted column width for a drag to act on, so a focusable/handled
//  divider there was purely misleading (it took Tab focus but resized nothing).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("NavigationSplitView resize-disabled dividers")
struct NavigationSplitViewResizeDisableTests {

    private func resizeContext(width: Int = 80, height: Int = 12) -> RenderContext {
        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        return RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)
    }

    /// The visible column of the divider grip (a `◦` dot) on the centre row,
    /// or nil when no grip is drawn.
    private func gripX(_ buffer: FrameBuffer) -> Int? {
        guard buffer.height > 0 else { return nil }
        let mid = buffer.lines[buffer.height / 2].stripped
        guard let r = mid.firstIndex(of: "◦") else { return nil }
        return mid.distance(from: mid.startIndex, to: r)
    }

    @Test("A size-to-fit style shows no resize handle and no divider focus section")
    func sizeToFitHasNoDividerHandle() {
        // Size-to-fit recomputes column widths from content every frame, so there
        // is nothing for a drag to resize — the divider must draw no grip dots
        // and take no focus, exactly as navigationSplitViewResizable(false) does.
        let context = resizeContext()
        let fm = context.environment.focusManager!
        let view = NavigationSplitView { Text("SIDEBAR") } detail: { Text("DETAIL") }
            .navigationSplitViewStyle(.sizeToFitFromLeft)

        let buffer = renderToBuffer(view, context: context)
        #expect(gripX(buffer) == nil, "size-to-fit draws no grip handle")
        #expect(
            fm.section(id: "nav-split-divider-0") == nil,
            "size-to-fit registers no divider focus section")
    }

    @Test("The default (proportional) style keeps its resize handle and focus section")
    func proportionalStyleStillResizable() {
        // Guard the gate is scoped to size-to-fit: the balanced/proportional
        // style must still expose a draggable, focusable divider.
        let context = resizeContext()
        let fm = context.environment.focusManager!
        let view = NavigationSplitView { Text("SIDEBAR") } detail: { Text("DETAIL") }
            .navigationSplitViewStyle(.balanced)

        let buffer = renderToBuffer(view, context: context)
        #expect(gripX(buffer) != nil, "a resizable split draws its grip handle")
        #expect(
            fm.section(id: "nav-split-divider-0") != nil,
            "a resizable split registers a divider focus section")
    }
}
