//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollbarBreathAlphaTests.swift
//
//  A focused scrollbar breathes between its accent and a lift of it. Both ends
//  are re-spellings of one colour, so both carry its alpha — at every phase.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
@Suite("A focused scrollbar's breath carries the accent's alpha")
struct ScrollbarBreathAlphaTests {

    /// Every shipped palette under a half-faded tint, and one whose every slot is
    /// faded — the palette `assertFramesOweOneClaim` first tripped on.
    private var palettes: [any Palette] {
        PaletteRegistry.all.map { TintedPalette(base: $0, tint: $0.accent.opacity(0.5)) }
            + [FadedAll()]
    }

    /// Asserted over every PHASE, not the two ends: the drift is in the middle,
    /// where the cycle interpolates alpha as a fourth channel between ends that
    /// disagree. The failure lists each offender's alphas in cycle order, which is
    /// what makes an interpolation legible (§29.3).
    ///
    /// It also counts the palettes whose lift left through `pulseLift`'s loop or
    /// fallback — the exits that went through `compositing`. A sweep in which every
    /// palette took the first exit could not fail, however wrong the others were.
    @Test(
        "Every phase of the breath carries the accent's alpha",
        arguments: [TextCursorStyle.Animation.pulse, .blink])
    func everyPhaseCarries(animation: TextCursorStyle.Animation) {
        var offenders: [String] = []
        var tookTheLoop = 0
        for palette in palettes {
            var environment = EnvironmentValues()
            environment.palette = palette
            environment.selectionIndicatorStyle = SelectionIndicatorStyle(animation: animation)
            let cycle = SelectionEmphasisClock(environment: environment).cycle(true)
            // A hovered cell, so the pointer's lift of each frame is checked too.
            let frames = ScrollbarPulse(cycle: cycle, hoveredCell: 0, palette: palette).frames
            let accent = palette.accent.resolve(with: palette).alpha
            let alphas = frames.flatMap { frame -> [UInt8?] in
                [frame.thumb.alpha, frame.arrow.alpha, frame.hover?.color.alpha]
            }
            if frames.isEmpty || alphas.contains(where: { $0 != accent }) {
                offenders.append("\(palette.name) (accent \(accent)): \(frames.map(\.thumb.alpha))")
            }
            let firstExit = ScrollbarColors.separated(
                palette.hoveredForeground(palette.accent), in: palette)
            if ScrollbarColors.pulseLift(palette) != firstExit { tookTheLoop += 1 }
        }
        #expect(offenders.isEmpty, "the breath's alpha moves with its phase: \(offenders)")
        #expect(tookTheLoop > 0, "no palette took pulseLift's loop, so this sweep could not fail")
    }

    /// The render `assertFramesOweOneClaim` trapped on: a focused scroll view under a wholly
    /// faded palette. It must breathe through runs, and the thumb under them must owe
    /// the accent's alpha as its field — the one claim every frame now shares.
    @Test("A focused scroll view's breathing bar renders, and claims its thumb")
    func focusedBarClaimsItsThumb() {
        // The shared context: its fresh focus manager hands the focus to the first
        // control that registers, which is the scroll view — nothing else here is
        // focusable.
        let drawn = renderToBuffer(
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(0..<30, id: \.self) { Text("row \($0)") }
                }
            }
            .scrollIndicators(.visible),
            context: makeRenderContext(width: 30, height: 10) { environment, _ in
                environment.palette = FadedAll()
            })
        #expect(!drawn.animatedCells.isEmpty, "the focused bar breathes through runs")
        // Scrolled to the top, the thumb is the first cell under the ▲: a full cell,
        // painted as a field in the thumb colour with no glyph.
        let thumb = owed(atColumn: drawn.width - 1, row: 1, in: drawn)
        #expect(
            thumb.ink == 1 && thumb.field == OpacityRegion.opacity(of: 128),
            "the thumb's cell owes \(thumb): \(drawn.lines.map(\.stripped))")
    }
}
