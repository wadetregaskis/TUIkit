//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClaimingRow.swift
//
//  A row of cells being assembled, together with the claim each run of them
//  owes — the two halves of a translucent paint, written in one place so they
//  cannot drift apart.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

/// A row's finished bytes, the cells that owe a blend, and how many cells were
/// actually drawn.
///
/// `TrackRenderer.render` used to return a bare `String`, and that was the whole
/// reason row 8 of §16.1 could not be migrated: nineteen `colorize` calls across
/// six functions each knew exactly which columns they were painting — a track's
/// entire job is to fill exactly `width` cells — and not one of them had anywhere
/// to SAY so. The `Gauge`'s circular dials were a twentieth and twenty-first
/// (§36.6), which is what made this a type of its own rather than the track's.
///
/// **The one place a row's cells become bytes and the one place its claims are
/// derived**, for the reason `BorderRenderer.band` is (§18.3): the pairing —
/// opaque bytes, alpha in a region — is a rule about the paint, not about a call
/// site, and a drawing arm added later would otherwise silently reintroduce the
/// trap.
///
/// ## Its relatives, and why they are still separate
///
/// `TextFieldContentRenderer.RunAccumulator` does the same job for a text field
/// and keeps its own external column, because the caret is written out of band and
/// the field's `outputCells` is read elsewhere. Converting it would mean moving
/// that bookkeeping in here, which is a change to the field's cursor arithmetic
/// wearing a refactor's clothes. It shares this type's *rule* and states it at its
/// own declaration.
struct ClaimingRow {
    /// The finished ANSI row.
    var text = ""

    /// The cells owing a blend, in the row's own coordinates: column 0 is the
    /// first cell this row draws, whatever the caller puts to its left.
    var claims: [OpacityRegion] = []

    /// How many cells were drawn — which is not always the width that was asked
    /// for. The coarse track path permanently shrinks a track to a whole multiple
    /// of its quantum, and a claim must sit on what was DRAWN. Same lesson
    /// `Slider`'s right-arrow run already learned.
    var cells = 0

    /// Appends one run: `count` columns of `glyphs`, painted in `ink` on `field`.
    ///
    /// The claim is merged into the previous one where the two are adjacent and owe
    /// the same alphas, through the shared `appendCoalescing`: a ring dial's rim is
    /// drawn a cell at a time and is one colour for most of its length, so a claim
    /// per cell would state twenty rectangles where two will do. The BYTES are not
    /// merged, deliberately: this type does not know whether its caller's runs are
    /// separable, and every caller today emits its own SGR introducer per run anyway.
    mutating func append(_ glyphs: String, cells count: Int, ink: Color?, field: Color? = nil) {
        text += ANSIRenderer.colorize(
            glyphs, foreground: ink?.opaqueSpelling, background: field?.opaqueSpelling)
        claims.appendCoalescing(
            OpacityRegion.claim(
                offsetX: cells, width: count, height: 1, ink: ink, field: field))
        cells += count
    }

    /// Appends bytes that are already finished — a picture's placeholder cells —
    /// which owe no claim because this renderer chose no colour for them.
    mutating func appendFinished(_ chunk: String, cells count: Int) {
        text += chunk
        cells += count
    }

    /// Advances past cells this row draws nothing for.
    ///
    /// A gap, not a paint: the interior of a dial, the pad between a wall and its
    /// value. It states no colour, so it owes no claim and must not be merged into
    /// the run beside it — a claim spanning it would state an alpha for a cell whose
    /// ink came from somewhere else entirely.
    mutating func skip(cells count: Int) {
        text += String(repeating: " ", count: max(0, count))
        cells += max(0, count)
    }
}
