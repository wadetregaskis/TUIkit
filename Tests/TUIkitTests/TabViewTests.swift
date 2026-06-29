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

private final class BoolBox {
    var value: Bool
    init(_ v: Bool) { value = v }
    var binding: Binding<Bool> { Binding(get: { self.value }, set: { self.value = $0 }) }
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

    @Test("Bordered style: folder tabs on a content box, border opens under the active tab")
    func borderedBox() {
        let lines = renderToBuffer(
            TabView(selection: .constant(1)) {
                Tab("RGB", value: 0) { Text("aaa") }
                // Wide content so the three tabs sit on one row (the strip folds
                // to the widest tab's content width).
                Tab("HSL", value: 1) { Text("body-here, the widest tab content row") }
                Tab("HSB", value: 2) { Text("ccc") }
            }.tabViewStyle(.bordered),
            context: makeRenderContext(width: 60, height: 12)
        ).lines.map { $0.stripped }
        // Tab labels sit in a row, separated by walls.
        #expect(lines.contains { $0.contains("│ RGB │") && $0.contains("│ HSL │") },
                "folder tabs with wall separators: \(lines)")
        // The active tab (HSL, a middle tab) has BOTH top corners rounded so it
        // reads as a raised `╭ … ╮` cell — its left ╭ deliberately cuts into the
        // neighbour. So the tops line carries two ╭ (the strip start and the
        // active tab's left corner), where a flush ┬ would leave only one.
        let labelsIndex = lines.firstIndex { $0.contains("│ HSL │") }!
        let topsLine = lines[labelsIndex - 1]
        #expect(topsLine.filter { $0 == "╭" }.count >= 2,
                "active tab's left top corner is rounded (╭), not a flush ┬: \(topsLine)")
        #expect(topsLine.contains("╮"), "active tab's right top corner is rounded (╮): \(topsLine)")
        // The content box's top border curves up around the active tab — a line
        // carrying the mouth ╯ … ╰ (╯ before ╰, distinguishing it from the
        // bottom border's ╰ … ╯).
        #expect(lines.contains { line in
            guard let p = line.firstIndex(of: "╯"), let q = line.firstIndex(of: "╰") else { return false }
            return p < q
        }, "border opens under the active tab (╯ … ╰ mouth): \(lines)")
        // A line-drawn content box with rounded bottom corners.
        #expect(lines.last?.contains("╰") == true && lines.last?.contains("╯") == true, "bottom border")
        // Only the active tab's content shows.
        #expect(lines.contains { $0.contains("body-here") }, "active tab content shows")
        #expect(!lines.joined().contains("aaa") && !lines.joined().contains("ccc"),
                "inactive tabs' content is hidden")
    }

    @Test("A tab's content background is contiguous — child resets don't punch holes (#3)")
    func contentBackgroundIsContiguous() {
        // A Toggle emits several interior ANSI resets (brackets, mark, label). The
        // active tab's content must stay fully backed by the surface across all of
        // them. Persistent background keeps one background code per reset, so the
        // counts match (the old naive wrap left a single opening code).
        let raw = renderToBuffer(
            TabView(selection: .constant(0)) {
                Tab("Settings", value: 0) { Toggle("Notify", isOn: .constant(true)) }
            }.tabViewStyle(.compact),
            context: makeRenderContext(width: 30, height: 4))
        // The content line (the one with the toggle label).
        let line = raw.lines.first { $0.contains("Notify") } ?? ""
        let resets = line.components(separatedBy: "\u{1B}[0m").count - 1
        let backgrounds = line.components(separatedBy: "48;2;").count - 1
        #expect(resets >= 2, "the toggle emits interior resets")
        #expect(backgrounds == resets,
                "every reset is followed by a re-applied background (got \(backgrounds) bg vs \(resets) resets)")
    }

    @Test("A ScrollView-wrapped tab sizes to its content, not the viewport (#4)")
    func scrollViewTabSizesToContent() {
        // A ScrollView is width-flexible; measured naively (AnyView render
        // fallback) it would fill the whole screen and balloon the panel. The
        // per-tab concrete measure closure + the ScrollView's content-sized ideal
        // size it to its content instead.
        let view = TabView(selection: .constant(0)) {
            Tab("A", value: 0) { ScrollView { Text("exactly-this-wide") } }
            Tab("B", value: 1) { ScrollView { Text("b") } }
        }.tabViewStyle(.compact)
        let buf = renderToBuffer(view, context: makeRenderContext(width: 120, height: 12))
        #expect(buf.width < 60,
                "panel sizes to the ScrollView's content (~17), not the 120-wide screen: \(buf.width)")
        #expect(buf.lines.map { $0.stripped }.joined().contains("exactly-this-wide"),
                "the scrolled content is shown")
    }

    @Test("Header alignment shifts the tab strip across the box")
    func headerAlignment() {
        func tabsLine(_ alignment: HorizontalAlignment) -> String {
            let view = TabView(selection: .constant(0)) {
                Tab("A", value: 0) { Text(String(repeating: "wide content ", count: 4)) }
                Tab("B", value: 1) { Text("b") }
            }.tabViewStyle(.bordered).tabViewHeaderAlignment(alignment)
            return renderToBuffer(view, context: makeRenderContext(width: 60, height: 8))
                .lines.map { $0.stripped }.first { $0.contains("│ A │") } ?? ""
        }
        func leadingSpaces(_ s: String) -> Int { s.prefix { $0 == " " }.count }
        let leading = leadingSpaces(tabsLine(.leading))
        let center = leadingSpaces(tabsLine(.center))
        let trailing = leadingSpaces(tabsLine(.trailing))
        #expect(leading < center && center < trailing,
                "leading(\(leading)) < centre(\(center)) < trailing(\(trailing))")
    }

    @Test("Compact adds no padding row; bordered pads its content (#1, #5)")
    func contentPadding() {
        // Compact: the content sits immediately under the strip — no blank row.
        let compact = renderToBuffer(
            TabView(selection: .constant(0)) {
                Tab("A", value: 0) { Text("CONTENT") }
            }.tabViewStyle(.compact),
            context: makeRenderContext(width: 20, height: 5)
        ).lines.map { $0.stripped }
        let compactStripRow = compact.firstIndex { $0.contains("A") } ?? 0
        #expect(compact[compactStripRow + 1].contains("CONTENT"),
                "compact: content is on the row right after the strip: \(compact)")

        // Bordered: a default inset puts a blank (padded) row above the content.
        let bordered = renderToBuffer(
            TabView(selection: .constant(0)) {
                Tab("A", value: 0) { Text("CONTENT") }
            }.tabViewStyle(.bordered),
            context: makeRenderContext(width: 30, height: 9)
        ).lines.map { $0.stripped }
        let contentRow = bordered.firstIndex { $0.contains("CONTENT") } ?? 0
        // The row above the content is interior padding (just the box walls), and
        // the content is indented by the leading inset.
        #expect(bordered[contentRow].contains("  CONTENT"), "bordered content is inset: \(bordered)")
    }

    @Test("The active tab breathes (background changes with the pulse) when focused (#4)")
    func activeTabAnimatesWhenFocused() {
        let tui = TUIContext()
        let fm = FocusManager()
        func activeChipBackground(phase: Double) -> String {
            // Wide content so both chips sit on one row (the active chip on the
            // sole strip line, where the test reads it).
            let view = TabView(selection: .constant(0)) {
                Tab("AAA", value: 0) { Text(String(repeating: "x", count: 16)) }
                Tab("BBB", value: 1) { Text(String(repeating: "y", count: 16)) }
            }.tabViewStyle(.compact)
            var env = EnvironmentValues()
            env.focusManager = fm
            env.pulsePhase = phase
            let ctx = RenderContext(
                availableWidth: 30, availableHeight: 5, environment: env, tuiContext: tui)
            fm.beginRenderPass()
            let line = renderToBuffer(view, context: ctx).lines.first ?? ""
            fm.endRenderPass()
            // The first 48;2;r;g;b run on the strip line is the active chip's fill.
            guard let r = line.range(of: "48;2;") else { return "none" }
            return String(line[r.upperBound...].prefix(11))
        }
        _ = activeChipBackground(phase: 0)  // first render auto-focuses the strip
        #expect(activeChipBackground(phase: 0.0) != activeChipBackground(phase: 1.0),
                "the focused active tab's fill tracks the pulse phase (it animates)")
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
                // Content wide enough that both chips sit on one row.
                Tab("One", value: 0) { Text("body content, wide enough for one row") }
                Tab("Two", value: 1) { Text("body") }
            }.tabViewStyle(.compact)).joined()
        #expect(out.contains("▐") && out.contains("▌"), "compact tabs carry ▐ ▌ edge caps: \(out)")
        // Between two tabs the caps abut as ▌▐.
        #expect(out.contains("▌▐"), "adjacent chips meet at their caps")
    }

    @Test("`.toContentWidth` folds the strip to the content; `.minimal` doesn't (#1, #3)")
    func headerWrapModes() {
        func tabs() -> some View {
            TabView(selection: .constant(0)) {
                ForEach(0..<10) { i in Tab("Tab\(i)", value: i) { Text(String(repeating: "x", count: 28)) } }
            }.tabViewStyle(.compact)
        }
        // .toContentWidth: even on a wide screen the ~80-wide strip folds to the
        // ~28-wide content, so the panel stays narrow.
        let folded = renderToBuffer(
            tabs().tabViewHeaderWrap(.toContentWidth), context: makeRenderContext(width: 120, height: 16))
        let foldedStrip = folded.lines.prefix { !$0.stripped.contains("x") }
        #expect(foldedStrip.count > 1, "toContentWidth folds despite the wide screen")
        #expect(folded.width <= 40, "panel sized to the widest content (~28): \(folded.width)")
        let joined = folded.lines.map { $0.stripped }.joined(separator: " ")
        for i in 0..<10 { #expect(joined.contains("Tab\(i)"), "Tab\(i) present after folding") }

        // .minimal (the default): the strip stays on one row when the screen has
        // room — it does NOT fold just because the content is narrower.
        let minimal = renderToBuffer(tabs(), context: makeRenderContext(width: 120, height: 16))
        let minimalStrip = minimal.lines.prefix { !$0.stripped.contains("x") }
        #expect(minimalStrip.count == 1, "minimal keeps one row when the screen has room")

        // Constrained narrower than the content: the panel stays within bounds.
        let narrow = renderToBuffer(
            tabs().tabViewHeaderWrap(.toContentWidth), context: makeRenderContext(width: 20, height: 16))
        #expect(narrow.width <= 20, "panel stays within the available width, got \(narrow.width)")
    }

    // MARK: - Vertical sizing (tallest tab)

    /// A TabView whose tabs have very different heights: a one-line tab and a
    /// five-line tab. Rendered at `sel` with the given content-sizing mode.
    private func unevenHeightTabs(
        _ sel: Int, sizing: TabViewContentSizing? = nil
    ) -> FrameBuffer {
        let view = TabView(selection: .constant(sel)) {
            Tab("Short", value: 0) { Text("one line") }
            Tab("Tall", value: 1) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<5, id: \.self) { Text("row \($0)") }
                }
            }
        }
        .tabViewStyle(.compact)
        let base = AnyView(view)
        let configured = sizing.map { AnyView(base.tabViewContentSizing($0)) } ?? base
        // A generous height so the panel sizes to content, not the viewport.
        return renderToBuffer(configured, context: makeRenderContext(width: 30, height: 20))
    }

    @Test("By default the panel sizes to the tallest tab — height is stable across switches")
    func panelSizesToTallestTab() {
        // Both the short tab and the tall tab render at the SAME panel height
        // (the tallest tab's), so switching tabs doesn't resize the panel.
        let onShort = unevenHeightTabs(0).height
        let onTall = unevenHeightTabs(1).height
        #expect(onShort == onTall,
                "panel height is stable across tabs (short=\(onShort), tall=\(onTall))")
        // And that height accommodates the tall tab's five content rows + strip.
        #expect(onTall >= 6, "panel is tall enough for the five-row tab plus the strip: \(onTall)")
        // The short tab's content still shows (it's just padded out below).
        #expect(unevenHeightTabs(0).lines.map { $0.stripped }.joined().contains("one line"))
    }

    @Test("`.tabViewContentSizing(.activeTab)` makes the panel track the active tab's height")
    func activeTabSizingTracksSelection() {
        let onShort = unevenHeightTabs(0, sizing: .activeTab).height
        let onTall = unevenHeightTabs(1, sizing: .activeTab).height
        #expect(onShort < onTall,
                "with .activeTab the short tab's panel is shorter than the tall tab's (short=\(onShort), tall=\(onTall))")
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
        let fm = ctx.environment.focusManager!
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
        // Content wide enough that all three tabs sit on one row (so the regions
        // are in tab order, not reordered by row folding/floating).
        let view = TabView(selection: sel.binding) {
            Tab("A", value: 0) { Text(String(repeating: "a", count: 18)) }
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

    @Test("A tab narrower than the panel is centred within it (#4)")
    func narrowTabContentCentred() {
        // The wide tab sets the panel width; the selected narrow tab's content
        // should sit centred in that panel, not left-aligned. (It is rendered at
        // the panel width then clamped to its natural width and block-centred.)
        let view = TabView(selection: .constant(1)) {
            Tab("Wide", value: 0) { Text(String(repeating: "x", count: 30)) }
            Tab("Narrow", value: 1) { Text("hi") }
        }
        .tabViewStyle(.compact)
        let buf = renderToBuffer(view, context: makeRenderContext(width: 60, height: 10))
        guard let row = buf.lines.map({ $0.stripped }).first(where: { $0.contains("hi") }) else {
            Issue.record("narrow tab content not found in render")
            return
        }
        let lead = row.prefix(while: { $0 == " " }).count
        let trail = Array(row).reversed().prefix(while: { $0 == " " }).count
        #expect(lead > 1, "narrow content has leading padding (centred, not left-aligned), got lead=\(lead)")
        #expect(abs(lead - trail) <= 1, "content is centred (lead ≈ trail), got \(lead)/\(trail)")
    }

    @Test("Up/down move between tab rows by nearest centre; past the edge they bubble (#2)")
    func verticalRowNavigation() {
        let sel = IntBox(2)
        let handler = TabStripHandler(
            focusID: "t",
            selection: Binding(get: { AnyHashable(sel.value) }, set: { sel.value = ($0.base as? Int) ?? sel.value }),
            values: [0, 1, 2, 3])
        // Two rows, [0,1] above [2,3], columns aligned by centre.
        handler.rows = [[0, 1], [2, 3]]
        handler.centers = [0: 2, 1: 8, 2: 2, 3: 8]

        // From tab 2 (row 1, left column) up → row 0, nearest centre → tab 0.
        #expect(handler.handleKeyEvent(KeyEvent(key: .up)) == true)
        #expect(sel.value == 0)
        // From the top row, up has no row above → bubbles out, selection unchanged.
        #expect(handler.handleKeyEvent(KeyEvent(key: .up)) == false)
        #expect(sel.value == 0)
        // Down → row 1, nearest centre → tab 2.
        #expect(handler.handleKeyEvent(KeyEvent(key: .down)) == true)
        #expect(sel.value == 2)
        // From the bottom row, down bubbles out, selection unchanged.
        #expect(handler.handleKeyEvent(KeyEvent(key: .down)) == false)
        #expect(sel.value == 2)
    }

    @Test("A focused wrapped strip moves the selection to another row on up (#2)")
    func arrowNavMovesBetweenRowsInRender() {
        let sel = IntBox(0)
        let ctx = makeRenderContext(width: 18, height: 12)
        let fm = ctx.environment.focusManager!
        let view = TabView(selection: sel.binding) {
            ForEach(0..<6) { i in Tab("Tab\(i)", value: i) { Text("c\(i)") } }
        }
        .tabViewStyle(.compact)
        _ = renderToBuffer(view, context: ctx)          // registers the handler + row geometry
        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))    // focus the strip (active row floated to bottom)
        let moved = fm.dispatchKeyEvent(KeyEvent(key: .up))
        #expect(moved, "up is handled — there is a row above the active (bottom) row")
        #expect(sel.value != 0, "selection moved to a tab in the row above, was 0 now \(sel.value)")
    }

    @Test("Repeated up cycles through every row of a wrapped strip (#2 rotation)")
    func upReachesEveryRow() {
        // Six tabs wrap to three rows of two ([0,1] [2,3] [4,5]); row = value / 2.
        let sel = IntBox(0)
        let ctx = makeRenderContext(width: 14, height: 14)
        let fm = ctx.environment.focusManager!
        let view = TabView(selection: sel.binding) {
            ForEach(0..<6) { i in Tab("T\(i)", value: i) { Text("c\(i)") } }
        }
        .tabViewStyle(.compact)
        _ = renderToBuffer(view, context: ctx)
        _ = fm.dispatchKeyEvent(KeyEvent(key: .tab))  // focus the strip
        var seenRows: Set<Int> = [sel.value / 2]
        for _ in 0..<6 {
            _ = renderToBuffer(view, context: ctx)    // refresh row geometry for the new selection
            _ = fm.dispatchKeyEvent(KeyEvent(key: .up))
            seenRows.insert(sel.value / 2)
        }
        // The float-to-bottom-by-removal layout could only ever reach two rows;
        // rotating the rows lets up walk through all three.
        #expect(seenRows.count == 3, "up reaches every row; saw rows \(seenRows.sorted())")
    }

    @Test("A control inside a bordered tab is clickable (its hit region survives the box chrome)")
    func borderedTabContentClickable() {
        let on = BoolBox(false)
        let ctx = makeRenderContext(width: 40, height: 12) { environment, tui in
            environment.mouseEventDispatcher = tui.mouseEventDispatcher
        }
        let dispatcher = ctx.environment.mouseEventDispatcher!
        let view = TabView(selection: .constant(0)) {
            Tab("Settings", value: 0) { Toggle("Online", isOn: on.binding) }
        }
        .tabViewStyle(.bordered)
        let buffer = renderToBuffer(view, context: ctx)
        dispatcher.setRegions(buffer.hitTestRegions)
        // The toggle sits in the content area, below the tab strip — i.e. the
        // lowest hit region. Before the fix the bordered box rebuilt its content
        // rows as fresh strings and dropped this region, so only the tab header
        // remained and the control was dead to the mouse.
        guard let r = buffer.hitTestRegions.max(by: { $0.offsetY < $1.offsetY }) else {
            Issue.record("no hit region for the toggle inside the bordered tab")
            return
        }
        let x = r.offsetX + r.width / 2
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: r.offsetY))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: r.offsetY))
        #expect(on.value, "clicking the toggle inside the bordered tab flipped it")
    }
}
