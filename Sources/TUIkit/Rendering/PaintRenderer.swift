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
    static func styled(
        _ lines: [String], blockWidth: Int, paint: Paint, style: TextStyle, depth: ColorDepth
    ) -> [String] {
        guard case .linear(let gradient, let from, let to) = paint else {
            var flat = style
            flat.foregroundColor = paint.representative
            return lines.map { ANSIRenderer.render($0, with: flat) }
        }

        let width = max(1, blockWidth)
        let height = max(1, lines.count)
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

        return lines.enumerated().map { row, line in
            let unitY = (Double(row) + 0.5) / Double(height)
            var result = ""
            var runText = ""
            var runColour: Color?
            var column = 0
            for character in line {
                // The cell the character STARTS at decides its colour: a wide
                // glyph is one glyph, and splitting a colour across it is not
                // something a terminal can draw.
                let unitX = (Double(column) + 0.5) / Double(width)
                let along =
                    ((unitX - from.x) * axisX + (unitY - from.y) * axisY) / lengthSquared
                let index = min(steps - 1, max(0, Int((along * Double(steps - 1)).rounded())))
                let colour = ramp[min(ramp.count - 1, index)]
                if colour != runColour, !runText.isEmpty {
                    result += rendered(runText, colour: runColour, style: style)
                    runText = ""
                }
                runColour = colour
                runText.append(character)
                column += character.terminalWidth
            }
            if !runText.isEmpty { result += rendered(runText, colour: runColour, style: style) }
            return result
        }
    }

    private static func rendered(_ text: String, colour: Color?, style: TextStyle) -> String {
        var run = style
        run.foregroundColor = colour
        return ANSIRenderer.render(text, with: run)
    }
}
