//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextEditorCaretRunTests.swift
//
//  A TextEditor's caret and its scrollbar both used to be drawn from the LIVE
//  clock, which meant a focused editor re-rendered the whole screen 20 times a
//  second to blink one cell — 6.7% of a core on the Example's Text Input page,
//  against 0.2% for the TextField two screens above it, which had already been
//  converted. Both now hand their cells to the run loop.
//
//  They had to convert together: the caret alone would have left the editor
//  still re-rendering for the bar, and the bar alone would have left its runs
//  replaying over a screen the caret was still repainting. Either half on its
//  own looks right in a screenshot and is wrong over time, which is why the
//  scrollbar case is in this file rather than a separate one.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A mutable string backing a test `Binding`.
private final class TextSink: @unchecked Sendable {
    var value: String
    init(_ value: String) { self.value = value }
    var binding: Binding<String> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
@Suite("TextEditor caret and scrollbar animation")
struct TextEditorCaretRunTests {

    private func editor(_ text: String, cursor: TextCursorStyle = TextCursorStyle()) -> some View {
        TextTextEditorHost(sink: TextSink(text), cursor: cursor)
    }

    /// Holds the sink for as long as the view is rendered — a local `let` dies
    /// at its last use, and a binding onto a dead box reads nothing.
    private struct TextTextEditorHost: View {
        let sink: TextSink
        let cursor: TextCursorStyle
        var body: some View {
            TextEditor(text: sink.binding).textCursor(cursor)
        }
    }

    private func render(
        _ view: some View, width: Int = 24, height: Int = 4, measuring: Bool = false
    ) -> FrameBuffer {
        var context = makeRenderContext(width: width, height: height)
        context.isMeasuring = measuring
        return renderToBuffer(view, context: context)
    }

    /// Whether replaying a run changes what a terminal would show — glyphs AND
    /// styling, via the framework's own ``ANSICellDiff/identical``. A caret is a
    /// colour-only animation, so a comparison of stripped glyphs would pass on
    /// a run that painted the caret the wrong colour entirely.
    private func replayPaintsIdentically(_ buffer: FrameBuffer, at step: Int = 0) -> Bool {
        for run in buffer.animatedCells {
            let replayed = buffer.composited(
                with: FrameBuffer(lines: [run.frame(atIndex: step)]),
                at: (x: run.offsetX, y: run.offsetY))
            guard replayed.lines.count == buffer.lines.count else { return false }
            for (before, after) in zip(buffer.lines, replayed.lines) {
                let width = before.strippedLength
                guard width > 0, width == after.strippedLength,
                    let old = ANSIRowCells(decomposing: before, width: width),
                    let new = ANSIRowCells(decomposing: after, width: width)
                else {
                    guard before.stripped == after.stripped else { return false }
                    continue
                }
                var emitted: SGRState?
                guard new.diff(replacing: old, mergingGapsUpTo: 0, continuing: &emitted)
                    == .identical
                else { return false }
            }
        }
        return true
    }

    // MARK: - The caret

    @Test("A focused editor hands over its caret cells, and only those")
    func caretIsHandedOver() {
        let buffer = render(editor("hello\nworld"))
        #expect(buffer.animatedCells.count == 1, "runs: \(buffer.animatedCells)")
        guard let run = buffer.animatedCells.first else { return }
        #expect(run.isAnimating, "a still run holds the clock open to repaint one picture")
        #expect(run.clock == .cursor)
        // The editor opens with the caret at the start of the first line.
        #expect(run.offsetY == 0 && run.offsetX == 0, "run: \(run)")
        #expect(run.width == 1)
        #expect(replayPaintsIdentically(buffer), "the run does not describe the drawn cells")
    }

    @Test("The caret follows the cursor onto its own row and column")
    func caretTracksTheCursor() {
        let sink = TextSink("alpha\nbravo\ncharlie")
        let context = makeRenderContext(width: 24, height: 4)
        let view = TextEditor(text: sink.binding)
        _ = renderToBuffer(view, context: context)  // register the handler
        guard let handler = context.environment.focusManager?.activeSection?.focusables
            .compactMap({ $0 as? TextEditorHandler }).first
        else {
            Issue.record("no editor handler registered")
            return
        }
        handler.cursorLine = 1
        handler.cursorColumn = 3
        let buffer = renderToBuffer(view, context: context)
        #expect(buffer.animatedCells.first?.offsetY == 1)
        #expect(buffer.animatedCells.first?.offsetX == 3)
        #expect(replayPaintsIdentically(buffer))
        withExtendedLifetime(sink) {}
    }

    @Test("A blink cycle carries both halves, and the off half is the character")
    func blinkHasBothHalves() {
        let buffer = render(
            editor("hello", cursor: TextCursorStyle(shape: .block, animation: .blink)))
        guard let frames = buffer.animatedCells.first?.frames else {
            Issue.record("no caret run")
            return
        }
        #expect(Set(frames).count == 2, "a blink is exactly two pictures: \(Set(frames).count)")
        // Both halves draw the character under the caret; only the styling
        // differs. A blink-off frame that drew a space would erase the text.
        #expect(frames.allSatisfy { $0.stripped == "h" }, "frames: \(frames)")
    }

    @Test("Every frame of the caret is exactly the caret's width")
    func framesAreUniformWidth() {
        // A frame occupying the wrong number of cells would shove the rest of
        // the line sideways on some ticks and not others.
        for shape in [TextCursorStyle.Shape.block, .bar, .underscore] {
            for animation in [TextCursorStyle.Animation.blink, .pulse] {
                let buffer = render(
                    editor("hello", cursor: TextCursorStyle(shape: shape, animation: animation)))
                for run in buffer.animatedCells {
                    #expect(
                        run.frames.allSatisfy { $0.strippedLength == run.width },
                        "\(shape)/\(animation): \(run)")
                }
                #expect(replayPaintsIdentically(buffer), "\(shape)/\(animation)")
            }
        }
    }

    @Test("The caret's frames stand alone")
    func framesAreSelfContained() {
        // A frame is spliced into a line that already exists, so it must not
        // lean on an escape earlier in that line: whatever colour happened to
        // precede it would become the caret's. Every frame therefore opens by
        // stating its own styling and closes by resetting it — including the
        // blink-OFF frame, which used to coalesce with its neighbours.
        let buffer = render(editor("hello"))
        guard let frames = buffer.animatedCells.first?.frames else {
            Issue.record("no caret run")
            return
        }
        for frame in frames {
            #expect(
                frame.hasPrefix("\u{1B}["),
                "a frame that opens unstyled takes the line's colour: \(frame.debugDescription)")
            #expect(
                frame.hasSuffix("\u{1B}[0m"),
                "a frame that does not close leaks into the line: \(frame.debugDescription)")
        }
    }

    @Test("An unfocused editor animates nothing")
    func unfocusedIsStill() {
        let context = makeRenderContext(width: 24, height: 4)
        context.environment.focusManager!.register(FocusSentinel())
        let sink = TextSink("hello")
        let buffer = renderToBuffer(TextEditor(text: sink.binding), context: context)
        #expect(buffer.animatedCells.isEmpty)
        withExtendedLifetime(sink) {}
    }

    @Test("A steady cursor style hands over nothing")
    func steadyCaretIsStill() {
        // `.none` shows the caret without animating it: one frame is a still
        // picture the ordinary render already drew.
        let buffer = render(
            editor("hello", cursor: TextCursorStyle(shape: .block, animation: .none)))
        #expect(buffer.animatedCells.isEmpty)
    }

    @Test("A measure pass hands over nothing")
    func measuringIsStill() {
        // A measure buffer describes a size being tried on, not cells on
        // screen; a run kept from one would repaint, on a clock, over whatever
        // took those cells.
        #expect(render(editor("hello"), measuring: true).animatedCells.isEmpty)
    }

    // MARK: - The scrollbar, which had to convert with it

    @Test("An overflowing focused editor animates its scrollbar as well as its caret")
    func scrollbarAnimatesWithTheCaret() {
        let buffer = render(editor("1\n2\n3\n4\n5\n6\n7\n8"), width: 24, height: 4)
        let barColumn = buffer.width - 1
        let bar = buffer.animatedCells.filter { $0.offsetX == barColumn }
        let caret = buffer.animatedCells.filter { $0.offsetX != barColumn }
        #expect(!bar.isEmpty, "the bar is the editor's focus indicator and must breathe")
        #expect(caret.count == 1, "the caret still animates: \(caret)")
        #expect(bar.allSatisfy { $0.width == 1 }, "a vertical bar is one cell wide")
        #expect(
            bar.count < buffer.lines.count,
            "the still track rows earn no run: \(bar.count) of \(buffer.lines.count)")
        #expect(replayPaintsIdentically(buffer))
    }

    @Test("An unfocused overflowing editor animates neither")
    func unfocusedOverflowIsStill() {
        let context = makeRenderContext(width: 24, height: 4)
        context.environment.focusManager!.register(FocusSentinel())
        let sink = TextSink("1\n2\n3\n4\n5\n6\n7\n8")
        let buffer = renderToBuffer(TextEditor(text: sink.binding), context: context)
        #expect(buffer.animatedCells.isEmpty)
        withExtendedLifetime(sink) {}
    }
}
