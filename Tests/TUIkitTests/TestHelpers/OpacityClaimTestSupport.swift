//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityClaimTestSupport.swift
//
//  Reading what a rendered buffer's cells OWE — the claims a translucent paint
//  leaves beside its bytes — the way the resolver will. Shared because every
//  suite that asserts a claim needs the same three questions answered, and a
//  copy per suite is how two of them came to fold overlapping claims two ways.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// The factor a colour's alpha becomes in a claim — what a cell painted in it owes.
func owed(_ color: Color) -> Double {
    OpacityRegion.opacity(of: color.alpha)
}

/// What the claims covering one cell multiply to, ink and field: the fold the
/// resolver makes for that cell (`OpacityResolution.foldedAlphas`).
///
/// A product, not a lookup, because overlapping claims multiply — so a cell
/// claimed twice at 128 owes a quarter, and asserting this against the one alpha
/// a cell was painted at is what catches a double claim.
func owed(atColumn column: Int, row: Int, in buffer: FrameBuffer) -> (ink: Double, field: Double) {
    buffer.opacityRegions
        .filter { $0.contains(column: column, row: row) }
        .reduce((ink: 1.0, field: 1.0)) { ($0.ink * $1.inkOpacity, $0.field * $1.fieldOpacity) }
}

/// Every cell `glyph` was drawn in.
///
/// Columns are characters of the stripped line, which are cells only while every
/// glyph before the one sought is one cell wide — true of chrome, arrows and ASCII,
/// and not of emoji or CJK text, where this answers in the wrong column.
func cells(of glyph: Character, in buffer: FrameBuffer) -> [(column: Int, row: Int)] {
    buffer.lines.enumerated().flatMap { row, line in
        line.stripped.enumerated().compactMap { column, character in
            character == glyph ? (column: column, row: row) : nil
        }
    }
}

/// Every cell of a row's label owes ``FadedInk``'s ink, and no other cell of `frame`
/// owes any. A label is `row`, its digits, and any dashes after them (`row7`,
/// `row11--`), which is how the suites using this name their rows — and not "rows",
/// so the "N more rows" line is not one. Columns are characters of the stripped
/// line, which are cells because every glyph such a frame draws is one cell wide.
func expectInkOnLabelsOnly(_ frame: FrameBuffer, sourceLocation: SourceLocation = #_sourceLocation) {
    let faded = owed(FadedInk().foreground)
    let screen = frame.lines.map(\.stripped)
    var wrong: [String] = []
    for (row, line) in screen.enumerated() {
        let label = line.range(of: "row[0-9]+-*", options: .regularExpression).map {
            line.distance(from: line.startIndex, to: $0.lowerBound)
                ..< line.distance(from: line.startIndex, to: $0.upperBound)
        }
        for column in 0..<line.count {
            let ink = owed(atColumn: column, row: row, in: frame).ink
            let expected = label?.contains(column) == true ? faded : 1
            if ink != expected { wrong.append("(\(column), \(row)): \(ink)") }
        }
    }
    #expect(
        wrong.isEmpty,
        """
        cells owing the wrong ink, \(wrong.count) of them: \(wrong.prefix(10))
        \(screen.joined(separator: "\n"))
        """,
        sourceLocation: sourceLocation)
}

/// Only the rows' ink faded — `foreground`, which `Text` draws in — with the quieter
/// rungs pinned opaque, since they default to `foreground` and the "N more" line and
/// the scrollbar's track are drawn in them: so the rows claim, and nothing else in a
/// list does.
struct FadedInk: Palette {
    let id = "faded-ink"
    let name = "Faded ink"
    let background = Color.rgb(10, 10, 20)
    let foreground = Color.rgb(230, 230, 240).opacity(0.5)
    let foregroundSecondary = Color.rgb(200, 200, 210)
    let foregroundTertiary = Color.rgb(150, 150, 160)
    let foregroundQuaternary = Color.rgb(110, 110, 120)
    let accent = Color.rgb(0, 180, 200)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}
