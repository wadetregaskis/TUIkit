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
    /// systems — for rendering dimmed background content beneath a modal / alert.
    ///
    /// The background renders only to be shown as an inert, dimmed backdrop, so
    /// it must not disturb the live page. The returned context has a throwaway
    /// `FocusManager`, `KeyEventDispatcher`, **and `StateStorage`**:
    ///
    /// - focus / key isolation stops the background's buttons and handlers from
    ///   competing with the modal's interactive elements;
    /// - **state isolation** stops the background re-render from mutating the
    ///   page's persistent `@State`. (The throwaway focus manager auto-focuses
    ///   the first background element; a `ScrollView` would then snap-scroll to
    ///   it and overwrite the real scroll offset — so dismissing the modal left
    ///   the page scrolled back to the top. With its own storage that write
    ///   lands on the throwaway state and the page's scroll position survives.)
    ///
    /// Lifecycle and preferences are still shared (they are keyed by identity,
    /// not affected by the backdrop, and must not double-fire / be lost).
    func isolatedForBackground() -> Self {
        var copy = self
        copy.environment.focusManager = FocusManager()
        copy.environment.keyEventDispatcher = KeyEventDispatcher()
        copy.environment.stateStorage = StateStorage()
        return copy
    }

    /// Returns a copy whose key-event dispatcher is a throwaway — for rendering
    /// the page *beneath* a root-hosted modal. The page renders normally (real
    /// focus + state, so it stays correct and isn't double-rendered), but its
    /// `onKeyPress` / Menu key handlers register into a discarded dispatcher so
    /// they can't fire while the modal is up. Focus is isolated separately by the
    /// modal's active section; mouse is isolated by the dimmed backdrop dropping
    /// the page's hit-test regions.
    func isolatingKeyDispatcher() -> Self {
        var copy = self
        copy.environment.keyEventDispatcher = KeyEventDispatcher()
        return copy
    }
}
