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

    /// Creates a context isolated from the real focus and key-event systems —
    /// for rendering the page *beneath* a root-hosted modal / alert as an inert
    /// backdrop. The returned context has a throwaway `FocusManager` (which
    /// gives focus to nothing) and `KeyEventDispatcher`:
    ///
    /// - **focus isolation** stops the background's controls from registering
    ///   into the live `FocusManager`. Crucially, the modal has already
    ///   `activateSection`'d its own section before the page renders, so a
    ///   background control registering with no explicit section would resolve to
    ///   `activeSectionID` — the *modal's* section — and the first one would
    ///   auto-focus there (see `FocusManager.register`), stealing the focus the
    ///   modal's own controls should receive and leaving the background live to
    ///   hotkeys. A throwaway manager keeps the real one seeing only the modal.
    /// - **no auto-focus** within that throwaway manager either
    ///   (`suppressesAutoFocus`). Without it the backdrop's first control was
    ///   focused, `onFocusReceived` fired, and a `ScrollView`'s scroll-to-reveal
    ///   rewrote the page's scroll position — dismissing the modal left the page
    ///   scrolled back to the top.
    /// - **key isolation** stops the background's `onKeyPress` / Menu key handlers
    ///   from firing while the modal is up.
    ///
    /// **State is deliberately NOT isolated.** A throwaway `StateStorage` used to
    /// stand in for suppressing that reveal, at two costs: the backdrop drew the
    /// page from DEFAULTS (a counter reading 7 while the page held 8), and — since
    /// the real storage never saw those identities marked active — the page's
    /// entire `@State` subtree was pruned by `endRenderPass` on the first
    /// presented frame, so dismissing re-hydrated the page from scratch. Focus
    /// memory and the reveal made the scroll position *look* restored, which is
    /// how it survived earlier rounds of modal fixes. With the auto-focus cause
    /// gone the backdrop can share the real storage: it draws the page as it is,
    /// and the page's state simply stays alive.
    ///
    /// Mouse is isolated separately by the dimmed backdrop dropping the page's
    /// hit-test regions. Lifecycle and preferences stay shared (keyed by identity,
    /// unaffected by the backdrop, and must not double-fire / be lost).
    func isolatedForBackground() -> Self {
        var copy = self
        let backdropFocus = FocusManager()
        backdropFocus.suppressesAutoFocus = true
        backdropFocus.isBackdrop = true
        copy.environment.focusManager = backdropFocus
        copy.environment.keyEventDispatcher = KeyEventDispatcher()
        return copy
    }
}
