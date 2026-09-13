//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// One live-loop-shaped frame with a persistent focus manager — and, as in
    /// `RenderLoop.beginSceneRender`, with the key handlers, shortcuts and
    /// status bar items starting empty, so what a test dispatches afterwards
    /// is exactly what this frame registered.
    private func renderFrame<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager, windowOffset: Int,
        statusBar: StatusBarState? = nil
    ) {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.statusBar = statusBar
        environment.scrollContentWindow = ScrollContentWindow(
            offset: windowOffset, viewportHeight: Self.viewportHeight)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 600,
            environment: environment, tuiContext: tuiContext)

        tuiContext.keyEventDispatcher.clearHandlers()
        tuiContext.keyboardShortcuts.beginRenderPass()
        statusBar?.beginRenderPass()
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
    }

    /// The probe must not START anything on the rows it walks past.
    ///
    /// `nearestFocusableRow` renders candidate rows against a throwaway
    /// `FocusManager` but the LIVE `StateStorage`, so every probed row resolves
    /// the app's real persisted handler. Reading `currentFocusedID != nil` as
    /// the discriminator meant relying on `register`'s auto-focus — so the
    /// probe called `onFocusReceived()` on rows nobody had focused, and
    /// `TextFieldHandler.onFocusReceived` is `onEditingChanged(true)`. Whole
    /// runs of off-screen fields began editing sessions, every frame.
    ///
    /// `onEditingChanged` is the public spelling of that callback, which makes
    /// it the honest oracle: nothing here reaches inside the focus system.
    @Test("Probing for the next focus stop does not begin editing in the rows it walks")
    func probeDoesNotDisturbTheRowsItWalks() {
        final class Log { var began: [Int] = [] }
        let log = Log()
        let text = Binding.constant("")
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<40, id: \.self) { index in
                TextField("field \(index)", text: text)
                    .onEditingChanged { if $0 { log.began.append(index) } }
            }
        }
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        // Two frames: the first registers and auto-focuses row 0, the second is
        // the steady state in which the probe walks for the ring continuation.
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)

        #expect(
            log.began.allSatisfy { $0 == 0 },
            "rows the probe only counted began editing: \(log.began)")
    }

    /// …nor REGISTER anything on them, on any channel a key can arrive on.
    ///
    /// The probe is a render, not a measure, so every row it asks performs its
    /// render-pass registrations. It used to swap only the focus manager (and
    /// drop the mouse dispatcher), so a row it merely counted on the way to the
    /// next stop — never drawn, never in the sweep — kept a live `onKeyPress`
    /// handler, a `.hidden()` button's `.keyboardShortcut` and its
    /// `.statusBarItems` for the rest of the frame. Rows 10, 20 and 30 of the
    /// run lie past the window (rows 0-5, margin row 6) and short of the stop
    /// at row 40, so only the probe ever renders them.
    @Test("Probing for the next focus stop registers no key channel for the rows it walks")
    func probeRegistersNoKeyChannelForTheRowsItWalks() {
        let log = KeyChannelLog()
        let tuiContext = TUIContext()
        let statusBar = StatusBarState()
        renderSteadyKeyChannelRun(log: log, tuiContext: tuiContext, statusBar: statusBar)

        let handled = tuiContext.keyEventDispatcher.dispatch(KeyEvent(key: .character("d")))
        let shortcutFired = tuiContext.keyboardShortcuts.trigger(for: KeyEvent(key: .enter))
        let barShortcuts = statusBar.currentUserItems.map(\.shortcut)

        #expect(!handled, "an undrawn row's onKeyPress took the key")
        #expect(!shortcutFired, "an undrawn row's hidden button answered Return")
        #expect(log.farRan.isEmpty, "undrawn rows acted on a key: \(log.farRan)")
        #expect(!barShortcuts.contains("f"), "an undrawn row's items reached the bar: \(barShortcuts)")
    }

    /// The rows beside the focus are the ones the probe always asks first, and
    /// the sweep draws them regardless. Registering the probe's render of them
    /// as well put their handlers in the dispatcher twice — so a handler that
    /// looks at a key and declines it (dispatch walks on past a `false`) ran
    /// twice per keypress, in every windowed stack holding the focus.
    @Test("A declining key handler beside the focus runs once per keypress")
    func handlerBesideTheFocusRunsOncePerKeypress() {
        let log = KeyChannelLog()
        let tuiContext = TUIContext()
        renderSteadyKeyChannelRun(log: log, tuiContext: tuiContext)

        _ = tuiContext.keyEventDispatcher.dispatch(KeyEvent(key: .character("j")))

        #expect(log.besideTaps == 1, "one keypress ran row 1's handler \(log.besideTaps) times")
    }

    /// Forty-one one-line rows whose only focus stops are the first and the
    /// last, rendered to the steady state: frame 1 registers and auto-focuses
    /// row 0, frame 2 probes from it across every row to row 40.
    private func renderSteadyKeyChannelRun(
        log: KeyChannelLog, tuiContext: TUIContext, statusBar: StatusBarState? = nil
    ) {
        let focusManager = FocusManager()
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<KeyChannelRow.count, id: \.self) { index in
                KeyChannelRow(index: index, log: log)
            }
        }
        for _ in 0..<2 {
            renderFrame(
                view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0,
                statusBar: statusBar)
        }
        // Without this a green run could be vacuous: no focus, no probe.
        #expect(
            focusManager.currentFocusedID?.contains("[0]") == true,
            "the walk must start from row 0: \(focusManager.currentFocusedID ?? "nil")")
    }

    /// Row 499's focus ID, captured the honest way: while it is on screen.
    /// (Default focus IDs embed the identity path; an app would capture one
    /// via FocusReference or use focus(id:) with an ID it saw while visible.)
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

/// What the rows of the key-channel run in `WindowedFocusReachTests` did with
/// the keys dispatched after it.
private final class KeyChannelLog: @unchecked Sendable {
    /// Runs of row 1's declining handler.
    var besideTaps = 0
    /// Every action a row past the window took.
    var farRan: [String] = []
}

/// One row of the key-channel run: a focus stop at each end, and between them
/// one declaration on each channel a key can arrive on — beside the focus
/// (row 1), and past the window, where only the probe renders (rows 10, 20, 30).
private struct KeyChannelRow: View {
    static let count = 41

    let index: Int
    let log: KeyChannelLog

    var body: some View {
        if index == 0 || index == Self.count - 1 {
            Button("stop \(index)") {}
        } else if index == 1 {
            Text("beside the focus")
                .onKeyPress(keys: [.character("j")]) { _ in
                    log.besideTaps += 1
                    return false
                }
        } else if index == 10 {
            Text("far handler")
                .onKeyPress(keys: [.character("d")]) { _ in
                    log.farRan.append("onKeyPress")
                    return true
                }
        } else if index == 20 {
            // The hidden-button-as-shortcut-holder idiom: `.hidden()` suppresses
            // the focus registration, so this row is no stop and the walk goes
            // straight past it, while the button still registers its shortcut.
            Button("far shortcut") { log.farRan.append("shortcut") }
                .keyboardShortcut(.defaultAction)
                .hidden()
        } else if index == 30 {
            Text("far items").statusBarItems {
                StatusBarItem(shortcut: "f", label: "far")
            }
        } else {
            Text("row \(index)")
        }
    }
}
