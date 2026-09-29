//  🖥️ TUIkit — Terminal UI Kit for Swift
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
///
/// What a snapshot does NOT skip is the root composite. `.offset`,
/// `.position`, `.popover`, `.sheet` and `.alert` leave their drawing in
/// `overlays` rather than in the lines, and `.opacity` leaves a blend still
/// to perform in `opacityRegions`; `flush` walks only `lines`, so both are
/// resolved first, by the same
/// ``FrameBuffer/compositingOverlays(maxWidth:maxHeight:palette:)`` the live
/// pipeline runs at the screen root. Without it a displaced view drew nothing
/// at all and a faded one drew at full strength. The palette that resolves
/// the fade is this renderer's own default: a snapshot has no scene, so there
/// is no `.palette(_:)` scene override to hoist.
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

    /// The host's cursor-advance model.
    ///
    /// This path skips the diff, the reuse cache and the whole frame pipeline —
    /// it draws one buffer once — but it does not get to skip THIS. A terminal
    /// whose cursor advance disagrees with a glyph's painted width disagrees
    /// however the bytes were produced, so a snapshot containing `⚙️` on
    /// Terminal.app puts the rest of its line one cell to the left without it.
    /// See ``FrameDiffWriter/compensatingCursorAdvance(_:)``
    /// and `Documentation/Terminal-compatibility.md`.
    private let writer: FrameDiffWriter

    /// Creates a new ViewRenderer.
    ///
    /// - Parameters:
    ///   - terminal: The target terminal (default: new Terminal instance).
    ///   - writer: The advance model to emit through (default: the detected
    ///     host). Injectable for the same reason `terminal` is: `TerminalHost`
    ///     answers once, from the process environment, so a test cannot ask it
    ///     what a different terminal would receive.
    init(terminal: (any TerminalProtocol)? = nil, writer: FrameDiffWriter = FrameDiffWriter()) {
        self.terminal = terminal ?? Terminal()
        self.writer = writer
        self.context = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage(),
            renderCache: RenderCache(valueHashPlans: .tuikit())
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
        // One wall-clock date for the snapshot's measure and render alike, as
        // the loop stamps one per frame: a timeline measured for one entry and
        // drawn for the next is laid out for the wrong text.
        context.renderCache.frameDate = FrameClock.nowDate

        let renderContext = RenderContext(
            availableWidth: size.width,
            availableHeight: size.height,
            environment: environment
        )
        let buffer = renderToBuffer(view, context: renderContext)
        // Any image the view drew has to reach the terminal before the cells
        // that name it — the same ordering the run loop keeps at `beginFrame`,
        // and for the same reason: a placeholder pointing at an image the
        // terminal has not been given draws nothing at all. This context is
        // discarded afterwards, so the images it transmitted are never deleted;
        // a one-off render is a one-off, and there is no lifecycle here to hang
        // a release on.
        let graphics = context.terminalImageStore.takePending()
        if !graphics.isEmpty { terminal.write(graphics) }
        // The root composite, before the write. `.offset`/`.position`/
        // `.popover`/`.alert` put their drawing in `buffer.overlays` and
        // `.opacity` leaves a blend still to perform in `buffer.opacityRegions`,
        // and `flush` walks neither: a snapshot of `Text("A").offset(x: 2)`
        // wrote one empty row and no "A" at all, and one of
        // `Text("x").opacity(0.3)` wrote the unfaded cells. This is the call
        // `RenderLoop` makes at the screen root (`compositeOverlays`), and its
        // first act is that root's opacity resolve — so ONE call covers both
        // halves and leaves a second nothing to do: resolution CLEARS the
        // regions, so a separate `resolvingOpacity` would not double-fade, it
        // would simply be dead. (The live loop calls it twice for that reason.)
        //
        // Unconditional, unlike the live loop's `!overlays.isEmpty` guard,
        // because the opacity half has to run when there are no layers at all.
        // Free when there is neither payload: the opacity pass returns `self`
        // on an empty region list and the layer queue never iterates, so the
        // buffer comes back byte-identical.
        let composited = buffer.compositingOverlays(maxWidth: size.width, maxHeight: size.height, palette: environment.palette)
        flush(composited, atRow: row, column: column)
    }
}

// MARK: - Private Helpers

extension ViewRenderer {
    /// Flushes a FrameBuffer to the terminal at the specified position.
    fileprivate func flush(_ buffer: FrameBuffer, atRow row: Int, column: Int) {
        for (index, line) in buffer.lines.enumerated() {
            terminal.moveCursor(toRow: row + index, column: column)
            // Through the SAME two treatments the live writer's `buildLine`
            // applies at its write boundary: the row sanitiser (a tab or a
            // newline in user data would otherwise move the cursor here, as it
            // cannot in an `App`) and the host's cursor-advance compensation.
            // This is a second write boundary, and it used to skip the first.
            terminal.write(writer.compensatingCursorAdvance(line.sanitizedForTerminalRow()))
            // Styled bytes this writer did not plan, so its belief about what
            // the terminal is wearing no longer holds — see
            // ``FrameDiffWriter/terminalStyle``.
            writer.forgetTerminalStyling()
        }
    }
}
