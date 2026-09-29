//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowContent.swift
//
//  A `List` row's content, and its fades as the row's own fill spends them.
//
//  A row's fill — its cursor, its selection, its alternating tint — is behind
//  every fade inside the row, as a `.background` is (`Opacity as composition.md`
//  §96): carried up past it, a fade met the fill as the faded view's own field and
//  faded it too, toward the page. So the row spends the content against the fill
//  it paints, and a breathing row against each colour of the breath.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

/// A `List` row's child buffer, as the row draws it over each colour it paints.
struct ListRowContent {
    /// The row's content, as its child rendered it.
    let buffer: FrameBuffer

    /// The opaque colour the row paints under the content in the frame being drawn,
    /// where the content has a fade to spend on it — `nil` where the row spends none
    /// of them: no fill, a reversal, a translucent tint, which is not a backdrop yet
    /// (§22), or content with nothing asking what is behind it
    /// (``FrameBuffer/hasFadeOnWhatIsBehind``).
    let fill: Color?

    /// The content over ``fill``, spent once: the frame being drawn.
    let drawn: FrameBuffer

    private let palette: any Palette

    /// The content of a row that paints `background`.
    @MainActor
    init(_ buffer: FrameBuffer, background: RowBackground, palette: any Palette) {
        self.buffer = buffer
        self.palette = palette
        let fill = Self.spentFill(of: background, under: buffer)
        self.fill = fill
        let drawn = fill.map { Self.spending(buffer, on: $0, palette: palette, buildingRuns: true) } ?? buffer
        self.drawn = drawn
        // Only for a row that spends: every row `renderRow` draws, every frame, is
        // built through here, and nearly none of them has anything to spend.
        spent = fill.map { Spent(byColour: [($0, drawn.lines)]) }
    }

    /// The content's lines spent against each colour asked for so far, ``drawn``'s
    /// first. A breath comes back through most of its colours on the way down — a
    /// symmetric pulse repeats about half of them — and each is spent once, as a
    /// menu row's bar spends its breath (`_MenuItemRowBar`).
    private final class Spent {
        var byColour: [(colour: Color, lines: [String])]

        init(byColour: [(colour: Color, lines: [String])]) {
            self.byColour = byColour
        }
    }
    /// `nil` for a row that spends nothing.
    private let spent: Spent?

    /// The content's lines as the row draws them over `colour`: spent against it
    /// where the row spends the content at all.
    ///
    /// Lines, not a buffer, and for any colour but the drawn one the lines alone are
    /// spent: a breath's frames are whole lines the row replays in place of its own,
    /// and keep nothing else. Spent whole, each colour faded every frame of every run
    /// inside the row and rebuilt a repeating fade's runs, to throw them away.
    func lines(over colour: Color?) -> [String] {
        guard let spent, let colour else { return buffer.lines }
        if let known = spent.byColour.first(where: { $0.colour == colour }) { return known.lines }
        let lines = Self.spending(buffer, on: colour, palette: palette, buildingRuns: false).lines
        spent.byColour.append((colour, lines))
        return lines
    }

    /// What the content owes the attach with `dropped` — what its dropped runs left
    /// behind — in the place of its buffer's own regions: `nil`, those regions, when
    /// nothing was dropped and the row spent nothing; only `dropped` where the row's
    /// fill spent the rest (`PopulatedRenderState.contentClaims`).
    func claims(leaving dropped: [OpacityRegion]) -> [OpacityRegion]? {
        if fill != nil { return dropped }
        return dropped.isEmpty ? nil : buffer.opacityRegions + dropped
    }

    /// The colour ``fill`` is, for a row painting `background` under `content`.
    ///
    /// Asked of the content first, so the rows with nothing to spend — nearly all of
    /// them — never walk the breath.
    @MainActor
    private static func spentFill(of background: RowBackground, under content: FrameBuffer) -> Color? {
        guard content.hasFadeOnWhatIsBehind else { return nil }
        switch background {
        case .fixed(let colour) where colour.isOpaque:
            return colour
        case .pulsing(let cycle, let dim, let bright):
            // The colour the row draws in this frame: the cycle's own step, not a
            // read of the clock, so the frame stays replayable — `perStep[step]` for
            // a breath, and for a still cycle (`.selectionIndicatorStyle(.none)`, a
            // blink at rest) the end it holds, which is BRIGHT (`stillLines`). Taken
            // as the dim end there, the row's runs were spent against a colour the
            // row never draws, and every tick put a faded spinner on the dim wash in
            // a bright row.
            return cycle.colorNow(dim: dim, bright: bright)
        case .pulsingReversal:
            // This frame's fill, or none on a reversed frame, whose content's colours
            // are dropped anyway.
            return background.colorNow
        case .none, .fixed, .reversed:
            return nil
        }
    }

    /// `content` with every fade inside it spent against `fill`: painted first, its
    /// lines and its runs' grounds, as the row paints them (`terminatedBackground`,
    /// `grounding`), so every cell reads as the row leaves it; then resolved, so each
    /// fades toward the fill under it — its lines alone where `buildingRuns` is false.
    private static func spending(
        _ content: FrameBuffer, on fill: Color, palette: any Palette, buildingRuns: Bool
    ) -> FrameBuffer {
        var painted = content.replacingLines(
            content.lines.map { $0.withPersistentBackground(fill) + ANSIRenderer.reset })
        if buildingRuns { painted.paintRunGrounds { _, ground in ground.withPersistentBackground(fill) } }
        return painted.resolvingOpacity(
            onOpaqueFill: { nil }, surface: fill, palette: palette, buildingRuns: buildingRuns)
    }
}
