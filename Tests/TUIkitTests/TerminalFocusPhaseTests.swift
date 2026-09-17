//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalFocusPhaseTests.swift
//
//  A terminal's focus report (mode 1004) moves the scene between `.active`
//  and `.inactive`. The seam the run loop calls with each report is pinned
//  here, and so is what an inactive frame costs the loop: progress keeps
//  animating on the content clock, and a focused text field alone leaves the
//  cursor clock nothing to wake for.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("A terminal focus report sets the scene phase", .serialized)
struct TerminalFocusPhaseTests {

    /// The render-request queue these tests drive and assert on: their own, not
    /// `AppState.shared`.
    ///
    /// An app's runner binds to the shared singleton, and must — every `@State`
    /// write, `@Observable` change and animated cell posts there (see
    /// `AppRunner.init`). A TEST reading it is reading a flag any other suite
    /// may set: swift-testing runs suites concurrently inside one process,
    /// sixteen test files touch that singleton, and the render paths beneath
    /// them set it from spawned tasks. `.serialized` does not help — it orders
    /// the tests within this suite and nothing else.
    ///
    /// Both directions were affected, not only the flaky one: a stranger's
    /// `setNeedsRender()` breaks `#expect(!needsRender)` and *satisfies*
    /// `#expect(needsRender)`. swift-testing builds a fresh suite value per
    /// test, so this is one clean queue per test that nothing else can reach,
    /// and the assertions below are exact rather than merely usually right.
    private let appState = AppState()

    private func freshRunner() -> AppRunner<FocusStillApp> {
        // `Terminal.init()` only reserves a buffer, so this touches no TTY.
        AppRunner(app: FocusStillApp(), appState: appState)
    }

    private var timer: CursorTimer { CursorTimer(renderNotifier: appState) }

    /// The loop the seam hands focus-in to, so it can ask the terminal what it
    /// paints now (step 5d — `TerminalColorRequester`). One per test, over its
    /// own `MockTerminal`, so what a test's terminal was asked is that test's.
    private func freshLoop() -> RenderLoop<FocusStillApp> {
        RenderLoopHarness().loop(FocusStillApp())
    }

    // MARK: - The seam

    @Test("Focus out makes the scene inactive and asks for a frame; focus in makes it active")
    func reportsMoveThePhase() {
        let runner = freshRunner()
        let timer = timer
        let loop = freshLoop()

        runner.terminalFocusChanged(isFocused: false, cursorTimer: timer, renderer: loop)
        #expect(runner.tuiContext.scenePhase == .inactive)
        #expect(appState.needsRender, "the inactive look needs a frame")

        appState.didRender()
        runner.terminalFocusChanged(isFocused: true, cursorTimer: timer, renderer: loop)
        #expect(runner.tuiContext.scenePhase == .active)
        #expect(appState.needsRender, "the active look needs a frame")
    }

    @Test("Focus in restarts the focus breath and the caret at their bright start; focus out does not")
    func focusInRestartsTheCursorClock() {
        let runner = freshRunner()
        let timer = timer
        let loop = freshLoop()
        // Whole seconds, so each is on the cursor clock's tick lattice.
        timer.observe(nowNanos: 1_000_000_000)

        runner.terminalFocusChanged(isFocused: false, cursorTimer: timer, renderer: loop)
        timer.observe(nowNanos: 2_000_000_000)
        #expect(timer.elapsed(for: .cursor) == 1, "focus out left the clock running from its old zero")

        runner.terminalFocusChanged(isFocused: true, cursorTimer: timer, renderer: loop)
        timer.observe(nowNanos: 3_000_000_000)
        #expect(timer.elapsed(for: .cursor) == 0)
    }

    @Test("While suspended a report changes nothing", arguments: [false, true])
    func backgroundIgnoresReports(isFocused: Bool) {
        let runner = freshRunner()
        runner.tuiContext.scenePhase = .background

        runner.terminalFocusChanged(isFocused: isFocused, cursorTimer: timer, renderer: freshLoop())
        #expect(runner.tuiContext.scenePhase == .background)
        #expect(!appState.needsRender)
    }

    @Test("A report of the focus the scene already has asks for no frame")
    func duplicateReportsAreQuiet() {
        let runner = freshRunner()
        let timer = timer
        let loop = freshLoop()

        // A terminal may report focus in as reporting is enabled.
        runner.terminalFocusChanged(isFocused: true, cursorTimer: timer, renderer: loop)
        #expect(runner.tuiContext.scenePhase == .active)
        #expect(!appState.needsRender)

        runner.terminalFocusChanged(isFocused: false, cursorTimer: timer, renderer: loop)
        appState.didRender()
        runner.terminalFocusChanged(isFocused: false, cursorTimer: timer, renderer: loop)
        #expect(runner.tuiContext.scenePhase == .inactive)
        #expect(!appState.needsRender)
    }

    // MARK: - What an inactive frame asks of the loop

    /// The second of two frames of `app` in a scene in `phase`: the first
    /// claims the focus, the second is drawn with it.
    private func activity<A: App>(
        of app: A, in phase: ScenePhase, beforeSecondFrame: () async -> Void = {}
    ) async -> RenderActivity {
        let harness = RenderLoopHarness()
        harness.tuiContext.scenePhase = phase
        let loop = harness.loop(app)
        let timer = CursorTimer(renderNotifier: harness.appState)
        timer.beginFrameReadTracking()
        _ = loop.render(cursorTimer: timer)
        await beforeSecondFrame()
        timer.beginFrameReadTracking()
        return loop.render(cursorTimer: timer)
    }

    @Test("Progress keeps animating while the scene is inactive", arguments: ProgressProbe.allCases)
    func progressContinues(probe: ProgressProbe) async {
        let active = await activity(of: ProgressProbeApp(probe: probe), in: .active)
        let inactive = await activity(of: ProgressProbeApp(probe: probe), in: .inactive)
        #expect(inactive.animatedClocks == active.animatedClocks)
        if probe.animates {
            #expect(inactive.animatedClocks.contains(.content))
        }
    }

    @Test("A refresh's indicator keeps spinning while the scene is inactive")
    func refreshIndicatorContinues() async {
        defer { refreshGate.release() }
        func runningRefresh(in phase: ScenePhase) async -> RenderActivity {
            let harness = RenderLoopHarness()
            harness.tuiContext.scenePhase = phase
            let loop = harness.loop(RefreshProbeApp())
            _ = loop.render()
            _ = harness.tuiContext.keyEventDispatcher.dispatch(
                KeyEvent(key: .character("r"), ctrl: true, alt: false, shift: false))
            for _ in 0..<20 { await Task.yield() }
            return loop.render()
        }
        let active = await runningRefresh(in: .active)
        #expect(active.animatedClocks.contains(.content), "the premise: a running refresh spins")
        let inactive = await runningRefresh(in: .inactive)
        #expect(inactive.animatedClocks.contains(.content))
    }

    @Test("A focused text field alone gives an inactive frame nothing to wake for")
    func inactiveTextFieldIsIdle() async {
        let active = await activity(of: FocusedFieldApp(), in: .active)
        #expect(active.animatedClocks.contains(.cursor), "the premise: its caret animates while active")

        let inactive = await activity(of: FocusedFieldApp(), in: .inactive)
        #expect(!inactive.usesCursor)
        #expect(!inactive.usesPulse)
        #expect(inactive.animatedClocks.isEmpty)
    }
}

// MARK: - Probes

/// A scene with nothing animating.
struct FocusStillApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { Text("content") }
    }
}

/// The progress views a scene can show.
enum ProgressProbe: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case spinner, indeterminate, determinate

    var testDescription: String { rawValue }

    /// Whether it animates at all: a determinate bar is a still picture.
    var animates: Bool { self != .determinate }
}

private struct ProgressProbeApp: App {
    var probe: ProgressProbe = .spinner

    init() {}

    init(probe: ProgressProbe) {
        self.probe = probe
    }

    var body: some Scene {
        WindowGroup {
            switch probe {
            case .spinner: Spinner()
            case .indeterminate: ProgressView()
            case .determinate: ProgressView(value: 0.5)
            }
        }
    }
}

/// Holds a refresh open until the test lets it finish.
private final class RefreshGate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false

    var isClosed: Bool { lock.withLock { !open } }
    func release() { lock.withLock { open = true } }
}

private let refreshGate = RefreshGate()

private struct RefreshProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("abcdefghij")
                .refreshable { while refreshGate.isClosed { await Task.yield() } }
        }
    }
}

private struct FocusedFieldApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { TextField("Name", text: .constant("hi")) }
    }
}
