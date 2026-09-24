//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoopHarness.swift
//
//  Everything `RenderLoop` needs, assembled the way `AppRunner` does, so a test
//  can drive whole frames against a `MockTerminal`. Shared rather than copied:
//  two suites drive the loop now — the render-pass scope tests and the
//  animation-replay tests — and a second copy of this assembly would be a
//  second thing to keep in step with `AppRunner`'s own.
//
//  Created by Wade Tregaskis
//  License: MIT

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
final class RenderLoopHarness {
    let terminal = MockTerminal()
    /// The same instance the status bar was built around, so a test can post
    /// the signals the run loop consumes (`setNeedsAnimationTick`, and so on).
    let appState: AppState
    let statusBar: StatusBarState
    let appHeader = AppHeaderState()
    let focusManager = FocusManager()
    let tuiContext: TUIContext
    let paletteManager: ThemeManager
    let appearanceManager: ThemeManager

    /// What every loop built here has published about the terminal's colours,
    /// in order.
    ///
    /// Kept here rather than assigned to `TerminalColors.current`, which every
    /// suite in the process reads: a colour answer one wiring test fed its loop
    /// stayed the terminal's background, and a later suite's translucent ground
    /// came out blended over it.
    var publishedColors: [TerminalColors] { colourRecord.published }

    /// A class so the loop's closure and this harness share one record.
    private final class ColourRecord {
        var published: [TerminalColors] = []
    }
    private let colourRecord = ColourRecord()

    /// - Parameter tuiContext: The context the loop renders with. A test that
    ///   drives an `AppRunner` seam — a terminal focus report, say — passes the
    ///   runner's own, so what the seam changes is what the loop draws.
    init(tuiContext: TUIContext = TUIContext()) {
        self.tuiContext = tuiContext
        let appState = AppState()
        self.appState = appState
        self.statusBar = StatusBarState(appState: appState)
        self.paletteManager = ThemeManager(items: PaletteRegistry.all, renderTrigger: {})
        self.appearanceManager = ThemeManager(items: AppearanceRegistry.all, renderTrigger: {})
    }

    /// A loop over this harness's terminal.
    ///
    /// `isTmux` is the seam `Terminal.askColors(isTmux:)` already uses:
    /// `TerminalHost.isTmux` is read from the environment once per process, so a
    /// test that needs the tmux branch has to say so rather than set it.
    ///
    /// What the loop publishes about the terminal's colours goes to
    /// ``publishedColors``.
    func loop<A: App>(_ app: A, isTmux: Bool = false) -> RenderLoop<A> {
        RenderLoop(
            app: app,
            terminal: terminal,
            statusBar: statusBar,
            appHeader: appHeader,
            focusManager: focusManager,
            paletteManager: paletteManager,
            appearanceManager: appearanceManager,
            tuiContext: tuiContext,
            isTmux: isTmux,
            publishTerminalColors: { [colourRecord] in colourRecord.published.append($0) })
    }
}
