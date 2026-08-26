//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderPassScopeTests.swift
//
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

// MARK: - Why these tests exist
//
// `RenderLoop.renderContent` may walk the scene tree MORE THAN ONCE inside a
// single `beginRenderPass()`/`endRenderPass()` bracket: a throwaway walk on the
// first frame to discover the app header's height, and a correction re-render on
// any frame where the header's actual height disagrees with the estimate the
// frame was laid out against. Only the last walk's buffer is drawn.
//
// The per-frame registries used to be reset once per PASS, so the discarded
// walk's registrations piled up on top of the drawn walk's. Nothing on either
// side of the loop could see it: `OnChangeModifier` is correct in isolation, and
// so is `KeyEventDispatcher` — the bug lived in how many times the loop ran them.
// These tests drive a whole render pass against a `MockTerminal` so that
// re-introducing it costs a failing test.

/// Counters the probe apps bump, reachable from an `App` — which the protocol
/// requires to be constructible with a bare `init()`, so it cannot carry them.
/// Test-only; the suite is `.serialized` and every test resets it first.
private final class ProbeState: @unchecked Sendable {
    static let shared = ProbeState()

    var onChangeFires = 0
    var keyTaps = 0
    /// Drives the header's height, so a test can make it change between frames.
    var headerLines = 1

    /// `isMeasuring` as seen by each walk of the scene, in order.
    var walkPhases: [Bool] = []
    /// How many walks had begun when `.onAppear` fired, or `nil` if it never did.
    var appearedDuringWalk: Int?

    func reset() {
        onChangeFires = 0
        keyTaps = 0
        headerLines = 1
        walkPhases = []
        appearedDuringWalk = nil
    }
}

/// Registers a declining key handler and an initial `.onChange`, under a header
/// whose height `ProbeState.headerLines` controls.
private struct ProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("content")
                .appHeader { ProbeHeader() }
                .onChange(of: 1, initial: true) { _, _ in
                    ProbeState.shared.onChangeFires += 1
                }
                // Declines the key, like the blessed log-the-key pattern: dispatch
                // then walks EVERY registered handler, so a duplicate registration
                // shows up as a doubled side effect.
                .onKeyPress { _ in
                    ProbeState.shared.keyTaps += 1
                    return false
                }
        }
    }
}

/// Records the phase of every walk, and when `.onAppear` fired relative to them.
private struct PhaseProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                WalkPhaseProbe()
                Text("content")
                    .onAppear {
                        ProbeState.shared.appearedDuringWalk = ProbeState.shared.walkPhases.count
                    }
            }
            .appHeader { ProbeHeader() }
        }
    }
}

/// A leaf that records `context.isMeasuring` each time it is walked. Renderable
/// rather than composed, because the phase is only visible from a `RenderContext`.
private struct WalkPhaseProbe: View, Renderable {
    var body: Never { fatalError("WalkPhaseProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        ProbeState.shared.walkPhases.append(context.isMeasuring)
        return FrameBuffer(lines: [""])
    }
}

private struct ProbeHeader: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<ProbeState.shared.headerLines, id: \.self) { i in
                Text("header \(i)")
            }
        }
    }
}

@MainActor
@Suite("Render-pass scope: one walk's worth of registrations", .serialized)
struct RenderPassScopeTests {

    /// Everything `RenderLoop` needs, assembled the way `AppRunner` does.
    @MainActor
    private final class Harness {
        let terminal = MockTerminal()
        let statusBar: StatusBarState
        let appHeader = AppHeaderState()
        let focusManager = FocusManager()
        let tuiContext = TUIContext()
        let paletteManager: ThemeManager
        let appearanceManager: ThemeManager

        init() {
            let appState = AppState()
            self.statusBar = StatusBarState(appState: appState)
            self.paletteManager = ThemeManager(items: PaletteRegistry.all, renderTrigger: {})
            self.appearanceManager = ThemeManager(items: AppearanceRegistry.all, renderTrigger: {})
        }

        func loop<A: App>(_ app: A) -> RenderLoop<A> {
            RenderLoop(
                app: app,
                terminal: terminal,
                statusBar: statusBar,
                appHeader: appHeader,
                focusManager: focusManager,
                paletteManager: paletteManager,
                appearanceManager: appearanceManager,
                tuiContext: tuiContext)
        }
    }

    /// The first frame always walks the scene twice — once to discover the header
    /// height, once for real. Both walks used to register into the same tables.
    @Test("The first frame registers one walk's worth of handlers and fires onChange once")
    func firstFrameRegistersOnce() {
        ProbeState.shared.reset()
        let harness = Harness()
        let loop = harness.loop(ProbeApp())

        _ = loop.render()

        #expect(
            ProbeState.shared.onChangeFires == 1,
            "the discarded walk must not re-fire the initial action")
        #expect(
            harness.tuiContext.keyEventDispatcher.handlerCount == 1,
            "only the drawn walk's key handler should be registered")

        // A declining handler runs for every registration dispatch walks past, so
        // this is the user-visible half: one keypress, one side effect.
        _ = harness.tuiContext.keyEventDispatcher.dispatch(KeyEvent(key: .character("x")))
        #expect(ProbeState.shared.keyTaps == 1, "one keypress must run a declining handler once")
    }

    /// The second half: a header whose height CHANGES sends a later frame through
    /// the correction re-render, which walks the tree a second time. Frame 1's
    /// double walk is already over, so only a per-walk reset keeps this frame's
    /// registrations single.
    @Test("A header-height correction re-render does not double-register")
    func correctedFrameRegistersOnce() {
        ProbeState.shared.reset()
        let harness = Harness()
        let loop = harness.loop(ProbeApp())

        _ = loop.render()
        let heightAfterFirstFrame = harness.appHeader.height

        // Grow the header. Frame 2 lays out against the previous height and then
        // re-renders once it sees the real one.
        ProbeState.shared.headerLines = 3
        _ = loop.render()

        // Pre-condition, so this test fails loudly rather than silently ceasing to
        // discriminate if the correction branch stops being reached.
        #expect(
            harness.appHeader.height != heightAfterFirstFrame,
            "the header must actually change height, or no correction re-render happens")

        #expect(
            harness.tuiContext.keyEventDispatcher.handlerCount == 1,
            "the corrected frame must not keep the discarded walk's handler")

        let tapsBefore = ProbeState.shared.keyTaps
        _ = harness.tuiContext.keyEventDispatcher.dispatch(KeyEvent(key: .character("x")))
        #expect(ProbeState.shared.keyTaps == tapsBefore + 1, "one keypress, one side effect")
    }

    /// The registration half of the throwaway walk was fixed by resetting the
    /// per-frame registries per WALK. The lifecycle half was not: the walk still
    /// ran with `isMeasuring == false`, so every guard written as
    /// `!context.isMeasuring` — `onAppear`, `.task`, `onChange`, focus and mouse
    /// registration — treated a walk whose buffer is thrown away as a real
    /// render.
    ///
    /// Counting fires cannot catch that: `recordAppear` is idempotent, so
    /// `onAppear` still fires exactly once either way. What differs is *which*
    /// walk it fires in — and that matters because the two walks see different
    /// heights (the throwaway one has not subtracted the header yet), so a tree
    /// that branches on available space can contain a view in the first walk and
    /// not the second. That view would appear, mount a `.task`, and then be told
    /// it disappeared, having never been drawn.
    @Test("The first-frame header measurement is a measure pass")
    func firstFrameMeasurementWalkIsMarkedMeasuring() {
        ProbeState.shared.reset()
        let harness = Harness()
        let loop = harness.loop(PhaseProbeApp())

        _ = loop.render()

        // Deliberately not asserting an exact sequence: two-pass layout means a
        // leaf is walked more than once per walk of the SCENE, and pinning that
        // count would fail on any layout change without a defect. The contract
        // is only about the last one.
        let phases = ProbeState.shared.walkPhases
        #expect(!phases.isEmpty)
        #expect(
            phases.last == false,
            "the drawn walk is a render pass")
        #expect(
            phases.dropLast().allSatisfy { $0 },
            "every walk before the drawn one is a measurement. Saw \(phases)")
        // `appearedDuringWalk` is how many walks had been recorded when the
        // effect ran; the probe is the drawn walk's first child, so a fire in
        // that walk lands after every recording. Anything less means it fired
        // in a walk that was thrown away — it was 2 of 4 before this was fixed.
        #expect(
            ProbeState.shared.appearedDuringWalk == phases.count,
            "onAppear belongs to the drawn walk, not a discarded one")
    }

    /// The same leak on the OTHER multi-walk path — and the half that cannot be
    /// closed the same way.
    ///
    /// Frame 1's extra walk is known to be throwaway *before* it runs, so it can
    /// simply be marked as a measurement. A header-height correction cannot be:
    /// the loop renders at the estimated height, discovers afterwards that the
    /// real height differs, and only then re-renders. Marking the first walk
    /// would suppress effects on every frame where the height turns out
    /// unchanged — which is nearly all of them.
    ///
    /// Closing it needs effects staged per walk and adopted from the last one,
    /// which is upstream's PR #60/#61 and a `defer` here; see
    /// `Documentation/Upstream-review/notes/PR-60.md`. Until then this pins the
    /// gap, and flips to a plain failure the moment it is fixed.
    @Test("KNOWN GAP: a header correction re-render still walks twice as a render")
    func correctionRerenderLeaksEffects() {
        ProbeState.shared.reset()
        let harness = Harness()
        let loop = harness.loop(PhaseProbeApp())

        _ = loop.render()
        let heightAfterFirstFrame = harness.appHeader.height

        ProbeState.shared.headerLines = 3
        ProbeState.shared.walkPhases = []
        _ = loop.render()

        #expect(
            harness.appHeader.height != heightAfterFirstFrame,
            "the header must actually change height, or no correction happens")

        withKnownIssue("effects are not yet staged per walk and adopted from the last") {
            let phases = ProbeState.shared.walkPhases
            #expect(
                phases.dropLast().allSatisfy { $0 },
                "the discarded walk should be a measurement. Saw \(phases)")
        }
    }
}
