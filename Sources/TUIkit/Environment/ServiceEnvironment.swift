//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ServiceEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Localization Service

/// EnvironmentKey for the localization service.
private struct LocalizationServiceKey: EnvironmentKey {
    static let defaultValue = LocalizationService.shared
}

// MARK: - Lifecycle Manager

/// EnvironmentKey for view lifecycle tracking (appear/disappear/task).
private struct LifecycleKey: EnvironmentKey {
    static let defaultValue: LifecycleManager? = nil
}

// MARK: - Key Event Dispatcher

/// EnvironmentKey for key event handler registration and dispatch.
private struct KeyEventDispatcherKey: EnvironmentKey {
    static let defaultValue: KeyEventDispatcher? = nil
}

// MARK: - Mouse Event Dispatcher

/// EnvironmentKey for mouse event handler registration and dispatch.
private struct MouseEventDispatcherKey: EnvironmentKey {
    static let defaultValue: MouseEventDispatcher? = nil
}

// MARK: - Synthesised Key Event Dispatch

/// EnvironmentKey for the synthesised-key path: a closure
/// that routes a ``KeyEvent`` through the full
/// ``InputHandler`` 5-layer chain. See ``TUIContext/
/// synthesizeKeyEvent`` for the rationale and consumer.
///
/// The closure is typed `@MainActor` because every caller
/// (``RenderLoop``, ``StatusBar``'s mouse handler) and the
/// only producer (``AppRunner/run()``) all run on the main
/// actor; the annotation also satisfies `Sendable` for the
/// static `defaultValue` storage.
private struct SynthesizeKeyEventKey: EnvironmentKey {
    static let defaultValue: (@MainActor (KeyEvent) -> Void)? = nil
}

// MARK: - Preference Storage

/// EnvironmentKey for preference value collection during rendering.
private struct PreferenceStorageKey: EnvironmentKey {
    static let defaultValue: PreferenceStorage? = nil
}

// MARK: - Pulse Phase

/// EnvironmentKey for the focus indicator breathing animation phase.
private struct PulsePhaseKey: EnvironmentKey {
    static let defaultValue: Double = 0
}

// MARK: - Cursor Timer

/// EnvironmentKey for TextField/SecureField cursor blink animation.
private struct CursorTimerKey: EnvironmentKey {
    // `CursorTimer` is `@MainActor` (hence implicitly `Sendable`), so a `nil`
    // default needs no `nonisolated(unsafe)`.
    static let defaultValue: CursorTimer? = nil
}

// MARK: - Focus Indicator Color

/// EnvironmentKey for the focus indicator color in the current subtree.
private struct FocusIndicatorColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

// MARK: - Active Focus Section

/// EnvironmentKey for the focus section that child views should register in.
private struct ActiveFocusSectionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

// MARK: - EnvironmentValues Extensions

extension EnvironmentValues {

    /// The localization service for retrieving translated strings.
    var localizationService: LocalizationService {
        get { self[LocalizationServiceKey.self] }
        set { self[LocalizationServiceKey.self] = newValue }
    }

    /// The currently active language.
    var currentLanguage: LocalizationService.Language {
        localizationService.currentLanguage
    }

    /// View lifecycle tracking (appear, disappear, task management).
    var lifecycle: LifecycleManager? {
        get { self[LifecycleKey.self] }
        set { self[LifecycleKey.self] = newValue }
    }

    /// Key event handler registration and dispatch.
    var keyEventDispatcher: KeyEventDispatcher? {
        get { self[KeyEventDispatcherKey.self] }
        set { self[KeyEventDispatcherKey.self] = newValue }
    }

    /// Dispatches a synthesised ``KeyEvent`` through the full
    /// ``InputHandler`` 5-layer chain. See
    /// ``TUIContext/synthesizeKeyEvent`` for the rationale.
    var synthesizeKeyEvent: (@MainActor (KeyEvent) -> Void)? {
        get { self[SynthesizeKeyEventKey.self] }
        set { self[SynthesizeKeyEventKey.self] = newValue }
    }

    /// Mouse event handler registration and dispatch.
    var mouseEventDispatcher: MouseEventDispatcher? {
        get { self[MouseEventDispatcherKey.self] }
        set { self[MouseEventDispatcherKey.self] = newValue }
    }

    /// Preference value collection during rendering.
    var preferenceStorage: PreferenceStorage? {
        get { self[PreferenceStorageKey.self] }
        set { self[PreferenceStorageKey.self] = newValue }
    }

    /// The current breathing animation phase (0-1) for the focus indicator.
    var pulsePhase: Double {
        get { self[PulsePhaseKey.self] }
        set { self[PulsePhaseKey.self] = newValue }
    }

    /// The cursor timer for TextField/SecureField animations.
    var cursorTimer: CursorTimer? {
        get { self[CursorTimerKey.self] }
        set { self[CursorTimerKey.self] = newValue }
    }

    /// The focus indicator color for the first border encountered in this subtree.
    var focusIndicatorColor: Color? {
        get { self[FocusIndicatorColorKey.self] }
        set { self[FocusIndicatorColorKey.self] = newValue }
    }

    /// The ID of the focus section that child views should register in.
    var activeFocusSectionID: String? {
        get { self[ActiveFocusSectionKey.self] }
        set { self[ActiveFocusSectionKey.self] = newValue }
    }
}

// MARK: - Runtime Service Wiring

extension EnvironmentValues {
    /// Wires the runtime services that the render pass and view
    /// modifiers read (state storage, lifecycle, the input
    /// dispatchers, render cache, preferences, localization) from a
    /// ``TUIContext`` into this environment.
    ///
    /// Shared by ``RenderLoop`` — the live pipeline — and
    /// ``ViewRenderer`` — one-off snapshot rendering — so the set of
    /// wired services can't drift between the two. It deliberately
    /// does **not** set the app-level managers (status bar, app
    /// header, focus, palette, appearance); callers add those as they
    /// need them.
    mutating func applyRuntimeServices(from context: TUIContext) {
        stateStorage = context.stateStorage
        lifecycle = context.lifecycle
        keyEventDispatcher = context.keyEventDispatcher
        synthesizeKeyEvent = context.synthesizeKeyEvent
        mouseEventDispatcher = context.mouseEventDispatcher
        renderCache = context.renderCache
        preferenceStorage = context.preferences
        localizationService = LocalizationService.shared
    }
}
