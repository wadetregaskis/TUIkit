//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorSpacesTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkitStyling

@MainActor
@Suite("Color space conversions")
struct ColorSpacesTests {

    // MARK: - HSL (regression after move to Color+ColorSpaces.swift)

    @Test("HSL primaries resolve to the expected RGB")
    func hslPrimaries() {
        #expect(Color.hsl(0, 100, 50) == .rgb(255, 0, 0))
        #expect(Color.hsl(120, 100, 50) == .rgb(0, 255, 0))
        #expect(Color.hsl(240, 100, 50) == .rgb(0, 0, 255))
        // Lightness 100 is white regardless of hue — the key HSL/HSB difference.
        #expect(Color.hsl(0, 100, 100) == .rgb(255, 255, 255))
    }

    // MARK: - HSB / HSV

    @Test("HSB primaries resolve to the expected RGB")
    func hsbPrimaries() {
        #expect(Color.hsb(0, 100, 100) == .rgb(255, 0, 0))
        #expect(Color.hsb(120, 100, 100) == .rgb(0, 255, 0))
        #expect(Color.hsb(240, 100, 100) == .rgb(0, 0, 255))
        #expect(Color.hsb(60, 100, 100) == .rgb(255, 255, 0))
        #expect(Color.hsb(180, 100, 100) == .rgb(0, 255, 255))
        #expect(Color.hsb(300, 100, 100) == .rgb(255, 0, 255))
    }

    @Test("HSB brightness and saturation extremes")
    func hsbExtremes() {
        // Brightness 100 / saturation 0 is white; HSL lightness 100 is also white,
        // but HSB brightness 100 with full saturation is a vivid hue (above).
        #expect(Color.hsb(0, 0, 100) == .rgb(255, 255, 255))
        // Brightness 0 is black regardless of hue/saturation.
        #expect(Color.hsb(200, 100, 0) == .rgb(0, 0, 0))
        // Saturation 0 is a pure gray at the brightness level.
        #expect(Color.hsb(123, 0, 50) == .rgb(128, 128, 128))
    }

    @Test("rgbToHSB reports the expected components")
    func rgbToHSBKnown() {
        let red = Color.rgbToHSB(red: 255, green: 0, blue: 0)
        #expect(red.hue == 0)
        #expect(red.saturation == 100)
        #expect(red.brightness == 100)

        let gray = Color.rgbToHSB(red: 128, green: 128, blue: 128)
        #expect(gray.saturation == 0)
        #expect(abs(gray.brightness - 50.196) < 0.01)
    }

    @Test("HSB round-trips through RGB exactly for non-gray colors")
    func hsbRoundTrip() {
        for rgb in [(255, 0, 0), (12, 200, 99), (40, 40, 200), (200, 130, 5), (1, 254, 130)] {
            let (r, g, b) = (UInt8(rgb.0), UInt8(rgb.1), UInt8(rgb.2))
            let hsb = Color.rgbToHSB(red: r, green: g, blue: b)
            let back = Color.hsb(hsb.hue, hsb.saturation, hsb.brightness)
            #expect(back == .rgb(r, g, b), "HSB round-trip failed for \(rgb): got \(back)")
        }
    }

    // MARK: - CMYK

    @Test("HSL and HSB report the SAME hue, which is why they share the computation")
    func hslAndHsbAgreeOnHue() {
        // The two models differ in what they call the third axis and in how
        // they derive saturation; they agree exactly about hue. Both carried
        // their own copy of the ten-line sector switch — including the
        // `segment + 6` wrap that keeps red on the positive side of the circle
        // — and nothing compared them. Now one function serves both, and this
        // is what says that was sound.
        let samples: [(UInt8, UInt8, UInt8)] = [
            (255, 0, 0), (0, 255, 0), (0, 0, 255),
            (255, 255, 0), (0, 255, 255), (255, 0, 255),
            (128, 64, 32), (32, 128, 64), (64, 32, 128),
            (200, 200, 100), (17, 250, 3), (3, 17, 250),
            // Just past each sector boundary, where the wrap and the `+2`/`+4`
            // offsets are chosen.
            (255, 1, 0), (255, 0, 1), (1, 255, 0), (0, 255, 1), (1, 0, 255), (0, 1, 255),
        ]
        for (red, green, blue) in samples {
            let hsl = Color.rgbToHSL(red: red, green: green, blue: blue)
            let hsb = Color.rgbToHSB(red: red, green: green, blue: blue)
            #expect(
                abs(hsl.hue - hsb.hue) < 0.000_001,
                "rgb(\(red),\(green),\(blue)): HSL \(hsl.hue) vs HSB \(hsb.hue)")
        }
    }

    @Test("Hue lands in the right sector, including the one that wraps")
    func hueSectors() {
        // The agreement test above cannot catch an error in the computation the
        // two models now SHARE — break it and both move together. So this pins
        // absolute values, one per 60-degree sector, and in particular the
        // magenta sector where `(green - blue) / delta` goes negative and the
        // `+ 6` wrap is what keeps the angle on the circle. Without that wrap
        // magenta reports -60 instead of 300.
        let expected: [(red: UInt8, green: UInt8, blue: UInt8, hue: Double)] = [
            (255, 0, 0, 0),  // red
            (255, 255, 0, 60),  // yellow
            (0, 255, 0, 120),  // green
            (0, 255, 255, 180),  // cyan
            (0, 0, 255, 240),  // blue
            (255, 0, 255, 300),  // magenta — the wrap
            (255, 0, 128, 330),  // rose, mid-wrap
        ]
        for sample in expected {
            let hsl = Color.rgbToHSL(red: sample.red, green: sample.green, blue: sample.blue)
            let hsb = Color.rgbToHSB(red: sample.red, green: sample.green, blue: sample.blue)
            #expect(
                abs(hsl.hue - sample.hue) < 0.5,
                "HSL rgb(\(sample.red),\(sample.green),\(sample.blue)) = \(hsl.hue), want \(sample.hue)")
            #expect(
                abs(hsb.hue - sample.hue) < 0.5,
                "HSB rgb(\(sample.red),\(sample.green),\(sample.blue)) = \(hsb.hue), want \(sample.hue)")
        }
    }

    @Test("A gray has no hue in either model")
    func grayHasNoHue() {
        // Both return 0 before the shared computation is reached; the helper
        // documents that its caller has already established `delta > 0`, so
        // this is the guard that keeps that true.
        for level in [UInt8(0), 1, 128, 254, 255] {
            let hsl = Color.rgbToHSL(red: level, green: level, blue: level)
            let hsb = Color.rgbToHSB(red: level, green: level, blue: level)
            #expect(hsl.hue == 0 && hsb.hue == 0)
            #expect(hsl.saturation == 0 && hsb.saturation == 0)
        }
    }

    @Test("CMYK primaries resolve to the expected RGB")
    func cmykPrimaries() {
        #expect(Color.cmyk(0, 0, 0, 0) == .rgb(255, 255, 255))
        #expect(Color.cmyk(0, 0, 0, 100) == .rgb(0, 0, 0))
        #expect(Color.cmyk(100, 0, 0, 0) == .rgb(0, 255, 255))
        #expect(Color.cmyk(0, 100, 0, 0) == .rgb(255, 0, 255))
        #expect(Color.cmyk(0, 0, 100, 0) == .rgb(255, 255, 0))
    }

    @Test("rgbToCMYK reports the expected components")
    func rgbToCMYKKnown() {
        let black = Color.rgbToCMYK(red: 0, green: 0, blue: 0)
        #expect(black.black == 100)
        #expect(black.cyan == 0 && black.magenta == 0 && black.yellow == 0)

        let white = Color.rgbToCMYK(red: 255, green: 255, blue: 255)
        #expect(white.cyan == 0 && white.magenta == 0 && white.yellow == 0 && white.black == 0)

        let red = Color.rgbToCMYK(red: 255, green: 0, blue: 0)
        #expect(red.cyan == 0)
        #expect(red.magenta == 100)
        #expect(red.yellow == 100)
        #expect(red.black == 0)
    }

    @Test("CMYK round-trips through RGB exactly")
    func cmykRoundTrip() {
        for rgb in [(0, 0, 0), (255, 255, 255), (255, 0, 0), (12, 200, 99), (200, 130, 5), (1, 254, 130)] {
            let (r, g, b) = (UInt8(rgb.0), UInt8(rgb.1), UInt8(rgb.2))
            let cmyk = Color.rgbToCMYK(red: r, green: g, blue: b)
            let back = Color.cmyk(cmyk.cyan, cmyk.magenta, cmyk.yellow, cmyk.black)
            #expect(back == .rgb(r, g, b), "CMYK round-trip failed for \(rgb): got \(back)")
        }
    }

    @Test("Out-of-range components are clamped, not trapped")
    func clampsOutOfRange() {
        // Values past the nominal ranges must not crash the UInt8 conversion.
        #expect(Color.hsb(400, 150, 150).rgbComponents != nil)
        #expect(Color.cmyk(-10, 200, 50, -5).rgbComponents != nil)
        // HSL must be just as robust as HSB/CMYK — both the achromatic
        // (saturation 0) path and the chromatic path.
        #expect(Color.hsl(0, 0, 200).rgbComponents != nil, "achromatic, lightness > 100")
        #expect(Color.hsl(720, 150, 150).rgbComponents != nil, "chromatic, all over range")
        #expect(Color.hsl(-30, -10, -20).rgbComponents != nil, "negative components")
    }

    @Test("Non-finite components are treated as zero, not trapped")
    func handlesNonFinite() {
        // NaN / infinity must never reach a UInt8 conversion unguarded.
        for bad in [Double.nan, .infinity, -.infinity] {
            #expect(Color.hsl(bad, 50, 50).rgbComponents != nil)
            #expect(Color.hsl(180, bad, 50).rgbComponents != nil)
            #expect(Color.hsl(180, 50, bad).rgbComponents != nil)
            #expect(Color.hsb(bad, bad, bad).rgbComponents != nil)
            #expect(Color.cmyk(bad, bad, bad, bad).rgbComponents != nil)
        }
    }
}
