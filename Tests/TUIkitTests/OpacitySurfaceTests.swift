//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacitySurfaceTests.swift
//
//  A blended span is spliced into a row that opened with the PAGE's background.
//  SGR 49 inside it does not mean "the page's" — it means the TERMINAL's, which
//  on a light profile is white. Reported as the spaces of a faded label punching
//  white cells through the band underneath it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A composite never says SGR 49")
struct OpacitySurfaceTests {

    private let surface = Color.rgb(5, 10, 5)
    private let accent = Color.rgb(102, 255, 102)

    /// SGR 49 — "back to the terminal's default background".
    private let defaultBackground = "\u{1B}[49m"

    @Test("A yielding source space leaves the destination on the page, not the terminal")
    func aYieldedSpaceKeepsThePage() {
        // The reported shape: a band drawn in the accent with NO background of
        // its own, and a label over it painting nothing at all — the state
        // where every cell of the label yields.
        let band = ANSIRenderer.colorize(String(repeating: "▒", count: 10), foreground: accent)
        let label = "AB CD"
        let span = FrameBuffer.blendedSpan(
            source: label, destination: band, columns: 0..<5, destinationShift: 0,
            alpha: { _ in 0.25 }, surface: surface, defaultForeground: .rgb(200, 200, 200))
        #expect(
            !span.contains(defaultBackground),
            "the span hands a cell to the terminal's background: \(span.debugDescription)")
        // And it says the page's, which is what the row it is spliced into is
        // painted in.
        let expected = ANSIRenderer.backgroundCodes(for: surface).joined(separator: ";")
        #expect(
            span.contains(expected),
            "the span does not name the surface: \(span.debugDescription)")
    }

    @Test("Every covered column names a background, whatever the alpha")
    func everyCoveredColumnNamesOne() {
        let band = ANSIRenderer.colorize(String(repeating: "▒", count: 8), foreground: accent)
        for alpha in [0.0, 0.01, 0.25, 0.5, 0.75, 1.0] {
            let span = FrameBuffer.blendedSpan(
                source: "  x  ", destination: band, columns: 0..<5, destinationShift: 0,
                alpha: { _ in alpha }, surface: surface, defaultForeground: .rgb(200, 200, 200))
            #expect(
                !span.contains(defaultBackground),
                "alpha \(alpha) handed a cell to the terminal: \(span.debugDescription)")
        }
    }

    @Test("An uncovered column is still passed through as it was")
    func uncoveredColumnsAreUntouched() {
        // The substitution is scoped to columns a region covers: a column the
        // span merely spans on its way between two regions belongs to a row
        // that was never taken apart, and must reach the terminal unaltered.
        let band = ANSIRenderer.colorize(String(repeating: "▒", count: 8), foreground: accent)
        let span = FrameBuffer.blendedSpan(
            source: band, destination: band, columns: 0..<4, destinationShift: 0,
            alpha: { column in column == 0 ? 0.5 : nil },
            surface: surface, defaultForeground: .rgb(200, 200, 200))
        let named = ANSIRenderer.backgroundCodes(for: surface).joined(separator: ";")
        // Exactly one cell was covered, so the surface is named at most once —
        // the three passed-through cells did not gain one.
        #expect(
            span.components(separatedBy: named).count - 1 <= 1,
            "an uncovered column was given a background: \(span.debugDescription)")
    }

    @Test("A change the cube cannot represent is not drawn as a change")
    func imperceptibleChangesSettle() {
        // 1% of a bright colour over a near-black page lands about three units
        // per channel away from it — and the 256-colour cube's nearest entry to
        // a faintly tinted near-black is a SATURATED one, so three units became
        // ninety-five and 1% opacity drew a visible green band.
        let band = ANSIRenderer.colorize(String(repeating: "▒", count: 6), foreground: accent)
        let label = ANSIRenderer.colorize(
            "  x  ", foreground: surface, background: .rgb(204, 255, 51))
        func backgrounds(atAlpha alpha: Double) -> Set<String> {
            let span = FrameBuffer.blendedSpan(
                source: label, destination: band, columns: 0..<5, destinationShift: 0,
                alpha: { _ in alpha }, surface: surface, defaultForeground: .rgb(200, 200, 200))
            return Set(
                span.components(separatedBy: "\u{1B}[").compactMap { part in
                    part.contains("48;") ? String(part.prefix(while: { $0 != "m" })) : nil
                })
        }
        ColorDepth.withCurrent(.palette256) {
            let page = ANSIRenderer.backgroundCodes(for: surface).joined(separator: ";")
            // At 1% every cell keeps the page: the composite is closer to what
            // was there than to the entry it would otherwise have taken.
            let faint = backgrounds(atAlpha: 0.01)
            #expect(
                faint.allSatisfy { $0.contains(page) },
                "1% painted something: \(faint)")
            // At a strength the cube CAN represent, it is drawn — the rule
            // settles what cannot be shown, it does not suppress the effect.
            let real = backgrounds(atAlpha: 0.4)
            #expect(
                real.contains(where: { !$0.contains(page) }),
                "40% painted nothing: \(real)")
        }
    }

    @Test("Nothing settles on a terminal that draws what it is given")
    func truecolorIsUntouched() {
        // The rule exists because the cube is sparse. A truecolor terminal has
        // no entries to round to, and rounding toward the backdrop there would
        // be discarding a difference it could have shown.
        let band = ANSIRenderer.colorize(String(repeating: "▒", count: 6), foreground: accent)
        let label = ANSIRenderer.colorize(
            "  x  ", foreground: surface, background: .rgb(204, 255, 51))
        ColorDepth.withCurrent(.truecolor) {
            let span = FrameBuffer.blendedSpan(
                source: label, destination: band, columns: 0..<5, destinationShift: 0,
                alpha: { _ in 0.01 }, surface: surface, defaultForeground: .rgb(200, 200, 200))
            let page = ANSIRenderer.backgroundCodes(for: surface).joined(separator: ";")
            #expect(
                !span.components(separatedBy: "\u{1B}[").allSatisfy {
                    !$0.contains("48;") || $0.contains(page)
                },
                "truecolor rounded a difference it could have drawn: \(span.debugDescription)")
        }
    }
}
