//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HeadlessApp.swift
//
//  An app driven frame by frame with no terminal: the real render loop and the
//  real input chain, over an in-memory terminal, for a harness that plays an
//  interaction script against an app and watches what it draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Headless App

/// An app assembled the way `AppRunner` assembles one — `RenderLoop`, the
/// five-layer ``InputHandler``, the focus manager, the status bar and header,
/// the theme managers — and driven one frame at a time, with no terminal, no
/// signals and no stdin.
///
/// For the `Stress` harness's SESSIONS: an interaction script played against an
/// app, frame after frame, the way a person uses one. A key goes through the
/// chain a keypress goes through, so it reaches the focused control, moves the
/// focus, scrolls the scroll view that owns the key; a frame is the loop's own
/// frame, header and status bar and diff writer included, so what it costs is
/// what a frame costs. The existing `--bench` renders a view with
/// `renderToBuffer`, which has none of that — no focus manager to type into,
/// no chrome, no emission.
///
/// Time is the caller's: ``frame(atNanos:)`` takes the frame's instant, so two
/// instances fed the same script draw the same pictures, carets and spinners
/// included. And a resize is what `SIGWINCH` does in the app — the terminal
/// reports the new size and the diff writer forgets what it drew.
///
/// A change made inside `withAnimation` plays out over the frames that follow
/// it, as it does in the app: each frame is fenced by an ``AnimationScheduler``
/// the way `AppRunner.renderFrame` fences it. Without one a frame cannot
/// animate — `AnimationFrame.canAnimate` is false, because a one-off render
/// would show an animation's first value and never advance — so every
/// animated change, every transition in and out, landed on its end state in
/// one frame, and a harness that exists to watch what an app draws could not
/// see any of them move. Only the fence: the loop's next firing is still the
/// caller's to choose, since time is.
///
/// `package`, not public: harness plumbing, not API.
@MainActor
package final class HeadlessApp<A: App> {
    private let terminal: InMemoryTerminal
    private let renderer: RenderLoop<A>
    private let inputHandler: InputHandler
    private let tuiContext: TUIContext
    private let animationScheduler = AnimationScheduler()

    /// Whether every frame starts from an EMPTY render cache — every memo
    /// missing, every kept size and buffer gone. `@State` survives, as it does
    /// across frames in the app; only what the cache keeps does not. The
    /// oracle a session holds a normal instance against: a cache is right
    /// exactly when a frame drawn through it is the frame drawn without it.
    package var clearsRenderCacheEachFrame = false

    /// Assembles `app` over an in-memory terminal of `width` × `height` cells.
    package init(_ app: A, width: Int, height: Int) {
        let terminal = InMemoryTerminal(width: width, height: height)
        let appState = AppState()
        let statusBar = StatusBarState(appState: appState)
        let focusManager = FocusManager()
        let tuiContext = TUIContext()
        let paletteManager = ThemeManager(items: PaletteRegistry.all, renderTrigger: {})
        let appearanceManager = ThemeManager(items: AppearanceRegistry.all, renderTrigger: {})
        self.terminal = terminal
        self.tuiContext = tuiContext
        self.renderer = RenderLoop(
            app: app, terminal: terminal, statusBar: statusBar, appHeader: AppHeaderState(),
            focusManager: focusManager, paletteManager: paletteManager,
            appearanceManager: appearanceManager, tuiContext: tuiContext, isTmux: false)
        self.inputHandler = InputHandler(
            statusBar: statusBar, keyEventDispatcher: tuiContext.keyEventDispatcher,
            focusManager: focusManager, paletteManager: paletteManager,
            appearanceManager: appearanceManager, keyboardShortcuts: tuiContext.keyboardShortcuts,
            dragAndDropSession: tuiContext.dragAndDropSession,
            tooltipState: tuiContext.tooltipState,
            // A script has no process to quit or suspend.
            onQuit: {}, onSuspend: {})
        // As `AppRunner` wires it, so a click on a status-bar item that only
        // names a key goes through the same chain the key does.
        let inputHandler = self.inputHandler
        tuiContext.synthesizeKeyEvent = { _ = inputHandler.handle($0) }
    }

    /// Renders one frame at `nanos` on the monotonic clock's scale, and at
    /// `date` on the wall clock — the date a `TimelineView` resolves its
    /// schedule against. The wall clock now unless given, since a script that
    /// holds no timeline has no use for one of its own.
    package func frame(atNanos nanos: Int64, date: Date = FrameClock.nowDate) {
        if clearsRenderCacheEachFrame { tuiContext.renderCache.clearAll() }
        animationScheduler.beginFrame()
        renderer.render(animationScheduler: animationScheduler, frameNowNanos: nanos, frameDate: date)
        animationScheduler.endFrame()
    }

    /// Delivers a key through the five-layer chain, as a keypress is.
    /// - Returns: Whether some layer consumed it.
    @discardableResult
    package func send(_ event: KeyEvent) -> Bool {
        inputHandler.handle(event)
    }

    /// Delivers a mouse event to the handlers the last frame registered.
    /// - Returns: Whether a handler consumed it.
    @discardableResult
    package func send(_ event: MouseEvent) -> Bool {
        tuiContext.mouseEventDispatcher.dispatch(event)
    }

    /// Changes the terminal's size, as `SIGWINCH` reports it: the next frame
    /// is laid out at the new size and rewrites every line.
    package func resize(width: Int, height: Int) {
        terminal.size = (width, height)
        renderer.invalidateDiffCache()
    }

    /// The frame on screen: the header's lines, the content's and the status
    /// bar's, as the diff writer last built them for the terminal.
    package var screen: [String] { renderer.diffWriter.shownLines }

    /// How many bytes every frame so far has written to the terminal.
    package var bytesWritten: Int { terminal.bytesWritten }

    /// The app's render cache, for what its counters say about the frames: how
    /// many rows were served and how many drawn, what the memos hit.
    package var renderCache: RenderCache { tuiContext.renderCache }

    /// How many views' parting pictures the app is holding — every view with a
    /// transition that is on screen, and every removal still playing. A removal
    /// that has played out is no longer counted.
    package var departureCount: Int { tuiContext.stateStorage.departures.count }

    /// The soonest instant after `nanos` that anything the last frame declared
    /// — a lattice or a one-shot wake — asks to be drawn at: what the app's run
    /// loop would sleep until. `nil` when nothing asked, and a real loop would
    /// idle. A harness renders whenever it is told to, so a wake nobody
    /// declared shows only here.
    package func nextWake(after nanos: Int64) -> Int64? {
        animationScheduler.nextFiring(after: nanos)
    }
}

// MARK: - In-Memory Terminal

/// A ``TerminalProtocol`` that writes nowhere and counts what it was asked to
/// write: the terminal a ``HeadlessApp`` draws on.
@MainActor
final class InMemoryTerminal: TerminalProtocol {
    var size: (width: Int, height: Int)
    private(set) var bytesWritten = 0

    init(width: Int, height: Int) {
        size = (width, height)
    }

    func getSize() -> (width: Int, height: Int) { size }
    func write(_ string: String) { bytesWritten &+= string.utf8.count }
    func readKeyEvent() -> KeyEvent? { nil }
    func enableRawMode() {}
    func disableRawMode() {}
    func beginFrame() {}
    func endFrame() {}
    // Counted as what a real terminal is sent for it, so the byte total is
    // the emission volume: a frame that repositions more writes more.
    func moveCursor(toRow row: Int, column: Int) {
        write(ANSIRenderer.moveCursor(toRow: row, column: column))
    }
    func hideCursor() {}
    func showCursor() {}
    func enterAlternateScreen() {}
    func exitAlternateScreen() {}
}
