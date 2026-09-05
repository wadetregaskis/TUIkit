//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollWindowWidthMetadataTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// The scroll window used to pad every visible line by scanning it for its
/// width, hand the result to a buffer that measured every line again, and the
/// scrollbar then scanned each line a third time. The window now takes the
/// widths its content buffer already knows and says what it knows in turn;
/// the lines it produces are the same bytes.
@MainActor
@Suite("The scroll window carries line widths instead of re-measuring them")
struct ScrollWindowWidthMetadataTests {

    private static func core() -> _ScrollViewCore<Text> {
        _ScrollViewCore(axes: .vertical, content: Text("x"), explicitFocusID: nil, isDisabled: false)
    }

    @Test("A uniform content buffer windows to a uniform buffer with the same lines")
    func uniformIn() {
        let lines = (0..<20).map { String(repeating: "a", count: 12) + "\($0 % 10)" }
        let full = FrameBuffer(lines: lines, width: 13, uniformWidth: true)
        let window = Self.core().windowedBuffer(
            full: full, scrollOffset: 3, viewportHeight: 5, viewportWidth: 20,
            horizontalEnabled: false, horizontalOffset: 0)
        let reference = FrameBuffer(lines: Array(lines[3..<8]).map { $0.padToVisibleWidth(20) })
        #expect(window.lines == reference.lines)
        #expect(window.linesAreUniformWidth)
        #expect(window.width == 20)
    }

    @Test("A ragged buffer with carried widths windows without a scan, and reports its widths")
    func raggedIn() {
        let lines = ["ab", "abcdef", "a", "abcdefghijkl"]
        let full = FrameBuffer(lines: lines, width: 12, uniformWidth: false, lineWidths: [2, 6, 1, 12])
        let window = Self.core().windowedBuffer(
            full: full, scrollOffset: 0, viewportHeight: 6, viewportWidth: 8,
            horizontalEnabled: false, horizontalOffset: 0)
        #expect(window.lines[0] == "ab      ")
        #expect(window.lines[1] == "abcdef  ")
        #expect(window.lines[3] == "abcdefghijkl", "a line wider than the viewport is kept whole")
        #expect(window.lines[4] == "        ", "filler rows are viewport-wide blanks")
        #expect(!window.linesAreUniformWidth)
        #expect(window.lineWidths == [8, 8, 8, 12, 8, 8])
    }

    @Test("Clamping carries the widths it measured")
    func clampCarries() {
        let buffer = FrameBuffer(lines: ["abcdef", "ab", "abcd"])
        let clamped = buffer.clamped(toWidth: 4, height: 3)
        #expect(clamped.lines == ["abcd", "ab", "abcd"])
        #expect(!clamped.linesAreUniformWidth)
        #expect(clamped.lineWidths == [4, 2, 4])
        let uniform = FrameBuffer(lines: ["abcdef", "abcdefgh"]).clamped(toWidth: 4, height: 2)
        #expect(uniform.linesAreUniformWidth)
        #expect(uniform.lineWidths == nil)
    }
}

/// A stack of uniform rows at two widths knows every line's width; the merge
/// used to forget them all because a uniform side carries no array.
@Suite("Stacking uniform rows keeps their widths")
struct StackedUniformRowsWidthTests {
    @Test("Two uniform buffers of different widths merge to explicit widths")
    func mergeKeepsWidths() {
        var stack = FrameBuffer(lines: ["aaaa", "bbbb"], width: 4, uniformWidth: true)
        stack.appendVertically(FrameBuffer(lines: ["cc"], width: 2, uniformWidth: true))
        #expect(!stack.linesAreUniformWidth)
        #expect(stack.lineWidths == [4, 4, 2])
        stack.appendVertically(FrameBuffer(lines: ["dddddd"], width: 6, uniformWidth: true), spacing: 1)
        #expect(stack.lineWidths == [4, 4, 2, 0, 6])
        var uniform = FrameBuffer(lines: ["aa"], width: 2, uniformWidth: true)
        uniform.appendVertically(FrameBuffer(lines: ["bb"], width: 2, uniformWidth: true))
        #expect(uniform.linesAreUniformWidth && uniform.lineWidths == nil)
    }
}
