//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// `context.stateStorage`, etc.
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
        env.terminalImageStore = tuiContext.terminalImageStore
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
    ///
    /// ## Every channel a key can arrive on, not just the focus ring
    ///
    /// The focus manager and the key dispatcher were isolated from the start,
    /// which covers Tab and `onKeyPress`. They are not the only ways a page can
    /// be driven: `InputHandler` runs the status bar as **layer 1** and the
    /// keyboard-shortcut registry as **layer 3.5**, both *ahead* of the check
    /// that suppresses app chrome behind a modal. A page rendered as a backdrop
    /// registered into the real ones, so with a dialog up:
    ///
    /// - `Button("Delete") { … }.keyboardShortcut("d")` still deleted on `d`;
    /// - `.statusBarItems { StatusBarItem(shortcut: "n", …) }` still fired on
    ///   `n`, and still advertised itself on the bar while doing it.
    ///
    /// Both now go to throwaways. The modal itself renders from the ORIGINAL
    /// context, so its own shortcuts and its ESC item publish exactly as
    /// before; what stops is the page underneath declaring things that outlive
    /// its own inertness.
    func isolatedForBackground() -> Self {
        var copy = withThrowawayKeyChannels()
        let backdropFocus = FocusManager()
        backdropFocus.suppressesAutoFocus = true
        backdropFocus.isBackdrop = true
        copy.environment.focusManager = backdropFocus
        return copy
    }

    /// A copy whose key dispatcher, keyboard-shortcut registry and status bar
    /// are throwaways — every channel a key can arrive on except the focus
    /// ring itself.
    ///
    /// Not the focus manager, because the two renders that need this want
    /// different ones: the backdrop above marks its manager `isBackdrop`, and
    /// the windowed stack's ring-continuation probe
    /// (`_VStackCore.focusRingContinuations`) wants a fresh one per row it
    /// asks, which must not pass for a backdrop.
    ///
    /// One list for both, because two had drifted. The probe kept its own —
    /// focus manager and mouse dispatcher, nothing else — and a probe is a
    /// render, not a measure: every row it walked past on the way to the next
    /// focus stop registered its `onKeyPress` handler, its `.keyboardShortcut`
    /// (a `.hidden()` holder registers no focusable, so the walk does not stop
    /// at it) and its `.statusBarItems` into the live services, for rows the
    /// frame never drew. A channel added here reaches both.
    func withThrowawayKeyChannels() -> Self {
        var copy = self
        copy.environment.keyEventDispatcher = KeyEventDispatcher()
        copy.environment.keyboardShortcutRegistry = KeyboardShortcutRegistry()
        copy.environment.statusBar = StatusBarState()
        return copy
    }

    /// A copy whose two channels for asking that the loop keep rendering are
    /// throwaways — for a render whose buffer is discarded ENTIRELY.
    ///
    /// Both channels are pass-wide, and a pass does not know which of its
    /// renders reached the screen. The volatile-read tracker's `reads` is read
    /// once at the end of the frame as `RenderActivity.usesPulse`, and the
    /// animation scheduler drops a token that stops re-declaring — an
    /// excellent rule that measures the wrong thing, because a view nobody can
    /// see re-declares exactly as a visible one does. So a discarded render
    /// went on costing a full render twenty times a second while showing
    /// nobody anything. See `Documentation/Opacity as composition.md` §92.
    ///
    /// The third demand channel needs nothing here: an `AnimatedCellRun` rides
    /// on the buffer, and `RenderLoop.recordActivity` builds `animatedClocks`
    /// from the runs that reached the FINAL buffer, so a run discarded with its
    /// buffer already keeps no clock alive. This is that rule, applied by hand
    /// to the two channels that could not carry themselves.
    ///
    /// ## Why this is not folded into `isolatedForBackground()`
    ///
    /// Because most of that method's callers are VISIBLE. A modal's or an
    /// alert's page, a `.dimmed()` subtree and a context menu's backdrop are
    /// all isolated from input and then DRAWN — dimmed, but on screen and
    /// animating. Blinding them here would freeze the page behind a dialog.
    /// Isolation is about what a render may REACH; this is about whether its
    /// picture survives, and only the caller knows that.
    ///
    /// A render that keeps PART of its output — `.hidden()`, which keeps
    /// screen-level overlays so a `.sheet` presented from inside still
    /// presents (as it does in SwiftUI), or `ScrollView`'s window, which keeps
    /// the rows inside the viewport — must NOT use this: the surviving part
    /// renders in the same pass, so its demand would be denied along with the
    /// rest. Those need a demand that rides on the buffer; §92 prices it.
    func withThrowawayFrameDemand() -> Self {
        var copy = self
        copy.environment.volatileReadTracker = VolatileReadTracker()
        copy.environment.animationScheduler = AnimationScheduler()
        return copy
    }
}
