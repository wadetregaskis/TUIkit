//  🖥️ TUIKit — Terminal UI Kit for Swift
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
/// One transition is real here, and it is the one worth knowing about:
/// **suspend**. <kbd>Ctrl</kbd>-<kbd>Z</kbd> (or an external `SIGTSTP`) stops
/// the process and hands the terminal back to the shell; `fg` brings it back,
/// by which time the working directory, the files, or the world may have
/// changed underneath it. The phase goes ``background`` on the way down and
/// ``active`` on the way back up, with a frame rendered at each so an
/// `onChange` observer actually sees both.
///
/// ``inactive`` — SwiftUI's "on screen but not receiving events" — is never
/// reported. Detecting it needs the terminal's focus-reporting mode
/// (`CSI ?1004h`), which TUIkit does not enable; a value that could only ever
/// be guessed at is worse than one that never appears. The case exists so the
/// `switch` you would write against SwiftUI still compiles.
public enum ScenePhase: Comparable, Hashable, Sendable {
    /// The scene is not visible: for a terminal app, suspended.
    case background

    /// The scene is visible but not receiving events. Never reported — see
    /// the type's discussion.
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
    public var scenePhase: ScenePhase {
        get { self[ScenePhaseKey.self] }
        set { self[ScenePhaseKey.self] = newValue }
    }
}
