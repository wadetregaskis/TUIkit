//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HeadlessInputChannels.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Headless Input Channels

/// The per-walk input registries a renderer without a `RenderLoop` wires into
/// its environment: a key event dispatcher, a keyboard-shortcut registry, a
/// status bar and a mouse dispatcher, emptied before every walk the way the
/// render loop empties them.
///
/// For the `Stress` bench, which renders headless and cannot see these types.
/// Without them a bench renders a tree whose registrations all go nowhere:
/// `onKeyPress` traps on its dispatcher, and a `Button` with
/// `.keyboardShortcut` neither registers nor declares, so the bench measured
/// cheaper frames than the app draws and could not see a memo that keeps a
/// subtree's registrations alive.
///
/// The mouse is one of those registries, not a separate kind of thing: a
/// control with a dispatcher in the environment registers a hit-test handler,
/// asks for the features it needs and emits a region into its buffer, and all
/// three are work an app pays on every frame. Without one the bench measured
/// controls with their pointer half removed.
///
/// `package`, not public: it is harness plumbing, not API.
package final class HeadlessInputChannels {
    private let keyEventDispatcher = KeyEventDispatcher()
    private let keyboardShortcuts = KeyboardShortcutRegistry()
    private let statusBar = StatusBarState()
    private let mouseEventDispatcher = MouseEventDispatcher()

    /// Creates four empty channels.
    package init() {}

    /// Wires the channels into `environment`.
    package func install(into environment: inout EnvironmentValues) {
        environment.keyEventDispatcher = keyEventDispatcher
        environment.keyboardShortcutRegistry = keyboardShortcuts
        environment.statusBar = statusBar
        environment.mouseEventDispatcher = mouseEventDispatcher
    }

    /// Empties what the previous walk registered, as `RenderLoop` does before
    /// each walk of the scene.
    package func beginWalk() {
        keyEventDispatcher.clearHandlers()
        keyboardShortcuts.beginRenderPass()
        statusBar.beginSceneRender()
        mouseEventDispatcher.beginRenderPass()
    }

    /// How many key handlers the last walk left registered.
    package var keyHandlerCount: Int { keyEventDispatcher.handlerCount }

    /// How many mouse handlers the last walk left registered.
    package var mouseHandlerCount: Int { mouseEventDispatcher.handlerCount }
}
