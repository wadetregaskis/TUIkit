//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TabViewSizeCacheTests.swift
//
//  A TabView sizes its panel to the tallest and widest of ALL its tabs, so that
//  switching tabs never changes the panel's size. Measuring every tab on every
//  frame would be wasteful, so the per-tab sizes are cached — but the cache was
//  keyed by tab value alone, with no record of the width they were measured at.
//  Only the selected tab is re-measured each pass, so after the terminal (or any
//  enclosing layout) changed width, every OTHER tab kept a size measured at the
//  old one — and the panel jumped the moment you switched to one of them. The
//  height is part of the same question: a tab can be as tall, and as wide, as
//  the height it is offered lets it be.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A TabView's per-tab size cache tracks the space it measured in")
struct TabViewSizeCacheTests {

    /// Long enough to sit on one line at 60 cells and to wrap at 20.
    private static let prose = "one two three four five six seven eight nine ten"

    private func tabs(selection: Int) -> some View {
        TabView(selection: .constant(selection)) {
            Tab("A", value: 0) { Text("a") }
            Tab("B", value: 1) { Text(Self.prose) }
        }
    }

    private func render(tui: TUIContext, width: Int, selection: Int) -> [String] {
        render(tabs(selection: selection), tui: tui, width: width, height: 24)
    }

    private func render(_ view: some View, tui: TUIContext, width: Int, height: Int) -> [String] {
        let focus = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = focus
        env.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focus.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer.lines.map(\.stripped)
    }

    /// Tab B's size depends on the HEIGHT it is offered: fifteen wide lines
    /// where they fit, one narrow word where they do not.
    private func heightDependentTabs() -> some View {
        TabView(selection: .constant(0)) {
            Tab("A", value: 0) { Text("a") }
            Tab("B", value: 1) {
                ViewThatFits(in: .vertical) {
                    VStack(spacing: 0) {
                        ForEach(0..<15, id: \.self) { _ in Text("wide wide wide wide") }
                    }
                    Text("narrow")
                }
            }
        }
    }

    @Test("After a width change the panel is the same height on either tab")
    func panelHeightSurvivesAWidthChange() {
        let tui = TUIContext()
        _ = render(tui: tui, width: 60, selection: 0)  // seeds both tabs at 60
        let narrowOnA = render(tui: tui, width: 20, selection: 0)
        let narrowOnB = render(tui: tui, width: 20, selection: 1)

        #expect(
            narrowOnA.count == narrowOnB.count,
            """
            the panel reserves room for the tallest tab AT THE CURRENT WIDTH, so \
            switching tabs does not resize it. Tab A gave \(narrowOnA.count) rows, \
            tab B \(narrowOnB.count):

            — on tab A —
            \(narrowOnA.joined(separator: "\n"))
            — on tab B —
            \(narrowOnB.joined(separator: "\n"))
            """)
    }

    @Test("A tab measured wide is re-measured when the panel narrows")
    func widthChangeRemeasuresEveryTab() {
        let tui = TUIContext()
        _ = render(tui: tui, width: 60, selection: 0)
        let narrow = render(tui: tui, width: 20, selection: 0)
        // Tab B's prose needs several lines at 20 cells; one content row means the
        // panel is still sized from the 60-cell measurement.
        #expect(
            narrow.count > 2,
            """
            tab B wraps to several rows at 20 cells, and the panel sizes to the \
            tallest tab, so it cannot be a single content row:
            \(narrow.joined(separator: "\n"))
            """)
    }

    /// A terminal that only got shorter. Tab B, not selected, was measured in
    /// forty rows — fifteen wide lines — and kept that size, because the cache
    /// was keyed by width alone and only the selected tab is re-measured: the
    /// panel stayed nineteen columns wide and sixteen rows tall around tab A's
    /// one letter, twelve rows of it on screen, until B was selected.
    @Test("After a height change the panel is the size a fresh one would be")
    func heightChangeRemeasuresEveryTab() {
        let tui = TUIContext()
        _ = render(heightDependentTabs(), tui: tui, width: 40, height: 40)
        let shortened = render(heightDependentTabs(), tui: tui, width: 40, height: 12)
        let fresh = render(heightDependentTabs(), tui: TUIContext(), width: 40, height: 12)
        #expect(
            shortened == fresh,
            """
            tab B is one narrow word in twelve rows, so the panel is the same \
            as a TabView that never saw forty:

            — shortened —
            \(shortened.joined(separator: "\n"))
            — fresh —
            \(fresh.joined(separator: "\n"))
            """)
    }

    @Test("Re-rendering at an unchanged width does not change the panel")
    func stableWidthIsStable() {
        let tui = TUIContext()
        let first = render(tui: tui, width: 30, selection: 0)
        let second = render(tui: tui, width: 30, selection: 0)
        #expect(first == second, "a steady-state frame renders identically")
    }
}
