//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollIndicatorBreathAlphaTests.swift
//
//  A focused scrollable's "N more" line breathes between the palette's tertiary
//  and its accent: two slots with alphas of their own, so both ends spend them
//  against the surface and every phase is opaque. At rest the line carries the
//  tertiary's alpha and claims it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A scroll indicator's breath spends both ends; its still line claims")
struct ScrollIndicatorBreathAlphaTests {

    /// Every shipped palette under a half-faded tint, and one whose every slot is
    /// faded.
    private var palettes: [any Palette] {
        PaletteRegistry.all.map { TintedPalette(base: $0, tint: $0.accent.opacity(0.5)) }
            + [FadedAll()]
    }

    /// Asserted over every PHASE, not the two ends: the drift is in the middle,
    /// where a cycle interpolates alpha as a fourth channel between ends that
    /// disagree (§29.3).
    @Test(
        "Every phase of the breath is opaque, and the breathing line claims nothing",
        arguments: [TextCursorStyle.Animation.pulse, .blink])
    func everyPhaseIsOpaque(animation: TextCursorStyle.Animation) {
        var offenders: [String] = []
        for palette in palettes {
            var environment = EnvironmentValues()
            environment.palette = palette
            environment.selectionIndicatorStyle = animation
            let cycle = SelectionEmphasisClock(environment: environment).cycle(true)
            let ends = scrollIndicatorBreath(palette: palette, over: palette.background)
            let colors = cycle.colors(dim: ends.dim, bright: ends.bright)
            let line = renderScrollIndicator(
                direction: .down, count: 3, unit: .rows, width: 30, palette: palette,
                cycle: cycle, over: palette.background)
            if !colors.allSatisfy(\.isOpaque) || !line.drawn.claims.isEmpty || line.animation == nil {
                offenders.append(
                    "\(palette.name): alphas \(colors.map(\.alpha)), "
                        + "\(line.drawn.claims.count) claims, run \(line.animation != nil)")
            }
        }
        #expect(offenders.isEmpty, "the breath carries an alpha: \(offenders)")
    }

    /// At rest nothing replays the line, so it keeps the tertiary's alpha and owes it
    /// on exactly the cells it painted: the arrow and its label, not the blanks that
    /// centre them.
    @Test("A still line owes the tertiary's alpha on its arrow and label, and nothing else")
    func stillLineClaims() {
        // A tertiary that owes an alpha no other slot does, so a line drawn from the
        // wrong slot shows: under `FadedAll` the tertiary IS the foreground.
        let palette = FadedNavigation()
        let line = renderScrollIndicator(
            direction: .down, count: 3, unit: .rows, width: 30, palette: palette,
            cycle: nil, over: palette.background)
        var buffer = FrameBuffer(lines: [line.text])
        buffer.opacityRegions = line.claims(atRow: 0)
        let padding = line.text.stripped.prefix { $0 == " " }.count
        let tertiary = owed(palette.foregroundTertiary)
        var wrong: [String] = []
        for column in 0..<line.drawn.cells {
            let owes = owed(atColumn: column, row: 0, in: buffer)
            let ink = column < padding ? 1 : tertiary
            if owes.ink != ink || owes.field != 1 { wrong.append("\(column): \(owes)") }
        }
        #expect(padding > 0, "the line is centred, so there are blanks to leave alone")
        #expect(wrong.isEmpty, "cells owing the wrong alpha: \(wrong)")
    }

    /// An opaque palette's breath is its own two colours, spelled exactly as they
    /// were: spending an opaque colour must not re-spell it (a lerp turns the
    /// terminal's own red into `rgb(205, 0, 0)`). Every shipped slot is already an
    /// `rgb`, which a lerp leaves looking the same, so the sweep adds slots that are
    /// the terminal's own named colours — the spelling a re-spell would change.
    @Test("An opaque palette breathes between its own two colours, unchanged")
    func opaqueBreathUnchanged() {
        let palettes: [any Palette] =
            PaletteRegistry.all + PaletteRegistry.all.map { TintedPalette(base: $0, tint: .red) }
            + [NamedSlots()]
        for palette in palettes {
            let ends = scrollIndicatorBreath(palette: palette, over: palette.background)
            #expect(ends.dim == palette.foregroundTertiary, "\(palette.name)'s dim end was re-spelled")
            #expect(ends.bright == palette.accent, "\(palette.name)'s bright end was re-spelled")
        }
    }
}

/// Opaque, and spelled in the terminal's own named colours where the breath reads:
/// a re-spelling of these shows as a different value, where one of an `rgb` does not.
private struct NamedSlots: Palette {
    let id = "named-slots"
    let name = "Named slots"
    let background = Color.black
    let foreground = Color.white
    let foregroundTertiary = Color.white
    let accent = Color.red
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}
