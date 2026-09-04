//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FadePerceptualEvennessTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitStyling

/// A fade has to LOOK like equal steps, which is a claim about the space the
/// blend happens in and nothing else.
///
/// Every other opacity test computes its expectation by calling the same blend
/// the code calls, so between them they pin which colour mixes with which
/// surface and none of them can see the space it mixes in. This is the one that
/// can: it asks how much RENDERED LIGHTNESS moves per unit of opacity at the two
/// ends of the range, which is a property of the arithmetic rather than of any
/// particular call.
///
/// The reason to have it is that the answer was 22× once, and the way you find
/// out is a bouncy spring transition looking asymmetric — a long way from the
/// line that decides it.
@MainActor
@Suite("A fade is perceptually even")
struct FadePerceptualEvennessTests {

    private let surface = Color.rgb(5, 10, 5)
    private let ink = Color.rgb(102, 255, 102)

    private func lightness(_ colour: Color) -> Double {
        guard let rgb = colour.rgbComponents else { return 0 }
        return Color.oklab(red: rgb.red, green: rgb.green, blue: rgb.blue).l
    }

    /// How far the rendered lightness moves for a 1% step of opacity at `alpha`.
    private func sensitivity(at alpha: Double) -> Double {
        abs(lightness(ink.opacity(alpha + 0.01, over: surface))
            - lightness(ink.opacity(alpha, over: surface))) / 0.01
    }

    @Test("A step of opacity moves the same amount of lightness at either end")
    func theRangeIsEven() {
        let transparent = sensitivity(at: 0)
        let opaque = sensitivity(at: 0.99)
        // Encoded sRGB is near enough perceptually uniform: measured 1.66.
        // Linear light — physically correct, and what this used to do — is 22.2,
        // because perceived lightness goes as the cube root of luminance and
        // almost all of the visible movement lands in the first few percent.
        #expect(
            transparent / opaque < 3,
            "the fade is \(transparent / opaque)× more sensitive near transparent, so the blend has gone back to linear light")
    }

    @Test("A spring's two directions bounce by comparable amounts")
    func insertionAndRemovalAgree() {
        // A transition plays the same oscillation either way — insertion phase
        // is `fraction`, removal is `1 - fraction` — so the excursions are
        // exactly symmetric in ALPHA by construction. What is NOT guaranteed is
        // that they look it, and that is what this measures.
        let spring = Animation.spring(duration: 0.6, bounce: 0.9)
        let full = lightness(ink)
        let empty = lightness(surface)
        var worst = 1.0
        for step in 1...4 {
            let fraction = spring.fraction(at: 0.603 * Double(step))
            // Past the first arrival, which is where the overshoot lives.
            guard fraction > 0.3 else { continue }
            let arriving = abs(full - lightness(ink.opacity(min(1, fraction), over: surface)))
            let leaving = abs(empty - lightness(ink.opacity(max(0, 1 - fraction), over: surface)))
            guard arriving > 1e-6 else { continue }
            worst = max(worst, leaving / arriving)
        }
        // Measured 1.20 / 1.33 / 1.42 / 1.49 encoded; 2.94 / 4.78 / 7.08 / 10.52
        // in linear light, which is the asymmetry a person actually reported.
        #expect(worst < 2, "the fade-out bounces \(worst)× as hard as the fade-in")
    }
}
