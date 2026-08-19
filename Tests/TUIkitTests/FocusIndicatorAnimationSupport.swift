//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusIndicatorAnimationSupport.swift
//
//  The assertions every converted focus-pulse producer is held to, shared by
//  the suites that hold them. See `FocusIndicatorAnimationTests` for what those
//  three points are and why "it animates" is not one of them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// Renders `view` against a context whose fresh `FocusManager` auto-focuses
/// the first focusable — i.e. the control under test.
@MainActor
func focusedRender(_ view: some View, width: Int = 40, height: Int = 8) -> FrameBuffer {
    renderToBuffer(view, context: makeRenderContext(width: width, height: height))
}

/// A buffer's rows as the terminal shows them: no styling, and no trailing
/// blanks — compositing squares a buffer's rows off to its widest line, so
/// a short row picks up padding that never reaches the screen. Anything a
/// misplaced run would actually do (shift a glyph, overwrite one, split a
/// wide character) still shows up here.
func visibleRows(_ buffer: FrameBuffer) -> [String] {
    buffer.lines.map { line in
        String(line.stripped.reversed().drop(while: { $0 == " " }).reversed())
    }
}

/// Asserts the run describes the cells that were actually drawn.
///
/// Splicing a run's *current* frame back over the buffer is precisely what
/// the run loop does on a tick. At the step the view rendered at, that must
/// change nothing — so any disagreement about where the run sits, or how
/// wide it is, shows up here as shifted or clobbered glyphs.
@MainActor
func expectReplayIsIdentity(
    _ buffer: FrameBuffer, at step: Int = 0,
    _ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation
) {
    let before = visibleRows(buffer)
    for run in buffer.animatedCells {
        let replayed = buffer.composited(
            with: FrameBuffer(lines: [run.frame(at: step)]),
            at: (x: run.offsetX, y: run.offsetY))
        #expect(
            visibleRows(replayed) == before, comment ?? "run \(run) moved the cells",
            sourceLocation: sourceLocation)
    }
}

/// The full contract for a control that should be animating.
@MainActor
func expectAnimates(
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

/// Parks the focus so a control can be rendered UNfocused: the first
/// `Focusable` to register with a fresh `FocusManager` takes it, which is what
/// makes "an unfocused control" testable at all.
final class FocusSentinel: Focusable {
    let focusID = "focus-indicator-animation-sentinel"
    func handleKeyEvent(_ event: KeyEvent) -> Bool { false }
}
