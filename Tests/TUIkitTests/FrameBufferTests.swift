//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameBufferTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("FrameBuffer Tests")
struct FrameBufferTests {

    @Test("Empty buffer has zero dimensions")
    func emptyBuffer() {
        let buffer = FrameBuffer()
        #expect(buffer.width == 0)
        #expect(buffer.height == 0)
        #expect(buffer.isEmpty)
    }

    @Test("Single line buffer has correct dimensions")
    func singleLine() {
        let buffer = FrameBuffer(text: "Hello")
        #expect(buffer.width == 5)
        #expect(buffer.height == 1)
        #expect(buffer.lines == ["Hello"])
    }

    @Test("Vertical append stacks lines")
    func verticalAppend() {
        var buffer = FrameBuffer(text: "Line 1")
        buffer.appendVertically(FrameBuffer(text: "Line 2"))
        #expect(buffer.height == 2)
        #expect(buffer.lines == ["Line 1", "Line 2"])
    }

    @Test("Vertical append with spacing")
    func verticalAppendWithSpacing() {
        var buffer = FrameBuffer(text: "Top")
        buffer.appendVertically(FrameBuffer(text: "Bottom"), spacing: 2)
        #expect(buffer.height == 4)
        #expect(buffer.lines == ["Top", "", "", "Bottom"])
    }

    @Test("Horizontal append places side by side")
    func horizontalAppend() {
        var buffer = FrameBuffer(text: "Left")
        buffer.appendHorizontally(FrameBuffer(text: "Right"), spacing: 1)
        #expect(buffer.height == 1)
        #expect(buffer.lines == ["Left Right"])
    }

    @Test("Horizontal append with different heights pads correctly")
    func horizontalAppendDifferentHeights() {
        var left = FrameBuffer(lines: ["AB", "CD"])
        let right = FrameBuffer(text: "X")
        left.appendHorizontally(right, spacing: 1)
        #expect(left.height == 2)
        #expect(left.lines[0] == "AB X")
        // Row 1: "CD" padded to width 2, spacing " ", no right content
        #expect(left.lines[1] == "CD ")
    }

    @Test("ANSI codes are excluded from width calculation")
    func ansiStrippedWidth() {
        let styled = "\u{1B}[1mBold\u{1B}[0m"
        let buffer = FrameBuffer(text: styled)
        #expect(buffer.width == 4)  // "Bold" is 4 chars
    }

    @Test("Horizontal append with ANSI codes pads correctly")
    func horizontalAppendWithAnsi() {
        let styled = "\u{1B}[1mHi\u{1B}[0m"
        var left = FrameBuffer(text: styled)
        left.appendHorizontally(FrameBuffer(text: "There"), spacing: 1)
        #expect(left.height == 1)
        // "Hi" (styled) + " " (spacing) + "There"
        #expect(left.lines[0].stripped == "Hi There")
    }
}

@MainActor
@Suite("Overlay Tests")
struct OverlayTests {

    @Test("Overlay modifier renders overlay on top of base")
    func overlayRendering() {
        let view = Text("Base Content")
            .overlay(alignment: .center) {
                Text("Top")
            }
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        // The overlay "Top" should be centered on "Base Content"
        #expect(buffer.height >= 1)
        let allContent = buffer.lines.joined()
        #expect(allContent.contains("Top"))
    }

    @Test("Dimmed modifier strips styling and applies uniform palette colors")
    func dimmedRendering() {
        let view = Text("Dimmed text").dimmed()
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(view, context: context)
        #expect(buffer.height == 1)
        // Should not use ANSI dim — uses palette-based flat coloring now
        #expect(!buffer.lines[0].contains("\u{1B}[2m"))
        // Visible text must be preserved
        #expect(buffer.lines[0].stripped.contains("Dimmed text"))
    }

    @Test("The convenience .modal presents a centred modal over the dimmed base")
    func modalRendering() {
        let view = Text("Background")
            .modal {
                Text("Modal")
            }
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        // The convenience modal floats to the screen root as an overlay (so it
        // centres + dims over the whole screen); composite it the way RenderLoop
        // does to see the final dimmed-base + centred-modal buffer.
        let buffer = renderToBuffer(view, context: context)
            .compositingOverlays(maxWidth: 80, maxHeight: 24, palette: context.environment.palette)
        let all = buffer.lines.map { $0.stripped }.joined(separator: "\n")
        #expect(all.contains("Background"), "the dimmed base is shown")
        #expect(all.contains("Modal"), "the modal content is shown over the base")
    }

    @Test("FrameBuffer compositing places overlay at correct position")
    func frameBufferCompositing() {
        let base = FrameBuffer(lines: ["AAAA", "AAAA", "AAAA"])
        let overlay = FrameBuffer(text: "X")

        // Place overlay at position (1, 1)
        let result = base.composited(with: overlay, at: (x: 1, y: 1))

        #expect(result.height == 3)
        #expect(result.lines[0] == "AAAA")
        #expect(result.lines[1].contains("X"))
        #expect(result.lines[2] == "AAAA")
    }

    @Test("FrameBuffer compositing with offset")
    func frameBufferCompositingOffset() {
        let base = FrameBuffer(lines: ["1234567890"])
        let overlay = FrameBuffer(text: "XXX")

        // Place overlay at column 3
        let result = base.composited(with: overlay, at: (x: 3, y: 0))

        #expect(result.lines[0].stripped == "123XXX7890")
    }

    @Test("Compositing over wide characters keeps every row's columns aligned")
    func compositingOverWideCharacters() {
        // Emoji are one Character but two cells. A base row whose wide
        // character straddles either edge of the overlay must render the
        // overlay at the SAME columns as every other row — the straddled
        // glyph becomes a gap space, never a one-cell shift. (This was the
        // ragged pop-up borders next to an emoji slider track.)
        let base = FrameBuffer(lines: [
            "0123456789ab",   // plain row: the alignment reference
            "😀😀😀😀😀😀",   // wide row: cells 0-11, glyphs straddle x=3 and x=9
        ])
        let overlay = FrameBuffer(lines: ["││││", "││││"])

        let result = base.composited(with: overlay, at: (x: 3, y: 0))
        let plain = result.lines[0].stripped
        let wide = result.lines[1].stripped

        #expect(plain == "012││││789ab")
        // Every row is still 12 cells wide…
        #expect(wide.strippedLength == 12, "|\(wide)|")
        // …and the overlay sits at cells 3..<7 in the wide row too: one whole
        // emoji before it, a gap for the straddled one, then the overlay.
        #expect(wide == "😀 ││││ 😀😀", "|\(wide)|")
    }

    /// Whether the final visible cell of a line is left in the underline SGR
    /// state — scans the line's `ESC[…m` sequences, tracking `4` (on) / `24`,`0`
    /// (off). Self-contained (no TUIkitCore-internal helpers).
    private func endsUnderlined(_ line: String) -> Bool {
        var underline = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            guard chars[i] == "\u{1B}", i + 1 < chars.count, chars[i + 1] == "[" else {
                i += 1
                continue
            }
            var j = i + 2
            var params: [Character] = []
            while j < chars.count, chars[j].isNumber || chars[j] == ";" {
                params.append(chars[j])
                j += 1
            }
            if j < chars.count, chars[j] == "m" {  // an SGR sequence
                for part in String(params).split(separator: ";", omittingEmptySubsequences: false) {
                    switch String(part) {
                    case "", "0", "24": underline = false
                    case "4": underline = true
                    default: break
                    }
                }
            }
            i = j < chars.count ? j + 1 : j
        }
        return underline
    }

    @Test("Compositing over underlined text doesn't leak underline into the trailing cell")
    func compositeOverUnderlinedTextNoTrailingUnderlineLeak() {
        // Repro of the Overlays-page bug: a DemoSection header `Text(title).underline()`
        // line is plain-padded to width; a notification overlay composited over its
        // start must leave the trailing padding plain — not re-apply the header's
        // (leading) underline to the cell after the overlay's bottom-right corner.
        let header = "\u{1B}[4mHow It Works\u{1B}[0m"  // 12 visible cells, underlined, then reset
        let base = FrameBuffer(lines: [header.padToVisibleWidth(20)])  // + 8 plain padding cells
        let overlay = FrameBuffer(lines: [String(repeating: "X", count: 18)])  // covers cols 0–17
        let result = base.composited(with: overlay, at: (x: 0, y: 0))

        #expect(result.lines[0].stripped.hasSuffix("XX  "), "visible layout intact")
        #expect(
            !endsUnderlined(result.lines[0]),
            "padding after the overlay must not inherit the header underline")
    }

    // MARK: - Trimming trailing blanks

    /// Compositing is opaque per cell, so anything drawn OVER the screen — the
    /// floating drag preview above all — erases a column for every blank it
    /// carries. A list row padded to its container's width is nearly all blanks.
    @Test("Trailing blank cells are trimmed, and stop erasing what they cover")
    func trimmingTrailingBlanks() {
        let padded = FrameBuffer(lines: ["AB" + String(repeating: " ", count: 10)])
        #expect(padded.width == 12)
        let trimmed = padded.trimmingTrailingBlankCells()
        #expect(trimmed.width == 2)

        let base = FrameBuffer(lines: ["UNDERNEATH.."])
        #expect(
            base.composited(with: padded, at: (x: 0, y: 0)).lines[0].stripped == "AB          ",
            "the untrimmed preview blanks the rest of the row")
        #expect(
            base.composited(with: trimmed, at: (x: 0, y: 0)).lines[0].stripped == "ABDERNEATH..",
            "the trimmed one covers only its own two cells")
    }

    /// On a selected or filled row the trailing blanks ARE the fill. Trimming
    /// them would turn a highlighted floating row into a ragged one.
    @Test("Trailing blanks that carry a background are kept")
    func trimmingKeepsStyledBlanks() {
        let filled = FrameBuffer(lines: ["\u{1B}[44mAB        \u{1B}[0m"])
        #expect(filled.trimmingTrailingBlankCells().width == 10, "the fill is content")

        // …but a background that has been switched off again is just padding.
        let reset = FrameBuffer(lines: ["\u{1B}[44mAB\u{1B}[0m        "])
        #expect(reset.trimmingTrailingBlankCells().width == 2)

        // And a line whose every cell is a blank with no styling disappears —
        // which is what lets a blank slot row float over nothing.
        #expect(FrameBuffer(lines: ["    "]).trimmingTrailingBlankCells().width == 0)
    }

    // MARK: - Pointer-anchored overlays

    /// The bug a fixture could not see: an overlay wider than the space to its
    /// right was SLID back on screen. Right for a drop-down, fatal for anything
    /// pinned to the pointer — a wide drag preview stopped following the cursor
    /// after a few cells and then painted over whatever was at the right edge.
    @Test("A pointer-anchored overlay is clipped at the edge, not slid back")
    func pointerAnchoredOverlayClipsInsteadOfSliding() {
        let wide = FrameBuffer(lines: [String(repeating: "X", count: 10)])
        let popover = OverlayLayer(offsetX: 15, offsetY: 0, content: wide)
        let pinned = OverlayLayer(offsetX: 15, offsetY: 0, content: wide, clampsToScreen: false)

        let slid = popover.placed(maxWidth: 20, maxHeight: 5)
        #expect(slid.x == 10, "a popover slides left to stay whole")
        #expect(slid.content.width == 10)

        let clipped = pinned.placed(maxWidth: 20, maxHeight: 5)
        #expect(clipped.x == 15, "the pinned one stays where the pointer put it")
        #expect(clipped.content.width == 5, "and loses what hangs off the edge")
    }

    /// Off the LEFT edge the overhang has to come off the content too: the
    /// compositor cannot take a negative column.
    @Test("A pointer-anchored overlay clipped at the left edge drops columns")
    func pointerAnchoredOverlayClipsLeftEdge() {
        let content = FrameBuffer(lines: ["ABCDEFGH", "abcdefgh"])
        let pinned = OverlayLayer(offsetX: -3, offsetY: -1, content: content, clampsToScreen: false)
        let placed = pinned.placed(maxWidth: 20, maxHeight: 5)
        #expect(placed.x == 0 && placed.y == 0)
        #expect(
            placed.content.lines.map(\.stripped) == ["defgh"],
            "the first three columns and the first row are gone: \(placed.content.lines)")
    }

    /// The clip has to carry the STYLE across the cut. Dropping the escapes that
    /// came before it left the surviving text with no colour at all, which the
    /// compositor writes between two resets — so a drag preview carried to the
    /// left edge rendered in the terminal's raw defaults and read as nothing but
    /// background.
    @Test("A left-clipped overlay keeps the styling it was cut through")
    func pointerAnchoredOverlayCarriesStyleAcrossTheCut() {
        let styled = "\u{1B}[38;5;213mABCDEFGH\u{1B}[0m"
        let pinned = OverlayLayer(
            offsetX: -3, offsetY: 0, content: FrameBuffer(lines: [styled]),
            clampsToScreen: false)
        let line = pinned.placed(maxWidth: 20, maxHeight: 5).content.lines[0]
        #expect(line.stripped == "DEFGH", "the visible cells are the ones that fit")
        #expect(line.contains("38;5;213"), "and they are still pink: \(line.debugDescription)")
    }

    /// A wide glyph cut in half cannot be drawn, so it goes — and the cell it
    /// owed has to be paid in spaces, or every later cell slides one column left
    /// and the preview stops holding the cell the pointer grabbed.
    @Test("A left-clipped overlay pads a straddled wide glyph")
    func pointerAnchoredOverlayPadsAStraddledGlyph() {
        // 🎵 is two cells; cutting one column into it drops it whole.
        let pinned = OverlayLayer(
            offsetX: -1, offsetY: 0, content: FrameBuffer(lines: ["\u{1F3B5} Aurora"]),
            clampsToScreen: false)
        let line = pinned.placed(maxWidth: 20, maxHeight: 5).content.lines[0]
        #expect(
            line.strippedLength == 8,
            "one cell of the glyph survives as a space: \(line.debugDescription)")
        #expect(line.stripped.hasSuffix(" Aurora"))
    }

    /// Ragged is fine: each line keeps its own silhouette, and `composited`
    /// already writes line by line.
    @Test("A multi-line preview trims each line independently")
    func trimmingIsPerLine() {
        let buffer = FrameBuffer(lines: ["one   ", "t     ", "three "])
        let trimmed = buffer.trimmingTrailingBlankCells()
        #expect(trimmed.lines.map(\.strippedLength) == [3, 1, 5])
        #expect(trimmed.width == 5)
        #expect(!trimmed.linesAreUniformWidth)
    }

    @Test("Horizontal append onto an empty buffer claims no spacing slot")
    func horizontalAppendOntoEmptyBuffer() {
        // The accumulating stack result after a leading child rendered empty.
        // A gap belongs between two occupied column ranges, so the first thing
        // in the row starts at column 0 — the mirror of the vertical rule.
        var buffer = FrameBuffer()
        buffer.appendHorizontally(FrameBuffer(text: "Right"), spacing: 2)
        #expect(buffer.lines == ["Right"])
        #expect(buffer.width == 5)
    }
}
