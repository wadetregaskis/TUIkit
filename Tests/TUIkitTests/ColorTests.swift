//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ColorTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Color Tests")
struct ColorTests {

    @Test("Hex color converts to correct RGB components")
    func hexColor() {
        let color = Color.hex(0xFF8040)
        #expect(color == Color.rgb(255, 128, 64))
    }

    @Test("Standard and bright colors are distinct")
    func standardVsBright() {
        #expect(Color.red != Color.brightRed)
        #expect(Color.blue != Color.brightBlue)
        #expect(Color.green != Color.brightGreen)
    }

    @Test("RGB colors with different components are distinct")
    func rgbDistinct() {
        #expect(Color.rgb(255, 0, 0) != Color.rgb(0, 255, 0))
        #expect(Color.rgb(0, 0, 255) != Color.rgb(0, 0, 254))
    }

    @Test("Palette colors with different indices are distinct")
    func paletteDistinct() {
        #expect(Color.palette(42) != Color.palette(43))
    }

    @Test("opacity(_:over:) over black matches the mix-toward-black opacity")
    func opacityOverBlackEquivalence() {
        // On a pure-black surface true alpha blending IS the historical
        // multiply-toward-black — dark palettes render byte-identically.
        for value in [0.0, 0.2, 0.45, 0.6, 1.0] {
            let color = Color.rgb(64, 149, 255)
            #expect(color.opacity(value, over: .rgb(0, 0, 0)) == color.opacity(value))
        }
    }

    @Test("opacity(_:over:) fades toward the surface, not black")
    func opacityOverLightSurface() {
        // 20% blue over white: a pale blue, NOT a near-black navy (the
        // dark-on-dark button bug under light palettes).
        let faded = Color.rgb(0, 0, 255).opacity(0.2, over: .rgb(255, 255, 255))
        guard let (red, green, blue) = faded.rgbComponents else {
            Issue.record("unresolved")
            return
        }
        #expect(red >= 200 && green >= 200, "\(faded) should be mostly white")
        #expect(blue == 255)
        // Endpoints: 0 disappears into the surface, 1 is the colour itself.
        #expect(Color.red.opacity(0, over: .rgb(10, 20, 30)) == Color.rgb(10, 20, 30))
        #expect(Color.rgb(1, 2, 3).opacity(1, over: .rgb(255, 255, 255)) == Color.rgb(1, 2, 3))
    }

    @Test("opacity(_:over:) leaves semantic colours unchanged")
    func opacityOverSemanticPassthrough() {
        let semantic = Color.palette.accent
        #expect(semantic.opacity(0.5, over: .rgb(0, 0, 0)) == semantic)
    }

    @Test("lerp at phase 0 returns from color")
    func lerpAtZero() {
        let from = Color.rgb(0, 0, 0)
        let to = Color.rgb(255, 255, 255)
        let result = Color.lerp(from, to, phase: 0)
        #expect(result == from)
    }

    @Test("lerp at phase 1 returns to color")
    func lerpAtOne() {
        let from = Color.rgb(0, 0, 0)
        let to = Color.rgb(255, 255, 255)
        let result = Color.lerp(from, to, phase: 1)
        #expect(result == to)
    }

    @Test("lerp at midpoint produces average")
    func lerpAtMidpoint() {
        let from = Color.rgb(0, 100, 200)
        let to = Color.rgb(100, 200, 50)
        let result = Color.lerp(from, to, phase: 0.5)
        let components = result.rgbComponents!
        #expect(components.red == 50)
        #expect(components.green == 150)
        #expect(components.blue == 125)
    }

    @Test("lerp clamps phase to 0-1 range")
    func lerpClampsPhase() {
        let from = Color.rgb(0, 0, 0)
        let to = Color.rgb(200, 200, 200)
        let underflow = Color.lerp(from, to, phase: -0.5)
        let overflow = Color.lerp(from, to, phase: 1.5)
        #expect(underflow == from)
        #expect(overflow == to)
    }

    @Test("lerp with ANSI colors converts to RGB")
    func lerpWithANSI() {
        let from = Color.black
        let to = Color.white
        let result = Color.lerp(from, to, phase: 0.5)
        // Should produce an RGB color (not crash)
        #expect(result.rgbComponents != nil)
    }
}
