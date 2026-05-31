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

    /// Colors already representable in the 256-color palette
    /// (standard, bright, palette256, semantic) pass through
    /// unchanged.
    @Test(
        "Already-palette256-representable colors pass through unchanged",
        arguments: [
            Color.red, .blue, .black, .white,  // standard
            .brightRed, .brightCyan,  // bright
            .palette(42), .palette(200),  // palette256
            Color.palette.accent,  // semantic
        ])
    func passthrough(_ color: Color) {
        #expect(color.downsampledToPalette256() == color)
    }

    /// RGB colors map to the nearest 256-color cube / grayscale
    /// index. Comments give the index arithmetic
    /// (16 + 36·r + 6·g + b over the cube levels 0/95/135/175/215/255).
    @Test(
        "RGB colors downsample to the nearest palette256 index",
        arguments: [
            (Color.rgb(255, 0, 0), 196),  // pure red: 16 + 36·5
            (Color.rgb(0, 255, 0), 46),  // pure green: 16 + 6·5
            (Color.rgb(0, 0, 255), 21),  // pure blue: 16 + 5
            (Color.rgb(255, 255, 255), 231),  // pure white
            (Color.rgb(0, 0, 0), 16),  // pure black: cube origin
            (Color.rgb(128, 128, 128), 244),  // mid-gray: grayscale ramp beats cube
            (Color.rgb(255, 128, 0), 208),  // orange: r→5, g→135(2), b→0
            (Color.rgb(95, 0, 0), 52),  // near boundary: r→level 1 → 16 + 36·1
            (Color.rgb(135, 175, 215), 110),  // exact cube levels 2,3,4
        ])
    func rgbToNearestIndex(_ input: Color, _ index: Int) {
        #expect(input.downsampledToPalette256() == .palette(UInt8(index)))
    }
}

// MARK: - downsampledToANSI16 Tests

@Suite("Color.downsampledToANSI16")
struct DownsampleToANSI16Tests {

    /// Standard, bright, and semantic colors pass through the
    /// 16-color downsample unchanged.
    @Test(
        "Already-ANSI16-representable colors pass through unchanged",
        arguments: [
            Color.red, .blue, .black,  // standard
            .brightRed, .brightGreen,  // bright
            Color.palette.accent,  // semantic
        ])
    func passthrough(_ color: Color) {
        #expect(color.downsampledToANSI16() == color)
    }

    /// palette256 and RGB colors map to their nearest 16-color ANSI
    /// equivalent. Indices 0–7 → standard, 8–15 → bright, higher
    /// indices and RGB → nearest by distance.
    @Test(
        "palette256 and RGB colors downsample to the nearest ANSI16 color",
        arguments: [
            (Color.palette(0), Color.black),
            (.palette(1), .red),
            (.palette(2), .green),
            (.palette(7), .white),
            (.palette(8), .brightBlack),
            (.palette(9), .brightRed),
            (.palette(14), .brightCyan),
            (.palette(15), .brightWhite),
            (.palette(196), .brightRed),  // pure red (255,0,0)
            (.rgb(255, 0, 0), .brightRed),  // exact bright red
            (.rgb(0, 0, 255), .blue),  // standard blue (0,0,238) closest
            (.rgb(0, 255, 0), .brightGreen),  // exact bright green
            (.rgb(0, 0, 0), .black),
            (.rgb(255, 255, 255), .brightWhite),
            (.rgb(255, 255, 0), .brightYellow),  // exact bright yellow
            (.rgb(200, 0, 0), .red),  // dark red → standard (205,0,0)
            (.rgb(127, 127, 127), .brightBlack),  // gray = bright black
        ])
    func toNearestANSI16(_ input: Color, _ expected: Color) {
        #expect(input.downsampledToANSI16() == expected)
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
        withColorDepth(.palette256) {
            #expect(ColorDepth.current == .palette256)
        }
    }
}

// MARK: - ANSIRenderer Downsample Tests

@MainActor
@Suite("ANSIRenderer.downsample")
struct ANSIRendererDownsampleTests {

    /// `ANSIRenderer.downsample(_:to:)` reduces a color to the given
    /// depth: truecolor and noColor pass everything through (noColor
    /// stripping happens later, in code generation); palette256
    /// downsamples only RGB; basic16 downsamples RGB and palette256.
    @Test(
        "Downsampling a color to a target depth yields the expected color",
        arguments: [
            // truecolor — everything passes through
            (Color.rgb(100, 200, 50), ColorDepth.truecolor, Color.rgb(100, 200, 50)),
            (.palette(42), .truecolor, .palette(42)),
            (.red, .truecolor, .red),
            // palette256 — RGB downsampled, the rest pass through
            (.rgb(255, 0, 0), .palette256, .palette(196)),
            (.palette(42), .palette256, .palette(42)),
            (.red, .palette256, .red),
            (.brightCyan, .palette256, .brightCyan),
            // basic16 — RGB and palette256 downsampled, ANSI passes through
            (.rgb(255, 0, 0), .basic16, .brightRed),
            (.palette(196), .basic16, .brightRed),
            (.red, .basic16, .red),
            (.brightGreen, .basic16, .brightGreen),
            // noColor — passes through (stripped during code generation)
            (.rgb(255, 0, 0), .noColor, .rgb(255, 0, 0)),
        ])
    func downsample(_ color: Color, _ depth: ColorDepth, _ expected: Color) {
        #expect(ANSIRenderer.downsample(color, to: depth) == expected)
    }
}

// MARK: - ANSIRenderer foregroundCodes/backgroundCodes with Explicit Depth

@MainActor
@Suite("ANSIRenderer Color Codes with Explicit Depth")
struct ANSIRendererExplicitDepthTests {

    /// SGR foreground parameter codes for a color at a given depth.
    @Test(
        "Foreground codes match the color and depth",
        arguments: [
            (Color.rgb(100, 200, 50), ColorDepth.truecolor, ["38", "2", "100", "200", "50"]),
            (.palette(42), .truecolor, ["38", "5", "42"]),
            (.red, .truecolor, ["31"]),
            (.rgb(255, 0, 0), .palette256, ["38", "5", "196"]),
            (.rgb(255, 0, 0), .basic16, ["91"]),  // bright red
            (.palette(196), .basic16, ["91"]),
            (.red, .noColor, []),
            (.rgb(255, 0, 0), .noColor, []),
        ])
    func foregroundCodes(_ color: Color, _ depth: ColorDepth, _ codes: [String]) {
        #expect(ANSIRenderer.foregroundCodes(for: color, depth: depth) == codes)
    }

    /// SGR background parameter codes for a color at a given depth.
    @Test(
        "Background codes match the color and depth",
        arguments: [
            (Color.rgb(100, 200, 50), ColorDepth.truecolor, ["48", "2", "100", "200", "50"]),
            (.rgb(0, 255, 0), .palette256, ["48", "5", "46"]),
            (.rgb(0, 255, 0), .basic16, ["102"]),  // bright green bg
            (.blue, .noColor, []),
        ])
    func backgroundCodes(_ color: Color, _ depth: ColorDepth, _ codes: [String]) {
        #expect(ANSIRenderer.backgroundCodes(for: color, depth: depth) == codes)
    }

    /// Bright colors are already 16-color-representable, so their
    /// codes are identical at every (color-capable) depth.
    @Test(
        "Bright foreground codes pass through at all color depths",
        arguments: [ColorDepth.truecolor, .palette256, .basic16])
    func brightForegroundPassthrough(_ depth: ColorDepth) {
        #expect(ANSIRenderer.foregroundCodes(for: .brightCyan, depth: depth) == ["96"])
    }

    @Test(
        "Bright background codes pass through at all color depths",
        arguments: [ColorDepth.truecolor, .palette256, .basic16])
    func brightBackgroundPassthrough(_ depth: ColorDepth) {
        #expect(ANSIRenderer.backgroundCodes(for: .brightBlue, depth: depth) == ["104"])
    }
}
