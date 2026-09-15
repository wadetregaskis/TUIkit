//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EquatableViewSurfaceTests.swift
//
//  A memoized buffer holds ink already composited against the surface it was
//  painted over — `Color.opacity(_:over:)` blends at render time. Serving that
//  buffer over a DIFFERENT surface shows the old blend, which is the same class
//  of bug `gradientFrame` is in the cache key to prevent: a cached child that
//  moved within a ramp had to re-render, and a cached child now over a different
//  colour has to as well.
//
//  It is reachable because `surfaceBackground` is assigned directly
//  (`TabView` does exactly that), which bypasses `noteAppliedEnvironment` and so
//  leaves nothing else to notice the change.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// Draws the surface it is told it sits on, so a served buffer is visible as
/// the WRONG surface rather than as a colour nobody can compare.
private struct SurfaceReader: View, Renderable {
    var body: Never { fatalError("SurfaceReader renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(lines: ["surface=\(context.environment.enclosingSurface)"])
    }
}

/// Equatable by a tag alone, so the memo hits while the surface moves under it.
private struct TaggedSurfaceReader: View, @preconcurrency Equatable {
    let tag: Int

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.tag == rhs.tag }

    var body: some View { SurfaceReader() }
}

@MainActor
@Suite("A memoized buffer is not served over a different surface")
struct EquatableViewSurfaceTests {
    /// Wide enough that the colour's description is not clipped — at 40 columns
    /// two different colours share their first 40 characters and the test
    /// silently compares nothing.
    private static let width = 200

    private func render(surface: Color, tui: TUIContext) -> [String] {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.surfaceBackground = surface
        let context = RenderContext(
            availableWidth: Self.width, availableHeight: 2, environment: environment,
            tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        let lines = renderToBuffer(
            EquatableView(content: TaggedSurfaceReader(tag: 1)), context: context
        ).lines.map(\.stripped)
        tui.stateStorage.endRenderPass()
        return lines
    }

    private func renderUnmemoized(surface: Color, tui: TUIContext) -> [String] {
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.surfaceBackground = surface
        let context = RenderContext(
            availableWidth: Self.width, availableHeight: 2, environment: environment,
            tuiContext: tui)
        return renderToBuffer(SurfaceReader(), context: context).lines.map(\.stripped)
    }

    @Test("the control: the two surfaces do render differently")
    func surfacesAreDistinguishable() {
        // Without this the real test below passes whenever the probe is broken.
        let tui = TUIContext()
        #expect(
            renderUnmemoized(surface: .ansi(.red), tui: tui)
                != renderUnmemoized(surface: .ansi(.blue), tui: tui))
    }

    @Test("a surface change re-renders a memoized subtree")
    func surfaceChangeInvalidates() {
        let tui = TUIContext()
        let onRed = render(surface: .ansi(.red), tui: tui)
        let onBlue = render(surface: .ansi(.blue), tui: tui)

        #expect(onRed != onBlue, "the buffer painted over red was served over blue")
        #expect(onBlue == renderUnmemoized(surface: .ansi(.blue), tui: tui))
    }

    @Test("an unchanged surface still hits")
    func unchangedSurfaceStillHits() {
        // The fix must not turn every lookup into a miss.
        let tui = TUIContext()
        _ = render(surface: .ansi(.red), tui: tui)
        let before = tui.renderCache.stats.hits
        _ = render(surface: .ansi(.red), tui: tui)
        #expect(tui.renderCache.stats.hits > before)
    }
}
