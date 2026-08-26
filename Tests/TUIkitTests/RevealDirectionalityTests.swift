//  🖥️ TUIkit — Terminal UI Kit for Swift
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
        // Predates the visibility/style split (#555): these reveal assertions are
        // written against the "N more" lines, which are now a style rather than
        // the default. The one test wanting a bar asks for it on its own view.
        environment.scrollIndicatorStyle = .text
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

    @Test("An off-band focused row's regions never land inside the visible band")
    func offBandGraftDoesNotStealClicks() {
        // The anchored walk (variable heights, > 256 rows) grafts the focused
        // off-band row's hit regions at an ESTIMATED y. With the tall section
        // between the band and the focused row, the running pitch average
        // undershoots and the graft used to land INSIDE the band — where the
        // ScrollView's viewport clip kept it, overlaying a visible row and
        // stealing its clicks.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<300, id: \.self) { i in
                    if i == 0 || i == 203 {
                        Button("b\(i)") {}
                    } else if i >= 200, i < 210 {
                        Text(Array(repeating: "tall \(i)", count: 20).joined(separator: "\n"))
                    } else {
                        Text("row \(i)")
                    }
                }
            }
        }
        .frame(height: 8)

        func renderBuffer() -> FrameBuffer {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            environment.scrollIndicatorStyle = .text
            let context = RenderContext(
                availableWidth: 30, availableHeight: 8,
                environment: environment, tuiContext: tuiContext)
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return buffer
        }
        func regions203(_ buffer: FrameBuffer) -> [HitTestRegion] {
            buffer.hitTestRegions.filter { $0.focusID?.contains("[203]") == true }
        }

        _ = renderBuffer()
        let id0 = focusManager.registeredFocusIDsInActiveSection().first ?? ""
        focusManager.focus(id: id0.replacingOccurrences(of: "[0]", with: "[203]"))
        // Jump the viewport straight from the top into the tall section
        // (peek: the handler offset is what wheel scrolling writes). On the
        // first anchored frames the running pitch average still reflects the
        // 1-line rows above, so the focused row's graft estimate undershoots
        // through the 20-line rows — landing its regions inside the viewport,
        // over a visible row, where they steal its clicks. Sweep the
        // section; wherever the focused row is NOT on screen, none of its
        // regions may sit inside the viewport.
        let handler = focusManager.activeSection?.focusables
            .compactMap { $0 as? ScrollViewHandler }.first
        #expect(handler != nil)
        for offset in stride(from: 180, through: 300, by: 5) {
            handler?.scrollOffset = offset
            let frame = renderBuffer()
            guard !frame.lines.contains(where: { $0.stripped.contains("b203") })
            else { continue }
            // The viewport INTERIOR: the first and last line belong to the
            // "N more" indicators, and a row scrolled exactly under one is
            // edge adjacency, not an estimate landing rows deep in the band.
            let strays = regions203(frame).filter { region in
                region.offsetY < 7 && region.offsetY + region.height > 1
            }
            let placements = strays.map { ($0.offsetY, $0.height) }
            #expect(
                strays.isEmpty,
                "offset \(offset): off-screen row 203's region inside the viewport: \(placements)")
        }
    }

    @Test("A far focus jump is pursued until the row is actually on screen")
    func farFocusJumpConverges() {
        // The snap toward an off-band row scrolls to its grafted region,
        // whose position is an ESTIMATE that can land short — and with focus
        // unchanged, nothing used to re-check: the viewport parked one band
        // away from the row it was sent to (reproducibly, at 'tall 200' with
        // focus on row 203, forever). The reveal now pursues while its own
        // last write is still the offset and the target remains off-band.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<300, id: \.self) { i in
                    if i == 0 || i == 203 {
                        Button("b\(i)") {}
                    } else if i >= 200, i < 210 {
                        Text(Array(repeating: "tall \(i)", count: 20).joined(separator: "\n"))
                    } else {
                        Text("row \(i)")
                    }
                }
            }
        }
        .frame(height: 8)

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
        let id0 = focusManager.registeredFocusIDsInActiveSection().first ?? ""
        focusManager.focus(id: id0.replacingOccurrences(of: "[0]", with: "[203]"))

        var frame: [String] = []
        var framesToConverge = 0
        for step in 1...25 {
            frame = renderFrame(
                view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
            framesToConverge = step
            if frame.contains(where: { $0.contains("b203") }) { break }
        }
        #expect(
            frame.contains { $0.contains("b203") },
            "the reveal parked after \(framesToConverge) frames: \(frame)")

        // And once revealed, a wheel peek away STAYS: the pursuit's memory is
        // its own last write, so any other writer ends it.
        let handler = focusManager.activeSection?.focusables
            .compactMap { $0 as? ScrollViewHandler }.first
        #expect(handler != nil)
        handler?.scrollOffset = max(0, (handler?.scrollOffset ?? 0) - 60)
        for _ in 0..<3 {
            let peeked = renderFrame(
                view, tuiContext: tuiContext, focusManager: focusManager, height: 8)
            #expect(
                !peeked.contains { $0.contains("b203") },
                "the peek must stick — pursuit re-armed and snapped back: \(peeked)")
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
        .scrollIndicators(.visible)
        .scrollIndicatorStyle(.scrollbar)  // this case is about the BAR
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
