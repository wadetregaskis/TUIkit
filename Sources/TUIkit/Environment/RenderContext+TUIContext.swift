//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderContext+TUIContext.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - TUIContext Integration

extension RenderContext {
    /// Creates a new RenderContext with runtime services from a `TUIContext`.
    ///
    /// Injects every service the `TUIContext` owns into
    /// `EnvironmentValues`, making them accessible via
    /// `context.environment.stateStorage`, etc.
    ///
    /// > Note: Services that live on `RenderLoop` rather than on
    ///   `TUIContext` (the focus manager, palette manager,
    ///   appearance manager, notification service, localization
    ///   service) are NOT set up by this initializer — callers
    ///   that need them must populate them on `environment`
    ///   beforehand. The full production setup lives in
    ///   ``RenderLoop/makeRenderContext``. Tests using this init
    ///   that exercise click handling will want to set
    ///   `environment.focusManager` themselves.
    ///
    /// - Parameters:
    ///   - availableWidth: The available width in characters.
    ///   - availableHeight: The available height in lines.
    ///   - environment: The environment values (defaults to empty).
    ///   - tuiContext: The TUI context whose services are injected into the environment.
    ///   - identity: The view identity path (defaults to root).
    init(
        availableWidth: Int,
        availableHeight: Int,
        environment: EnvironmentValues = EnvironmentValues(),
        tuiContext: TUIContext,
        identity: ViewIdentity = ViewIdentity(path: "")
    ) {
        var env = environment
        env.stateStorage = tuiContext.stateStorage
        env.lifecycle = tuiContext.lifecycle
        env.keyEventDispatcher = tuiContext.keyEventDispatcher
        // Forgetting mouseEventDispatcher here causes any view
        // tested through this init that emits hit-test regions
        // (Button, TextField, .onMouseEvent, etc.) to silently
        // no-op its mouse handling — OnMouseEventModifier skips
        // registration when the dispatcher is nil. That made an
        // entire class of mouse tests vacuous until we noticed.
        env.mouseEventDispatcher = tuiContext.mouseEventDispatcher
        env.renderCache = tuiContext.renderCache
        env.preferenceStorage = tuiContext.preferences
        self.init(
            availableWidth: availableWidth,
            availableHeight: availableHeight,
            environment: env,
            identity: identity
        )
    }

    /// Creates a context isolated from the real focus, key-event, and state
    /// systems — for rendering the page *beneath* a root-hosted modal / alert as
    /// an inert backdrop. The returned context has a throwaway `FocusManager`,
    /// `KeyEventDispatcher`, **and `StateStorage`**:
    ///
    /// - **focus isolation** stops the background's controls from registering
    ///   into the live `FocusManager`. Crucially, the modal has already
    ///   `activateSection`'d its own section before the page renders, so a
    ///   background control registering with no explicit section would resolve to
    ///   `activeSectionID` — the *modal's* section — and the first one would
    ///   auto-focus there (see `FocusManager.register`), stealing the focus the
    ///   modal's own controls should receive and leaving the background live to
    ///   hotkeys. A throwaway manager keeps the real one seeing only the modal.
    /// - **key isolation** stops the background's `onKeyPress` / Menu key handlers
    ///   from firing while the modal is up.
    /// - **state isolation** stops the background re-render from mutating the
    ///   page's persistent `@State`. (The throwaway focus manager auto-focuses the
    ///   first background element; a `ScrollView` would then snap-scroll to it and
    ///   overwrite the real scroll offset — so dismissing the modal left the page
    ///   scrolled back to the top. With its own storage that write lands on the
    ///   throwaway state and the page's scroll position survives.)
    ///
    /// Mouse is isolated separately by the dimmed backdrop dropping the page's
    /// hit-test regions. Lifecycle and preferences stay shared (keyed by identity,
    /// unaffected by the backdrop, and must not double-fire / be lost).
    func isolatedForBackground() -> Self {
        var copy = self
        copy.environment.focusManager = FocusManager()
        copy.environment.keyEventDispatcher = KeyEventDispatcher()
        copy.environment.stateStorage = StateStorage()
        return copy
    }
}
