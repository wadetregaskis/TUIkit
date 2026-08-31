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
    static func styled(
        _ lines: [String], blockWidth: Int, frame: GradientFrame? = nil, paint: Paint,
        style: TextStyle, depth: ColorDepth, cellAspect: Double
    ) -> [String] {
        let extent = frame ?? GradientFrame(width: blockWidth, height: lines.count)
        guard
            let sampler = RampSampler(
                paint: paint, extent: extent, depth: depth, cellAspect: cellAspect)
        else {
            // Not a ramp, or a degenerate one — both mean paint flat.
            var flat = style
            flat.foregroundColor = paint.representative
            return lines.map { ANSIRenderer.render($0, with: flat) }
        }

        let reset = ANSIRenderer.reset
        var sequences: [String?] = []
        var result: [String] = []
        result.reserveCapacity(lines.count)

        for (row, line) in lines.enumerated() {
            guard sampler.variesAcrossRow else {
                // One colour for the whole row, so no run table and no per-cell
                // walk — just the wrapping `ANSIRenderer.render` would have
                // produced. Allocating the table here cost an array per leaf to
                // hold a single entry, which was the whole difference between
                // `.gradientExtent(.subtree)` and doing it by hand.
                var run = style
                run.foregroundColor = sampler.colour(row: row)
                let opening = ANSIRenderer.styleSequence(for: run) ?? ""
                result.append(opening.isEmpty ? line : opening + line + reset)
                continue
            }

            // One SGR introducer per ramp entry, built once. `ANSIRenderer.render`
            // re-derives a `TextStyle`'s codes and re-joins them on every call,
            // and a ramp that varies along a row changes colour every few cells.
            // `styleSequence(for:)` exists for exactly this, and its own note
            // says `sequence + text + reset` is byte-for-byte what `render`
            // produces.
            if sequences.isEmpty {
                sequences = [String?](repeating: nil, count: sampler.ramp.count)
            }
            let rowTerm = sampler.rowTerm(row)

            var painted = ""
            // Reserved for the worst case, which is what this path IS: a run
            // per cell, each an SGR introducer (up to ~19 bytes for truecolor)
            // plus a reset.
            painted.reserveCapacity(line.utf8.count * 25 + 16)
            var runStart = line.startIndex
            var runEntry = -1
            var column = 0
            var cursor = line.startIndex

            // Appended in place, never `a + b + c`: the `+` chain builds two
            // throwaway strings per run, and a horizontal ramp at truecolor is
            // one run per CELL.
            func flush(_ end: String.Index) {
                guard runEntry >= 0, runStart < end else { return }
                painted += sequences[runEntry] ?? ""
                painted += line[runStart..<end]
                painted += reset
            }

            while cursor < line.endIndex {
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
                        run.foregroundColor = sampler.ramp[next]
                        sequences[next] = ANSIRenderer.styleSequence(for: run) ?? ""
                    }
                }
                column += line[cursor].terminalWidth
                cursor = line.index(after: cursor)
            }
            flush(line.endIndex)
            result.append(painted)
        }
        return result
    }
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
            steps = max(2, Int((abs(axisX) * width + abs(axisY) * height).rounded()))
            mapping = .linear
            variesAcrossRow = axisX != 0
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
            steps = max(2, min(abs(endRadius - startRadius), Self.stepCeiling))
            mapping = Self.distance(from: Double(startRadius), to: Double(endRadius))
            variesAcrossRow = true
            columnScale = 1
            columnBase = originX + 0.5 - center.x * width
            rowScale = aspect
            rowBase = (originY + 0.5 - center.y * height) * aspect

        case .elliptical(let center, let startFraction, let endFraction):
            // Fractions of the box, so the box's own proportions ARE the
            // ellipse and there is no aspect to correct for.
            let span = abs(endFraction - startFraction)
            steps = max(2, min(Int((span * max(width, height)).rounded()), Self.stepCeiling))
            mapping = Self.distance(from: startFraction, to: endFraction)
            variesAcrossRow = true
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
            steps = max(2, min(Int((sweep * 2 * .pi * reach).rounded()), Self.stepCeiling))
            mapping = .sweep(
                base: -direction * startAngle.radians / (2 * .pi),
                scale: direction / (2 * .pi),
                span: sweep,
                // The far side of the arc the sweep does NOT cover: cells
                // before it take the ramp's end, cells after it its start.
                midpoint: (sweep + 1) / 2)
            variesAcrossRow = true
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
        return min(lastEntry, max(0, Int((along * stepScale).rounded())))
    }

    /// The colour of a whole row, for a ramp that does not vary along one.
    func colour(row: Int) -> Color {
        ramp[entry(column: 0, rowTerm: rowTerm(row))]
    }

    /// The `(columns, colour)` runs across one row, for a ramp that does.
    func runs(row: Int, cells: Int) -> [(columns: Range<Int>, colour: Color)] {
        guard cells > 0 else { return [] }
        let term = rowTerm(row)
        var out: [(columns: Range<Int>, colour: Color)] = []
        var start = 0
        var current = entry(column: 0, rowTerm: term)
        for column in 1..<cells {
            let next = entry(column: column, rowTerm: term)
            if next != current {
                out.append((start..<column, ramp[current]))
                start = column
                current = next
            }
        }
        out.append((start..<cells, ramp[current]))
        return out
    }
}
