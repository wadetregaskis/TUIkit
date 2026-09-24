//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScenePhaseEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - ScenePhase

/// An indication of a scene's operational state. Matches SwiftUI's type of the
/// same name.
///
/// ```swift
/// @Environment(\.scenePhase) private var scenePhase
///
/// var body: some View {
///     ContentView()
///         .onChange(of: scenePhase) { _, phase in
///             if phase == .active { reloadFromDisk() }
///         }
/// }
/// ```
///
/// ## What a terminal can actually tell you
///
/// **Suspend** is always reported. <kbd>Ctrl</kbd>-<kbd>Z</kbd> (or an
/// external `SIGTSTP`) stops the process and hands the terminal back to the
/// shell; `fg` brings it back, by which time the working directory, the files,
/// or the world may have changed underneath it. The phase goes ``background``
/// on the way down and ``active`` on the way back up, with a frame rendered at
/// each so an `onChange` observer actually sees both.
///
/// **Focus** is reported only where the terminal reports it. While an app
/// runs, TUIkit turns on the terminal's focus reporting (DEC private mode 1004,
/// `CSI ?1004h`). The phase goes ``inactive`` when the terminal says its
/// window, tab or pane lost focus, and ``active`` when it says focus came back.
/// Many never say: a terminal without the mode, and tmux without its
/// `focus-events` option set before the client attaches. A report sent the
/// moment reporting is turned on can also be lost among the startup queries.
/// So **do not build behaviour that depends on noticing an inactive window.**
/// Treat ``inactive`` as a hint that arrived, never as one that is guaranteed
/// to.
///
/// It differs from SwiftUI's ``inactive`` in two ways:
/// - SwiftUI says a scene in this phase should pause timers and free any
///   unnecessary resources. An unfocused terminal window is still on screen,
///   so TUIkit keeps progress running: spinners, indeterminate progress bars
///   and a refresh's indicator go on animating.
/// - On macOS, SwiftUI's ``inactive`` is transitional. Here it lasts for as
///   long as the terminal window is unfocused.
///
/// What an inactive scene changes is how it looks, through
/// ``EnvironmentValues/appearsActive``: the focus is parked rather than lost,
/// so focus indicators stay on screen and hold still — a highlighted row in the
/// still tint of an unfocused selection, everything else half-way between the
/// two ends it breathes or blinks between — and a text caret holds still and
/// dims (see <doc:FocusSystem>).
/// To draw a view of your own that way, read `appearsActive` rather than the
/// phase.
public enum ScenePhase: Comparable, Hashable, Sendable {
    /// The scene is not visible: for a terminal app, suspended.
    case background

    /// The scene is visible but not receiving events: the terminal reported
    /// that its window, tab or pane lost focus. Many terminals never report
    /// it — see the type's discussion.
    case inactive

    /// The scene is running and taking input.
    case active
}

// MARK: - Environment key

private struct ScenePhaseKey: EnvironmentKey {
    /// A view rendered outside a running app (a test, a snapshot) is being
    /// looked at, so `.active` is the truthful default.
    static let defaultValue: ScenePhase = .active
}

extension EnvironmentValues {
    /// The current phase of the app's scene.
    ///
    /// Published each frame from the run loop's own state, so it is one source
    /// of truth rather than a value each view guesses at — the same treatment
    /// `\.locale` gets.
    ///
    /// ``ScenePhase/inactive`` arrives only where the terminal reports focus,
    /// so do not build behaviour that depends on noticing it. See
    /// ``ScenePhase`` for what a terminal reports and where TUIkit differs from
    /// SwiftUI, and ``appearsActive`` for the look an inactive scene takes.
    public var scenePhase: ScenePhase {
        get { self[ScenePhaseKey.self] }
        set { self[ScenePhaseKey.self] = newValue }
    }
}

// MARK: - appearsActive

private struct AppearsActiveKey: EnvironmentKey {
    /// A view rendered outside a running app is being looked at, the same
    /// reasoning as `ScenePhaseKey`.
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether views and styles in this environment should prefer an active
    /// appearance over an inactive one. Matches SwiftUI's property of the same
    /// name.
    ///
    /// Published each frame beside ``scenePhase``, as `scenePhase == .active`:
    /// `false` for the frame rendered on the way into a suspend, and whenever
    /// the scene is reported ``ScenePhase/inactive``. See ``ScenePhase`` for
    /// what a terminal can and cannot report, and do not build behaviour that
    /// depends on noticing an inactive window: many terminals never say.
    ///
    /// Settable, as in SwiftUI: `.environment(\.appearsActive, true)` makes a
    /// subtree look active whatever the scene is doing, and `false` makes it
    /// look inactive.
    ///
    /// SwiftUI's `controlActiveState` is not published beside it. SwiftUI
    /// soft-deprecates it on macOS in favour of this property, and the one
    /// distinction it adds, between the key window (`.key`) and an active app's
    /// other windows (`.active`), has no meaning for a single terminal scene.
    public var appearsActive: Bool {
        get { self[AppearsActiveKey.self] }
        set { self[AppearsActiveKey.self] = newValue }
    }
}
