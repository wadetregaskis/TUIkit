//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TrackStyleParityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  A TrackStyle must look the SAME on every control that offers it: a style
//  name is a visual contract, and "shade on a Slider" diverging from "shade on
//  a ProgressView" (as the Slider demo once suggested by mislabelling
//  `.shadeRamp` as "shade") reads as the controls disagreeing. Both controls
//  render through the shared TrackRenderer with the same colour roles; these
//  tests pin the glyph-level parity so a control growing its own private
//  track rendering shows up as a failure here.

import Testing

@testable import TUIkit

@MainActor
@Suite("TrackStyle parity across controls")
struct TrackStyleParityTests {

    /// Every parameterless track style a user can name on both controls.
    private static let sharedStyles: [(name: String, style: TrackStyle)] = [
        ("bar", .bar),
        ("block", .block),
        ("blockFine", .blockFine),
        ("dot", .dot),
        ("knob", .knob),
        ("marker", .marker),
        ("shade", .shade),
        ("braille", .braille),
        ("shadeRamp", .shadeRamp(gradient: nil)),
    ]

    /// The bar line of a bare (label-free) ProgressView: the whole rendered line.
    private func progressTrack(_ style: TrackStyle, width: Int, fraction: Double) -> String {
        let view = ProgressView(value: fraction).trackStyle(style)
        let buffer = renderToBuffer(view, context: makeRenderContext(width: width, height: 2))
        return buffer.lines[0].stripped
    }

    /// The track region of a Slider: the rendered line minus the "◀ " / " ▶"
    /// chrome (value read-out disabled, so chrome is exactly 2 + 2 columns).
    private func sliderTrack(_ style: TrackStyle, width: Int, fraction: Double) -> String {
        let view = Slider(value: .constant(fraction))
            .trackStyle(style)
            .frame(width: width + 4)
            .sliderShowsValue(false)
        let buffer = renderToBuffer(view, context: makeRenderContext(width: width + 10, height: 2))
        let line = buffer.lines[0].stripped
        guard line.count > 4 else { return line }
        return String(line.dropFirst(2).dropLast(2))
    }

    @Test("Every shared style renders identical track glyphs on ProgressView and Slider")
    func sharedStylesMatch() {
        for (name, style) in Self.sharedStyles {
            for fraction in [0.0, 0.33, 0.5, 0.87, 1.0] {
                let progress = progressTrack(style, width: 24, fraction: fraction)
                let slider = sliderTrack(style, width: 24, fraction: fraction)
                #expect(
                    progress == slider,
                    """
                    '\(name)' @ \(fraction) diverges:
                      ProgressView: '\(progress)'
                      Slider:       '\(slider)'
                    """)
            }
        }
    }
}
