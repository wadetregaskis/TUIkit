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

/// Whether two built rows put the same thing on screen — the same glyphs in
/// the same STYLING.
///
/// Not string equality: two spellings of one styling are the same picture, and
/// splicing a frame into a row legitimately produces the longer spelling. Not
/// stripped glyphs either, which is what this compared until a scrollbar's
/// hover lift was replayed away by runs that had never been told about the
/// pointer — a colour-only difference, invisible to a `.stripped` comparison,
/// and the whole of what the user saw. See §9 of
/// `Documentation/Animating your own view efficiently.md`.
///
/// The styling half is ``ANSICellDiff/identical``, which is the framework's own
/// answer to "would a terminal show anything different" — the same judgement
/// `FrameDiffWriter` makes about whether a cell is worth rewriting. Rows the
/// decomposer declines (a wide glyph, an emoji, a cursor move) fall back to the
/// glyph comparison, which is all that can be checked there.
func paintsIdentically(_ before: [String], _ after: [String]) -> Bool {
    guard before.count == after.count else { return false }
    for (old, new) in zip(before, after) {
        guard trimmedGlyphs(old) == trimmedGlyphs(new) else { return false }
        let width = old.strippedLength
        guard width > 0, width == new.strippedLength,
            let oldCells = ANSIRowCells(decomposing: old, width: width),
            let newCells = ANSIRowCells(decomposing: new, width: width)
        else { continue }
        var emitted: SGRState?
        guard newCells.diff(replacing: oldCells, mergingGapsUpTo: 0, continuing: &emitted)
            == .identical
        else { return false }
    }
    return true
}

/// A row's glyphs with trailing blanks dropped — compositing squares a buffer
/// off to its widest line, so a short row picks up padding that never reaches
/// the screen.
private func trimmedGlyphs(_ line: String) -> String {
    String(line.stripped.reversed().drop(while: { $0 == " " }).reversed())
}

/// Asserts the run describes the cells that were actually drawn.
///
/// Splicing a run's *current* frame back over the buffer is precisely what the
/// run loop does on a tick. At the step the view rendered at, that must change
/// nothing — so any disagreement about where the run sits, how wide it is, or
/// what colour it paints shows up here.
///
/// Through ``FrameBuffer/patchingAnimatedCells(in:replaying:atIndex:)``,
/// which is the splice `RenderLoop` actually performs less the writer's page and
/// host, and NOT ``FrameBuffer/composited(with:at:)``, which this used to use.
/// The two differ in one load-bearing way: `composited` resets before an
/// overlay, so a foreground-only frame lands on the terminal's default
/// background, while the tick paints the frame over the field recorded beneath
/// it (the run's ground). Replaying the wrong one made every focus cap inside a
/// `.background()` look broken here and fine on screen. And through the ground,
/// this also catches a container that paints under a run without recording it:
/// the replayed cells would lose that container's field.
@MainActor
func expectReplayIsIdentity(
    _ buffer: FrameBuffer, at step: Int = 0,
    _ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation
) {
    for run in buffer.animatedCells {
        guard run.offsetY < buffer.lines.count else {
            Issue.record("run \(run) sits past the buffer's \(buffer.lines.count) rows")
            continue
        }
        var replayed = buffer.lines
        replayed[run.offsetY] = FrameBuffer.patchingAnimatedCells(
            in: replayed[run.offsetY], replaying: run, atIndex: step)
        #expect(
            paintsIdentically(buffer.lines, replayed),
            comment ?? "run \(run) moved the cells",
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
