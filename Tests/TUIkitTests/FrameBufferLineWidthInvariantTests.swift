//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameBufferLineWidthInvariantTests.swift
//
//  `FrameBuffer.lineWidths` caches each row's visible width, and a debug-only
//  assertion guards it against drifting from the rows it describes. That guard
//  used to re-measure the WHOLE buffer on every `appendVertically` — which is
//  the O(n²) in the child count the append itself was restructured to remove
//  (88fede9c), reintroduced as measuring rather than copying. It now measures
//  only the rows each call newly claims.
//
//  That is the same check only because of a premise: a row's text never changes
//  after the call that added it, and its carried width is never restated without
//  being re-measured. These pin both halves — the predicate still catches a
//  width that lies, and every OTHER mutator drops the field to `nil` rather
//  than leaving a stale array behind.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("Frame buffer line-width invariant")
struct FrameBufferLineWidthInvariantTests {
    /// A buffer that really carries per-line widths: ragged, so the merge spells
    /// the array out instead of leaving uniformity to cover it.
    private func raggedCarryingWidths() -> FrameBuffer {
        var buffer = FrameBuffer(lines: ["ab"], width: 2, uniformWidth: true)
        buffer.appendVertically(FrameBuffer(lines: ["cde"], width: 3, uniformWidth: true))
        return buffer
    }

    @Test("A carried width that disagrees with its row is caught, and named")
    func aWidthThatLiesIsCaught() {
        let rows = ["ab", "cde", "f"]
        #expect(FrameBuffer.firstLineWidthMismatch(in: rows, against: [2, 3, 1], from: 0) == nil)
        #expect(FrameBuffer.firstLineWidthMismatch(in: rows, against: [2, 4, 1], from: 0) == 1)
        #expect(FrameBuffer.firstLineWidthMismatch(in: rows, against: [0, 3, 1], from: 0) == 0)

        // Visible CELLS, not bytes: a styled row is as wide as what it prints,
        // which is the entire reason the cache is worth keeping.
        let styled = ["\u{1B}[31mab\u{1B}[0m"]
        #expect(FrameBuffer.firstLineWidthMismatch(in: styled, against: [2], from: 0) == nil)
        #expect(
            FrameBuffer.firstLineWidthMismatch(in: styled, against: [styled[0].count], from: 0)
                == 0)
    }

    @Test("Only the rows a call newly claims are measured")
    func earlierRowsAreNotRemeasured() {
        let rows = ["ab", "cde"]
        // The whole point of the parameter: row 0 was measured when it was added
        // and is not measured again, so a violation planted there is invisible
        // from row 1 — and visible from 0, which is what the uniform-hint
        // derivation passes.
        #expect(FrameBuffer.firstLineWidthMismatch(in: rows, against: [99, 3], from: 1) == nil)
        #expect(FrameBuffer.firstLineWidthMismatch(in: rows, against: [99, 3], from: 0) == 0)
        // A newly-claimed row is still measured, however far in it is.
        #expect(FrameBuffer.firstLineWidthMismatch(in: rows, against: [2, 99], from: 1) == 1)
        // Out-of-range starts clamp rather than trap.
        #expect(FrameBuffer.firstLineWidthMismatch(in: rows, against: [99, 99], from: 9) == nil)
        #expect(FrameBuffer.firstLineWidthMismatch(in: rows, against: [99, 99], from: -3) == 0)
    }

    @Test("Stacking measures every row it carries a width for, exactly once")
    func everyStackedRowIsMeasured() {
        // Walks the two paths the append takes in turn: a derived prefix (the
        // uniform hint spelled out, checked from 0) and then a carried one
        // (checked from the new rows only). Whichever path each append took, the
        // finished array must describe the finished lines.
        var stacked = FrameBuffer()
        for row in 0..<12 {
            stacked.appendVertically(
                FrameBuffer(
                    lines: [String(repeating: "x", count: row + 1)],
                    width: row + 1, uniformWidth: true),
                spacing: row % 3)
        }
        #expect(stacked.lineWidths != nil, "the ragged stack must really carry widths")
        let widths = stacked.lineWidths ?? []
        #expect(widths == stacked.lines.map(\.strippedLength))
        #expect(
            FrameBuffer.firstLineWidthMismatch(in: stacked.lines, against: widths, from: 0) == nil)
    }

    @Test("No mutator leaves a stale width behind")
    func noMutatorLeavesStaleWidths() {
        var cases: [(what: String, buffer: FrameBuffer)] = []

        var reassigned = raggedCarryingWidths()
        reassigned.lines = ["a much longer row than before", "x"]
        cases.append(("lines =", reassigned))

        var stackedBelow = raggedCarryingWidths()
        stackedBelow.appendVertically(FrameBuffer(lines: ["fghi"]), spacing: 2)
        cases.append(("appendVertically", stackedBelow))

        var placedBeside = raggedCarryingWidths()
        placedBeside.appendHorizontally(FrameBuffer(lines: ["zz"]), spacing: 1)
        cases.append(("appendHorizontally", placedBeside))

        var compositedInPlace = raggedCarryingWidths()
        compositedInPlace.composite(with: FrameBuffer(lines: ["Q"]), at: (x: 0, y: 0))
        cases.append(("composite(with:at:)", compositedInPlace))

        cases.append(
            (
                "composited(with:at:)",
                raggedCarryingWidths().composited(
                    with: FrameBuffer(lines: ["Q"]), at: (x: 1, y: 1))
            ))
        cases.append(
            ("clamped(toWidth:height:)", raggedCarryingWidths().clamped(toWidth: 2, height: 2)))
        cases.append(
            (
                "trimmingTrailingBlankCells()",
                FrameBuffer(
                    lines: ["ab  ", "cd  "], width: 4, uniformWidth: true, lineWidths: [4, 4]
                ).trimmingTrailingBlankCells()
            ))
        cases.append(
            (
                "paintedOver(background:)",
                raggedCarryingWidths().paintedOver(background: "\u{1B}[41m")
            ))
        cases.append(
            (
                "replacingLines",
                raggedCarryingWidths().replacingLines(["ab", "cde"], width: 3, lineWidths: [2, 3])
            ))

        for (what, buffer) in cases {
            // `nil` is always honest — "measure on demand" is the safe answer and
            // the one most of these deliberately give. Only a non-`nil` array is
            // a claim, and every claim must describe the rows it was left with.
            guard let widths = buffer.lineWidths else { continue }
            #expect(
                widths == buffer.lines.map(\.strippedLength),
                """
                \(what) left a stale lineWidths \(widths) against rows measuring \
                \(buffer.lines.map(\.strippedLength)) — the incremental invariant check \
                assumes a carried array was measured when it was set.
                """)
        }
    }
}
