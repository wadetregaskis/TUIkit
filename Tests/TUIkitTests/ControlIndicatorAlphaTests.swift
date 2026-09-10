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
        for (name, pair) in [
            ("accentPulse", tinted.accentPulse()),
            ("accentFillPulse", tinted.accentFillPulse()),
        ] {
            #expect(pair.dim.isOpaque, "\(name) dim carried an alpha")
            #expect(pair.bright.isOpaque, "\(name) bright carried an alpha")
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
