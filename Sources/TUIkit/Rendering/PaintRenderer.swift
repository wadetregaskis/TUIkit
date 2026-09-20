//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaintRenderer.swift
//
//  Painting a block of text with something that is not one colour.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

import TUIkitCore
import TUIkitStyling

/// Turns a laid-out block of plain text into styled lines under a ``Paint``.
enum PaintRenderer {

    /// `lines` styled with `paint`, resolved over the block they form.
    ///
    /// The extent is the **block**, not the line — measured against SwiftUI,
    /// where a two-line `Text` under a horizontal gradient ends its short first
    /// line partway along the ramp rather than at the far end. So `t` comes
    /// from a cell's position in the whole rectangle.
    ///
    /// - Parameters:
    ///   - lines: The laid-out plain text, one string per row.
    ///   - blockWidth: The widest line — the rectangle's width in cells.
    ///   - style: Everything about the appearance except the foreground, which
    ///     is what the paint supplies.
    ///   - cellAspect: How many columns tall one row is, for the geometries
    ///     with a centre — ``EnvironmentValues/imageCellAspect``.
    /// - Parameter frame: The rectangle the ramp runs across and where these
    ///   lines sit in it, when a `.gradientExtent(.subtree)` is in force. `nil`
    ///   means the lines are their own extent, which is SwiftUI's per-leaf
    ///   meaning and the default.
    /// - Parameter lineWidths: Each line's visible width in CELLS, which only the
    ///   caller knows — a text block is ragged, and a claim must not outrun the line
    ///   it is about.
    /// - Returns: The painted lines, and the cells each owes a blend, one list per
    ///   line so the caller can interleave line spacing without moving them.
    static func styled(
        _ lines: [String], blockWidth: Int, lineWidths: [Int], frame: GradientFrame? = nil,
        paint: Paint, style: TextStyle, depth: ColorDepth, cellAspect: Double
    ) -> (lines: [String], claims: [[OpacityRegion]]) {
        func width(of row: Int) -> Int {
            lineWidths.indices.contains(row) ? lineWidths[row] : blockWidth
        }
        let fieldAlpha = style.backgroundColor?.alpha ?? .max
        let extent = frame ?? GradientFrame(width: blockWidth, height: lines.count)
        guard
            let sampler = RampSampler(
                paint: paint, extent: extent, depth: depth, cellAspect: cellAspect)
        else {
            // Not a ramp, or a degenerate one — both mean paint flat. Reachable with
            // a ONE-STOP gradient, which `Paint.solid` does not divert, so
            // `Gradient(colors: [.red.opacity(0.5)])` came through here and rendered
            // at full strength.
            var flat = style.opaqueColours
            flat.foregroundColor = paint.representative.opaqueSpelling
            return (
                lines.map { ANSIRenderer.render($0, with: flat) },
                lines.indices.map { row in
                    OpacityRegion.claim(
                        width: width(of: row), height: 1, ink: paint.representative,
                        field: style.backgroundColor).map { [$0] } ?? []
                }
            )
        }

        // The same two lines `BackgroundModifier` derives, for the same reason and in
        // the same order: what shape the INK's alpha is, and therefore whether its
        // bytes may state the opaque spelling.
        //
        // The FIELD is not part of that question. It is one rectangle per line on
        // every shape — `style.backgroundColor` is a flat colour, whatever the ramp
        // over it does — so it is always claimed and its bytes always state the
        // opaque spelling. Folding it into `shape` (an earlier version asked
        // `isOpaqueThroughout && fieldAlpha == .max`) got both ends wrong: an opaque
        // ramp over a faded background reported `.opaque` and claimed nothing, and a
        // per-cell one left the background's own bytes translucent while claiming it.
        let shape: RampSampler.AlphaShape =
            paint.isOpaqueThroughout ? .opaque : sampler.alphaShape
        // Whether ANY claim is possible, asked once of the shape rather than
        // rediscovered per line. `[]` rather than a list of empties — the contract
        // `Text.uniformAlphaClaims` already states and `rowed` already relies on — so
        // an opaque ramp grows no outer array at all. This runs per painted block per
        // frame, and `gradients` paints a great many of them.
        let wantsClaims = shape != .opaque || fieldAlpha != .max
        var bandStyle = style
        bandStyle.backgroundColor = style.backgroundColor?.opaqueSpelling
        var sequences: [String?] = []
        var result: [String] = []
        var claims: [[OpacityRegion]] = []
        result.reserveCapacity(lines.count)
        if wantsClaims { claims.reserveCapacity(lines.count) }
        for (row, line) in lines.enumerated() {
            // Deliberately NOT reserved here: the vertical case emits ONE run
            // for the whole row and reserving the varying case's worst case
            // for it cost 26 µs → 118 µs on a 40 × 100 block, measured. `band`
            // reserves where reserving is what the path needs.
            var painted = ""
            var column = 0
            band(
                line, column: &column, row: row, style: bandStyle, sampler: sampler,
                sequences: &sequences, into: &painted)
            result.append(painted)
            guard wantsClaims else { continue }
            claims.append(
                Self.claims(
                    for: shape, row: row, cells: width(of: row), sampler: sampler,
                    fieldAlpha: fieldAlpha))
        }
        return (result, claims)
    }

    /// One line's claims for a ramp of the given shape.
    ///
    /// All four shapes are rectangles; they differ in how many. The two that vary
    /// along the row are one case here — a run of equal alpha at a time — and the
    /// two that do not are a single rectangle each. See §36 for what the last of
    /// them cost, and §34.3 for the estimate it replaced.
    private static func claims(
        for shape: RampSampler.AlphaShape, row: Int, cells: Int,
        sampler: RampSampler, fieldAlpha: UInt8
    ) -> [OpacityRegion] {
        switch shape {
        case .opaque:
            // The FIELD alone. A rectangle is a rectangle whether or not the ink over
            // it is one, and refusing it for being adjacent to something unhonourable
            // would be a second gap for no reason. `claim` answers nil when the field
            // is opaque too, so an ordinary opaque ramp still costs nothing.
            return OpacityRegion.claim(
                offsetY: row, width: cells, height: 1, inkAlpha: .max, fieldAlpha: fieldAlpha)
                .map { [$0] } ?? []
        case .uniform(let alpha):
            return OpacityRegion.claim(
                offsetY: row, width: cells, height: 1, inkAlpha: alpha, fieldAlpha: fieldAlpha)
                .map { [$0] } ?? []
        case .perRow:
            return OpacityRegion.claim(
                offsetY: row, width: cells, height: 1, inkAlpha: sampler.colour(row: row).alpha,
                fieldAlpha: fieldAlpha)
                .map { [$0] } ?? []
        case .perColumn, .perCell:
            // One run of equal alpha at a time, which is the same walk for both
            // shapes: `perColumn` happens to give every row the same answer and
            // `perCell` a different one, and neither fact changes what a row owes.
            // Asking the sampler per row is what makes them one case — see
            // ``RampSampler/AlphaShape/perCell``, where the two used to part.
            //
            // Per line rather than one full-height strip, because a text block is
            // RAGGED: a strip as tall as the block would reach past a short line's
            // end, where there is nothing of this text to fade.
            return sampler.alphaClaims(
                row: row, line: row, columns: 0..<cells, fieldAlpha: fieldAlpha)
        }
    }

    /// The attributed twin: each line already cut into the pieces its
    /// concatenated `Text` gave it, so a ramp bands ACROSS the pieces instead
    /// of collapsing to one colour for the whole line.
    ///
    /// A piece that stated a colour of its own keeps it and is painted flat —
    /// `Text("a").foregroundStyle(.red) + Text("b")` under a ramp is a red "a"
    /// and a ramped "b", which is the precedence every other styling follows.
    ///
    /// ## Claims
    ///
    /// This returned bytes and nothing else until §36.5, which is why §16.3 listed
    /// "`Text`'s concatenated-run arm under a ramp" as not honoured: a fragment's
    /// own translucent colour was dropped here even though the very same colour on
    /// an unramped concatenation was claimed (`Text.fragmentAlphaClaims`), and the
    /// ramp's own alpha was dropped for every fragment it painted. Both halves are
    /// stated now, and they are two different derivations over one row:
    ///
    /// | piece | bytes | claim |
    /// |---|---|---|
    /// | states its own colour | its style's opaque spelling | its own ink and field |
    /// | takes the ramp | the ramp's opaque spelling | the ramp's alpha per run, plus the piece's own FIELD |
    ///
    /// - Parameters:
    ///   - lines: The laid-out lines, each in its styled pieces, left to right.
    ///   - blockWidth: The widest line — the rectangle's width in cells.
    ///   - frame: The rectangle the ramp runs across, as above.
    ///   - paint: What is being painted with.
    ///   - depth: The colour depth to quantise the ramp for.
    ///   - cellAspect: ``EnvironmentValues/imageCellAspect``.
    /// - Returns: One styled string per line, and one list of claims per line in
    ///   that line's own columns — `[]` for a block with nothing translucent in it,
    ///   which is the contract `Text.uniformAlphaClaims` states and `rowed` relies
    ///   on.
    static func styled(
        pieces lines: [[StyledPiece]], blockWidth: Int, frame: GradientFrame? = nil,
        paint: Paint, depth: ColorDepth, cellAspect: Double
    ) -> (lines: [String], claims: [[OpacityRegion]]) {
        let extent = frame ?? GradientFrame(width: blockWidth, height: lines.count)
        // Asked of the PAINT and the styles, which are a handful, before touching a
        // single fragment: the walk below costs a width per piece — a grapheme scan
        // in the general case — and every concatenated `Text` in an app would pay it
        // to discover that all its colours are opaque, which is the answer for
        // essentially all of them. §35.1's lesson, applied before it could recur.
        let wantsClaims =
            !paint.isOpaqueThroughout
            || lines.contains { pieces in
                pieces.contains {
                    $0.style.foregroundColor?.isOpaque == false
                        || $0.style.backgroundColor?.isOpaque == false
                }
            }
        guard
            let sampler = RampSampler(
                paint: paint, extent: extent, depth: depth, cellAspect: cellAspect)
        else {
            return flatPieces(lines, paint: paint, wantsClaims: wantsClaims)
        }

        // One sequence table per PIECE STYLE, not per line: the table caches an
        // SGR introducer per ramp entry, and an introducer is only reusable
        // among pieces that agree about everything else (bold, underline, the
        // background). Pieces are few — a concatenation is a handful of
        // fragments — so a small association list beats hashing a `TextStyle`.
        //
        // Keyed on the style as EMITTED, which is its opaque spelling: two pieces
        // differing only in a background's alpha put the same bytes on the screen,
        // and the difference between them is in the claim rather than in the table.
        var tables: [(style: TextStyle, sequences: [String?])] = []
        var result: [String] = []
        var claims: [[OpacityRegion]] = []
        result.reserveCapacity(lines.count)
        if wantsClaims { claims.reserveCapacity(lines.count) }

        for (row, pieces) in lines.enumerated() {
            var painted = ""
            var column = 0
            var rowClaims: [OpacityRegion] = []
            for piece in pieces {
                let start = column
                guard piece.takesRamp else {
                    painted += ANSIRenderer.render(piece.text, with: piece.style.opaqueColours)
                    column += piece.text.reduce(0) { $0 + $1.terminalWidth }
                    guard wantsClaims else { continue }
                    rowClaims.appendCoalescing(
                        OpacityRegion.claim(
                            offsetX: start, width: column - start, height: 1,
                            ink: piece.style.foregroundColor, field: piece.style.backgroundColor))
                    continue
                }
                let bandStyle = piece.style.opaqueColours
                var index = tables.firstIndex { $0.style == bandStyle }
                if index == nil {
                    tables.append((bandStyle, []))
                    index = tables.count - 1
                }
                band(
                    piece.text, column: &column, row: row, style: bandStyle,
                    sampler: sampler, sequences: &tables[index!].sequences, into: &painted)
                guard wantsClaims else { continue }
                // `band` leaves `column` where it was for a ramp that does not vary
                // along the row — deliberately, because nothing downstream read it and
                // advancing it is a grapheme walk per character (26 µs → 108 µs,
                // measured at its own note). A claim IS something downstream, so the
                // walk happens here and only when there is a claim to place.
                if !sampler.variesAcrossRow {
                    column = start + piece.text.reduce(0) { $0 + $1.terminalWidth }
                }
                rowClaims += sampler.alphaClaims(
                    row: row, line: row, columns: start..<column,
                    fieldAlpha: piece.style.backgroundColor?.alpha ?? .max)
            }
            result.append(painted)
            if wantsClaims { claims.append(rowClaims) }
        }
        return (result, claims)
    }

    /// Not a ramp, or a degenerate one — both mean paint flat, each piece in its own
    /// colour or the paint's.
    ///
    /// Its own function only because the ramped arm reached the complexity limit with
    /// it inline; it is a real seam, being the one arm with no sampler in it. A
    /// ONE-STOP gradient lands here (`RampSampler.init?` refuses it), and its
    /// representative can be translucent, so this arm claims too — a gap that stood
    /// until §36.5 for the same reason as the ramped one: the function returned bytes.
    private static func flatPieces(
        _ lines: [[StyledPiece]], paint: Paint, wantsClaims: Bool
    ) -> (lines: [String], claims: [[OpacityRegion]]) {
        let representative = paint.representative
        var painted: [String] = []
        var claims: [[OpacityRegion]] = []
        painted.reserveCapacity(lines.count)
        if wantsClaims { claims.reserveCapacity(lines.count) }
        for pieces in lines {
            var line = ""
            var row: [OpacityRegion] = []
            var column = 0
            for piece in pieces {
                var flat = piece.style
                if piece.takesRamp { flat.foregroundColor = representative }
                line += ANSIRenderer.render(piece.text, with: flat.opaqueColours)
                guard wantsClaims else { continue }
                let width = piece.text.reduce(0) { $0 + $1.terminalWidth }
                row.appendCoalescing(
                    OpacityRegion.claim(
                        offsetX: column, width: width, height: 1,
                        ink: flat.foregroundColor, field: flat.backgroundColor))
                column += width
            }
            painted.append(line)
            if wantsClaims { claims.append(row) }
        }
        return (painted, claims)
    }

    /// Paints one piece of a row, splitting it at the ramp's own boundaries.
    ///
    /// The single place the per-cell walk lives, so a plain line, one fragment
    /// of an attributed line and one cell of a `Table` row cannot disagree
    /// about where a colour changes.
    ///
    /// - Parameters:
    ///   - text: The piece, plain (no escapes of its own).
    ///   - column: Where the piece starts in the row; advanced past it.
    ///   - row: The row, for the sampler.
    ///   - style: Everything except the foreground, which the ramp supplies.
    ///   - sampler: The ramp over the rectangle.
    ///   - sequences: One SGR introducer per ramp entry for `style`, built on
    ///     demand and reused across every row this style paints.
    ///   - painted: The row being assembled; appended to in place, never
    ///     `a + b + c`, which would build two throwaway strings per run — and a
    ///     horizontal ramp at truecolor is one run per CELL.
    ///
    /// The ramp's colours go into the bytes at their OPAQUE spelling, always — an
    /// emitter has no backdrop to composite against, so a translucent colour has no
    /// SGR spelling at all. `style`'s own colours are the CALLER's to spell, because
    /// the caller is the one that claimed them.
    ///
    /// There was a `carriesAlpha: Bool` here until §36. It existed for the one arm
    /// whose alpha was dropped rather than claimed — the bytes went in raw so the
    /// emitter's assertion still fired, because spelling them opaque without a claim
    /// turns a loud gap into a silently discarded alpha (§18.3). Every arm claims
    /// now, so the flag had one value, and a flag with one value is a place for the
    /// next caller to guess wrong.
    static func band(
        _ text: String, column: inout Int, row: Int, style: TextStyle,
        sampler: RampSampler, sequences: inout [String?], into painted: inout String
    ) {
        guard !text.isEmpty else { return }
        let reset = ANSIRenderer.reset

        guard sampler.variesAcrossRow else {
            // One colour for the whole row, so no run table and no per-cell
            // walk — just the wrapping `ANSIRenderer.render` would have
            // produced. Allocating the table here cost an array per leaf to
            // hold a single entry, which was the whole difference between
            // `.gradientExtent(.subtree)` and doing it by hand.
            var run = style
            let colour = sampler.colour(row: row)
            run.foregroundColor = colour.opaqueSpelling
            let opening = ANSIRenderer.styleSequence(for: run) ?? ""
            painted += opening.isEmpty ? text : opening + text + reset
            // `column` is deliberately left where it was. Nothing downstream
            // reads it on this path — the row has ONE colour, so where a later
            // piece starts cannot change what it is — and advancing it means a
            // grapheme walk and a width lookup per character, which is 26 µs →
            // 108 µs on a 40 × 100 block. Measured.
            return
        }

        // Reserved for the worst case, which is what THIS path is: a run per
        // cell, each an SGR introducer (up to ~19 bytes for truecolor) plus a
        // reset. The row above it emits one run and reserves nothing.
        //
        // `Table`'s row loops call this per CELL, onto an accumulator they
        // already reserved, so the request repeats and climbs. That is NOT the
        // shape 26ebf26f fixed. That finding is about `Array`, which sizes to
        // exactly what is asked for, so reserving the final length on each of
        // N appends reallocates on each of them. `String` rounds up instead.
        // Measured on 6.2.4 `-O` with a storage-ADDRESS oracle, because the
        // `capacity` that would answer it directly is not public on `String`
        // — which is also why a "reserve only when short" form cannot be
        // written here. Appending 384 bytes a cell onto a 192-byte reserve,
        // the buffer moves at the same byte counts whether or not the per-cell
        // reserve runs: 384, 768, 1152, 2304, 4224, 8448, 16512, 33024, 65664
        // — ~2x geometric, 9 moves across 200 cells either way, byte for byte
        // identical to the no-reserve control. `reserveCapacity(1000)` then
        // took 1496 bytes before moving.
        //
        // So the repeat buys no copy and costs only the call: 422.6 vs 409.4
        // ns for a 6-cell row in isolation (+3.2%, against a 0.65% null), ~2
        // ns a cell next to a cell that also walks a grapheme, looks up a
        // width and appends three times. Reserving in the callers cannot
        // recover that — the call still happens — and deleting it would hand
        // back the ~7% a559b2ef measured on the two callers above, where
        // `painted` starts as `""` in small-string form.
        painted.reserveCapacity(painted.utf8.count + text.utf8.count * 25 + 16)

        // One SGR introducer per ramp entry, built once. `ANSIRenderer.render`
        // re-derives a `TextStyle`'s codes and re-joins them on every call,
        // and a ramp that varies along a row changes colour every few cells.
        // `styleSequence(for:)` exists for exactly this, and its own note says
        // `sequence + text + reset` is byte-for-byte what `render` produces.
        if sequences.isEmpty {
            sequences = [String?](repeating: nil, count: sampler.ramp.count)
        }
        let rowTerm = sampler.rowTerm(row)
        var runStart = text.startIndex
        var runEntry = -1
        var cursor = text.startIndex

        func flush(_ end: String.Index) {
            guard runEntry >= 0, runStart < end else { return }
            painted += sequences[runEntry] ?? ""
            painted += text[runStart..<end]
            painted += reset
        }

        while cursor < text.endIndex {
            // The cell the character STARTS at decides its colour: a wide
            // glyph is one glyph, and splitting a colour across it is not
            // something a terminal can draw.
            let next = sampler.entry(column: column, rowTerm: rowTerm)
            if next != runEntry {
                flush(cursor)
                runEntry = next
                runStart = cursor
                if sequences[next] == nil {
                    var run = style
                    run.foregroundColor = sampler.ramp[next].opaqueSpelling
                    sequences[next] = ANSIRenderer.styleSequence(for: run) ?? ""
                }
            }
            column += text[cursor].terminalWidth
            cursor = text.index(after: cursor)
        }
        flush(text.endIndex)
    }
}

// MARK: - A piece of an attributed line

/// One run of a laid-out line that carries its own styling.
///
/// What a concatenated ``Text`` hands the painter: the fragments of one
/// wrapped line, left to right, each with the style its own `Text` resolved.
struct StyledPiece {
    /// The characters, plain — no escapes of its own.
    let text: String

    /// Everything about the appearance except, perhaps, the foreground.
    let style: TextStyle

    /// Whether the ramp supplies this piece's foreground.
    ///
    /// `false` for a fragment that stated a colour of its own, which keeps it:
    /// an explicit colour beats an inherited style here as it does everywhere.
    let takesRamp: Bool
}

// MARK: - Sampling a ramp over a rectangle

/// Where a ramp lands on each cell of a rectangle.
///
/// Built once per painted view and asked per cell, so the setup does the
/// divisions and the trigonometry and the query does an add, a multiply and a
/// round. Shared by the foreground path
/// (``PaintRenderer/styled(_:blockWidth:frame:paint:style:depth:cellAspect:)``)
/// and the background one (`BackgroundModifier`), because "which colour is this
/// cell" is one question however it is being used.
///
/// All four geometries reduce to the same two stages: an affine map from
/// `(column, row)` to the geometry's own coordinates, then a ``Mapping`` from
/// those to `t`. That is why a radial gradient costs a square root and an
/// angular one an `atan2`, and a linear one still costs neither.
struct RampSampler {
    /// The quantised ramp — sampled once at the resolution it actually spans,
    /// so `quantisedRamp`'s monotonicity repair applies to the SEQUENCE. A
    /// per-cell nearest match has no memory of its neighbours, which is the
    /// banding that repair exists to remove.
    let ramp: [Color]

    /// Whether the colour changes along a row. It does not for a vertical
    /// linear ramp, and that collapses the whole per-cell walk to one run —
    /// which matters, because "a ramp down a list" is the common ask. Every
    /// other geometry has a centre, so every other geometry varies.
    let variesAcrossRow: Bool

    /// Whether the colour changes down a column — the mirror of
    /// ``variesAcrossRow``, and false for a HORIZONTAL linear ramp.
    ///
    /// Beside its twin because the two are one fact about the geometry and a
    /// second derivation of either would drift. It exists because a horizontal
    /// ramp is the commonest one anyone writes — a fade along a header, a bar, a
    /// title — and without this it was classified `perCell` and declined, when
    /// its alpha is in fact one full-height rectangle per column.
    let variesDownColumn: Bool

    /// How `t` comes out of a cell's mapped coordinates.
    private enum Mapping {
        /// The coordinates ARE `t`: a linear ramp is affine in the cell's
        /// position, so both halves fold into the offsets and nothing is left
        /// to do.
        case linear

        /// `t` is affine in the distance from the centre — radial (distance in
        /// cells) and elliptical (distance in fractions of the box) differ
        /// only in what the offsets were divided by.
        case distance(base: Double, scale: Double)

        /// `t` is the position of the cell's angle within the sweep, and
        /// outside the sweep it is whichever end is nearer.
        case sweep(base: Double, scale: Double, span: Double, midpoint: Double)
    }

    private let mapping: Mapping
    /// The affine map from a column to the geometry's horizontal coordinate:
    /// `t`'s column term for a linear ramp, the offset from the centre for the
    /// rest.
    private let columnBase: Double
    private let columnScale: Double
    /// The same for a row. See ``rowTerm(_:)``, which is where it is applied.
    private let rowBase: Double
    private let rowScale: Double
    private let stepScale: Double
    private let lastEntry: Int

    /// `nil` when the paint is not a ramp, or names a degenerate one — the
    /// caller then paints flat, which is what those mean.
    ///
    /// - Parameters:
    ///   - paint: What is being painted with.
    ///   - extent: The rectangle the ramp runs across, and where the thing
    ///     being drawn sits inside it.
    ///   - depth: The colour depth to quantise the ramp for.
    ///   - cellAspect: How many columns tall one row is — ``EnvironmentValues/imageCellAspect``.
    ///     Only the geometries with a centre use it, and they use it so that a
    ///     circle looks like one.
    init?(paint: Paint, extent: GradientFrame, depth: ColorDepth, cellAspect: Double) {
        guard case .gradient(let ramped) = paint else { return nil }
        // One stop is a solid colour: `nil` sends the caller down the flat
        // path, which paints the paint's representative — that colour — with
        // no ramp, no run table and no per-cell walk.
        guard ramped.gradient.stops.count > 1 else { return nil }
        // `.in(_:)` names the rectangle outright, and it re-anchors: a leaf
        // resolves at its own origin over that size, which is what makes it a
        // scale knob rather than a second `.gradientExtent(.subtree)`.
        let extent = ramped.extent.map {
            GradientFrame(width: $0.width, height: $0.height)
        } ?? extent
        let width = Double(max(1, extent.width))
        let height = Double(max(1, extent.height))
        let aspect = cellAspect > 0 ? cellAspect : 2
        let originX = Double(extent.originX)
        let originY = Double(extent.originY)
        let steps: Int

        switch ramped.geometry {
        case .linear(let from, let to):
            let axisX = to.x - from.x
            let axisY = to.y - from.y
            let lengthSquared = axisX * axisX + axisY * axisY
            guard lengthSquared > 0 else { return nil }
            // `along` is affine in the cell's coordinates, so it splits into a
            // term per column and a term per row. Precomputing both halves
            // turns the inner loop — which runs once per CELL of every painted
            // view — into an add, a multiply and a round.
            // Ceilinged like the other three, which it was not: a
            // `UnitPoint` an order of magnitude out of range asked for a ramp
            // of millions of entries and quantised every one of them.
            guard let count = Self.steps(abs(axisX) * width + abs(axisY) * height) else {
                return nil
            }
            steps = count
            mapping = .linear
            variesAcrossRow = axisX != 0
            // `rowScale` and `rowBase` are BOTH zero when `axisY == 0` — see the
            // two assignments below — so `rowTerm(row)` is zero for every row and
            // the entry depends on the column alone.
            variesDownColumn = axisY != 0
            columnScale = axisX / lengthSquared / width
            columnBase =
                (originX + 0.5) / width * (axisX / lengthSquared)
                - from.x * axisX / lengthSquared
            rowScale = axisY / lengthSquared / height
            rowBase =
                (originY + 0.5) / height * (axisY / lengthSquared)
                - from.y * axisY / lengthSquared

        case .radial(let center, let startRadius, let endRadius):
            // A radius is cells along the horizontal axis; a row is `aspect`
            // of those tall, which is what keeps a circle circular.
            // Through `Double`, because `endRadius - startRadius` overflows
            // for radii at the ends of `Int` and `abs` traps on `Int.min`.
            guard let count = Self.steps(abs(Double(endRadius) - Double(startRadius))) else {
                return nil
            }
            steps = count
            mapping = Self.distance(from: Double(startRadius), to: Double(endRadius))
            variesAcrossRow = true
            variesDownColumn = true
            columnScale = 1
            columnBase = originX + 0.5 - center.x * width
            rowScale = aspect
            rowBase = (originY + 0.5 - center.y * height) * aspect

        case .elliptical(let center, let startFraction, let endFraction):
            // Fractions of the box, so the box's own proportions ARE the
            // ellipse and there is no aspect to correct for.
            let span = abs(endFraction - startFraction)
            guard let count = Self.steps(span * max(width, height)) else { return nil }
            steps = count
            mapping = Self.distance(from: startFraction, to: endFraction)
            variesAcrossRow = true
            variesDownColumn = true
            columnScale = 1 / width
            columnBase = (originX + 0.5 - center.x * width) / width
            rowScale = 1 / height
            rowBase = (originY + 0.5 - center.y * height) / height

        case .angular(let center, let startAngle, let endAngle):
            let turns = (endAngle.radians - startAngle.radians) / (2 * .pi)
            let sweep = abs(turns)
            let direction: Double = turns < 0 ? -1 : 1
            // One entry per cell of the longest arc the sweep can draw inside
            // the extent: any finer is invisible, any coarser bands.
            let reach = ((width * width) + (height * aspect * height * aspect)).squareRoot() / 2
            guard let count = Self.steps(sweep * 2 * .pi * reach) else { return nil }
            steps = count
            mapping = .sweep(
                base: -direction * startAngle.radians / (2 * .pi),
                scale: direction / (2 * .pi),
                span: sweep,
                // The far side of the arc the sweep does NOT cover: cells
                // before it take the ramp's end, cells after it its start.
                midpoint: (sweep + 1) / 2)
            variesAcrossRow = true
            variesDownColumn = true
            columnScale = 1
            columnBase = originX + 0.5 - center.x * width
            rowScale = aspect
            rowBase = (originY + 0.5 - center.y * height) * aspect
        }

        let sampled = Color.quantisedRamp(ramped.gradient, count: steps, depth: depth)
        guard !sampled.isEmpty else { return nil }
        ramp = sampled
        stepScale = Double(steps - 1)
        lastEntry = sampled.count - 1
    }

    /// How many ramp entries a geometry's own arithmetic asks for, or `nil`
    /// when it has not asked for a number at all.
    ///
    /// The four geometries all reach a step count through arithmetic on values
    /// a caller supplies, and `UnitPoint`, `Angle` and the radius fractions are
    /// public, unvalidated and `Double`. A NaN or an infinity in any of them
    /// reaches `Int(_: Double)`, which traps — so this answers `nil` instead
    /// and `init?` returns `nil`, which is the answer the sampler already has
    /// for a degenerate ramp: paint flat. A caller handing a gradient a NaN has
    /// a bug, but a crash three frames later is a worse way to be told about it
    /// than a flat fill.
    ///
    /// - Parameter count: The geometry's own number.
    /// - Returns: A usable step count, or `nil` when there is not one.
    private static func steps(_ count: Double) -> Int? {
        guard count.isFinite else { return nil }
        return max(2, Int(min(Double(stepCeiling), max(0, count.rounded()))))
    }

    /// A ramp of more entries than this cannot be told apart on any terminal
    /// anyone has, and radii are a number a caller can type.
    private static let stepCeiling = 4096

    /// The affine that turns a distance into `t`.
    ///
    /// Equal radii are a hard edge rather than a ramp: SwiftUI draws the last
    /// stop inside it and the first outside, which a slope steep enough to
    /// saturate either side reproduces — without the infinity that would make
    /// a cell exactly ON the edge a NaN, and NaN is the one value the entry
    /// clamp cannot survive.
    private static func distance(from start: Double, to end: Double) -> Mapping {
        let span = end - start
        guard span != 0 else { return .distance(base: start * 1e9, scale: -1e9) }
        return .distance(base: -start / span, scale: 1 / span)
    }

    /// The row's contribution, hoisted out of the cell loop. Squared for the
    /// distance geometries, because the square root wants the sum and not the
    /// operands.
    func rowTerm(_ row: Int) -> Double {
        let offset = rowBase + rowScale * Double(row)
        if case .distance = mapping { return offset * offset }
        return offset
    }

    /// Which ramp entry a cell takes, given its row's precomputed term.
    @inline(__always)
    func entry(column: Int, rowTerm: Double) -> Int {
        let along: Double
        switch mapping {
        case .linear:
            along = columnBase + columnScale * Double(column) + rowTerm
        case .distance(let base, let scale):
            let offset = columnBase + columnScale * Double(column)
            along = base + scale * (offset * offset + rowTerm).squareRoot()
        case .sweep(let base, let scale, let span, let midpoint):
            let offset = columnBase + columnScale * Double(column)
            var turn = base + scale * atan2(rowTerm, offset)
            turn -= turn.rounded(.down)
            if turn > span {
                along = turn < midpoint ? 1 : 0
            } else {
                along = span > 0 ? turn / span : 0
            }
        }
        // Clamped BEFORE the conversion, not after: `Int(_: Double)` traps on
        // a NaN or an infinity, so a clamp on the far side of it never runs.
        // `max(0, .nan)` is 0 — Swift's `max` returns its first argument when
        // the comparison is false, and every comparison with a NaN is — so a
        // geometry that has gone non-finite paints the ramp's start rather than
        // killing the process. Same two comparisons either way; only the order
        // changed.
        return Int(min(Double(lastEntry), max(0, (along * stepScale).rounded())))
    }

    /// The colour of a whole row, for a ramp that does not vary along one.
    func colour(row: Int) -> Color {
        ramp[entry(column: 0, rowTerm: rowTerm(row))]
    }

    /// How much of this ramp's translucency can be stated as rectangles.
    ///
    /// A colour's alpha reaches the screen through an `OpacityRegion`, which is a
    /// rectangle carrying one alpha — so what can be honoured is decided by
    /// whether a rectangle can be drawn around each distinct alpha.
    ///
    /// All four are rectangles now; what differs is HOW MANY. A uniform ramp is
    /// one for the whole block, a vertical one is a row each, a horizontal one a
    /// strip each, and only the shapes that vary in both directions need a
    /// rectangle per run per row. The distinction is what lets the cheap shapes
    /// stay cheap rather than every ramp paying the expensive shape's price.
    enum AlphaShape: Equatable {
        /// Every entry is opaque. Nothing to state.
        case opaque

        /// One alpha for the whole ramp: `Gradient(colors: [.red.opacity(0.5),
        /// .blue.opacity(0.5)])`, and any ramp between two spellings of one
        /// alpha. `Color.lerp` interpolates alpha as a fourth channel, so equal
        /// endpoints give a constant.
        case uniform(UInt8)

        /// One colour per row, therefore one alpha per row — a vertical linear
        /// ramp, which is the shape a scrim fading a list out at the bottom has.
        /// A rectangle each.
        case perRow

        /// One colour per column, therefore one alpha per column — a HORIZONTAL
        /// linear ramp, which is the shape a fade along a header or a bar has, and
        /// the commonest ramp anyone writes. A full-height rectangle each.
        ///
        /// The mirror of ``perRow``, and it was missing: the classifier asked only
        /// whether the colour varied ACROSS a row, so every horizontal ramp fell
        /// into ``perCell`` and was declined for a cost it does not have.
        case perColumn

        /// The alpha changes along a row AND down a column — radial, angular,
        /// elliptical, or a diagonal linear ramp. A run of equal alpha per ROW,
        /// which is ``perColumn``'s walk repeated rather than shared: the only
        /// shape whose claim count grows with the block's AREA.
        ///
        /// Declined on cost until §36, when the resolver stopped answering per
        /// column across the regions and started answering per row across them —
        /// which is what made the count affordable. The case is still named
        /// separately from ``perColumn`` because the two cost different amounts,
        /// and a shape that cost nothing to tell apart is worth telling apart.
        case perCell
    }

    /// - Returns: The narrowest ``AlphaShape`` that describes this ramp.
    var alphaShape: AlphaShape {
        guard let first = ramp.first else { return .opaque }
        var sharesOneAlpha = true
        var allOpaque = true
        for colour in ramp {
            if colour.alpha != first.alpha { sharesOneAlpha = false }
            if colour.alpha != .max { allOpaque = false }
            if !sharesOneAlpha, !allOpaque { break }
        }
        if allOpaque { return .opaque }
        if sharesOneAlpha { return .uniform(first.alpha) }
        // Narrowest first: a ramp that is invariant in EITHER direction is a strip,
        // and only one that varies in both is genuinely per cell.
        if !variesAcrossRow { return .perRow }
        if !variesDownColumn { return .perColumn }
        return .perCell
    }

    /// The `(columns, alpha)` runs across a span of one row — the claim twin of
    /// ``runs(row:cells:)``.
    ///
    /// A COLUMN RANGE rather than a cell count, because a `Table` claims the span
    /// it actually painted: its cells start past the selection gutter, and a run
    /// that began at column 0 would state the alpha of a cell one column to the
    /// left of the one it was painted for.
    ///
    /// A separate walk rather than a `map` over that one, because it coalesces on a
    /// different key. `runs` breaks at every change of ramp ENTRY, which is right
    /// for emitting colour and wrong for a claim: two adjacent entries usually
    /// share an alpha, so a claim per colour run over-splits — a `uniform` ramp
    /// would come back as eighty width-1 rectangles instead of one.
    func alphaRuns(row: Int, columns: Range<Int>) -> [(columns: Range<Int>, alpha: UInt8)] {
        guard !columns.isEmpty, !ramp.isEmpty else { return [] }
        let term = rowTerm(row)
        func alpha(at column: Int) -> UInt8 {
            ramp[max(0, min(ramp.count - 1, entry(column: column, rowTerm: term)))].alpha
        }
        var out: [(columns: Range<Int>, alpha: UInt8)] = []
        var start = columns.lowerBound
        var current = alpha(at: start)
        for column in (start + 1)..<columns.upperBound {
            let next = alpha(at: column)
            if next != current {
                out.append((start..<column, current))
                start = column
                current = next
            }
        }
        out.append((start..<columns.upperBound, current))
        return out
    }

    /// The claims this ramp owes for the cells it painted across `columns` of
    /// `row` — one rectangle per run of equal alpha.
    ///
    /// The one derivation, because there are two callers and they are in different
    /// files: `PaintRenderer.claims` states it for a block of text, and a `Table`'s
    /// row renderer for the span its cells occupy. Both had the same four lines in
    /// them, which is how `List` and `Table` drift (see `SelectableRowClaims`).
    ///
    /// - Parameters:
    ///   - row: The ramp's row — which for a tall table row is the ROW's step, shared
    ///     by every line of it.
    ///   - line: The line the claim lands on, in the carrying buffer's coordinates.
    ///     The same as `row` wherever the ramp's rows and the buffer's are the same
    ///     rows, and not for a `Table`.
    ///   - columns: The span actually painted. A `Table`'s cells start past the
    ///     selection gutter, and the padding past the last column is bare — an ink
    ///     claim on a cell with no ink of its own lets what is behind it through.
    ///   - fieldAlpha: A flat background's alpha, folded into the same rectangle
    ///     rather than claimed as a second one over the same cells: overlapping
    ///     claims multiply at the resolver, so two regions would give the same
    ///     answer at twice the count, and this path is the hot one.
    func alphaClaims(
        row: Int, line: Int, columns: Range<Int>, fieldAlpha: UInt8 = .max
    ) -> [OpacityRegion] {
        alphaRuns(row: row, columns: columns).compactMap { run in
            OpacityRegion.claim(
                offsetX: run.columns.lowerBound, offsetY: line, width: run.columns.count,
                height: 1, inkAlpha: run.alpha, fieldAlpha: fieldAlpha)
        }
    }

    /// The `(columns, entry)` runs across one row, for a ramp that does.
    ///
    /// The ramp ENTRY rather than the colour, so a caller can key a table on
    /// it — the background twin of what
    /// ``PaintRenderer/band(_:column:row:style:sampler:sequences:into:)`` does
    /// with `sequences`. ``ramp`` subscripted by it is the colour, one lookup
    /// away, and the walk already had the index in hand.
    func runs(row: Int, cells: Int) -> [(columns: Range<Int>, entry: Int)] {
        guard cells > 0 else { return [] }
        let term = rowTerm(row)
        var out: [(columns: Range<Int>, entry: Int)] = []
        var start = 0
        var current = entry(column: 0, rowTerm: term)
        for column in 1..<cells {
            let next = entry(column: column, rowTerm: term)
            if next != current {
                out.append((start..<column, current))
                start = column
                current = next
            }
        }
        out.append((start..<cells, current))
        return out
    }
}
