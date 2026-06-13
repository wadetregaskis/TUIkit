//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorSpacesTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

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
    }
}
