//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ShapeEdgeOrientationTests.swift
//
//  The shape-aware renderer detects a strong directional edge in each cell
//  (via a Sobel-style gradient over its six sampling regions) and draws it
//  with the orientation-matched line glyph; the edge style follows the
//  charset — ASCII slashes for `.ascii`, box-drawing for `.unicode`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitImage

@MainActor
@Suite("shape edge orientation")
struct ShapeEdgeOrientationTests {
    /// Builds an image where each pixel's grey level is `value(x, y)` (0…255).
    private func image(_ width: Int, _ height: Int, _ value: (Int, Int) -> UInt8) -> RGBAImage {
        var pixels = [RGBA]()
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let v = value(x, y)
                pixels.append(RGBA(r: v, g: v, b: v))
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    private func render(_ img: RGBAImage, w: Int, h: Int, _ set: ASCIICharacterSet) -> String {
        ASCIIConverter(characterSet: set, shapeAware: true, colorMode: .mono, dithering: .none)
            .convert(img, width: w, height: h).joined()
    }

    @Test("A vertical light/dark boundary renders vertical line glyphs")
    func verticalEdge() {
        // A vertical step placed mid-cell (px 47, inside the 45–49 cell at 5px
        // per cell) so a column of cells straddles it → strong horizontal
        // gradient → '|'.
        let img = image(100, 30) { x, _ in x < 47 ? 0 : 255 }
        let ascii = render(img, w: 20, h: 3, .ascii)
        #expect(ascii.contains("|"), "a vertical edge picks '|': \(ascii)")

        let unicode = render(img, w: 20, h: 3, .unicode)
        #expect(unicode.contains("│"), "the unicode charset uses '│' for a vertical edge: \(unicode)")
        #expect(!unicode.contains("|"), "the unicode charset uses box-drawing, not ASCII '|'")
    }

    @Test("A horizontal boundary renders horizontal line glyphs")
    func horizontalEdge() {
        // A horizontal step placed mid-cell (px 27, inside the 20–29 row cell at
        // 10px per cell) so a row of cells straddles it → '-'.
        let img = image(90, 60) { _, y in y < 27 ? 0 : 255 }
        let ascii = render(img, w: 18, h: 6, .ascii)
        #expect(ascii.contains("-"), "a horizontal edge picks '-': \(ascii)")

        let unicode = render(img, w: 18, h: 6, .unicode)
        #expect(unicode.contains("─"), "the unicode charset uses '─' for a horizontal edge: \(unicode)")
    }

    @Test("A diagonal boundary renders a slash glyph")
    func diagonalEdge() {
        // Dark below the y = x line, light above → a "/" edge (bottom-left dark).
        let img = image(90, 90) { x, y in y > x ? 0 : 255 }
        let ascii = render(img, w: 18, h: 9, .ascii)
        #expect(ascii.contains("/") || ascii.contains("\\"), "a diagonal edge picks a slash: \(ascii)")

        let unicode = render(img, w: 18, h: 9, .unicode)
        #expect(
            unicode.contains("╱") || unicode.contains("╲"),
            "the unicode charset uses box-drawing diagonals: \(unicode)")
    }

    @Test("A flat cell carries no edge — it falls back to the coverage match")
    func flatCellNoEdge() {
        // A uniform mid-grey field has no gradient anywhere, so no line glyphs
        // are forced; the coverage match fills it.
        let img = image(90, 30) { _, _ in 128 }
        let ascii = render(img, w: 18, h: 3, .ascii)
        #expect(!ascii.contains("|"), "a flat field forces no vertical lines: \(ascii)")
        #expect(!ascii.contains("/"), "a flat field forces no diagonals: \(ascii)")
    }
}
