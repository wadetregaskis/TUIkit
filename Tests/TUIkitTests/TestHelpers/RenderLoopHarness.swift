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
    let tuiContext = TUIContext()
    let paletteManager: ThemeManager
    let appearanceManager: ThemeManager

    init() {
        let appState = AppState()
        self.appState = appState
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
