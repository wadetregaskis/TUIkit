//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorDownsamplingTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

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

    /// `Color.downsampled(to:)` reduces a colour to the given
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
        #expect(color.downsampled(to: depth) == expected)
    }
}

// MARK: - foregroundCodes/backgroundCodes with Explicit Depth

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
        #expect(color.foregroundCodes(depth: depth) == codes)
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
        #expect(color.backgroundCodes(depth: depth) == codes)
    }

    /// Bright colors are already 16-color-representable, so their
    /// codes are identical at every (color-capable) depth.
    @Test(
        "Bright foreground codes pass through at all color depths",
        arguments: [ColorDepth.truecolor, .palette256, .basic16])
    func brightForegroundPassthrough(_ depth: ColorDepth) {
        #expect(Color.brightCyan.foregroundCodes(depth: depth) == ["96"])
    }

    @Test(
        "Bright background codes pass through at all color depths",
        arguments: [ColorDepth.truecolor, .palette256, .basic16])
    func brightBackgroundPassthrough(_ depth: ColorDepth) {
        #expect(Color.brightBlue.backgroundCodes(depth: depth) == ["104"])
    }
}

// MARK: - Hue preservation (perceptual quantisation)

@Suite("Palette256 quantisation preserves hue for pale tones")
struct HuePreservingQuantisationTests {

    /// Prints the chosen entries for the shipped pale palette tones.
    @Test("Report: quantisation of the Terminal-profile pale tones")
    func report() {
        let cases: [(String, Color)] = [
            ("SolidColors bg #F2DEC9", .rgb(242, 222, 201)),
            ("SolidColors statusBar #EDD1B4", .rgb(237, 209, 180)),
            ("SolidColors appHeader #E9C8A5", .rgb(233, 200, 165)),
            ("ManPage bg #FEF49C", .rgb(254, 244, 156)),
            ("Novel bg #DFDBC3", .rgb(223, 219, 195)),
            ("SilverAerogel bg #929292", .rgb(146, 146, 146)),
        ]
        for (name, color) in cases {
            if case .palette256(let index) = color.downsampledToPalette256().value {
                let rgb = Color.palette256ToRGB(index)
                print("\(name) -> \(index) (\(rgb.red),\(rgb.green),\(rgb.blue))")
            }
        }
    }

    @Test("Warm cream quantises to a warm cube entry, not pink")
    func creamStaysWarm() {
        // #F2DEC9 (Solid Colors' background): per-channel rounding used to
        // pick (255,215,215) — a pink cast across the whole screen. The warm
        // entry (255,215,175) is the same colour family.
        let quantised = Color.rgb(242, 222, 201).downsampledToPalette256()
        guard case .palette256(let index) = quantised.value else {
            Issue.record("expected a palette256 index")
            return
        }
        let rgb = Color.palette256ToRGB(index)
        #expect(
            rgb.red > rgb.green && rgb.green > rgb.blue,
            "cream keeps its warm channel ordering; got (\(rgb.red),\(rgb.green),\(rgb.blue))")
    }

    /// The Colors page's six-stop rainbow, quantised at 60 cells, used to
    /// contain single-cell washed-out interlopers — `FFAF5F` between `FF8700`
    /// and `FFAF00`, and three more like it. A duller candidate can win on
    /// lightness because the hue term shrinks as a colour approaches the
    /// neutral axis, so the weighting that is meant to keep hues intact does
    /// least where it matters most. The result read as dithering noise in a
    /// ramp that should be smooth.
    @Test("A gradient does not pick up washed-out speckles")
    func gradientHasNoDesaturatedSpeckles() {
        let stops: [Color] = [
            .rgb(255, 0, 0), .rgb(255, 165, 0), .rgb(255, 255, 0),
            .rgb(0, 200, 0), .rgb(0, 100, 255), .rgb(140, 0, 200),
        ]
        let width = 60
        var chroma: [Double] = []
        for cell in 0..<width {
            let t = Double(cell) / Double(width - 1)
            // Piecewise-linear across the stops, as TrackRenderer does.
            let scaled = t * Double(stops.count - 1)
            let index = min(stops.count - 2, Int(scaled))
            let mixed = Color.lerp(stops[index], stops[index + 1], phase: scaled - Double(index))
            let quantised = mixed.downsampledToPalette256()
            guard let (red, green, blue) = quantised.rgbComponents else {
                Issue.record("unresolved at cell \(cell)")
                return
            }
            // Saturation stands in for "did it stay in its family": a speckle is
            // a cell markedly duller than BOTH of its neighbours.
            let maxC = Double(max(red, max(green, blue)))
            let minC = Double(min(red, min(green, blue)))
            chroma.append(maxC <= 0 ? 0 : (maxC - minC) / maxC)
        }
        for cell in 1..<(width - 1) {
            let dip = min(chroma[cell - 1], chroma[cell + 1]) - chroma[cell]
            #expect(
                dip < 0.2,
                "cell \(cell) is a desaturation speckle: \(chroma[cell - 1]) → \(chroma[cell]) → \(chroma[cell + 1])")
        }
    }

    /// A fade runs out of in-family cube entries long before it runs out of
    /// darkness — the 6×6×6 cube's lowest non-zero channel is 0x5F, so olive
    /// has nothing tinted below OKLab L 0.47. The greyscale ramp used to take
    /// over there, so a fading red went red, red, red, GREY, grey, black: a
    /// colour turning neutral partway down, which reads as a glitch. Holding
    /// the darkest in-family entry and then dropping to black gives fewer
    /// steps, all of them the right colour.
    @Test("A fading colour never passes through grey on its way to black")
    func fadeHoldsItsHueThenGoesBlack() {
        for (name, base) in [
            ("error", Color.rgb(220, 50, 47)),
            ("accent", Color.rgb(38, 139, 210)),
            ("success", Color.rgb(133, 153, 0)),
        ] {
            var sawBlack = false
            for step in stride(from: 16, through: 0, by: -1) {
                // `opacity(_:over: .black)` rather than `opacity(_:)`: the fade
                // this is about is the SEQUENCE OF COLOURS a dimming ramp walks
                // through, and since `opacity(_:)` began carrying real alpha it
                // returns the same colour every step with a different alpha —
                // nothing for a downsample to quantise differently. The
                // surface-taking spelling is the one that produces the colours.
                let quantised = base.opacity(Double(step) / 16, over: .black)
                    .downsampledToPalette256()
                guard let (red, green, blue) = quantised.rgbComponents else { continue }
                let isBlack = red == 0 && green == 0 && blue == 0
                if isBlack { sawBlack = true }
                #expect(
                    isBlack || !quantised.isAchromatic,
                    "\(name) at \(step)/16 went grey: (\(red),\(green),\(blue))")
            }
            // …and the fade does reach the bottom rather than stalling on a
            // colour it can never leave.
            #expect(sawBlack, "\(name) never reached black")
        }
    }

    @Test("Greys still take the grayscale ramp")
    func greysUnaffected() {
        let quantised = Color.rgb(146, 146, 146).downsampledToPalette256()
        guard case .palette256(let index) = quantised.value else {
            Issue.record("expected a palette256 index")
            return
        }
        #expect(index >= 232, "mid-grey belongs to the ramp; got \(index)")
    }
}
