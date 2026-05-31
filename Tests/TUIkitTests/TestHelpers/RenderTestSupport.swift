//  🖥️ TUIKit — Terminal UI Kit for Swift
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

    return RenderContext(
        availableWidth: width,
        availableHeight: height,
        environment: environment,
        tuiContext: TUIContext()
    )
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
///     further environment values.
/// - Returns: A render context using the configured environment.
func makeRenderContext(
    width: Int = 80,
    height: Int = 24,
    configure: (inout EnvironmentValues, TUIContext) -> Void
) -> RenderContext {
    let tuiContext = TUIContext()
    var environment = EnvironmentValues()
    environment.focusManager = FocusManager()
    configure(&environment, tuiContext)

    return RenderContext(
        availableWidth: width,
        availableHeight: height,
        environment: environment,
        tuiContext: tuiContext
    )
}
