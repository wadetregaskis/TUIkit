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
}
