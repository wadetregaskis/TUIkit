//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlIndicatorAlphaTests.swift
//
//  The glyphs a control paints for itself — a checkbox's mark, a switch's knob,
//  a radio button's dot. They take their colours from the palette rather than
//  from `.foregroundStyle`, so a faded `.tint` is what reaches them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A control's own indicator glyph")
struct ControlIndicatorAlphaTests {

    private func buffer<V: View>(_ view: V, width: Int = 20, height: Int = 3) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    // MARK: - Both ends of a pulse must agree

    @Test("Every pulse pair spends a translucent accent, on both ends")
    func pulsePairsAgree() {
        // Four sites took `accentPulse().dim` and then spelled their own bright end
        // from `palette.accent`, so the dim end consumed a translucent tint's alpha
        // and the bright end carried it — half a cycle honoured, half a debug trap.
        // They ask for the pair now. Asserted through the palette rather than
        // through each control, because it is the PAIR that has to agree.
        let tinted = TintedPalette(base: SystemPalette.default, tint: Color.red.opacity(0.5))
        let surface = tinted.background
        for (name, pair) in [
            ("accentPulse", tinted.accentPulse()),
            ("accentFillPulse", tinted.accentFillPulse()),
            // The three the first pass missed, each a separate copy of the same
            // pair. `breathEnds` reaches a focused Link's and a bordered box's ●
            // through `focusIndicatorEnds`; `activeSection` is a focus section's;
            // and a standard button's caps breathe from the button's own face to
            // the accent. All four now come from `Color.breathEnds`.
            ("BorderRenderer.breathEnds", BorderRenderer.breathEnds(from: tinted.accent, on: surface)),
            ("BorderRenderer.focusIndicatorEnds",
                BorderRenderer.focusIndicatorEnds(palette: tinted, on: surface)),
            ("Color.breathEnds", tinted.accent.breathEnds(dimmedTo: 0.35, over: surface)),
        ] {
            #expect(pair.dim.isOpaque, "\(name) dim carried an alpha")
            #expect(pair.bright.isOpaque, "\(name) bright carried an alpha")
        }
    }

    /// **An opaque accent must come back byte-identical, not merely equal.**
    ///
    /// The bright end is `spendingAlpha(over:)`, and the reason it guards on
    /// `isOpaque` instead of compositing at 1 is that `opacity(_:over:)` lerps —
    /// and a lerp re-spells `.red` (SGR 31, the terminal's own red) as
    /// `rgb(205, 0, 0)`. Arithmetically the same colour; on any terminal whose
    /// palette is not the default, a visibly different one. This is the bright end
    /// of every focus pulse in all sixteen shipped palettes, so the assertion is
    /// on the SPELLING.
    @Test("An opaque pulse end keeps its named spelling")
    func opaqueEndKeepsItsSpelling() {
        let named = Color.red
        #expect(named.spendingAlpha(over: .black) == named)
        let ends = named.breathEnds(dimmedTo: 0.35, over: .black)
        #expect(
            ends.bright.foregroundCodes() == named.foregroundCodes(),
            "re-spelled as \(ends.bright.foregroundCodes())")
    }

    /// A `ButtonCapCycle`'s caps are a fourth pulse pair, and the one whose dim end
    /// is not a dimmed accent but the button's own face — so it shares only the
    /// bright half of the rule. Every frame of the breath must be opaque, because
    /// a run's frames all answer to one static claim.
    @Test("A button's cap breath is opaque at every phase under a faded tint")
    func capBreathIsOpaqueThroughout() {
        let tinted = TintedPalette(base: SystemPalette.default, tint: Color.red.opacity(0.5))
        let context = RenderContext(
            availableWidth: 20, availableHeight: 3, tuiContext: TUIContext())
        let caps = ButtonCapCycle(
            isFocused: true, background: tinted.restingControlFace, accent: tinted.accent,
            context: context)
        #expect(caps.colorNow.isOpaque, "this phase carried \(caps.colorNow.alpha)")
        for run in caps.runs(width: 12) {
            // The frames are already bytes, so the assertion is that building them
            // did not trip the emitter — which it would have, loudly, before.
            #expect(!run.frames.isEmpty)
        }
    }

    // MARK: - Toggle

    @Test("A checkbox's mark claims its own cells under a faded tint")
    func checkboxClaims() throws {
        let drawn = buffer(
            Toggle("Enable", isOn: .constant(true)).tint(Color.red.opacity(0.5)), width: 20)
        let claim = try #require(
            drawn.opacityRegions.first, "the mark's own alpha: \(drawn.opacityRegions)")
        #expect(claim.offsetX == 0, "the indicator opens the row")
        #expect(claim.width > 0)
        #expect(claim.inkOpacity == 128.0 / 255)
    }

    @Test("An opaque tint leaves a checkbox claiming nothing")
    func opaqueCheckbox() {
        #expect(
            buffer(Toggle("Enable", isOn: .constant(true)).tint(Color.red), width: 20)
                .opacityRegions.isEmpty)
        #expect(
            buffer(Toggle("Enable", isOn: .constant(true)), width: 20).opacityRegions.isEmpty)
    }

    @Test("A switch's knob and its track are separate claims")
    func switchClaims() {
        // The knob is ink and the track is a field, and a switch under a faded tint
        // has both. One region over the pair would fade the knob at the track's
        // alpha, which is the mistake the run description exists to prevent.
        let drawn = buffer(
            Toggle("Enable", isOn: .constant(true))
                .toggleStyle(.switch)
                .tint(Color.red.opacity(0.5)),
            width: 20)
        #expect(!drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
    }

    // MARK: - Radio button

    @Test("A radio button's dot claims one glyph, not the label beside it")
    func radioClaims() throws {
        let drawn = buffer(
            RadioButtonGroup(selection: .constant(1)) {
                RadioButtonItem(1) { Text("One") }
            }.tint(Color.red.opacity(0.5)),
            width: 20)
        let claim = try #require(
            drawn.opacityRegions.first, "the indicator's alpha: \(drawn.opacityRegions)")
        #expect(claim.offsetX == 0)
        #expect(claim.width <= 2, "the glyph, not the words: \(claim)")
        #expect(claim.inkOpacity == 128.0 / 255)
    }

    @Test("An opaque tint leaves a radio button claiming nothing")
    func opaqueRadio() {
        let drawn = buffer(
            RadioButtonGroup(selection: .constant(1)) {
                RadioButtonItem(1) { Text("One") }
            }.tint(Color.red),
            width: 20)
        #expect(drawn.opacityRegions.isEmpty, "\(drawn.opacityRegions)")
    }
}
