//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ViewRenderer.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Convenience class for standalone one-off view rendering.
///
/// `ViewRenderer` wraps the free function ``renderToBuffer(_:context:)``
/// with terminal cursor positioning. It is a thin wrapper — the actual
/// rendering dispatch happens in `renderToBuffer`, not here.
///
/// This class is **not** part of the main render pipeline. The main
/// pipeline is:
///
/// ```
/// AppRunner → RenderLoop.render() → renderToBuffer() → FrameDiffWriter → Terminal
/// ```
///
/// `ViewRenderer` is used by the ``renderOnce(_:)`` convenience API
/// for simple CLI tools that don't need a full ``App``. It bypasses
/// `RenderLoop`, `FrameDiffWriter`, and diff-based rendering, but it
/// still has to provide the runtime services the render pass reads
/// (state storage, lifecycle, render cache, …) — so it builds a
/// private snapshot ``TUIContext``.
///
/// ## Snapshot semantics
///
/// A `renderOnce` render is a one-shot **snapshot of the initial
/// frame**. Its lifecycle manager runs with effects disabled, so
/// `onAppear` actions and `.task` work do **not** fire: there is no
/// run loop to observe their results and no teardown pass to balance
/// them, and a snapshot must not mutate shared state as a side effect.
/// The render cache is private to this renderer, so a snapshot never
/// disturbs the shared cache a live app may be using.
@MainActor
final class ViewRenderer {
    /// The terminal to render to.
    ///
    /// Typed as ``TerminalProtocol`` rather than the concrete
    /// ``Terminal`` so tests can inject a capturing mock — the
    /// renderer only needs `getSize()`, `moveCursor(toRow:column:)`,
    /// and `write(_:)`.
    private let terminal: any TerminalProtocol

    /// The private snapshot context supplying runtime services.
    private let context: TUIContext

    /// A focus manager for the snapshot (interactive views read it).
    private let focusManager = FocusManager()

    /// Creates a new ViewRenderer.
    ///
    /// - Parameter terminal: The target terminal (default: new Terminal instance).
    init(terminal: (any TerminalProtocol)? = nil) {
        self.terminal = terminal ?? Terminal()
        self.context = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage(),
            renderCache: RenderCache()
        )
    }
}

// MARK: - Internal API

extension ViewRenderer {
    /// Renders a view to the terminal.
    ///
    /// Queries the terminal size, renders the view into a ``FrameBuffer``,
    /// and writes the result line-by-line to the terminal.
    ///
    /// - Parameters:
    ///   - view: The view to render.
    ///   - row: The starting row (1-based, default: 1).
    ///   - column: The starting column (1-based, default: 1).
    func render<V: View>(_ view: V, atRow row: Int = 1, column: Int = 1) {
        let size = terminal.getSize()

        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: context)
        environment.focusManager = focusManager

        // Initialise per-frame tracking the way the live pipeline does
        // before evaluating a frame, so @State hydration and the render
        // cache behave. No matching end-of-frame pass runs: a snapshot
        // has no removed views to fire `onDisappear`, and the context
        // is discarded afterwards.
        context.stateStorage.beginRenderPass()
        context.lifecycle.beginRenderPass()
        context.renderCache.beginRenderPass()

        let renderContext = RenderContext(
            availableWidth: size.width,
            availableHeight: size.height,
            environment: environment
        )
        let buffer = renderToBuffer(view, context: renderContext)
        flush(buffer, atRow: row, column: column)
    }
}

// MARK: - Private Helpers

extension ViewRenderer {
    /// Flushes a FrameBuffer to the terminal at the specified position.
    fileprivate func flush(_ buffer: FrameBuffer, atRow row: Int, column: Int) {
        for (index, line) in buffer.lines.enumerated() {
            terminal.moveCursor(toRow: row + index, column: column)
            terminal.write(line)
        }
    }
}
