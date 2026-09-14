//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HeadlessKeyChannels.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Headless Key Channels

/// The key channels a renderer without a `RenderLoop` wires into its
/// environment: a key event dispatcher, a keyboard-shortcut registry and a
/// status bar, emptied before every walk the way the render loop empties them.
///
/// For the `Stress` bench, which renders headless and cannot see these types.
/// Without them a bench renders a tree whose registrations all go nowhere:
/// `onKeyPress` traps on its dispatcher, and a `Button` with
/// `.keyboardShortcut` neither registers nor declares, so the bench measured
/// cheaper frames than the app draws and could not see a memo that keeps a
/// subtree's registrations alive.
///
/// `package`, not public: it is harness plumbing, not API.
package final class HeadlessKeyChannels {
    private let keyEventDispatcher = KeyEventDispatcher()
    private let keyboardShortcuts = KeyboardShortcutRegistry()
    private let statusBar = StatusBarState()

    /// Creates three empty channels.
    package init() {}

    /// Wires the three channels into `environment`.
    package func install(into environment: inout EnvironmentValues) {
        environment.keyEventDispatcher = keyEventDispatcher
        environment.keyboardShortcutRegistry = keyboardShortcuts
        environment.statusBar = statusBar
    }

    /// Empties what the previous walk registered, as `RenderLoop` does before
    /// each walk of the scene.
    package func beginWalk() {
        keyEventDispatcher.clearHandlers()
        keyboardShortcuts.beginRenderPass()
        statusBar.beginSceneRender()
    }

    /// How many key handlers the last walk left registered.
    package var keyHandlerCount: Int { keyEventDispatcher.handlerCount }
}
