//  🖥️ TUIkit — Terminal UI Kit for Swift
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

    /// The palettes that state their own colours: the phosphor presets and the Terminal
    /// profiles. A palette that leaves a role to the terminal has no ramp to quantise
    /// until the terminal reports it.
    private var statedPalettes: [any Palette] {
        PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles
    }

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
        for palette in statedPalettes {
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

    /// A continuous lerp does not have to quantise monotonically: rounding two
    /// channels at different rates makes the chosen palette entry step forward,
    /// back, and forward again. Novel's accent did — #D7AF87, #D7875F, #AF875F,
    /// #D7875F, #AF875F — so the "breath" wobbled between two shades instead of
    /// fading through them. Dedup was against the PREVIOUS step only, which a
    /// bounce walks straight past.
    @Test("A shade appears once, so the breath never doubles back")
    func noRepeatedShades() {
        for palette in statedPalettes {
            let rendered = ramp(palette).map { $0.rendered(at: .palette256) }
            for (index, colour) in rendered.enumerated() {
                #expect(
                    !rendered[..<index].contains(colour),
                    "\(palette.name): step \(index) repeats an earlier shade — \(rendered)")
            }
        }
    }

    /// …but a fade ASKED to reach black keeps it. Red Sands' focus wash breathes
    /// away from its brick page, from a dark brown (`3D1916`) to near-black
    /// (`000005`); the cube draws that as `5F0000` to black, and with the black
    /// dropped as a lost hue the ramp held one colour — a focused list's cursor
    /// row that did not breathe on a 256-colour terminal. The black is the colour
    /// the breath was asked for, and the dim end that DOES lose its hue
    /// (`noGreyFrames` above) is still dropped.
    ///
    /// Red Sands' rows now read constants (`RowFills`), so the fade is spelled
    /// out: it is the rule's, and still what a custom palette like it gets.
    @Test("A fade whose visible end is black keeps that end")
    func achromaticBrightEndIsKept() {
        let (dim, bright) = (Color.rgb(0x3D, 0x19, 0x16), Color.rgb(0x00, 0x00, 0x05))
        #expect(
            bright.rendered(at: .palette256).isAchromatic,
            "the premise: the far end renders black, \(bright.rendered(at: .palette256))")
        let rendered = Color.pulseRamp(from: dim, to: bright, depth: .palette256)
            .map { $0.rendered(at: .palette256) }
        #expect(
            rendered.count >= 2 && rendered.last == bright.rendered(at: .palette256),
            "Red Sands' wash breath holds \(rendered) on 256 colours")
    }

    @Test("The ramp is never empty, so a pulse always has something to show")
    func neverEmpty() {
        for palette in statedPalettes {
            #expect(!ramp(palette).isEmpty, "\(palette.name)")
        }
    }

    /// A glyph that merely *is* the accent — a focused button's end caps — has
    /// no readability ceiling, so it gets the full span and should offer more
    /// steps than the readability-bounded row fill.
    @Test("The full-accent span offers at least as many shades as the bounded one")
    func fullAccentSpanIsNoWorse() {
        for palette in statedPalettes {
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
        let palette = statedPalettes[0]
        let steps = ramp(palette, depth: .truecolor)
        #expect(steps.count == 2, "just the endpoints; the caller lerps between them")
    }

    // MARK: - Two cube entries

    /// The sixteen shipped palettes' 256-colour breaths (the cursor row, F,
    /// and the selected cursor row, B), as the reference rule —
    /// `Tools/RowFillValues/generate.py --ramps` — steps them. Every
    /// caller that breathes between two cube entries draws these steps, so a
    /// drift here changes every shipped look at 256 colours.
    private static let shippedCubeBreaths: [(dim: UInt8, bright: UInt8, steps: [UInt8])] = [
        (236, 28, [236, 28]), (28, 70, [28, 34, 70]),  // Green
        (236, 94, [236, 94]), (94, 101, [94, 101]),  // Amber
        (234, 88, [234, 88]), (236, 124, [236, 124]),  // Red
        (234, 90, [234, 90]), (54, 92, [54, 55, 92]),  // Violet
        (17, 20, [17, 18, 20]), (20, 26, [20, 21, 26]),  // Blue
        (235, 240, [235, 237, 240]), (240, 244, [240, 242, 244]),  // White
        (254, 75, [254, 75]), (110, 32, [110, 68, 32]),  // Basic
        (101, 143, [101, 107, 143]), (64, 178, [64, 142, 178]),  // Grass
        (234, 28, [234, 28]), (28, 70, [28, 34, 70]),  // Homebrew
        (192, 144, [192, 150, 144]), (143, 101, [143, 107, 101]),  // Man Page
        (217, 202, [217, 209, 202]), (209, 166, [209, 202, 166]),  // Novel
        (27, 105, [27, 69, 105]), (69, 146, [69, 105, 146]),  // Ocean
        (235, 243, [235, 239, 243]), (240, 246, [240, 243, 246]),  // Pro
        (94, 101, [94, 101]), (130, 172, [130, 166, 172]),  // Red Sands
        (103, 61, [103, 97, 61]), (61, 55, [61, 56, 55]),  // Silver Aerogel
        (153, 75, [153, 117, 75]), (110, 32, [110, 68, 32]),  // Solid Colors
    ]

    @Test("A breath between two cube entries takes the reference rule's steps")
    func cubeEntriesBreatheByTheReferenceRule() {
        for breath in Self.shippedCubeBreaths {
            let ramp = Color.pulseRamp(
                from: .palette256(breath.dim), to: .palette256(breath.bright), depth: .palette256,
                terminalColorsGeneration: -2)
            #expect(ramp == breath.steps.map { .palette256($0) }, "\(breath.dim) → \(breath.bright)")
        }
    }

    /// The middle step is chosen from the ends alone, so it never leaves their
    /// hue: a grey end and a hued one get no middle, because there it would
    /// be the cube's darkest tinted entry, where the selected row sits.
    @Test("A grey end and a hued one breathe with no middle step")
    func greyToHueHasNoMiddle() {
        #expect(Color.cubeRamp(from: 236, to: 28) == [.palette256(236), .palette256(28)])
        #expect(Color.cubeRamp(from: 28, to: 28) == [.palette256(28)])
    }
}
