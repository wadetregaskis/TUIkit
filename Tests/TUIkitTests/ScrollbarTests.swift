//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollbarTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@Suite("Scrollbar")
struct ScrollbarTests {
    typealias Bar = ScrollbarRenderer

    @Test("Block glyph helpers map eighths to the right code points")
    func blockGlyphs() {
        #expect(Bar.lowerBlock(1) == "▁")
        #expect(Bar.lowerBlock(7) == "▇")
        #expect(Bar.lowerBlock(8) == "█")
        #expect(Bar.leftBlock(1) == "▏")
        #expect(Bar.leftBlock(7) == "▉")
        #expect(Bar.leftBlock(8) == "█")
    }

    @Test("Content that fits fills the whole track")
    func fitsFillsTrack() {
        let cells = Bar.trackCells(count: 4, extent: 4, viewport: 4, offset: 0, vertical: true)
        #expect(cells.allSatisfy { $0 == .full })
    }

    @Test("Half the content at the top fills the top half")
    func topHalf() {
        // extent 8, viewport 4 → thumb 4/8 of 32 = 16 sub = 2 cells, at offset 0.
        let cells = Bar.trackCells(count: 4, extent: 8, viewport: 4, offset: 0, vertical: true)
        #expect(cells == [.full, .full, .empty, .empty])
    }

    @Test("Half the content at the bottom fills the bottom half")
    func bottomHalf() {
        let cells = Bar.trackCells(count: 4, extent: 8, viewport: 4, offset: 4, vertical: true)
        #expect(cells == [.empty, .empty, .full, .full])
    }

    @Test("A fractional vertical thumb end uses a top-anchored (inverted) partial block")
    func fractionalVertical() {
        // extent 10, viewport 4, offset 0 → thumb 4/10·32 = 12.8 → 13 sub.
        // cell0 [0,8) full; cell1 [8,16) covered [8,13) → hi=5 within cell → top-anchored 5/8.
        let cells = Bar.trackCells(count: 4, extent: 10, viewport: 4, offset: 0, vertical: true)
        #expect(cells[0] == .full)
        #expect(
            cells[1] == ScrollbarCell(glyph: "▃", inverted: true),
            "top-anchored 5/8 = invert(lower 3/8 = ▃): \(cells)")
        #expect(cells[2] == .empty && cells[3] == .empty)
    }

    @Test("A fractional horizontal thumb uses left blocks; its left end is inverted")
    func fractionalHorizontal() {
        // extent 10, viewport 4, offset 6 (max) → thumb 13 sub, travel 19, start 19.
        // cell2 [16,24): lo = 19-16 = 3 → covered [3,8) → right-anchored 5/8 = invert(left 3/8 = ▍).
        let cells = Bar.trackCells(count: 4, extent: 10, viewport: 4, offset: 6, vertical: false)
        #expect(cells[0] == .empty && cells[1] == .empty)
        #expect(
            cells[2] == ScrollbarCell(glyph: "▍", inverted: true),
            "right-anchored = invert(left 3/8 = ▍): \(cells)")
        #expect(cells[3] == .full)
    }

    @Test("The thumb is at least one whole cell")
    func minimumThumb() {
        // A tiny viewport against a huge extent would round the thumb below one
        // cell; it is clamped to a whole cell so it never vanishes.
        let cells = Bar.trackCells(count: 10, extent: 1000, viewport: 5, offset: 0, vertical: true)
        #expect(cells.contains { $0 != .empty }, "thumb spans at least one cell: \(cells)")
    }
}
