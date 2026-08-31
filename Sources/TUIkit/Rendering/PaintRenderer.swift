//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaintRenderer.swift
//
//  Painting a block of text with something that is not one colour.
//
//  Created by Wade Tregaskis
//  License: MIT

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
    /// - Parameter frame: The rectangle the ramp runs across and where these
    ///   lines sit in it, when a `.gradientExtent(.subtree)` is in force. `nil`
    ///   means the lines are their own extent, which is SwiftUI's per-leaf
    ///   meaning and the default.
    static func styled(
        _ lines: [String], blockWidth: Int, frame: GradientFrame? = nil, paint: Paint,
        style: TextStyle, depth: ColorDepth
    ) -> [String] {
        let extent = frame ?? GradientFrame(width: blockWidth, height: lines.count)
        guard let sampler = RampSampler(paint: paint, extent: extent, depth: depth) else {
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
/// division and the query does an add, a multiply and a round. Shared by the
/// foreground path (``PaintRenderer/styled(_:blockWidth:frame:paint:style:depth:)``)
/// and the background one (`BackgroundModifier`), because "which colour is this
/// cell" is one question however it is being used.
struct RampSampler {
    /// The quantised ramp — sampled once at the resolution it actually spans,
    /// so `quantisedRamp`'s monotonicity repair applies to the SEQUENCE. A
    /// per-cell nearest match has no memory of its neighbours, which is the
    /// banding that repair exists to remove.
    let ramp: [Color]

    /// Whether the colour changes along a row. It does not for a vertical
    /// ramp, and that collapses the whole per-cell walk to one run — which
    /// matters, because "a ramp down a list" is the common ask.
    let variesAcrossRow: Bool

    private let columnBase: Double
    private let columnScale: Double
    private let rowBase: Double
    private let rowScale: Double
    private let stepScale: Double
    private let lastEntry: Int

    /// `nil` when the paint is not a ramp, or names a degenerate one — the
    /// caller then paints flat, which is what those mean.
    init?(paint: Paint, extent: GradientFrame, depth: ColorDepth) {
        guard case .linear(let gradient, let from, let to) = paint else { return nil }
        let width = Double(max(1, extent.width))
        let height = Double(max(1, extent.height))
        let axisX = to.x - from.x
        let axisY = to.y - from.y
        let lengthSquared = axisX * axisX + axisY * axisY
        guard lengthSquared > 0 else { return nil }

        let steps = max(2, Int((abs(axisX) * width + abs(axisY) * height).rounded()))
        let sampled = Color.quantisedRamp(gradient, count: steps, depth: depth)
        guard !sampled.isEmpty else { return nil }

        // `along` is affine in the cell's coordinates, so it splits into a term
        // per column and a term per row. Precomputing both halves turns the
        // inner loop — which runs once per CELL of every painted view — into an
        // add, a multiply and a round.
        ramp = sampled
        variesAcrossRow = axisX != 0
        stepScale = Double(steps - 1)
        lastEntry = sampled.count - 1
        columnScale = axisX / lengthSquared / width
        columnBase =
            (Double(extent.originX) + 0.5) / width * (axisX / lengthSquared)
            - from.x * axisX / lengthSquared
        rowScale = axisY / lengthSquared / height
        rowBase =
            (Double(extent.originY) + 0.5) / height * (axisY / lengthSquared)
            - from.y * axisY / lengthSquared
    }

    /// The row's contribution to `along`, hoisted out of the cell loop.
    func rowTerm(_ row: Int) -> Double { rowBase + rowScale * Double(row) }

    /// Which ramp entry a cell takes, given its row's precomputed term.
    @inline(__always)
    func entry(column: Int, rowTerm: Double) -> Int {
        let along = columnBase + columnScale * Double(column) + rowTerm
        return min(lastEntry, max(0, Int((along * stepScale).rounded())))
    }

    /// The colour of a whole row, for a ramp that does not vary along one.
    func colour(row: Int) -> Color {
        ramp[min(lastEntry, max(0, Int((rowTerm(row) * stepScale).rounded())))]
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
