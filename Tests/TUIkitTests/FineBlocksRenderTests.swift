//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FineBlocksRenderTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

// MARK: - Fine-Block Grid Integrity
//
// `.fineBlocks` is the only image mode that encodes pixel data in the cell
// *background*: each cell is `▀` (Upper Half Block) painted with the top
// pixel as foreground and the BOTTOM pixel as the cell's background. The cell
// is therefore filled edge-to-edge — top half = fg = top pixel, bottom half =
// bg = bottom pixel — so a correctly-emitted grid has NO unpainted cells.
//
// If a terminal shows thin gaps between rows of such an image, that is the
// terminal failing to paint the SGR background across its inter-line leading
// (a line-/character-spacing setting), NOT a gap in the bytes TUIkit writes —
// those gaps fall in the unaddressable space *between* cells. These tests pin
// the invariant that the bytes are gap-free at the source: every `▀` carries a
// real background, and the frame-diff line builder never drops a cell's bg
// (e.g. via a future clip/erase/reset optimisation). A failure here WOULD be a
// real, in-our-output gap.

@Suite("Fine-block grid integrity")
struct FineBlocksRenderTests {

    /// A `w`×`h` image with a smooth 2-D gradient, so adjacent cells differ in
    /// colour and the converter is forced through its per-cell colour-run and
    /// reset paths (a flat image would emit one run and exercise nothing).
    private func gradientImage(_ w: Int, _ h: Int) -> RGBAImage {
        var pixels = [RGBA]()
        pixels.reserveCapacity(w * h)
        for y in 0..<h {
            for x in 0..<w {
                pixels.append(RGBA(
                    r: UInt8(clamping: x * 255 / max(1, w - 1)),
                    g: UInt8(clamping: y * 255 / max(1, h - 1)),
                    b: UInt8(clamping: (x + y) * 255 / max(1, w + h - 2))))
            }
        }
        return RGBAImage(width: w, height: h, pixels: pixels)
    }

    /// Walks a rendered line and returns the active background SGR — `""` when
    /// none is set — at every `▀` glyph, in visible order. An empty entry means
    /// that cell's bottom half would show the terminal/app background: a gap.
    private func backgroundsAtBlocks(in line: String) -> [String] {
        var activeBg = ""
        var result: [String] = []
        let scalars = Array(line.unicodeScalars)
        var index = 0
        while index < scalars.count {
            if scalars[index].value == 0x1B, index + 1 < scalars.count, scalars[index + 1] == "[" {
                var end = index + 2
                var params = ""
                while end < scalars.count {
                    let value = scalars[end].value
                    if value >= 0x40 && value <= 0x7E {  // CSI final byte
                        if scalars[end] == "m" { activeBg = Self.updatedBackground(activeBg, params) }
                        break
                    }
                    params.unicodeScalars.append(scalars[end])
                    end += 1
                }
                index = end + 1
                continue
            }
            if Character(scalars[index]) == "\u{2580}" { result.append(activeBg) }
            index += 1
        }
        return result
    }

    /// Applies one SGR parameter string to the tracked background state.
    private static func updatedBackground(_ current: String, _ params: String) -> String {
        let parts = params.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        var background = (params.isEmpty || parts.contains("0")) ? "" : current
        if let marker = parts.firstIndex(where: { $0 == "48" || $0 == "49" }) {
            if parts[marker] == "49" {
                background = "\u{1B}[49m"
            } else if marker + 1 < parts.count, parts[marker + 1] == "2", marker + 4 < parts.count {
                background = "\u{1B}[48;2;\(parts[marker + 2]);\(parts[marker + 3]);\(parts[marker + 4])m"
            } else if marker + 1 < parts.count, parts[marker + 1] == "5", marker + 2 < parts.count {
                background = "\u{1B}[48;5;\(parts[marker + 2])m"
            }
        }
        return background
    }

    @Test("Converter paints every fine-block cell's background (no source gaps)")
    func converterPaintsEveryCell() {
        let converter = ASCIIConverter(
            characterSet: .fineBlocks, colorMode: .trueColor, dithering: .none)
        withColorDepth(.truecolor) {
            let lines = converter.convert(gradientImage(40, 40), width: 20, height: 10)
            for (row, line) in lines.enumerated() {
                let emptyColumns = backgroundsAtBlocks(in: line)
                    .enumerated().filter { $0.element.isEmpty }.map(\.offset)
                #expect(emptyColumns.isEmpty, "row \(row): ▀ with no background at columns \(emptyColumns)")
            }
        }
    }

    @MainActor
    @Test("Frame-diff line builder preserves every cell's background")
    func frameDiffPreservesBackgrounds() {
        let converter = ASCIIConverter(
            characterSet: .fineBlocks, colorMode: .trueColor, dithering: .none)
        withColorDepth(.truecolor) {
            let raw = converter.convert(gradientImage(40, 40), width: 20, height: 10)
            let buffer = FrameBuffer(lines: raw)
            // A realistic dark app background, exactly as `RenderLoop` supplies it;
            // its only effect on a fine-block line is to re-assert the app bg after
            // each reset, which the next cell's own bg immediately overrides.
            let backgroundCode = "\u{1B}[48;2;30;30;46m"
            let reset = "\u{1B}[0m"
            // Exercise both output paths — the Terminal.app cursor-compensation
            // path and the plain path — since both rewrite the line.
            for isAppleTerminal in [false, true] {
                let writer = FrameDiffWriter(isAppleTerminal: isAppleTerminal)
                let output = writer.buildOutputLines(
                    buffer: buffer, terminalWidth: 20, terminalHeight: raw.count,
                    bgCode: backgroundCode, reset: reset)
                for row in 0..<raw.count {
                    #expect(
                        backgroundsAtBlocks(in: output[row]) == backgroundsAtBlocks(in: raw[row]),
                        "apple=\(isAppleTerminal) row \(row): a cell background was altered by line building")
                }
            }
        }
    }

    @MainActor
    @Test("Horizontal scroll slice carries the background into the window")
    func horizontalSliceCarriesBackground() {
        // Scrolling/zooming an image drops leading columns; the slice must replay
        // the SGR state so the first visible cell still has its background.
        let converter = ASCIIConverter(
            characterSet: .fineBlocks, colorMode: .trueColor, dithering: .none)
        withColorDepth(.truecolor) {
            let lines = converter.convert(gradientImage(40, 40), width: 20, height: 10)
            for offset in [1, 3, 7, 13] {
                for (row, line) in lines.enumerated() {
                    let sliced = line.ansiAwareSlice(visibleStart: offset, visibleCount: 6)
                    let emptyColumns = backgroundsAtBlocks(in: sliced)
                        .enumerated().filter { $0.element.isEmpty }.map(\.offset)
                    #expect(
                        emptyColumns.isEmpty,
                        "offset \(offset) row \(row): sliced ▀ with no background at \(emptyColumns)")
                }
            }
        }
    }
}
