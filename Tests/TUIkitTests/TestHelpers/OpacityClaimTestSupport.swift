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
