//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HalfBlockUniformCellTests.swift
//
//  A half block encodes two stacked pixels, and most of the time they are the
//  same colour — 86.5% of the demo photograph's cells at sixteen colours,
//  because the coarser the palette the more often two neighbours land on one
//  entry. Such a cell has no shape in it, and saying so with a space rather
//  than a block is what keeps a terminal from treating it as unreadable text
//  (Warp's `enforce_minimum_contrast`) or rasterising a glyph that cannot
//  matter.
//
//  The cases here are about WHEN a cell counts as uniform, which is a question
//  about the colour that gets painted and not about the pixels.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitStyling

@testable import TUIkitImage

@Suite("A half-block cell with nothing to draw")
struct HalfBlockUniformCellTests {

    /// `height` rows of `width` pixels, each row a flat colour from `rows`.
    private func banded(width: Int, _ rows: [RGBA]) -> RGBAImage {
        var pixels: [RGBA] = []
        for row in rows {
            pixels.append(contentsOf: Array(repeating: row, count: width))
        }
        return RGBAImage(width: width, height: rows.count, pixels: pixels)
    }

    private func lines(_ image: RGBAImage, _ mode: ASCIIColorMode, cells: Int) -> [String] {
        ASCIIConverter(characterSet: .blocks(.fine), colorMode: mode)
            .convert(image, width: cells, height: image.height / 2).lines
    }

    private func glyphs(_ line: String) -> String {
        line.replacing(/\u{1B}\[[0-9;]*[A-Za-z]/, with: "")
    }

    private let grey = RGBA(r: 40, g: 40, b: 40)

    // MARK: - When there is nothing to draw

    /// One colour top and bottom: a space, and a background to paint it in.
    /// No foreground is stated at all, which is the point — there is no text
    /// for a terminal to decide is illegible.
    @Test("A cell of one colour is a space with only a background")
    func uniformCellIsASpace() {
        let flat = lines(banded(width: 6, [grey, grey]), .ansi16, cells: 6)
        #expect(flat.count == 1)
        #expect(glyphs(flat[0]) == "      ")
        #expect(flat[0].contains("\u{1B}[40m"), "the background is stated")
        for named in 30...37 {
            #expect(!flat[0].contains("\u{1B}[\(named)m"), "no foreground is stated")
        }
    }

    /// Two colours: a block, and both halves stated. The saving must not eat
    /// the picture.
    @Test("A cell of two colours is still a block with both halves")
    func twoTonedCellKeepsItsBlock() {
        let split = lines(
            banded(width: 6, [RGBA(r: 0, g: 0, b: 0), RGBA(r: 255, g: 255, b: 255)]),
            .ansi16, cells: 6)
        #expect(glyphs(split[0]) == "▄▄▄▄▄▄")
        #expect(split[0].contains("\u{1B}[40m"), "the top pixel is the background")
        #expect(split[0].contains("\u{1B}[97m"), "the bottom pixel is the foreground")
    }

    /// The whole point: uniform is about the colour PAINTED, not the pixels.
    /// These two greys are eleven apart and quantise to the same one of the
    /// sixteen, so the cell has nothing to draw — and a comparison of pixels
    /// would have missed it and kept the block.
    @Test("Different pixels that quantise together count as uniform")
    func uniformityIsAboutTheQuantisedColour() {
        let near = banded(width: 6, [RGBA(r: 34, g: 34, b: 34), RGBA(r: 45, g: 45, b: 45)])
        #expect(glyphs(lines(near, .ansi16, cells: 6)[0]) == "      ", "one slot, so one field")
        #expect(
            glyphs(lines(near, .trueColor, cells: 6)[0]) == "▄▄▄▄▄▄",
            "true colour keeps them apart, so the cell still has a shape")
    }

    /// …and the converse, which is what stops this from being a way to lose
    /// detail: a mode that can tell two pixels apart still draws both.
    @Test("The finer the mode, the fewer cells collapse")
    func finerModesCollapseFewer() {
        var steps: [RGBA] = []
        for step in 0..<16 {
            let value = UInt8(step * 17)
            steps.append(RGBA(r: value, g: value, b: value))
        }
        let ramp = banded(width: 4, steps)
        func blocks(_ mode: ASCIIColorMode) -> Int {
            let joined: String = lines(ramp, mode, cells: 4).joined()
            return joined.filter { (character: Character) in character == "▄" }.count
        }
        #expect(blocks(.trueColor) >= blocks(.ansi256))
        #expect(blocks(.ansi256) >= blocks(.ansi16))
    }

    // MARK: - What the terminal is spared

    /// Warp lightens a foreground it judges unreadable when that foreground is
    /// NAMED (`enforce_minimum_contrast` = `only_named_colors`, its default).
    /// A block with foreground == background is the most unreadable text
    /// there is, so the emission must never contain one.
    @Test("No cell is ever emitted with its foreground equal to its background")
    func neverStatesAnInvisibleForeground() {
        var pixels: [RGBA] = []
        var seed: UInt64 = 99
        for _ in 0..<(24 * 24) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = UInt8(truncatingIfNeeded: seed >> 56)
            pixels.append(RGBA(r: v, g: v / 2, b: 255 &- v))
        }
        let noisy = RGBAImage(width: 24, height: 24, pixels: pixels)
        for mode in [ASCIIColorMode.ansi16, .ansi256, .grayscale, .trueColor] {
            for line in lines(noisy, mode, cells: 24) {
                for run in line.split(separator: "\u{1B}[0m") where run.contains("▄") {
                    let foreground = run.contains("[38;") || run.contains(/\[(3[0-7]|9[0-7])m/)
                    #expect(foreground, "\(mode): a block with no foreground of its own")
                }
            }
        }
    }
}
