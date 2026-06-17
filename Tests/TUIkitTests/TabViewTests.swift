//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabViewTests.swift
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

private final class DoubleBox {
    var value: Double
    init(_ v: Double) { value = v }
    var binding: Binding<Double> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
@Suite("TabView")
struct TabViewTests {

    private func lines(_ v: some View, w: Int = 40, h: Int = 8) -> [String] {
        renderToBuffer(v, context: makeRenderContext(width: w, height: h)).lines.map { $0.stripped }
    }

    // MARK: - Extraction + selection

    @Test("Renders a strip of tab titles and the selected tab's content")
    func stripAndContent() {
        let out = lines(
            TabView(selection: .constant(1)) {
                Tab("One", value: 0) { Text("first-body") }
                Tab("Two", value: 1) { Text("second-body") }
                Tab("Three", value: 2) { Text("third-body") }
            })
        let joined = out.joined(separator: "\n")
        // All three tab titles appear in the strip.
        #expect(joined.contains("One") && joined.contains("Two") && joined.contains("Three"))
        // Only the selected tab's content is shown.
        #expect(joined.contains("second-body"), "selected tab content shows: \(out)")
        #expect(!joined.contains("first-body") && !joined.contains("third-body"),
                "unselected tab content is hidden: \(out)")
    }

    @Test("Bordered style wraps tabs + content in a box, notch open under the active tab")
    func borderedBox() {
        let lines = renderToBuffer(
            TabView(selection: .constant(1)) {
                Tab("RGB", value: 0) { Text("aaa") }
                Tab("HSL", value: 1) { Text("body-here") }
                Tab("HSB", value: 2) { Text("ccc") }
            }.tabViewStyle(.bordered),
            context: makeRenderContext(width: 44, height: 10)
        ).lines.map { $0.stripped }
        // A line-drawn box.
        #expect(lines.first?.contains("╭") == true && lines.first?.contains("╮") == true, "top border")
        #expect(lines.last?.contains("╰") == true && lines.last?.contains("╯") == true, "bottom border")
        // Tabs are inside the box.
        #expect(lines.contains { $0.contains("│") && $0.contains("RGB") && $0.contains("HSL") },
                "tabs inside the box")
        // The notch separator (├ … ┤) carries a run of border with a gap (spaces)
        // opened under the active tab.
        let notch = lines.first { $0.contains("├") && $0.contains("┤") } ?? ""
        #expect(notch.contains("─") && notch.contains("   "),
                "notch is open under the active tab: \(notch)")
        #expect(lines.contains { $0.contains("body-here") }, "content shows inside the box")
    }

    @Test("The active tab's row moves to the bottom of the wrapped strip")
    func activeRowMovesToBottom() {
        // Ten tabs wrap to several rows at a narrow width. Selecting Tab0 (which
        // would otherwise be in the first row) must put its whole row last, so it
        // sits directly above the content.
        let view = TabView(selection: .constant(0)) {
            ForEach(0..<10) { i in Tab("Tab\(i)", value: i) { Text("body-marker") } }
        }.tabViewStyle(.compact)
        let lines = renderToBuffer(view, context: makeRenderContext(width: 50, height: 16))
            .lines.map { $0.stripped }
        let stripRows = lines.prefix { !$0.contains("body-marker") }
        #expect(stripRows.count > 1, "the strip wrapped to multiple rows")
        // Tab0 is in the last strip row (adjacent to the content).
        #expect(stripRows.last?.contains("Tab0") == true,
                "the active tab's row is the bottom strip row: \(Array(stripRows))")
    }

    @Test("Compact tabs render as chips with half-block edge caps")
    func compactChipEdges() {
        let out = lines(
            TabView(selection: .constant(0)) {
                Tab("One", value: 0) { Text("body") }
                Tab("Two", value: 1) { Text("body") }
            }.tabViewStyle(.compact)).joined()
        #expect(out.contains("▐") && out.contains("▌"), "compact tabs carry ▐ ▌ edge caps: \(out)")
        // Between two tabs the caps abut as ▌▐.
        #expect(out.contains("▌▐"), "adjacent chips meet at their caps")
    }

    @Test("A strip too wide for the available width wraps to multiple rows, bounded")
    func stripWrapsWhenWide() {
        let many = TabView(selection: .constant(0)) {
            ForEach(0..<10) { i in Tab("Tab\(i)", value: i) { Text("body") } }
        }.tabViewStyle(.compact)
        // Wide enough for a single row: no wrapping, the strip is one line.
        let wide = renderToBuffer(many, context: makeRenderContext(width: 120, height: 12))
        let wideStrip = wide.lines.prefix { !$0.stripped.contains("body") }
        #expect(wideStrip.count == 1, "fits on one row when there's room")
        // Narrow: the strip wraps across rows and the panel never exceeds the
        // available width (the bug would be a single 90-wide row overflowing).
        let narrow = renderToBuffer(many, context: makeRenderContext(width: 60, height: 16))
        let narrowStrip = narrow.lines.prefix { !$0.stripped.contains("body") }
        #expect(narrowStrip.count > 1, "wraps when the single row would overflow")
        #expect(narrow.width <= 60, "panel stays within the available width, got \(narrow.width)")
        // Every tab is still present across the wrapped rows.
        let joined = narrow.lines.map { $0.stripped }.joined(separator: " ")
        for i in 0..<10 { #expect(joined.contains("Tab\(i)"), "Tab\(i) present after wrapping") }
    }

    @Test("Changing the selection shows a different tab's content")
    func selectionSwitchesContent() {
        func body(_ sel: Int) -> [String] {
            lines(
                TabView(selection: .constant(sel)) {
                    Tab("A", value: 0) { Text("alpha") }
                    Tab("B", value: 1) { Text("bravo") }
                })
        }
        #expect(body(0).joined().contains("alpha"))
        #expect(body(1).joined().contains("bravo"))
    }

    @Test("Tabs declared with ForEach are extracted")
    func forEachTabs() {
        let out = lines(
            TabView(selection: .constant(2)) {
                ForEach(0..<4) { i in
                    Tab("T\(i)", value: i) { Text("body-\(i)") }
                }
            }).joined(separator: "\n")
        #expect(out.contains("T0") && out.contains("T3"))
        #expect(out.contains("body-2") && !out.contains("body-1"))
    }

    @Test("A selection with no matching tab falls back to the first tab (no crash)")
    func unmatchedSelectionFallsBack() {
        let out = lines(
            TabView(selection: .constant(99)) {
                Tab("A", value: 0) { Text("alpha") }
                Tab("B", value: 1) { Text("bravo") }
            }).joined()
        #expect(out.contains("alpha"), "falls back to the first tab: \(out)")
    }

    // MARK: - Per-tab state isolation (the colour-picker Bug B)

    @Test("Each tab's content keeps isolated @State — a slider's range can't leak across tabs")
    func perTabStateIsolation() {
        // Two tabs, each a slider of a DIFFERENT range. Mirrors the picker's RGB
        // (0…255) vs HSL (0…100) channels. Without per-tab identity the sliders
        // share @State and the wide slider inherits the narrow one's bounds,
        // clamping its value. With TabView's branch-per-tab identity they don't.
        let sel = IntBox(0)
        let wide = DoubleBox(200)  // valid in 0…255, but would clamp to 100 in 0…100
        let narrow = DoubleBox(50)

        // A persistent context so slider @State survives across renders.
        let tui = TUIContext()
        let fm = FocusManager()
        func render() {
            var env = EnvironmentValues()
            env.focusManager = fm
            let ctx = RenderContext(
                availableWidth: 40, availableHeight: 8, environment: env, tuiContext: tui)
            _ = renderToBuffer(
                TabView(selection: sel.binding) {
                    Tab("Wide", value: 0) { Slider(value: wide.binding, in: 0...255) }
                    Tab("Narrow", value: 1) { Slider(value: narrow.binding, in: 0...100) }
                },
                context: ctx)
        }

        render()                 // tab 0 (wide) active: clamps to 0…255 → 200 stays
        #expect(wide.value == 200)
        sel.value = 1; render()  // tab 1 (narrow) active
        sel.value = 0; render()  // back to tab 0
        #expect(wide.value == 200, "the wide slider kept its 0…255 bounds; state did not leak from the narrow tab")
    }

    // MARK: - Keyboard + mouse

    @Test("Left/Right arrows move the selection when the strip is focused")
    func arrowNavigation() {
        let sel = IntBox(1)
        let ctx = makeRenderContext(width: 40, height: 8)
        let fm = ctx.environment.focusManager
        let view = TabView(selection: sel.binding) {
            Tab("A", value: 0) { Text("a") }
            Tab("B", value: 1) { Text("b") }
            Tab("C", value: 2) { Text("c") }
        }
        _ = renderToBuffer(view, context: ctx)  // registers + auto-focuses the strip
        #expect(fm.dispatchKeyEvent(KeyEvent(key: .right)))
        #expect(sel.value == 2, "right moved to the next tab")
        _ = renderToBuffer(view, context: ctx)
        #expect(fm.dispatchKeyEvent(KeyEvent(key: .left)))
        #expect(sel.value == 1, "left moved back")
        // Clamps at the ends.
        _ = renderToBuffer(view, context: ctx)
        _ = fm.dispatchKeyEvent(KeyEvent(key: .left))  // → 0
        _ = renderToBuffer(view, context: ctx)
        _ = fm.dispatchKeyEvent(KeyEvent(key: .left))  // stays 0
        #expect(sel.value == 0)
    }

    @Test("Clicking a tab in the strip selects it")
    func clickSelectsTab() {
        let sel = IntBox(0)
        let ctx = makeRenderContext(width: 40, height: 8) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
        }
        let dispatcher = ctx.environment.mouseEventDispatcher!
        let view = TabView(selection: sel.binding) {
            Tab("A", value: 0) { Text("a") }
            Tab("B", value: 1) { Text("b") }
            Tab("C", value: 2) { Text("c") }
        }
        let buffer = renderToBuffer(view, context: ctx)
        dispatcher.setRegions(buffer.hitTestRegions)
        // The third tab's region.
        #expect(buffer.hitTestRegions.count >= 3, "a hit region per tab")
        let r = buffer.hitTestRegions[2]
        let x = r.offsetX + r.width / 2
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: r.offsetY))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: r.offsetY))
        #expect(sel.value == 2, "clicking tab C selected it")
    }
}
