//  🖥️ TUIKit — Terminal UI Kit for Swift
//  BlocksRenderTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

// `.blocks` renders one image pixel per cell as a space whose *background* is
// the pixel colour. Because it draws no glyph, it can't show the inter-row
// seams a font leaves when its block glyphs are rasterised short of the cell —
// the whole point of the mode. These tests pin that: every cell is a
// background-filled space, no foreground/glyph, and the row is exactly `width`
// cells wide.
@MainActor
@Suite("Blocks image mode (gap-free background fill)")
struct BlocksRenderTests {
    private func gradient(_ width: Int, _ height: Int) -> RGBAImage {
        var pixels = [RGBA]()
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels.append(RGBA(
                    r: UInt8(clamping: x * 255 / max(1, width - 1)),
                    g: UInt8(clamping: y * 255 / max(1, height - 1)),
                    b: 128))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    @Test("Every cell is a background-filled space — no glyphs, no gaps")
    func backgroundFilledNoGlyphs() {
        let converter = ASCIIConverter(characterSet: .blocks(.solid), colorMode: .trueColor, dithering: .none)
        withColorDepth(.palette256) {
            let lines = converter.convert(gradient(20, 12), width: 20, height: 12)
            #expect(lines.count == 12)
            for (row, line) in lines.enumerated() {
                let visible = line.stripped
                // One cell per pixel: exactly `width` visible columns, all spaces.
                #expect(visible.count == 20, "row \(row) visible width \(visible.count)")
                #expect(
                    visible.allSatisfy { $0 == " " },
                    "row \(row) draws no glyphs: \(visible.debugDescription)")
                // Colour comes from the BACKGROUND (SGR 48), never a foreground.
                #expect(line.contains("48;"), "row \(row) carries a background colour")
                #expect(!line.contains("38;"), "row \(row) uses no foreground colour")
                // None of the block glyphs that a font can seam.
                #expect(!line.contains("▄") && !line.contains("▀") && !line.contains("█"))
            }
        }
    }

    @Test("Mono blocks fall back to a █ / space threshold with no colour codes")
    func monoFallback() {
        let converter = ASCIIConverter(characterSet: .blocks(.solid), colorMode: .mono, dithering: .none)
        withColorDepth(.noColor) {
            let joined = converter.convert(gradient(10, 4), width: 10, height: 4).joined(separator: "\n")
            #expect(!joined.contains("\u{1B}["), "mono emits no colour escape codes")
            #expect(joined.contains("█") || joined.contains(" "))
        }
    }
}
