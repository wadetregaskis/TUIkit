//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorDownsamplingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - downsampledToPalette256 Tests

@Suite("Color.downsampledToPalette256")
struct DownsampleToPalette256Tests {

    @Test("Standard ANSI colors pass through unchanged")
    func standardPassthrough() {
        #expect(Color.red.downsampledToPalette256() == .red)
        #expect(Color.blue.downsampledToPalette256() == .blue)
        #expect(Color.black.downsampledToPalette256() == .black)
        #expect(Color.white.downsampledToPalette256() == .white)
    }

    @Test("Bright ANSI colors pass through unchanged")
    func brightPassthrough() {
        #expect(Color.brightRed.downsampledToPalette256() == .brightRed)
        #expect(Color.brightCyan.downsampledToPalette256() == .brightCyan)
    }

    @Test("Palette256 colors pass through unchanged")
    func palette256Passthrough() {
        #expect(Color.palette(42).downsampledToPalette256() == .palette(42))
        #expect(Color.palette(200).downsampledToPalette256() == .palette(200))
    }

    @Test("Pure red RGB maps to palette red (index 196)")
    func pureRed() {
        let result = Color.rgb(255, 0, 0).downsampledToPalette256()
        // 256-color pure red: 16 + 36*5 + 6*0 + 0 = 196
        #expect(result == .palette(196))
    }

    @Test("Pure green RGB maps to palette green (index 46)")
    func pureGreen() {
        let result = Color.rgb(0, 255, 0).downsampledToPalette256()
        // 16 + 36*0 + 6*5 + 0 = 46
        #expect(result == .palette(46))
    }

    @Test("Pure blue RGB maps to palette blue (index 21)")
    func pureBlue() {
        let result = Color.rgb(0, 0, 255).downsampledToPalette256()
        // 16 + 36*0 + 6*0 + 5 = 21
        #expect(result == .palette(21))
    }

    @Test("Pure white RGB maps to palette white (index 231)")
    func pureWhite() {
        let result = Color.rgb(255, 255, 255).downsampledToPalette256()
        // 16 + 36*5 + 6*5 + 5 = 231
        #expect(result == .palette(231))
    }

    @Test("Pure black RGB maps to cube origin (index 16)")
    func pureBlack() {
        let result = Color.rgb(0, 0, 0).downsampledToPalette256()
        // Cube index 16 is (0,0,0) — exact match, distance = 0
        #expect(result == .palette(16))
    }

    @Test("Mid-gray RGB prefers grayscale ramp over cube")
    func midGray() {
        // 128,128,128 — grayscale 244 has value 128 (exact),
        // cube 102 has (135,135,135)
        let result = Color.rgb(128, 128, 128).downsampledToPalette256()
        #expect(result == .palette(244))
    }

    @Test("Orange RGB maps to nearest cube entry")
    func orangeRGB() {
        let result = Color.rgb(255, 128, 0).downsampledToPalette256()
        // r=255→5, g=128→nearest is 135(index 2), b=0→0
        // Index: 16 + 36*5 + 6*2 + 0 = 208
        #expect(result == .palette(208))
    }

    @Test("Semantic colors pass through unchanged")
    func semanticPassthrough() {
        let semantic = Color.palette.accent
        #expect(semantic.downsampledToPalette256() == semantic)
    }

    @Test("Near-cube-boundary colors quantize correctly")
    func nearBoundary() {
        // Channel value 115 is equidistant between 95 (level 1) and 135 (level 2)
        // but closer to 95 by 20 vs 135 by 20 — should pick 95 (first found)
        let result = Color.rgb(95, 0, 0).downsampledToPalette256()
        // r=95→level 1, g=0→0, b=0→0 → index 16 + 36*1 = 52
        #expect(result == .palette(52))
    }

    @Test("Exact cube channel values map directly")
    func exactCubeValues() {
        // All six cube levels: 0, 95, 135, 175, 215, 255
        let r135g175b215 = Color.rgb(135, 175, 215).downsampledToPalette256()
        // r=2, g=3, b=4 → 16 + 36*2 + 6*3 + 4 = 16 + 72 + 18 + 4 = 110
        #expect(r135g175b215 == .palette(110))
    }
}

// MARK: - downsampledToANSI16 Tests

@Suite("Color.downsampledToANSI16")
struct DownsampleToANSI16Tests {

    @Test("Standard ANSI colors pass through unchanged")
    func standardPassthrough() {
        #expect(Color.red.downsampledToANSI16() == .red)
        #expect(Color.blue.downsampledToANSI16() == .blue)
        #expect(Color.black.downsampledToANSI16() == .black)
    }

    @Test("Bright ANSI colors pass through unchanged")
    func brightPassthrough() {
        #expect(Color.brightRed.downsampledToANSI16() == .brightRed)
        #expect(Color.brightGreen.downsampledToANSI16() == .brightGreen)
    }

    @Test("Palette256 indices 0-7 map to standard ANSI colors")
    func palette256StandardRange() {
        #expect(Color.palette(0).downsampledToANSI16() == .black)
        #expect(Color.palette(1).downsampledToANSI16() == .red)
        #expect(Color.palette(2).downsampledToANSI16() == .green)
        #expect(Color.palette(7).downsampledToANSI16() == .white)
    }

    @Test("Palette256 indices 8-15 map to bright ANSI colors")
    func palette256BrightRange() {
        #expect(Color.palette(8).downsampledToANSI16() == .brightBlack)
        #expect(Color.palette(9).downsampledToANSI16() == .brightRed)
        #expect(Color.palette(14).downsampledToANSI16() == .brightCyan)
        #expect(Color.palette(15).downsampledToANSI16() == .brightWhite)
    }

    @Test("Palette256 higher indices map to nearest ANSI color")
    func palette256HigherIndices() {
        // Index 196 = pure red (255,0,0) → should match bright red
        let result = Color.palette(196).downsampledToANSI16()
        #expect(result == .brightRed)
    }

    @Test("Pure RGB red maps to nearest ANSI red")
    func pureRGBRed() {
        let result = Color.rgb(255, 0, 0).downsampledToANSI16()
        // Bright red is (255, 0, 0) — exact match
        #expect(result == .brightRed)
    }

    @Test("Pure RGB blue maps to nearest ANSI blue")
    func pureRGBBlue() {
        let result = Color.rgb(0, 0, 255).downsampledToANSI16()
        // Standard blue (0, 0, 238) is closest
        #expect(result == .blue)
    }

    @Test("Pure RGB green maps to nearest ANSI green")
    func pureRGBGreen() {
        let result = Color.rgb(0, 255, 0).downsampledToANSI16()
        // Bright green is (0, 255, 0) — exact match
        #expect(result == .brightGreen)
    }

    @Test("RGB black maps to ANSI black")
    func rgbBlack() {
        let result = Color.rgb(0, 0, 0).downsampledToANSI16()
        #expect(result == .black)
    }

    @Test("RGB white maps to ANSI bright white")
    func rgbWhite() {
        let result = Color.rgb(255, 255, 255).downsampledToANSI16()
        #expect(result == .brightWhite)
    }

    @Test("Semantic colors pass through unchanged")
    func semanticPassthrough() {
        let semantic = Color.palette.accent
        #expect(semantic.downsampledToANSI16() == semantic)
    }

    @Test("RGB yellow maps to nearest ANSI yellow")
    func rgbYellow() {
        let result = Color.rgb(255, 255, 0).downsampledToANSI16()
        // Bright yellow is (255, 255, 0) — exact match
        #expect(result == .brightYellow)
    }

    @Test("Dark red maps to standard ANSI red, not bright")
    func darkRed() {
        let result = Color.rgb(200, 0, 0).downsampledToANSI16()
        // Standard red is (205, 0, 0) — very close
        #expect(result == .red)
    }

    @Test("Gray maps to bright black (gray)")
    func gray() {
        let result = Color.rgb(127, 127, 127).downsampledToANSI16()
        // Bright black is (127, 127, 127) — exact match
        #expect(result == .brightBlack)
    }
}

// MARK: - ColorDepth Tests

@Suite("ColorDepth")
struct ColorDepthTests {

    @Test("Cases are ordered by capability")
    func ordering() {
        #expect(ColorDepth.noColor < .basic16)
        #expect(ColorDepth.basic16 < .palette256)
        #expect(ColorDepth.palette256 < .truecolor)
    }

    @Test("Comparable conformance works")
    func comparable() {
        #expect(ColorDepth.noColor <= .noColor)
        #expect(ColorDepth.basic16 >= .basic16)
        #expect(ColorDepth.truecolor > .palette256)
    }

    @Test("Current is settable for override")
    func settable() {
        let saved = ColorDepth.current
        defer { ColorDepth.current = saved }
        ColorDepth.current = .palette256
        #expect(ColorDepth.current == .palette256)
    }
}

// MARK: - ANSIRenderer Downsample Tests

@MainActor
@Suite("ANSIRenderer.downsample")
struct ANSIRendererDownsampleTests {

    // MARK: - Truecolor depth

    @Test("At truecolor, RGB passes through")
    func truecolorRGB() {
        let color = Color.rgb(100, 200, 50)
        let result = ANSIRenderer.downsample(color, to: .truecolor)
        #expect(result == color)
    }

    @Test("At truecolor, palette256 passes through")
    func truecolorPalette() {
        let color = Color.palette(42)
        let result = ANSIRenderer.downsample(color, to: .truecolor)
        #expect(result == color)
    }

    @Test("At truecolor, standard passes through")
    func truecolorStandard() {
        let result = ANSIRenderer.downsample(.red, to: .truecolor)
        #expect(result == .red)
    }

    // MARK: - 256-color depth

    @Test("At palette256, RGB is downsampled")
    func palette256RGB() {
        let result = ANSIRenderer.downsample(.rgb(255, 0, 0), to: .palette256)
        #expect(result == .palette(196))
    }

    @Test("At palette256, palette256 passes through")
    func palette256Palette() {
        let result = ANSIRenderer.downsample(.palette(42), to: .palette256)
        #expect(result == .palette(42))
    }

    @Test("At palette256, standard passes through")
    func palette256Standard() {
        let result = ANSIRenderer.downsample(.red, to: .palette256)
        #expect(result == .red)
    }

    @Test("At palette256, bright passes through")
    func palette256Bright() {
        let result = ANSIRenderer.downsample(.brightCyan, to: .palette256)
        #expect(result == .brightCyan)
    }

    // MARK: - 16-color depth

    @Test("At basic16, RGB is downsampled to ANSI")
    func basic16RGB() {
        let result = ANSIRenderer.downsample(.rgb(255, 0, 0), to: .basic16)
        #expect(result == .brightRed)
    }

    @Test("At basic16, palette256 is downsampled to ANSI")
    func basic16Palette() {
        let result = ANSIRenderer.downsample(.palette(196), to: .basic16)
        #expect(result == .brightRed)
    }

    @Test("At basic16, standard passes through")
    func basic16Standard() {
        let result = ANSIRenderer.downsample(.red, to: .basic16)
        #expect(result == .red)
    }

    @Test("At basic16, bright passes through")
    func basic16Bright() {
        let result = ANSIRenderer.downsample(.brightGreen, to: .basic16)
        #expect(result == .brightGreen)
    }

    // MARK: - noColor depth

    @Test("At noColor, colors pass through (stripping happens in code generation)")
    func noColorPassthrough() {
        let result = ANSIRenderer.downsample(.rgb(255, 0, 0), to: .noColor)
        #expect(result == .rgb(255, 0, 0))
    }
}

// MARK: - ANSIRenderer foregroundCodes/backgroundCodes with Explicit Depth

@MainActor
@Suite("ANSIRenderer Color Codes with Explicit Depth")
struct ANSIRendererExplicitDepthTests {

    // MARK: - Foreground codes

    @Test("Foreground codes at truecolor emit 38;2;r;g;b for RGB")
    func fgTruecolorRGB() {
        let codes = ANSIRenderer.foregroundCodes(for: .rgb(100, 200, 50), depth: .truecolor)
        #expect(codes == ["38", "2", "100", "200", "50"])
    }

    @Test("Foreground codes at truecolor emit 38;5;n for palette256")
    func fgTruecolorPalette() {
        let codes = ANSIRenderer.foregroundCodes(for: .palette(42), depth: .truecolor)
        #expect(codes == ["38", "5", "42"])
    }

    @Test("Foreground codes at truecolor emit standard code for ANSI color")
    func fgTruecolorStandard() {
        let codes = ANSIRenderer.foregroundCodes(for: .red, depth: .truecolor)
        #expect(codes == ["31"])
    }

    @Test("Foreground codes at palette256 downsamples RGB to 38;5;n")
    func fgPalette256RGB() {
        let codes = ANSIRenderer.foregroundCodes(for: .rgb(255, 0, 0), depth: .palette256)
        #expect(codes == ["38", "5", "196"])
    }

    @Test("Foreground codes at basic16 downsamples RGB to standard code")
    func fgBasic16RGB() {
        let codes = ANSIRenderer.foregroundCodes(for: .rgb(255, 0, 0), depth: .basic16)
        // Bright red = SGR 91
        #expect(codes == ["91"])
    }

    @Test("Foreground codes at basic16 downsamples palette256 to standard code")
    func fgBasic16Palette() {
        let codes = ANSIRenderer.foregroundCodes(for: .palette(196), depth: .basic16)
        #expect(codes == ["91"])
    }

    @Test("Foreground codes at noColor returns empty")
    func fgNoColor() {
        let codes = ANSIRenderer.foregroundCodes(for: .red, depth: .noColor)
        #expect(codes.isEmpty)
    }

    @Test("Foreground codes at noColor returns empty for RGB")
    func fgNoColorRGB() {
        let codes = ANSIRenderer.foregroundCodes(for: .rgb(255, 0, 0), depth: .noColor)
        #expect(codes.isEmpty)
    }

    // MARK: - Background codes

    @Test("Background codes at truecolor emit 48;2;r;g;b for RGB")
    func bgTruecolorRGB() {
        let codes = ANSIRenderer.backgroundCodes(for: .rgb(100, 200, 50), depth: .truecolor)
        #expect(codes == ["48", "2", "100", "200", "50"])
    }

    @Test("Background codes at palette256 downsamples RGB to 48;5;n")
    func bgPalette256RGB() {
        let codes = ANSIRenderer.backgroundCodes(for: .rgb(0, 255, 0), depth: .palette256)
        #expect(codes == ["48", "5", "46"])
    }

    @Test("Background codes at basic16 downsamples RGB to standard code")
    func bgBasic16RGB() {
        let codes = ANSIRenderer.backgroundCodes(for: .rgb(0, 255, 0), depth: .basic16)
        // Bright green background = SGR 102
        #expect(codes == ["102"])
    }

    @Test("Background codes at noColor returns empty")
    func bgNoColor() {
        let codes = ANSIRenderer.backgroundCodes(for: .blue, depth: .noColor)
        #expect(codes.isEmpty)
    }

    // MARK: - Bright colors

    @Test("Bright foreground codes pass through at all depths")
    func brightFgPassthrough() {
        for depth: ColorDepth in [.truecolor, .palette256, .basic16] {
            let codes = ANSIRenderer.foregroundCodes(for: .brightCyan, depth: depth)
            #expect(codes == ["96"])
        }
    }

    @Test("Bright background codes pass through at all depths")
    func brightBgPassthrough() {
        for depth: ColorDepth in [.truecolor, .palette256, .basic16] {
            let codes = ANSIRenderer.backgroundCodes(for: .brightBlue, depth: depth)
            #expect(codes == ["104"])
        }
    }
}
