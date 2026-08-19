//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PublicAnimationAPITests.swift
//
//  Animating a view of your own must be possible from OUTSIDE the framework —
//  otherwise "an app can be as efficient as the built-ins" is a claim about
//  code nobody else can write. Everything below is the recipe an app follows,
//  and it is checked here the only way that means anything: this file imports
//  TUIkit WITHOUT `@testable`, so it sees exactly the public surface an app
//  sees. Reach for one internal symbol and the target stops compiling.
//
//  See `Documentation/Animating your own view efficiently.md` and the
//  `AnimatingYourOwnView` article.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit

// MARK: - The recipe

/// The inner half: a `Renderable` that owns a buffer and puts runs on it.
///
/// Split in two because a view assembled from other views has no buffer of its
/// own — the outer view reads the environment, the inner one draws.
private struct PublicProbeIndicator: View, Renderable {
    let cycle: SelectionEmphasisCycle
    let dim: Color
    let bright: Color

    var body: Never { fatalError("renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(
            lines: ["●".styled(foreground: cycle.colorNow(dim: dim, bright: bright))])
        if let run = cycle.run("●", dim: dim, bright: bright, offsetX: 0, offsetY: 0) {
            buffer.animatedCells = [run]
        }
        return buffer
    }
}

/// The composed half: no buffer of its own, so it declares its runs instead.
private struct PublicProbeComposed: View {
    let cycle: SelectionEmphasisCycle
    let dim: Color
    let bright: Color

    var body: some View {
        HStack(spacing: 0) {
            Text("[")
            Text("●").foregroundStyle(cycle.colorNow(dim: dim, bright: bright))
            Text("]")
        }
        .animatedCells(
            [cycle.run("●", dim: dim, bright: bright, offsetX: 1, offsetY: 0)].compactMap { $0 })
    }
}

/// The outer half of both: reads the focus state and the shared clock.
private struct PublicProbeControl<Body: View>: View {
    let build: (SelectionEmphasisCycle, Color, Color) -> Body

    @Environment(\.isFocused) private var isFocused
    @Environment(\.selectionEmphasis) private var emphasis
    @Environment(\.palette) private var palette

    var body: some View {
        build(emphasis.cycle(isFocused), palette.border, palette.accent)
    }
}

@MainActor
@Suite("Public animation API")
struct PublicAnimationAPITests {

    /// A focused control, rendered the way an app's own would be.
    private func focused<Body: View>(
        @ViewBuilder _ build: @escaping (SelectionEmphasisCycle, Color, Color) -> Body
    ) -> FrameBuffer {
        // `.focusable()` is what makes an app's own view a focus stop, and the
        // first stop registered with a fresh manager takes the focus.
        renderToBuffer(
            PublicProbeControl(build: build).focusable(),
            context: makeRenderContext(width: 20, height: 4))
    }

    @Test("An app's own Renderable can hand the run loop its animated cells")
    func renderableRoute() {
        let buffer = focused { PublicProbeIndicator(cycle: $0, dim: $1, bright: $2) }
        #expect(buffer.animatedCells.count == 1, "no run reached the buffer")
        #expect(buffer.animatedCells[0].isAnimating)
        #expect(buffer.animatedCells[0].clock == .cursor)
    }

    @Test("An app's own COMPOSED view can declare them instead")
    func composedRoute() {
        let buffer = focused { PublicProbeComposed(cycle: $0, dim: $1, bright: $2) }
        #expect(buffer.animatedCells.count == 1, "no run reached the buffer")
        // Declared at offset 1 — between the two brackets, where it was drawn.
        #expect(buffer.animatedCells[0].offsetX == 1)
        // And replaying the current step must change nothing on screen, which is
        // what says the offset describes the cells that were actually drawn.
        let run = buffer.animatedCells[0]
        let replayed = buffer.composited(
            with: FrameBuffer(lines: [run.frame(at: 0)]), at: (x: run.offsetX, y: run.offsetY))
        #expect(replayed.lines.map(\.stripped) == buffer.lines.map(\.stripped))
    }

    @Test("An unfocused view of an app's own animates nothing")
    func unfocusedIsStill() {
        // No `.focusable()`, so nothing is focused and the cycle is still.
        let buffer = renderToBuffer(
            PublicProbeControl { PublicProbeIndicator(cycle: $0, dim: $1, bright: $2) },
            context: makeRenderContext(width: 20, height: 4))
        #expect(buffer.animatedCells.isEmpty)
    }

    @Test("A styled string is self-contained")
    func styledStringResets() {
        // A frame handed to the run loop is spliced in without whatever escape
        // preceded it, so a cell that leans on its neighbour's styling draws
        // wrong the moment it is replayed.
        let styled = "●".styled(foreground: .red, background: .blue, bold: true)
        #expect(styled.stripped == "●")
        #expect(styled.hasSuffix("\u{1B}[0m"), "not terminated: \(styled.debugDescription)")
    }
}
