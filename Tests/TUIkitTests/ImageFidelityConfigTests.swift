//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageFidelityConfigTests.swift
//
//  The configurable image-fidelity surface: the fundamental charsets under
//  shape-aware matching (blocks/quadrants/shades matched by measured ink
//  coverage; unicode's box-drawing edges), caller-supplied luminance ramps
//  (`.customRamp`), the luminance-renderer supersampling factor, and the
//  shape-mode edge-glyph threshold (including disabling edges entirely).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitImage

@MainActor
@Suite("Image fidelity configuration")
struct ImageFidelityConfigTests {

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

    private func render(
        _ img: RGBAImage, w: Int, h: Int, _ set: ASCIICharacterSet,
        shapeAware: Bool = false,
        supersampling: Int? = nil, edgeThreshold: Double? = 0.9
    ) -> String {
        ASCIIConverter(
            characterSet: set, shapeAware: shapeAware, colorMode: .mono, dithering: .none,
            supersampling: supersampling, edgeThreshold: edgeThreshold
        )
        .convert(img, width: w, height: h).joined()
    }

    /// Like `render` but in true colour (pinned to a truecolor terminal), for
    /// asserting the exact per-cell RGB the block modes emit.
    private func renderColor(
        _ img: RGBAImage, w: Int, h: Int, _ set: ASCIICharacterSet,
        supersampling: Int? = nil
    ) -> String {
        withColorDepth(.truecolor) {
            ASCIIConverter(
                characterSet: set, colorMode: .trueColor, dithering: .none,
                supersampling: supersampling
            )
            .convert(img, width: w, height: h).joined()
        }
    }

    // MARK: - Report (not an assertion; run with --filter to eyeball the modes)

    @Test("Report: synthetic scene through each shape-aware charset")
    func shapeModeReport() {
        // A ball (curved edges), a diagonal bar, and a horizontal gradient —
        // the three features the shape matcher exists for.
        let img = image(240, 120) { x, y in
            let dx = Double(x - 60) / 45.0
            let dy = Double(y - 60) / 45.0
            if dx * dx + dy * dy < 1.0 { return 0 }
            if abs((x - 120) - (y * 2 - 120)) < 14 && x > 100 && x < 200 { return 40 }
            return x > 160 ? UInt8(min(255, (x - 160) * 3)) : 255
        }
        for set in [ASCIICharacterSet.ascii, .unicode, .blocks(.half)] {
            print("== \(set) shape-aware ==")
            for line in ASCIIConverter(
                characterSet: set, shapeAware: true, colorMode: .mono, dithering: .none
            ).convert(img, width: 60, height: 15) {
                print(line.stripped)
            }
        }
    }

    // MARK: - Shape-aware blocks

    @Test("A solid dark image renders full blocks")
    func blocksShapeSolid() {
        let img = image(50, 30) { _, _ in 0 }
        let out = render(img, w: 10, h: 3, .blocks(.half), shapeAware: true, edgeThreshold: nil)
        #expect(out.contains("█"), "solid ink is a full block: \(out)")
    }

    @Test("Corner-weighted ink picks quadrant-family glyphs")
    func blocksShapeQuadrants() {
        // Dark only in each cell's top-left quadrant (cells are 5×10 px in
        // shape modes). Edge detection is moot for blocks (the repertoire
        // carries its own directional glyphs).
        let img = image(50, 30) { x, y in (x % 5 < 2 && y % 10 < 5) ? 0 : 255 }
        let out = render(img, w: 10, h: 3, .blocks(.half), shapeAware: true)
        let quadrantFamily = Set("▘▝▖▗▚▞▛▜▙▟▀▄▌▐▍▎▏▉▊▋◢◣◤◥")
        #expect(
            out.contains(where: { quadrantFamily.contains($0) }),
            "corner-weighted cells pick from the block/quadrant family: \(out)")
    }

    @Test("An even mid-tone picks a shade, never blank or solid")
    func blocksShapeMidTone() {
        let img = image(50, 30) { _, _ in 128 }
        let out = render(img, w: 10, h: 3, .blocks(.half), shapeAware: true)
        #expect(!out.contains(" "), "an even mid-tone is never blank: \(out)")
        #expect(!out.contains("█"), "an even mid-tone is never solid: \(out)")
        #expect(
            out.contains(where: { Set("░▒▓").contains($0) }),
            "an even mid-tone reads as a shade: \(out)")
    }

    @Test("Shape-aware blocks differ from luminance blocks (the resolution is unused)")
    func blocksShapeIgnoresResolution() {
        // A corner-weighted image: the shape matcher picks quadrants; the
        // luminance `.coarse` path can only pick shades — so the two must
        // differ, and every `.blocks(_)` resolution shape-matches identically.
        let img = image(50, 30) { x, y in (x % 5 < 2 && y % 10 < 5) ? 0 : 255 }
        let shaped = render(img, w: 10, h: 3, .blocks(.half), shapeAware: true)
        let shapedCoarse = render(img, w: 10, h: 3, .blocks(.coarse), shapeAware: true)
        let luminance = render(img, w: 10, h: 3, .blocks(.coarse))
        #expect(shaped == shapedCoarse, "shape-aware blocks ignore the resolution")
        #expect(shaped != luminance, "shape matching is not the luminance path")
    }

    // MARK: - Shape-aware unicode

    @Test("The unicode charset excludes Block Elements even when shape-aware")
    func unicodeExcludesBlocks() {
        // Solid ink: the blocks charset answers with █; unicode must answer
        // with its own densest non-block glyph instead.
        let img = image(50, 30) { _, _ in 0 }
        let out = render(img, w: 10, h: 3, .unicode, shapeAware: true, edgeThreshold: nil)
        #expect(!out.isEmpty)
        #expect(
            !out.contains(where: { GlyphRepertoire.isBlockElement($0) }),
            "no Block Elements in the unicode charset: \(out)")
    }

    @Test("Shape-aware unicode edges use box-drawing lines")
    func unicodeShapeEdges() {
        let img = image(100, 30) { x, _ in x < 47 ? 0 : 255 }
        let out = render(img, w: 20, h: 3, .unicode, shapeAware: true)
        #expect(out.contains("│"), "a vertical edge uses '│': \(out)")
    }

    // MARK: - .customRamp

    @Test("A custom ramp's glyphs are used, in luminance order")
    func customRamp() {
        // Left half black, right half white, two-level ramp ordered darkest →
        // brightest: black cells '.', white cells 'X'.
        let img = image(20, 4) { x, _ in x < 10 ? 0 : 255 }
        let lines = ASCIIConverter(
            characterSet: .customRamp(".X"), colorMode: .mono, dithering: .none
        ).convert(img, width: 20, height: 4)
        let out = lines.joined()
        #expect(lines.allSatisfy { $0.hasPrefix(".") }, "black maps to the FIRST ramp glyph: \(out)")
        #expect(lines.allSatisfy { $0.hasSuffix("X") }, "white maps to the LAST ramp glyph: \(out)")
        #expect(
            !out.contains(where: { !".X".contains($0) }),
            "no glyphs outside the supplied ramp: \(out)")
    }

    @Test("An empty custom ramp falls back to a 10-level calibrated ASCII ramp")
    func customRampEmpty() {
        // A white image: the fallback ramp's brightest (densest) glyph.
        let img = image(20, 4) { _, _ in 255 }
        let out = render(img, w: 20, h: 4, .customRamp(""))
        let fallback = GlyphRepertoire.densityRamp(from: GlyphRepertoire.ascii, count: 10)
        #expect(
            out.contains(fallback.last!),
            "empty ramp falls back to the calibrated ramp's brightest glyph: \(out)")
    }

    @Test("A custom ramp is always luminance-mapped — shape-awareness does not apply")
    func customRampIgnoresShape() {
        let img = image(50, 30) { x, y in (x % 5 < 2 && y % 10 < 5) ? 0 : 255 }
        let plain = render(img, w: 10, h: 3, .customRamp(" .oO@"))
        let shaped = render(img, w: 10, h: 3, .customRamp(" .oO@"), shapeAware: true)
        #expect(plain == shaped, "shapeAware is a no-op for custom ramps")
    }

    // MARK: - Supersampling

    @Test("Explicit supersampling smooths a checkerboard the 1× path aliases")
    func supersamplingAverages() {
        // A 1-px checkerboard: at 1× each cell reads a single pixel (pure black
        // or white); at 2× each cell averages four pixels to mid-grey — so the
        // two renders MUST differ, and the 2× one must use interior ramp levels.
        let img = image(40, 8) { x, y in (x + y).isMultiple(of: 2) ? 0 : 255 }
        let ramp = GlyphRepertoire.densityRamp(from: GlyphRepertoire.ascii, count: 10)
        let oneX = render(img, w: 20, h: 4, .ascii(glyphs: 10), supersampling: 1)
        let twoX = render(img, w: 20, h: 4, .ascii(glyphs: 10), supersampling: 2)
        #expect(oneX != twoX, "supersampling changes what the cells read")
        let interior = Set(ramp.dropFirst().dropLast())
        #expect(
            twoX.contains(where: { interior.contains($0) }),
            "averaged cells land on interior ramp levels: \(twoX)")
    }

    @Test("Solid blocks supersample: point-sampled checkerboard becomes area-averaged grey")
    func solidSupersamplingAverages() {
        // A 1-px checkerboard downscaled 2:1. At 1× the bilinear scaler's
        // sample points land exactly on even source coordinates — pure
        // point sampling, every cell reads black. At 2× each cell averages
        // its 2×2 source block to mid-grey.
        let img = image(40, 8) { x, y in (x + y).isMultiple(of: 2) ? 0 : 255 }
        let oneX = renderColor(img, w: 20, h: 4, .blocks(.solid), supersampling: 1)
        let twoX = renderColor(img, w: 20, h: 4, .blocks(.solid), supersampling: 2)
        #expect(oneX != twoX, "supersampling changes what the cells read")
        #expect(oneX.contains("48;2;0;0;0"), "1× point-samples the black pixels: \(oneX)")
        #expect(twoX.contains("48;2;127;127;127"), "2× area-averages to mid-grey: \(twoX)")
        #expect(!twoX.contains("48;2;0;0;0"), "no aliased solid-black cells at 2×: \(twoX)")
    }

    @Test("Half blocks supersample: each sub-cell pixel is area-averaged")
    func halfBlocksSupersamplingAverages() {
        // Same checkerboard; the half-block mode reads two pixels per cell
        // (top = background, bottom = foreground), each of which must be an
        // area average at 2× rather than an aliased point read.
        let img = image(40, 16) { x, y in (x + y).isMultiple(of: 2) ? 0 : 255 }
        let oneX = renderColor(img, w: 20, h: 4, .blocks(.half), supersampling: 1)
        let twoX = renderColor(img, w: 20, h: 4, .blocks(.half), supersampling: 2)
        #expect(oneX != twoX, "supersampling changes what the sub-pixels read")
        #expect(twoX.contains("2;127;127;127"), "2× sub-pixels average to mid-grey: \(twoX)")
    }

    @Test("Braille supersamples per dot: sparse texture thresholds from the average")
    func brailleSupersamplingAverages() {
        // One black pixel per 2×2 tile, sitting exactly on the even source
        // coordinates the 1× scaler point-samples — so at 1× every braille
        // dot reads black and switches OFF (dots mark bright pixels, like
        // the ramp convention), while at 2× each dot averages its tile to
        // 191 (light) and switches ON. The image is 75% white either way;
        // only area averaging sees that.
        let img = image(80, 32) { x, y in (x.isMultiple(of: 2) && y.isMultiple(of: 2)) ? 0 : 255 }
        let oneX = render(img, w: 20, h: 4, .blocks(.braille), supersampling: 1)
        let twoX = render(img, w: 20, h: 4, .blocks(.braille), supersampling: 2)
        #expect(!oneX.contains("⣿"), "1× aliases every dot to the black point samples: \(oneX)")
        #expect(twoX.contains("⣿"), "2× thresholds each dot from its area average: \(twoX)")
    }

    // MARK: - Edge threshold

    @Test("edgeThreshold nil disables line glyphs (pure coverage matching)")
    func edgeThresholdDisables() {
        let img = image(100, 30) { x, _ in x < 47 ? 0 : 255 }
        let withEdges = render(img, w: 20, h: 3, .unicode, shapeAware: true)
        let withoutEdges = render(
            img, w: 20, h: 3, .unicode, shapeAware: true, edgeThreshold: nil)
        #expect(withEdges.contains("│"), "default threshold draws the edge: \(withEdges)")
        #expect(!withoutEdges.contains("│"), "nil threshold never draws line glyphs: \(withoutEdges)")
    }
}
