//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TintAlphaTests.swift
//
//  `.tint(.red.opacity(0.5))`. The accent fans out to dozens of controls, and it
//  used to fan out INCONSISTENTLY: one derivation ate the alpha, another carried
//  it, so half a focus pulse was honoured and half was a debug trap.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

@Suite("A translucent tint")
struct TintAlphaTests {

    private let palette = SystemPalette.default

    private func tinted(_ colour: Color) -> any Palette {
        TintedPalette(base: palette, tint: colour)
    }

    @Test("A faded tint reaches the accent as a faded accent")
    func tintCarriesAlpha() {
        // `TintedPalette.accent` resolves the tint against the base palette, which
        // used to substitute the reference's alpha for the slot's and so came back
        // opaque whatever the tint said. See §20.
        #expect(tinted(Color.red.opacity(0.5)).accent.alpha == 128)
        #expect(tinted(Color.red).accent.isOpaque)
    }

    @Test("Both ends of a focus pulse spend the alpha, and neither carries it")
    func pulseEndsAgree() {
        // THE BUG. `accentPulse` was `(accent.opacity(min, over: ground), accent)`:
        // the dim end composited against a stated ground and came back opaque, and
        // the bright end was the raw accent and came back translucent. A control
        // breathing between them was correct for half its cycle and tripped the
        // emitter's assertion for the other half.
        let pulse = tinted(Color.red.opacity(0.5)).accentPulse()
        #expect(pulse.dim.isOpaque, "the dim end composites against a known ground")
        #expect(pulse.bright.isOpaque, "and so, now, does the bright end")
    }

    @Test("A faded tint gives a subtler face than an opaque one")
    func fadedTintIsSubtler() {
        // The point of honouring it: `opacity(_:over:)` folds the source's own alpha
        // into the coverage, so a half-faded tint composites half as far toward the
        // accent. Reading only the parameter — what it did before — made these two
        // identical, which is the silent-wrong-colour shape: no assertion fires on
        // an opaque result.
        let faded = tinted(Color.red.opacity(0.5)).restingControlFace
        let solid = tinted(Color.red).restingControlFace
        #expect(faded != solid, "a faded tint must not resolve to the opaque face")
        // And it lands between the background and the opaque face, not past either.
        let background = palette.background
        #expect(faded != background, "nor all the way back to the page")
    }

    @Test("A fully transparent tint is the page itself")
    func clearTint() {
        // Zero coverage: the composite is the ground, exactly. The one place where
        // consuming the alpha against a STATED surface gives the whole answer.
        let face = tinted(Color.clear).restingControlFace.resolve(with: palette)
        #expect(face == palette.background.resolve(with: palette), "got \(face)")
    }

    /// `hoveredControlFace`'s fallback returned the RAW accent when no tint step
    /// cleared the colour cube — and at `.tint(.clear)` every candidate composites to
    /// the page, so the fallback is certain there. A transparent colour then reached
    /// the caps' emitter on hover alone. It is spent over the page now, like every
    /// other exit of either face (§49).
    @Test("A fully transparent tint hovers at the page itself")
    func clearTintHovers() {
        let face = tinted(Color.clear).hoveredControlFace
        #expect(face.isOpaque, "the hovered face at a clear tint: alpha \(face.alpha)")
        #expect(face.resolve(with: palette) == palette.background.resolve(with: palette), "got \(face)")
    }

    /// Every shipped palette under a faint tint: each hovered face is opaque. And the
    /// sweep must reach the fallback at least once — alpha 0 guarantees it — or it
    /// could pass on the first exit alone and prove nothing about the one that broke.
    @Test("The hovered face is opaque under every faint tint")
    func hoveredFaceIsOpaqueUnderFaintTints() {
        var fellBack = 0
        for base in PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles {
            for step in stride(from: 0, through: 48, by: 4) {
                let tinted = TintedPalette(base: base, tint: Color.red.opacity(Double(step) / 255))
                let face = tinted.hoveredControlFace
                #expect(face.isOpaque, "\(base.name) at alpha \(step): \(face.alpha)")
                if face == tinted.accent.spendingAlpha(over: tinted.background) { fellBack += 1 }
            }
        }
        #expect(fellBack > 0, "the sweep never reached the fallback")
    }

    @Test("An opaque tint is unchanged in every derivation")
    func opaqueTintUnchanged() {
        // The regression guard: every palette that ships is opaque, so folding the
        // source alpha in must be the exact identity for them — a multiply by 1,
        // not a multiply by 254/255.
        let tint = tinted(Color.red)
        // Not merely the same COLOUR — the same spelling. `opacity(_:over:)` lerps,
        // and a lerp re-spells `.red` (SGR 31, the terminal's own red) as
        // `rgb(205, 0, 0)`. That is a different colour on any terminal whose palette
        // is not the default, and this is the bright end of every focus pulse.
        #expect(tint.accentPulse().bright == Color.red, "got \(tint.accentPulse().bright)")
        #expect(tint.restingControlFace.resolve(with: tint).isOpaque)
    }
}
