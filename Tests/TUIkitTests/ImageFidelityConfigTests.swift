//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageFidelityConfigTests.swift
//
//  The configurable image-fidelity surface: the wide-Unicode shape set
//  (`.unicodeDetailed` — blocks/quadrants/shades matched by measured ink
//  coverage), caller-supplied luminance ramps (`.customRamp`), the
//  brightness-mapping supersampling factor, and the shape-mode edge-glyph
//  threshold (including disabling edges entirely).
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
        supersampling: Int? = nil, edgeThreshold: Double? = 0.9
    ) -> String {
        ASCIIConverter(
            characterSet: set, colorMode: .mono, dithering: .none,
            supersampling: supersampling, edgeThreshold: edgeThreshold
        )
        .convert(img, width: w, height: h).joined()
    }

    // MARK: - Calibrated glyph tables

    @Test("Every calibrated glyph is single-cell by TUIkit's width tables")
    func calibratedGlyphsAreSingleCell() {
        // The shape renderer appends exactly one glyph per output cell with
        // no width validation at render time, so a double-width entry in the
        // calibration tables would shear every row it appears on. This is
        // the framework-side gate for glyphs added to the candidate sets in
        // Tools/GenerateImageGlyphs.
        for (glyph, _) in generatedShapeCoverage {
            #expect(String(glyph).strippedLength == 1, "'\(glyph)' is not single-cell")
        }
        for (glyph, _) in generatedUnicodeShapeCoverage {
            #expect(String(glyph).strippedLength == 1, "'\(glyph)' is not single-cell")
        }
    }

    @Test("The wide-Unicode table strictly extends the ASCII shape table")
    func unicodeTableExtendsAscii() {
        let ascii = Set(generatedShapeCoverage.map(\.0))
        let unicode = Set(generatedUnicodeShapeCoverage.map(\.0))
        #expect(ascii.isSubset(of: unicode))
        // "Much richer" pinned coarsely, so a regressed regeneration (wrong
        // font, over-aggressive skip list) fails loudly rather than
        // silently shipping a starved matcher.
        #expect(ascii.count >= 90, "full printable ASCII: \(ascii.count)")
        #expect(unicode.count >= 150, "blocks + lines + shapes: \(unicode.count)")
    }

    // MARK: - Report (not an assertion; run with --filter to eyeball the modes)

    @Test("Report: synthetic scene through each shape mode")
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
        for set in [ASCIICharacterSet.shapeBased, .shapeUnicode, .unicodeDetailed] {
            print("== \(set) ==")
            for line in ASCIIConverter(
                characterSet: set, colorMode: .mono, dithering: .none
            ).convert(img, width: 60, height: 15) {
                print(line.stripped)
            }
        }
    }

    // MARK: - .unicodeDetailed

    @Test("A solid dark image renders full blocks")
    func unicodeDetailedSolid() {
        let img = image(50, 30) { _, _ in 0 }
        let out = render(img, w: 10, h: 3, .unicodeDetailed, edgeThreshold: nil)
        #expect(out.contains("█"), "solid ink is a full block, not an ASCII glyph: \(out)")
    }

    @Test("Corner-weighted ink picks quadrant-family glyphs")
    func unicodeDetailedQuadrants() {
        // Dark only in each cell's top-left quadrant (cells are 5×10 px in
        // shape modes). Edge detection off so the coverage match is what's
        // being tested.
        let img = image(50, 30) { x, y in (x % 5 < 2 && y % 10 < 5) ? 0 : 255 }
        let out = render(img, w: 10, h: 3, .unicodeDetailed, edgeThreshold: nil)
        let quadrantFamily = Set("▘▝▖▗▚▞▛▜▙▟▀▄▌▐▍▎▏▉▊▋")
        #expect(
            out.contains(where: { quadrantFamily.contains($0) }),
            "corner-weighted cells pick from the block/quadrant family: \(out)")
    }

    @Test("An even mid-tone picks a mid-coverage glyph, never blank or solid")
    func unicodeDetailedMidTone() {
        // The measured coverages of '▒' and dense ASCII textures like '#'
        // sit close together, so either family is a correct match — what
        // must never happen is the extremes.
        let img = image(50, 30) { _, _ in 128 }
        let out = render(img, w: 10, h: 3, .unicodeDetailed, edgeThreshold: nil)
        #expect(!out.contains(" "), "an even mid-tone is never blank: \(out)")
        #expect(!out.contains("█"), "an even mid-tone is never solid: \(out)")
        let midFamilies = Set("░▒▓#%@*+=")
        #expect(
            out.contains(where: { midFamilies.contains($0) }),
            "an even mid-tone reads as a mid-coverage texture: \(out)")
    }

    @Test("unicodeDetailed edges use box-drawing lines")
    func unicodeDetailedEdges() {
        let img = image(100, 30) { x, _ in x < 47 ? 0 : 255 }
        let out = render(img, w: 20, h: 3, .unicodeDetailed)
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

    @Test("An empty custom ramp falls back to the classic ascii levels")
    func customRampEmpty() {
        // A white image: the fallback ramp's brightest (densest) glyph.
        let img = image(20, 4) { _, _ in 255 }
        let out = render(img, w: 20, h: 4, .customRamp(""))
        #expect(out.contains("@"), "empty ramp falls back to ascii's brightest glyph: \(out)")
    }

    // MARK: - Supersampling

    @Test("Explicit supersampling smooths a checkerboard the 1× path aliases")
    func supersamplingAverages() {
        // A 1-px checkerboard: at 1× each cell reads a single pixel (pure black
        // or white); at 2× each cell averages four pixels to mid-grey — so the
        // two renders MUST differ, and the 2× one must use interior ramp levels.
        let img = image(40, 8) { x, y in (x + y).isMultiple(of: 2) ? 0 : 255 }
        let oneX = render(img, w: 20, h: 4, .ascii, supersampling: 1)
        let twoX = render(img, w: 20, h: 4, .ascii, supersampling: 2)
        #expect(oneX != twoX, "supersampling changes what the cells read")
        let interior = Set(".:;+=xX$")  // everything between the ramp's ends
        #expect(
            twoX.contains(where: { interior.contains($0) }),
            "averaged cells land on interior ramp levels: \(twoX)")
    }

    // MARK: - Edge threshold

    @Test("edgeThreshold nil disables line glyphs (pure coverage matching)")
    func edgeThresholdDisables() {
        let img = image(100, 30) { x, _ in x < 47 ? 0 : 255 }
        let withEdges = render(img, w: 20, h: 3, .shapeUnicode)
        let withoutEdges = render(img, w: 20, h: 3, .shapeUnicode, edgeThreshold: nil)
        #expect(withEdges.contains("│"), "default threshold draws the edge: \(withEdges)")
        #expect(!withoutEdges.contains("│"), "nil threshold never draws line glyphs: \(withoutEdges)")
    }
}
