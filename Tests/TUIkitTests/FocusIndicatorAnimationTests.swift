//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FocusIndicatorAnimationTests.swift
//
//  Every control that breathes while focused is being converted from "read the
//  clock and re-render the screen" to "hand the run loop a finished cycle" (see
//  ``AnimatedCellRun``). Converting one wrong does not look like a bug — it
//  looks like a WIN, because the page's CPU drops to nothing. It has simply
//  stopped animating. That happened once already (47aa5420).
//
//  So each converted producer is pinned here on the same three points:
//
//  1. focused ⇒ it leaves an animating run,
//  2. unfocused / disabled ⇒ it leaves none (a still cap replayed on a clock is
//     bytes emitted for no change), and
//  3. replaying the CURRENT step is a no-op — which is what proves the run's
//     offset, width and frames actually describe the cells that were drawn. A
//     run in the wrong place is worse than no run at all: it repaints, forever,
//     over whatever is really there.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Focus indicator animation")
struct FocusIndicatorAnimationTests {

    // MARK: - Shared assertions

    /// Renders `view` against a context whose fresh `FocusManager` auto-focuses
    /// the first focusable — i.e. the control under test.
    private func focused(_ view: some View, width: Int = 40) -> FrameBuffer {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 8))
    }

    /// Asserts the run describes the cells that were actually drawn.
    ///
    /// Splicing a run's *current* frame back over the buffer is precisely what
    /// the run loop does on a tick. At the step the view rendered at, that must
    /// change nothing — so any disagreement about where the run sits, or how
    /// wide it is, shows up here as shifted or clobbered glyphs.
    private func expectReplayIsIdentity(
        _ buffer: FrameBuffer, at step: Int = 0,
        _ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let before = buffer.lines.map(\.stripped)
        for run in buffer.animatedCells {
            let replayed = buffer.composited(
                with: FrameBuffer(lines: [run.frame(at: step)]),
                at: (x: run.offsetX, y: run.offsetY))
            #expect(
                replayed.lines.map(\.stripped) == before, comment ?? "run \(run) moved the cells",
                sourceLocation: sourceLocation)
        }
    }

    /// The full contract for a control that should be animating.
    private func expectAnimates(
        _ buffer: FrameBuffer, runs expected: Int,
        _ what: Comment, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            buffer.animatedCells.count == expected, "\(what): wrong number of runs",
            sourceLocation: sourceLocation)
        #expect(
            buffer.animatedCells.allSatisfy { $0.isAnimating }, "\(what): a run is a still picture",
            sourceLocation: sourceLocation)
        expectReplayIsIdentity(buffer, "\(what): the run does not match the drawn cells")
    }

    // MARK: - Button

    @Test("A focused bracketed button hands over both caps")
    func bracketedButtonCaps() {
        let buffer = focused(Button("Save") {})
        expectAnimates(buffer, runs: 2, "bracketed button")

        // The caps are the ends of the control and nothing between them.
        let width = buffer.lines[0].strippedLength
        #expect(buffer.animatedCells.map(\.offsetX).sorted() == [0, width - 1])
        #expect(buffer.animatedCells.allSatisfy { $0.width == 1 })
    }

    @Test("A focused plain button hands over its indicator prefix")
    func plainButtonPrefix() {
        let buffer = focused(Button("Save") {}.buttonStyle(.plain))
        expectAnimates(buffer, runs: 1, "plain button")
        #expect(buffer.animatedCells[0].offsetX == 0)
        #expect(buffer.animatedCells[0].width == BorderRenderer.focusIndicatorWidth)
    }

    @Test("A focused button with a view label hands over its caps too")
    func viewLabelButtonCaps() {
        // The `@ViewBuilder` path composes an HStack rather than assembling a
        // string, so it arrives at its geometry differently and is pinned
        // separately.
        let buffer = focused(Button {} label: { Text("Save") })
        expectAnimates(buffer, runs: 2, "view-label button")
        let width = buffer.lines[0].strippedLength
        #expect(buffer.animatedCells.map(\.offsetX).sorted() == [0, width - 1])
    }

    @Test("An unfocused button animates nothing")
    func unfocusedButtonIsStill() {
        // A sentinel takes the focus first, so the button renders unfocused.
        let context = makeRenderContext(width: 40, height: 8)
        context.environment.focusManager!.register(FocusSentinel())
        let buffer = renderToBuffer(Button("Save") {}, context: context)
        #expect(buffer.animatedCells.isEmpty, "an unfocused button must not animate")
    }

    @Test("A disabled button animates nothing, focus manager or not")
    func disabledButtonIsStill() {
        // Disabled controls never register for focus, but the style is handed
        // `isFocused` independently — so this pins the style's own guard.
        #expect(focused(Button("Save") {}.disabled(true)).animatedCells.isEmpty)
        #expect(
            focused(Button("Save") {}.buttonStyle(.plain).disabled(true)).animatedCells.isEmpty)
    }

    @Test("A button whose style does not animate hands over nothing")
    func steadyStyleIsStill() {
        // `.selectionIndicatorStyle(.none)` means focus is shown by colour
        // alone. There is no cycle, so there is nothing for the loop to replay
        // — and a one-frame run would cost bytes per tick to redraw what is
        // already on screen.
        let buffer = focused(Button("Save") {}.selectionIndicatorStyle(.none))
        #expect(buffer.animatedCells.isEmpty)
    }

    @Test("Every frame of a cap cycle is the same width")
    func capFramesAreUniformWidth() {
        // A frame that did not occupy exactly `width` cells would shove the
        // rest of the row sideways on some ticks and not others — the reflow
        // the whole mechanism exists to avoid.
        for run in focused(Button("Save") {}).animatedCells {
            #expect(run.frames.allSatisfy { $0.strippedLength == run.width }, "run: \(run)")
        }
    }

    @Test("A button keeps its runs through the tree a page wraps it in")
    func capsSurviveRealChrome() {
        // The producer and the propagation both have to hold for the page to
        // animate; this is the two of them together, which is what the live
        // app actually exercises.
        let page = ScrollView {
            VStack {
                Text("Header")
                Button("Save") {}.padding().border()
            }
        }
        let buffer = focused(page)
        expectAnimates(buffer, runs: 2, "button inside real chrome")
        // Indented by the padding and border it is wrapped in, so this is not
        // accidentally passing on an un-shifted run.
        #expect(buffer.animatedCells.allSatisfy { $0.offsetX > 0 && $0.offsetY > 0 })
    }
}

/// Claims auto-focus before the control under test renders, so that control
/// renders in its un-focused state.
private final class FocusSentinel: Focusable {
    let focusID = "focus-indicator-animation-sentinel"
    func handleKeyEvent(_ event: KeyEvent) -> Bool { false }
}
