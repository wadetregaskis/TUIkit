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
        guard case .linear(let gradient, let from, let to) = paint else {
            var flat = style
            flat.foregroundColor = paint.representative
            return lines.map { ANSIRenderer.render($0, with: flat) }
        }

        let extent = frame ?? GradientFrame(width: blockWidth, height: lines.count)
        let width = max(1, extent.width)
        let height = max(1, extent.height)
        let axisX = to.x - from.x
        let axisY = to.y - from.y
        let lengthSquared = axisX * axisX + axisY * axisY
        guard lengthSquared > 0 else {
            var flat = style
            flat.foregroundColor = gradient.color(at: 0)
            return lines.map { ANSIRenderer.render($0, with: flat) }
        }

        // How many distinguishable positions the ramp actually has across this
        // block: the cells it spans along its own axis. Sampling the ramp once
        // at that resolution is what lets `quantisedRamp` do its monotonicity
        // repair over the SEQUENCE — a per-cell nearest match has no memory of
        // its neighbours, which is the banding that repair exists to remove.
        let steps = max(2, Int((abs(axisX) * Double(width) + abs(axisY) * Double(height)).rounded()))
        let ramp = Color.quantisedRamp(gradient, count: steps, depth: depth)
        guard !ramp.isEmpty else { return lines.map { ANSIRenderer.render($0, with: style) } }

        let reset = ANSIRenderer.reset

        // `along` is affine in the cell's coordinates, so it splits into a term
        // per column and a term per row. Precomputing the column half turns the
        // inner loop into an add, a multiply and a round — no division, no
        // per-cell closure. That inner loop runs once per CELL of every styled
        // leaf, which is the only reason any of this is spelled out.
        let stepScale = Double(steps - 1)
        let columnScale = axisX / lengthSquared / Double(width)
        let columnBase =
            (Double(extent.originX) + 0.5) / Double(width) * (axisX / lengthSquared)
            - from.x * axisX / lengthSquared
        let rowScale = axisY / lengthSquared / Double(height)
        let rowBase =
            (Double(extent.originY) + 0.5) / Double(height) * (axisY / lengthSquared)
            - from.y * axisY / lengthSquared

        // A vertical gradient is one colour per row, and the whole per-cell walk
        // collapses to a single run — which matters, because "a ramp down a
        // list" is the common ask.
        let variesAcrossRow = axisX != 0
        let lastEntry = ramp.count - 1

        var sequences: [String?] = []
        var result: [String] = []
        result.reserveCapacity(lines.count)
        for (row, line) in lines.enumerated() {
            let rowTerm = rowBase + rowScale * Double(row)

            guard variesAcrossRow else {
                // One colour for the whole row, so no run table and no
                // per-cell walk — just the wrap `ANSIRenderer.render` would
                // have produced. Allocating the table here cost an array per
                // leaf to hold a single entry.
                let entry = min(lastEntry, max(0, Int((rowTerm * stepScale).rounded())))
                var run = style
                run.foregroundColor = ramp[entry]
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
            if sequences.isEmpty { sequences = [String?](repeating: nil, count: ramp.count) }

            var painted = ""
            // Reserved for the worst case, which is what this path IS: a run
            // per cell, each an SGR introducer (up to ~19 bytes for truecolor)
            // plus a reset. Reserving the line's own length instead meant half
            // a dozen reallocations and copies per row.
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
            func open(_ entry: Int, at index: String.Index) {
                runEntry = entry
                runStart = index
                if sequences[entry] == nil {
                    var run = style
                    run.foregroundColor = ramp[entry]
                    sequences[entry] = ANSIRenderer.styleSequence(for: run) ?? ""
                }
            }
            @inline(__always) func entry(atColumn column: Int) -> Int {
                let along = columnBase + columnScale * Double(column) + rowTerm
                return min(lastEntry, max(0, Int((along * stepScale).rounded())))
            }

            while cursor < line.endIndex {
                // The cell the character STARTS at decides its colour: a wide
                // glyph is one glyph, and splitting a colour across it is not
                // something a terminal can draw.
                let next = entry(atColumn: column)
                if next != runEntry {
                    flush(cursor)
                    open(next, at: cursor)
                }
                column += line[cursor].terminalWidth
                cursor = line.index(after: cursor)
            }
            flush(line.endIndex)
            result.append(painted)
        }
        return result
    }

    private static func rendered(_ text: String, colour: Color?, style: TextStyle) -> String {
        var run = style
        run.foregroundColor = colour
        return ANSIRenderer.render(text, with: run)
    }
}
