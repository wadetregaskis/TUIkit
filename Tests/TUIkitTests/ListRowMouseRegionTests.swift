//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListRowMouseRegionTests.swift
//
//  List rows render into standalone (per-frame memoised) buffers, so the
//  regions their interactive content registers — per-row `.onMouseEvent`,
//  Buttons, etc. — must be explicitly merged into the List's own buffer,
//  translated to each row's on-screen position. These pin that merge: without
//  it the List's container-wide fallback region is the only thing a click can
//  hit, and per-row handlers silently never fire (the "double-click a folder
//  does nothing" file-browser bug).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("List row mouse regions")
struct ListRowMouseRegionTests {

    /// The demo's file-browser pattern: rows carry their own `.onMouseEvent`
    /// (single-click selects, double-click "opens"), driven end-to-end through
    /// the real dispatcher with an injected clock — including a re-render
    /// between the clicks, as the live run loop would do.
    @Test("Per-row onMouseEvent sees clicks, and a quick second click reaches clickCount 2")
    func rowMouseEventReceivesDoubleClick() {
        var now: UInt64 = 0
        final class Box {
            var opened: [String] = []
            var selected: [String] = []
        }
        let box = Box()
        let items = ["Folder-A", "Folder-B", "File-C"]

        let view = List(selection: .constant(String?.none)) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 1) {
                    Text("📁")
                    Text(item)
                }
                .onMouseEvent { event in
                    guard event.button == .left else { return false }
                    switch event.phase {
                    case .pressed:
                        return true
                    case .released:
                        if event.clickCount >= 2 {
                            box.opened.append(item)
                        } else {
                            box.selected.append(item)
                        }
                        return true
                    default:
                        return false
                    }
                }
            }
        }
        .frame(height: 8)

        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.nowNanos = { now }
        dispatcher.setActiveSupport(.full)

        func frame() -> FrameBuffer {
            dispatcher.beginRenderPass()
            var env = EnvironmentValues()
            env.mouseEventDispatcher = dispatcher
            env.focusManager = FocusManager()
            let context = RenderContext(
                availableWidth: 30, availableHeight: 10, environment: env, tuiContext: tui)
            let buffer = renderToBuffer(view, context: context)
            dispatcher.setRegions(buffer.hitTestRegions)
            return buffer
        }

        let buffer = frame()
        // The rows' own regions must exist alongside the container fallback.
        #expect(
            buffer.hitTestRegions.count > 1,
            "per-row regions merged into the list buffer: \(buffer.hitTestRegions)")

        guard let rowY = buffer.lines.firstIndex(where: { $0.stripped.contains("Folder-A") }) else {
            Issue.record("Folder-A not rendered")
            return
        }
        func click() {
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: rowY))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 4, y: rowY))
        }

        click()
        #expect(box.selected == ["Folder-A"], "first click selects")
        _ = frame()  // re-render between clicks, like the real run loop
        now += 120_000_000  // 120 ms — within the double-click window
        click()
        #expect(box.opened == ["Folder-A"], "second quick click opens (clickCount 2)")
    }

    /// A Button inside a List row is clickable — the general "interactive
    /// children win over the list container" contract, not just onMouseEvent.
    @Test("A Button inside a List row receives its click")
    func buttonInRowIsClickable() {
        final class Box { var taps = 0 }
        let box = Box()

        let view = List(selection: .constant(String?.none)) {
            ForEach(["row-1", "row-2"], id: \.self) { item in
                HStack(spacing: 1) {
                    Text(item)
                    Button("Go") { box.taps += 1 }
                }
            }
        }
        .frame(height: 6)

        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var env = EnvironmentValues()
        env.mouseEventDispatcher = dispatcher
        env.focusManager = FocusManager()
        let context = RenderContext(
            availableWidth: 30, availableHeight: 8, environment: env, tuiContext: tui)
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        guard let rowY = buffer.lines.firstIndex(where: { $0.stripped.contains("row-1") }),
            let line = buffer.lines[rowY].stripped as String?,
            let range = line.range(of: "Go")
        else {
            Issue.record("row with button not rendered")
            return
        }
        let buttonX = line.distance(from: line.startIndex, to: range.lowerBound)
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: buttonX, y: rowY))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: buttonX, y: rowY))
        #expect(box.taps == 1, "the row's Button gets the click, not the list container")
    }

    /// The list's border is chrome: clicking a border character must not
    /// select the row that happens to share its y — and the scrollbar's
    /// region annexes the border column beside it, so a click there acts on
    /// the bar (the likely intent), not on row selection.
    @Test("Border clicks never select; the right border belongs to the scrollbar")
    func borderClicksAreChrome() {
        var selection: String?
        let items = (1...20).map { "Row-\($0)" }
        let view = List(selection: Binding(get: { selection }, set: { selection = $0 })) {
            ForEach(items, id: \.self) { Text($0) }
        }
        .frame(height: 8)
        .scrollbarVisibility(.visible)

        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var env = EnvironmentValues()
        env.mouseEventDispatcher = dispatcher
        env.focusManager = FocusManager()
        let context = RenderContext(
            availableWidth: 30, availableHeight: 10, environment: env, tuiContext: tui)
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        guard let rowY = buffer.lines.firstIndex(where: { $0.stripped.contains("Row-1") }) else {
            Issue.record("Row-1 not rendered")
            return
        }
        let rightBorderX = buffer.width - 1

        // Left border: consumed, but no selection.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 0, y: rowY))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 0, y: rowY))
        #expect(selection == nil, "a left-border click must not select the adjacent row")

        // Right border: the scrollbar's widened region owns it — still no
        // selection (whatever the bar does with the click).
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: rightBorderX, y: rowY))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: rightBorderX, y: rowY))
        #expect(selection == nil, "a right-border click acts on the scrollbar, not selection")
        let barRegion = buffer.hitTestRegions.first {
            $0.width == 2 && $0.offsetX + $0.width == buffer.width
        }
        #expect(barRegion != nil, "the bar's region annexes the border column: \(buffer.hitTestRegions)")

        // Sanity: an actual content click still selects.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 4, y: rowY))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 4, y: rowY))
        #expect(selection == "Row-1", "content clicks still select")
    }

    @Test("A borderless (.plain) list maps each click to its own row (no off-by-one)")
    func plainListRowHitAlignment() {
        // The .plain style has NO top border row, so content starts at buffer
        // y = 0. The container-handler's y→row translation once hardcoded a
        // 1-row inset (assuming a top border), shifting every click up a row:
        // clicking row 2 selected row 1. This drives a click at each row's
        // actual rendered y and checks the RIGHT item is selected.
        var selection: String?
        let items = ["alpha", "bravo", "charlie"]
        let view = List(selection: Binding(get: { selection }, set: { selection = $0 })) {
            ForEach(items, id: \.self) { Text($0) }
        }
        .listStyle(.plain)
        .frame(height: 5)

        let tui = TUIContext()
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.full)
        dispatcher.beginRenderPass()
        var env = EnvironmentValues()
        env.mouseEventDispatcher = dispatcher
        env.focusManager = FocusManager()
        let context = RenderContext(
            availableWidth: 30, availableHeight: 8, environment: env, tuiContext: tui)
        let buffer = renderToBuffer(view, context: context)
        dispatcher.setRegions(buffer.hitTestRegions)

        for item in items {
            guard let y = buffer.lines.firstIndex(where: { $0.stripped.contains(item) }) else {
                Issue.record("\(item) not rendered")
                continue
            }
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 3, y: y))
            _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 3, y: y))
            #expect(selection == item, "clicking the '\(item)' row (y=\(y)) selects it, not a neighbour")
        }
    }

    @Test("A selected .plain row terminates its background (no rightward bleed)")
    func plainSelectionBackgroundIsBounded() {
        // The selection highlight is a persistent background; without a
        // trailing reset it bled past the borderless list's right edge into
        // whatever was composited beside it. Every rendered row line must end
        // with a reset when it carries a background.
        var selection: String? = "one"
        let view = List(selection: Binding(get: { selection }, set: { selection = $0 })) {
            ForEach(["one", "two"], id: \.self) { Text($0) }
        }
        .listStyle(.plain)
        .frame(height: 4)

        let tui = TUIContext()
        var env = EnvironmentValues()
        env.focusManager = FocusManager()
        env.mouseEventDispatcher = tui.mouseEventDispatcher
        let context = RenderContext(
            availableWidth: 24, availableHeight: 6, environment: env, tuiContext: tui)
        let buffer = renderToBuffer(view, context: context)
        let selectedLine = buffer.lines.first { $0.stripped.contains("one") }
        #expect(selectedLine != nil)
        if let line = selectedLine {
            #expect(
                line.contains("\u{1B}["),  // it IS styled (has the selection bg)
                "the selected row carries a background: \(line.debugDescription)")
            #expect(
                line.hasSuffix(ANSIRenderer.reset),
                "the row's background is terminated at its edge: \(line.debugDescription)")
        }
    }
}
