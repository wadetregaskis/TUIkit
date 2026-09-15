//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ClaimingRowTests.swift
//
//  `ClaimingRow.append(contentsOf:)` splices one row into another: its bytes, and
//  its claims moved to the columns they now sit at.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A ClaimingRow splices a row, claims and all")
struct ClaimingRowTests {

    /// Three blanks, an opaque wall, then a spliced row of two translucent cells: the
    /// splice's claim must land on the two cells it was drawn in, past everything
    /// the row had already drawn.
    @Test("A spliced row's claims land on the columns it now sits at")
    func spliceMovesTheClaims() {
        var inner = ClaimingRow()
        inner.append("ab", cells: 2, ink: Color.ansi(.red).opacity(0.5))
        var row = ClaimingRow()
        row.skip(cells: 3)
        row.append("│", cells: 1, ink: Color.ansi(.white))
        row.append(contentsOf: inner)

        #expect(row.cells == 6)
        #expect(row.text.stripped == "   │ab")
        var buffer = FrameBuffer(lines: [row.text])
        buffer.opacityRegions = row.claims
        // Coverage, not claim count: what a row owes is an alpha per column.
        let claimed = (0..<6).filter { owed(atColumn: $0, row: 0, in: buffer).ink != 1 }
        #expect(claimed == [4, 5])
    }
}
