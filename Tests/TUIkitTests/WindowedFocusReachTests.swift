//  🖥️ TUIKit — Terminal UI Kit for Swift
//  WindowedFocusReachTests.swift
//
//  Stage 1 acceptance of "Locating things without drawing them" (§1, §5d):
//  every row of a windowed lazy stack is reachable by focus — focus(id:)
//  lands on a row hundreds of rows outside the window (durable pending
//  intent + routed registration), keeps it across subsequent frames, and
//  Tab walks past the window edge row by row.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("windowed focus reach (the 500-button bug)")
struct WindowedFocusReachTests {
    private static let rowCount = 500
    private static let viewportHeight = 6

    private func makeView() -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<Self.rowCount, id: \.self) { i in
                Button("row \(i)") {}
            }
        }
    }

    /// One live-loop-shaped frame with a persistent focus manager.
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager, windowOffset: Int
    ) {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollContentWindow = ScrollContentWindow(
            offset: windowOffset, viewportHeight: Self.viewportHeight)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 600,
            environment: environment, tuiContext: tuiContext)

        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
    }

    /// Row 499's focus ID, captured the honest way: while it is on screen.
    /// (Default focus IDs embed the identity path; an app would capture one
    /// via FocusState or use focus(id:) with an ID it saw while visible.)
    private func captureTailRowID(
        _ view: some View, tuiContext: TUIContext, focusManager: FocusManager
    ) -> String {
        renderFrame(
            view, tuiContext: tuiContext, focusManager: focusManager,
            windowOffset: Self.rowCount - Self.viewportHeight)
        // The bottom-most registered focusable is row 499 (registration is
        // walk order, top to bottom).
        let id = focusManager.registeredFocusIDsInActiveSection().last
        #expect(id != nil, "row 499 must have registered while visible")
        return id ?? ""
    }

    @Test("focus(id:) reaches row 499 while the window shows rows 0-5")
    func focusReachesTheTail() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = makeView()

        let tailID = captureTailRowID(view, tuiContext: tuiContext, focusManager: focusManager)

        // Back to the top; row 499 no longer registers.
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        #expect(focusManager.currentFocusedID != tailID)

        // The jump: focus an id that exists 494 rows outside the window.
        focusManager.focus(id: tailID)
        #expect(focusManager.pendingFocusID == tailID, "unregistered target becomes durable intent")

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        #expect(
            focusManager.currentFocusedID == tailID,
            "the routing render must register and focus row 499")
        #expect(focusManager.pendingFocusID == nil, "the intent resolved")

        // And it STICKS: the focused row keeps registering wherever it is,
        // so the end-of-pass validation must not steal focus back.
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        #expect(focusManager.currentFocusedID == tailID, "focus survives subsequent frames")
    }

    @Test("Tab walks past the window edge, one off-window row per step")
    func tabWalksPastTheWindow() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = makeView()

        // Window at rows 0-5 (+ margin row 6). Focus the bottom visible row
        // by walking from the auto-focused row 0.
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        let ring = focusManager.registeredFocusIDsInActiveSection()
        #expect(ring.count == Self.viewportHeight + 1, "window rows + one margin row register")

        // Walk downward well past the original window; each step re-renders,
        // which re-centres the enumeration margin on the new focused row.
        focusManager.focus(id: ring[0])
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        var previousID = focusManager.currentFocusedID
        for step in 1...12 {
            focusManager.focusNext()
            renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
            let current = focusManager.currentFocusedID
            #expect(current != nil && current != previousID, "step \(step) must advance focus")
            previousID = current
        }

        // Twelve steps from row 0 lands on row 12 — six rows past the window
        // edge, unreachable before this design (the ring held only what the
        // viewport drew).
        let finalRing = focusManager.registeredFocusIDsInActiveSection()
        #expect(finalRing.contains(previousID ?? ""), "the walked-to row is registered")
        #expect(
            focusManager.currentFocusedID == previousID,
            "focus rests stably on the off-window row")
    }

    @Test("Tab walks past a disabled row at the window edge")
    func tabWalksPastDisabledRow() {
        // Rows 8-10 are disabled: a disabled row renders but never registers
        // with the focus system, so the enumeration margin past the focused
        // row must extend BEYOND the disabled run — otherwise the ring ends
        // at row 7, Tab wraps back into the band, and every row after the
        // run is permanently unreachable by keyboard.
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<Self.rowCount, id: \.self) { i in
                Button("row \(i)") {}.disabled((8...10).contains(i))
            }
        }

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        let ring = focusManager.registeredFocusIDsInActiveSection()
        focusManager.focus(id: ring[0])
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)

        // Twelve steps from row 0: rows 1-7, then STRAIGHT OVER the disabled
        // run to rows 11-15. Focus must advance on every step, never repeat,
        // and never land on a disabled row.
        var visited: [String] = [focusManager.currentFocusedID ?? ""]
        for step in 1...12 {
            focusManager.focusNext()
            renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
            let current = focusManager.currentFocusedID ?? "nil"
            #expect(
                !visited.contains(current),
                "step \(step) revisited \(current) — the walk is trapped: \(visited)")
            visited.append(current)
        }
        for id in visited {
            for disabled in 8...10 {
                #expect(!id.contains("[\(disabled)]"), "disabled row \(disabled) took focus: \(id)")
            }
        }
        #expect(
            visited.last?.contains("[15]") == true,
            "12 steps from row 0 over a 3-row disabled run lands on row 15: \(visited)")
    }

    @Test("A bogus focus(id:) expires without stealing focus")
    func bogusIntentExpires() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = makeView()

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        let before = focusManager.currentFocusedID
        #expect(before != nil)

        focusManager.focus(id: "no-such-control")
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)

        #expect(focusManager.pendingFocusID == nil, "an unmatchable intent expires")
        #expect(focusManager.currentFocusedID == before, "focus never moved")
    }
}

@MainActor
@Suite("focus ID subtree matching")
struct FocusIDMatchingTests {
    @Test("Path boundaries are respected")
    func boundaries() {
        // Deeper component: matches.
        #expect(FocusManager.focusID(
            "button-Root/Stack/Row[7]/Button", addressesSubtreeAt: "Root/Stack/Row[7]"))
        // Exact end: matches.
        #expect(FocusManager.focusID(
            "button-Root/Stack/Row[7]", addressesSubtreeAt: "Root/Stack/Row[7]"))
        // A keyed sibling must not match its unkeyed prefix.
        #expect(!FocusManager.focusID(
            "button-Root/Stack/Row[70]/Button", addressesSubtreeAt: "Root/Stack/Row[7]"))
        // Index boundaries: .7 is not .70.
        #expect(!FocusManager.focusID(
            "button-Root/Stack/Row.70/Button", addressesSubtreeAt: "Root/Stack/Row.7"))
        // Branch continuation counts as inside the subtree.
        #expect(FocusManager.focusID(
            "toggle-Root/Row.3#true/Toggle", addressesSubtreeAt: "Root/Row.3"))
        // Explicit (path-free) IDs never match.
        #expect(!FocusManager.focusID("save-button", addressesSubtreeAt: "Root/Stack/Row[7]"))
    }
}
