//  🖥️ TUIKit — Terminal UI Kit for Swift
//  PulseRampTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitStyling

/// The focus pulse is written as a continuous fade, but a terminal without
/// truecolor cannot show one: every step rounds onto the 256-colour cube. These
/// pin the two properties that make the difference between a breath and a
/// stutter — how many shades the fade actually produces, and whether any of them
/// is off-hue.
@MainActor
@Suite("Focus pulse ramp")
struct PulseRampTests {

    /// The ramp the framework's own focus affordances use.
    private func ramp(_ palette: any Palette, depth: ColorDepth = .palette256) -> [Color] {
        Color.pulseRamp(
            from: palette.accent.opacity(ViewConstants.focusPulseMin, over: palette.background),
            to: palette.accent.opacity(ViewConstants.focusPulseMax, over: palette.background),
            depth: depth)
    }

    /// The defect the owner saw as "juddering": the 6×6×6 cube has no dark
    /// tinted entries, so the bottom of an accent ramp over a near-black
    /// background quantises to a GREY. A green control turning grey mid-breath
    /// reads as a glitch, not as a dim.
    @Test("A chromatic accent never fades through grey")
    func noGreyFrames() {
        for palette in PaletteRegistry.all {
            let bright = palette.accent.opacity(
                ViewConstants.focusPulseMax, over: palette.background)
            // An achromatic accent (White, Pro, Silver Aerogel) is *supposed* to
            // render grey — the rule is about hue being lost, not about grey.
            guard bright.hasHue(depth: .palette256) else { continue }
            for (step, colour) in ramp(palette).enumerated() {
                #expect(
                    !colour.rendered(at: .palette256).isAchromatic,
                    "\(palette.name) step \(step) renders achromatic")
            }
        }
    }

    @Test("The ramp is never empty, so a pulse always has something to show")
    func neverEmpty() {
        for palette in PaletteRegistry.all {
            #expect(!ramp(palette).isEmpty, "\(palette.name)")
        }
    }

    /// A glyph that merely *is* the accent — a focused button's end caps — has
    /// no readability ceiling, so it gets the full span and should offer more
    /// steps than the readability-bounded row fill.
    @Test("The full-accent span offers at least as many shades as the bounded one")
    func fullAccentSpanIsNoWorse() {
        for palette in PaletteRegistry.all {
            let capRamp = Color.pulseRamp(
                from: palette.accent.opacity(
                    ViewConstants.focusBorderDim, over: palette.background),
                to: palette.accent,
                depth: .palette256)
            #expect(
                capRamp.count >= ramp(palette).count,
                "\(palette.name): caps \(capRamp.count) vs rows \(ramp(palette).count)")
        }
    }

    @Test("Truecolor keeps the continuous fade — the ramp is only a fallback")
    func truecolorIsContinuous() {
        let palette = PaletteRegistry.all[0]
        let steps = ramp(palette, depth: .truecolor)
        #expect(steps.count == 2, "just the endpoints; the caller lerps between them")
    }
}
