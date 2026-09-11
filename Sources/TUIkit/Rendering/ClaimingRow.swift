//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClaimingRow.swift
//
//  A row of cells being assembled, together with the claim each run of them
//  owes — the two halves of a translucent paint, written in one place so they
//  cannot drift apart. And its transpose, a column one cell wide.
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
/// `TextFieldContentRenderer.RunAccumulator` does the same job for a text field and
/// a `TextEditor`'s rows, and keeps its own external column, because in both the
/// caret is written out of band and `outputCells` is read elsewhere. Converting it
/// would mean moving
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

    /// Appends one run: `count` columns of `glyphs`, painted in `ink` on `field`, and
    /// emboldened if asked. `bold` is passed straight to the emitter and does not enter
    /// the claim — a bold cell owes exactly what a plain one does.
    ///
    /// The claim is merged into the previous one where the two are adjacent and owe
    /// the same alphas, through the shared `appendCoalescing`: a ring dial's rim is
    /// drawn a cell at a time and is one colour for most of its length, so a claim
    /// per cell would state twenty rectangles where two will do. The BYTES are not
    /// merged, deliberately: this type does not know whether its caller's runs are
    /// separable, and every caller today emits its own SGR introducer per run anyway.
    mutating func append(
        _ glyphs: String, cells count: Int, ink: Color?, field: Color? = nil, bold: Bool = false
    ) {
        text += ANSIRenderer.colorize(
            glyphs, foreground: ink?.opaqueSpelling, background: field?.opaqueSpelling, bold: bold)
        claims.appendCoalescing(
            OpacityRegion.claim(
                offsetX: cells, width: count, height: 1, ink: ink, field: field))
        cells += count
    }

    /// Appends bytes that are already finished — a picture's placeholder cells, or a
    /// child's rendered line whose claims travel on its own buffer — which owe no
    /// claim here because this renderer chose no colour for them.
    mutating func appendFinished(_ chunk: String, cells count: Int) {
        text += chunk
        cells += count
    }

    /// Appends another row after this one: its bytes, and its claims moved to the
    /// columns they now sit at.
    ///
    /// For a piece drawn by a function of its own — a folder tab's label, a panel row
    /// between two walls — because an animation's frames must be the same cells the
    /// render drew, so the piece is built once for the line and again per frame.
    /// Splicing it here keeps its claims' columns this row's arithmetic, not the
    /// caller's.
    mutating func append(contentsOf row: Self) {
        text += row.text
        for claim in row.claims { claims.appendCoalescing(claim.shifted(byX: cells, y: 0)) }
        cells += row.cells
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

// MARK: - A column of single cells

/// A column one cell wide, assembled a line at a time: each line's finished bytes,
/// and the cells that owe a blend.
///
/// The transpose of ``ClaimingRow``, and built out of it — every cell goes through
/// `ClaimingRow.append`, so the pairing is still stated in exactly one place. Its
/// user is the vertical scrollbar, which used to be `[String]`: one styled cell per
/// line, handed to call sites that each put it at a column of their own, with
/// nowhere for a claim to travel (§40.2). Claims in the column's own coordinates
/// are what let each of them place the bar with one shift.
struct ClaimingColumn {
    /// One finished single-cell string per line, top to bottom.
    private(set) var lines: [String] = []

    /// The cells owing a blend, in the column's own coordinates: column 0, and row
    /// N for line N. Cells stacked on one another that owe the same alphas are one
    /// rectangle — see `appendCoalescing`.
    private(set) var claims: [OpacityRegion] = []

    var count: Int { lines.count }

    var isEmpty: Bool { lines.isEmpty }

    /// Appends one line: a single cell of `glyph`, painted in `ink` on `field`.
    mutating func append(_ glyph: String, ink: Color?, field: Color?) {
        var cell = ClaimingRow()
        cell.append(glyph, cells: 1, ink: ink, field: field)
        let line = lines.count
        lines.append(cell.text)
        for claim in cell.claims { claims.appendCoalescing(claim.shifted(byX: 0, y: line)) }
    }

    /// Cuts or pads the column to exactly `count` lines — padding with blank cells
    /// painted in `field`, and cutting each claim back to the lines that are left.
    ///
    /// Every caller pairs the column with lines of its own, one for one, and the two
    /// counts are not always equal: a list pads a bar shorter than its rows with
    /// plain track, and a menu draws fewer rows than its bar is tall when it has
    /// fewer to show. Stated here so a claim cannot outlive the line it was for.
    mutating func fit(toCount count: Int, field: Color?) {
        let count = max(0, count)
        if lines.count > count {
            lines.removeLast(lines.count - count)
            claims = claims.compactMap { $0.clipped(toColumns: 0..<1, rows: 0..<count) }
        }
        while lines.count < count { append(" ", ink: nil, field: field) }
    }

    /// The claims where the column is drawn: in `column`, its line 0 on `row`.
    func claims(atColumn column: Int, row: Int = 0) -> [OpacityRegion] {
        claims.map { $0.shifted(byX: column, y: row) }
    }
}

// MARK: - A run's frames and the one claim under them

/// Traps, in a debug build, when the frames of one breath do not all owe the same
/// claims.
///
/// A run replays BYTES, and the bytes are opaque spellings. The alpha is in the drawn
/// picture's claims, which the resolver applies to every frame of a run at one alpha
/// per cell (§29.2) — so a run is right only if every frame owes exactly what the
/// drawn one does. A breath whose ends disagree about alpha blends all but one of its
/// frames at the wrong alpha with nothing on screen to say so, since the bytes are
/// fine; this is what says so. The scrollbar's breath is where it was written and what
/// it first caught (§44); anything that pre-renders a cycle and claims under it owes
/// the same check.
///
/// - Parameters:
///   - claims: Each frame's claims, in the drawn picture's own coordinates.
///   - what: Whose frames these are, for the message — "a scrollbar's pulse".
func assertFramesOweOneClaim(_ claims: [[OpacityRegion]], _ what: @autoclosure () -> String) {
    assert(
        claims.allSatisfy { $0 == claims.first },
        "\(what()) frames owe different claims: its breath's two ends disagree about alpha (§29)")
}
