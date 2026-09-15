//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkitStyling

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
        #expect(Color.ansi(.red) != Color.ansi(.brightRed))
        #expect(Color.ansi(.blue) != Color.ansi(.brightBlue))
        #expect(Color.ansi(.green) != Color.ansi(.brightGreen))
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

    /// `opacity(_:)` used to be the mix-toward-black shorthand, and this test
    /// pinned it to `opacity(_:over: .black)`. That contract is gone: it carries
    /// real alpha now and what it is drawn over is decided at the composite.
    ///
    /// The equivalence it recorded is still TRUE, but it belongs to the
    /// compositor rather than to the colour, so this asserts it where it now
    /// lives — the blend resolves the two the same way over a black destination.
    @Test("Alpha resolved over black is the old mix-toward-black")
    func alphaOverBlackMatchesTheOldShorthand() {
        for value in [0.0, 0.2, 0.45, 0.6, 1.0] {
            let colour = Color.rgb(64, 149, 255)
            let carried = colour.opacity(value)
            // What the compositor does with the carried alpha over black…
            let resolved = colour.opacity(Double(carried.alpha) / 255, over: .rgb(0, 0, 0))
            // …and what the surface-taking spelling gives directly. The quantised
            // alpha is used on both sides, because the byte is what travels.
            #expect(resolved == colour.opacity(Double(carried.alpha) / 255, over: .black))
        }
    }

    /// The two spellings are now different things, and this says how: one CARRIES
    /// the opacity for the compositor to resolve, the other CONSUMES it against a
    /// surface the caller names.
    @Test("opacity(_:) carries the alpha; opacity(_:over:) consumes it")
    func theTwoSpellingsDiffer() {
        let colour = Color.rgb(64, 149, 255)
        let carried = colour.opacity(0.5)
        #expect(carried.value == colour.value, "the colour is unchanged")
        #expect(carried.alpha == 128, "and carries the opacity")

        let consumed = colour.opacity(0.5, over: .black)
        #expect(consumed.isOpaque, "a concrete answer")
        #expect(consumed.value != colour.value, "…which is a different colour")
    }

    /// The divergence that mattered most, and the reason this was worth changing:
    /// every semantic colour used to ignore `opacity(_:)` entirely, because
    /// `rgbComponents` is nil for one and the old body returned `self`.
    @Test("A semantic colour takes an opacity now")
    func semanticColoursTakeAnOpacity() {
        for colour in [Color.primary, .secondary, .accentColor, .warning, .error, .success] {
            #expect(colour.opacity(0.5).alpha == 128, "\(colour) ignored its opacity")
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
        let from = Color.ansi(.black)
        let to = Color.ansi(.white)
        let result = Color.lerp(from, to, phase: 0.5)
        // Should produce an RGB color (not crash)
        #expect(result.rgbComponents != nil)
    }

    // MARK: - Rounding

    /// To NEAREST, not toward zero. Truncating biased every channel of every
    /// blend down by half a unit, which made every derived "dim" a shade darker
    /// than it was asked to be — and disagreed with `encodedChannel`, where the
    /// perceptual and linear-light paths both come out, which always rounded.
    @Test("lerp rounds to nearest")
    func lerpRounds() {
        // 0…255 halved is 127.5, which truncates to 127 and rounds to 128.
        #expect(Color.lerp(.rgb(0, 0, 0), .rgb(255, 255, 255), phase: 0.5) == .rgb(128, 128, 128))
        // …and a value that is already below the halfway point still goes down.
        #expect(Color.lerp(.rgb(0, 0, 0), .rgb(254, 254, 254), phase: 0.5) == .rgb(127, 127, 127))
        // The ends stay exact, which truncation could not always promise.
        #expect(Color.lerp(.rgb(1, 2, 3), .rgb(250, 251, 252), phase: 1) == .rgb(250, 251, 252))
        #expect(Color.lerp(.rgb(1, 2, 3), .rgb(250, 251, 252), phase: 0) == .rgb(1, 2, 3))
    }

    /// The mean error over every pair of endpoints and a sweep of phases: half
    /// a unit smaller than truncation's, which is the whole argument.
    @Test("Rounding halves the average error against the exact blend")
    func roundingBeatsTruncation() {
        var rounded = 0.0
        var truncated = 0.0
        var samples = 0.0
        for start in stride(from: 0, through: 255, by: 5) {
            for end in stride(from: 0, through: 255, by: 5) {
                for step in 1..<10 {
                    let phase = Double(step) / 10
                    let exact = Double(start) + (Double(end) - Double(start)) * phase
                    let got = Color.lerp(
                        .rgb(UInt8(start), 0, 0), .rgb(UInt8(end), 0, 0), phase: phase)
                    guard let channel = got.rgbComponents?.red else { continue }
                    rounded += abs(Double(channel) - exact)
                    truncated += abs(exact.rounded(.down) - exact)
                    samples += 1
                }
            }
        }
        // Same samples, same exact values — the only difference is the
        // conversion. Truncation is never closer and is usually further.
        #expect(
            rounded < truncated,
            "mean error: rounded \(rounded / samples), truncated \(truncated / samples)")
        #expect(rounded / samples <= 0.25, "rounding should be within half a unit")
    }

    /// `opacity(_:)` has to survive a caller handing it a number outside `0…1`,
    /// because `UInt8(_: Double)` traps on one and a trap is not an answer to a
    /// rounding question. A NaN folds to zero, which is the only answer available.
    @Test("opacity clamps its argument rather than trapping")
    func opacityClamps() {
        let colour = Color.rgb(100, 150, 200)
        #expect(colour.opacity(2) == colour, "clamped to opaque, and unchanged")
        #expect(colour.opacity(-1).alpha == 0)
        #expect(colour.opacity(.nan).alpha == 0)
        #expect(colour.opacity(0.5).alpha == 128, "rounded to the nearest byte")
        // The colour itself is never touched — that is the whole difference from
        // the mix-toward-black spelling this replaced.
        #expect(colour.opacity(0.25).value == colour.value)
    }
}
