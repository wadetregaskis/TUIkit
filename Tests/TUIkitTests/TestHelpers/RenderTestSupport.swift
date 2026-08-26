//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderTestSupport.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Shared render-test context

/// Builds a `RenderContext` for rendering a view to a `FrameBuffer` in tests.
///
/// This is the canonical replacement for the `createTestContext` /
/// `testContext` helpers that were duplicated across ~24 test files. It
/// mirrors the most common shape exactly: a fresh `FocusManager` in the
/// environment and a fresh `TUIContext` providing the remaining services.
/// Suites that need extra environment values (e.g. mouse-event dispatch)
/// set them on top of this — see `makeRenderContext(width:height:configure:)`.
///
/// - Parameters:
///   - width: The available width for layout. Defaults to 80.
///   - height: The available height for layout. Defaults to 24.
/// - Returns: A render context with a fresh focus manager and TUI context.
func makeRenderContext(width: Int = 80, height: Int = 24) -> RenderContext {
    var environment = EnvironmentValues()
    environment.focusManager = FocusManager()
    // A status bar of this context's own, wired to its focus manager exactly
    // as `RenderLoop.beginRenderPass` does. Both halves matter: without the
    // instance the bar is absent and anything asserting on it reads nil, and
    // without the focus manager it cannot resolve which section's items are
    // showing. This used to come from a SHARED environment-key default, so
    // tests rendering in parallel registered into one object and read each
    // other's items back — `isolatingRenderCache()` below is the same idea for
    // the render cache.
    let statusBar = StatusBarState()
    statusBar.focusManager = environment.focusManager
    environment.statusBar = statusBar

    return RenderContext(
        availableWidth: width,
        availableHeight: height,
        environment: environment,
        tuiContext: TUIContext()
    ).isolatingRenderCache()
}

/// Builds a *bare* render context: a fresh `TUIContext` with the default
/// environment and **no** focus manager explicitly installed.
///
/// This matches the `testContext` helper used by pure-rendering / modifier
/// suites (background, border, frame, padding, stacks, etc.) that don't
/// exercise focus and deliberately render without an active focus manager —
/// keeping it distinct from ``makeRenderContext(width:height:)`` matters for
/// auto-focusing controls (Slider/Stepper), which would draw a focus
/// indicator if a focus manager were present.
///
/// - Parameters:
///   - width: The available width for layout. Defaults to 40.
///   - height: The available height for layout. Defaults to 24.
/// - Returns: A render context with only a backing TUI context.
func makeBareRenderContext(width: Int = 40, height: Int = 24) -> RenderContext {
    RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
        .isolatingRenderCache()
}

/// Builds a render context (as ``makeRenderContext(width:height:)``) and then
/// lets the caller mutate its `EnvironmentValues` before the context is
/// finalised — for suites that need additional services wired into the
/// environment (state storage, the key/mouse dispatchers, etc.).
///
/// - Parameters:
///   - width: The available width for layout. Defaults to 80.
///   - height: The available height for layout. Defaults to 24.
///   - configure: A closure that receives the `EnvironmentValues` (with the
///     focus manager already set) and the backing `TUIContext`, and may set
///     further environment values. Note `RenderContext(tuiContext:)` then
///     wires the six core services (state storage, lifecycle, dispatchers,
///     render cache, preferences) from the backing `TUIContext`, OVERWRITING
///     any values `configure` set for them — configure the app-level values
///     (focus manager, palette, cursor style, …) here, and reach the core
///     services through `context.environment` afterwards. The returned
///     context also swaps in an isolated render cache, which diverges from
///     `tuiContext.renderCache` (and so from `@State`-driven invalidation);
///     suites that exercise state-change re-render coherence build their
///     context by hand instead, keeping the caches unified.
/// - Returns: A render context using the configured environment.
func makeRenderContext(
    width: Int = 80,
    height: Int = 24,
    configure: (inout EnvironmentValues, TUIContext) -> Void
) -> RenderContext {
    let tuiContext = TUIContext()
    var environment = EnvironmentValues()
    environment.focusManager = FocusManager()
    // …as above. Set BEFORE `configure`, so a caller that installs its own
    // focus manager or status bar still wins.
    let statusBar = StatusBarState()
    environment.statusBar = statusBar
    configure(&environment, tuiContext)
    statusBar.focusManager = environment.focusManager

    return RenderContext(
        availableWidth: width,
        availableHeight: height,
        environment: environment,
        tuiContext: tuiContext
    ).isolatingRenderCache()
}

// MARK: - Render-cache isolation

extension RenderContext {
    /// Returns a copy whose render cache is a fresh, test-local `RenderCache`.
    ///
    /// Each `TUIContext` owns its own cache (there is no process-wide
    /// singleton), so a context built via `RenderContext(tuiContext:)` is
    /// already isolated. This makes that isolation explicit and construction-
    /// independent: however the context was assembled, the test gets a cache no
    /// other suite can touch. Under Swift Testing's parallel execution that
    /// prevents a memoized buffer from one suite satisfying a same-identity
    /// lookup in another (e.g. a Spinner's `▇` frame surfacing in a Text
    /// render), which used to produce rare, confusing cross-suite failures.
    func isolatingRenderCache() -> RenderContext {
        var copy = self
        let cache = RenderCache()
        copy.environment.renderCache = cache
        // `RenderContext` mirrors the env's render cache in a stored field for the
        // hot memoization paths. This mutates the env on an existing context, so
        // the field must be re-set to match or it would serve the old cache.
        copy.renderCache = cache
        return copy
    }
}

// MARK: - Finishing a frame the way the loop does

/// Renders `view` and then resolves what the compositor would resolve — the
/// picture a user would actually see.
///
/// `renderToBuffer` stops one step short of that on purpose: `.opacity` marks
/// its subtree with an ``OpacityRegion`` and the blend happens where what is
/// BEHIND the subtree is known, which is at a composite or at a root. A test
/// that renders a faded view and inspects its lines is standing at neither, so
/// without this it reads the unresolved layer and passes while the screen is
/// something else. That is the "test passed while the app broke" shape, and it
/// is why this helper exists rather than a note telling people to remember.
///
/// The surface is the content area's, which is where a page is drawn. A test
/// about the status bar or the app header wants its own.
@MainActor
func renderToScreen(_ view: some View, context: RenderContext) -> FrameBuffer {
    let palette = context.environment.palette
    return renderToBuffer(view, context: context)
        .resolvingOpacity(surface: palette.background, palette: palette)
}
