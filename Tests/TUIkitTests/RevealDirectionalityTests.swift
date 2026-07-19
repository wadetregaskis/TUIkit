//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RevealDirectionalityTests.swift
//
//  The untested halves of reveal-on-focus: the BACKWARD walk (every
//  existing walk test drives focusNext only), and the interaction-
//  generation snap for CONTAINER focus — a focused List consuming arrows
//  while the enclosing ScrollView is wheel-scrolled away must snap back,
//  while wheel scrolling alone (peek mode) must not.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("reveal directionality + container interaction")
struct RevealDirectionalityTests {
    private static let viewport = 6

    @discardableResult
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager, height: Int
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 30, availableHeight: height,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    @Test("Shift+Tab walks upward mid-list, viewport following each step")
    func shiftTabWalksUpward() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<200, id: \.self) { i in Button("row \(i)") {} }
            }
        }
        .frame(height: Self.viewport)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: Self.viewport)
        let id0 = focusManager.registeredFocusIDsInActiveSection().first ?? ""
        let id100 = id0.replacingOccurrences(of: "[0]", with: "[100]")
        focusManager.focus(id: id100)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: Self.viewport)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: Self.viewport)

        // Ten Shift+Tabs: focus steps 99 → 90, one row per press, the
        // focused row visible on EVERY frame.
        for step in 1...10 {
            focusManager.focusPrevious()
            let frame = renderFrame(
                view, tuiContext: tuiContext, focusManager: focusManager, height: Self.viewport)
            let expected = 100 - step
            #expect(
                focusManager.currentFocusedID?.contains("[\(expected)]") == true,
                "step \(step): focus is on row \(expected): \(focusManager.currentFocusedID ?? "nil")")
            #expect(
                frame.contains { $0.contains("row \(expected)") },
                "step \(step): the focused row is visible: \(frame)")
        }
    }

    @Test("A focused List consuming arrows snaps back after a scroll-away peek")
    func containerInteractionSnapsBackFromPeek() {
        // The interactionGeneration half of the reveal, for CONTAINER focus.
        // The peeked state is modelled by writing the handler's offset
        // directly — exactly what wheel scrolling produces (no focus
        // change, no consumed key; the wheel PLUMBING has its own suites).
        // The peek must STICK across frames (no spurious snap), and the
        // focused List consuming an arrow must snap the viewport back so
        // its selection change is never invisible.
        struct Item: Identifiable {
            let id: Int
            var label: String { "item \(id)" }
        }
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                List((0..<5).map(Item.init), selection: Binding<Int?>.constant(nil)) {
                    Text($0.label)
                }
                .frame(height: 7)
                ForEach(0..<30, id: \.self) { i in Text("filler \(i)") }
            }
        }
        .frame(height: 8)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        let settled = renderFrame(
            view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        #expect(settled.contains { $0.contains("item 0") }, "the list starts visible: \(settled)")

        // Peek: scroll the outer ScrollView away. Its handler is the
        // registered focusable (the List holds focus; both register).
        let handler = focusManager.activeSection?.focusables
            .compactMap { $0 as? ScrollViewHandler }.first
        #expect(handler != nil, "the overflowing ScrollView registered its handler")
        handler?.scrollOffset = 20
        let peeked = renderFrame(
            view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        #expect(
            !peeked.contains { $0.contains("item 0") },
            "the peek scrolled the list off-screen and STAYED (no spurious snap): \(peeked)")
        let stillPeeked = renderFrame(
            view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        #expect(
            !stillPeeked.contains { $0.contains("item 0") },
            "peek mode persists across frames: \(stillPeeked)")

        // The focused List consumes .down — the interaction generation
        // bumps and the snap brings it back into view.
        _ = focusManager.dispatchKeyEvent(KeyEvent(key: .down))
        let snapped = renderFrame(
            view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        #expect(
            snapped.contains { $0.contains("item ") },
            "consuming a key snapped the focused list back into view: \(snapped)")
    }

    @Test("With a scrollbar, reveals scroll minimally (no indicator headroom)")
    func scrollbarRevealScrollsMinimally() {
        // A scrollbar supersedes the "N more" text indicators, so a reveal
        // must NOT reserve the indicator's edge row: doing so over-scrolled
        // every reveal by exactly one line (the Forms shift-tab sighting —
        // the focused control landed one row inside the edge instead of on
        // it). Minimal scroll: the revealed control sits ON the viewport
        // edge row in the direction it was revealed from.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<20, id: \.self) { i in
                    Button("b\(i)e") {}.focusID("b\(i)")
                }
            }
        }
        .scrollbarVisibility(.visible)
        .frame(height: 8)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)

        // Reveal downward: b10 must land exactly on the LAST viewport row.
        focusManager.focus(id: "b10")
        let down = renderFrame(
            view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        #expect(down.last?.contains("b10e") == true, "b10 sits on the last row: \(down)")
        #expect(!down.contains { $0.contains("b11e") }, "no over-scroll below b10: \(down)")

        // Reveal upward (the shift-tab direction): b2 must land exactly on
        // the FIRST viewport row.
        focusManager.focus(id: "b2")
        let up = renderFrame(
            view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        #expect(up.first?.contains("b2e") == true, "b2 sits on the first row: \(up)")
        #expect(!up.contains { $0.contains("b1e") }, "no over-scroll above b2: \(up)")
    }
}
