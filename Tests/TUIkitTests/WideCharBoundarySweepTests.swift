//  🖥️ TUIKit — Terminal UI Kit for Swift
//  WideCharBoundarySweepTests.swift
//
//  Property sweep over the width-math seams where a double-width character
//  (CJK, emoji) can straddle a boundary: string truncation, buffer clamping,
//  ANSI-aware prefixing, escape-sequence balance after a cut, ZStack
//  compositing at odd offsets, and Text wrapping — each checked at every
//  target width around the samples' extents.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Wide-character boundary sweep")
struct WideCharBoundarySweepTests {
    @Test("Clamp and truncation never split a wide character or overflow")
    func wideCharBoundaries() {
        let samples = [
            "你好世界测试宽度",            // pure CJK (all width 2)
            "a你b好c世d界e",              // interleaved
            "🎉🎊🎈🎁",                   // emoji
            "x🎉y🎊z",                    // interleaved emoji
            "eé你🎉!",                    // mixed widths incl. combining é
            "\u{1B}[31m你好\u{1B}[0m世界", // ANSI-styled CJK
        ]
        var problems: [String] = []

        for sample in samples {
            let fullWidth = sample.strippedLength
            for target in 1...(fullWidth + 2) {
                // 1. String truncation.
                let truncated = sample.truncatedToWidth(target)
                if truncated.strippedLength > target {
                    problems.append("truncatedToWidth(\(target)) of '\(sample)': \(truncated.strippedLength) wide")
                }
                // 2. Buffer clamp.
                let clamped = FrameBuffer(text: sample).clamped(toWidth: target, height: 1)
                for line in clamped.lines where line.strippedLength > target {
                    problems.append("clamped(\(target)) of '\(sample)': line \(line.strippedLength) wide: '\(line.stripped)'")
                }
                // 3. ansiAwarePrefix.
                let prefix = sample.ansiAwarePrefix(visibleCount: target)
                if prefix.strippedLength > target {
                    problems.append("ansiAwarePrefix(\(target)) of '\(sample)': \(prefix.strippedLength) wide")
                }
                // 4. Escape balance: a kept SGR must still be terminated.
                for produced in [truncated, prefix] {
                    var escapes = 0
                    var index = produced.startIndex
                    while let range = produced.range(of: "\u{1B}[", range: index..<produced.endIndex) {
                        escapes += 1
                        index = range.upperBound
                    }
                    let terminators = produced.filter { $0 == "m" }.count
                    if escapes > 0 && terminators == 0 {
                        problems.append("unterminated escape in '\(produced.debugDescription)'")
                    }
                }
            }
        }

        // 5. Wide chars under ZStack compositing at odd offsets.
        for offset in 0...4 {
            let base = FrameBuffer(text: "你好世界你好")
            let overlay = FrameBuffer(text: "XX")
            let composited = base.composited(with: overlay, at: (x: offset, y: 0))
            let line = composited.lines[0].stripped
            if line.strippedLength > base.width {
                problems.append("composite at x=\(offset): '\(line)' is \(line.strippedLength) wide (base \(base.width))")
            }
            if !line.contains("XX") {
                problems.append("composite at x=\(offset): overlay lost: '\(line)'")
            }
        }

        if !problems.isEmpty {
            print("=== WIDE-CHAR PROBLEMS (\(problems.count)) ===")
            for problem in problems.prefix(20) { print(problem) }
        }
        #expect(problems.isEmpty)
    }

    @Test("Text view wraps/truncates wide chars inside its width")
    func textViewWideChars() {
        var problems: [String] = []
        for width in 1...9 {
            for sample in ["你好世界测试", "🎉🎊🎈", "mix你ed🎉"] {
                let context = makeBareRenderContext(width: width, height: 6)
                let buffer = renderToBuffer(Text(sample), context: context)
                for (i, line) in buffer.lines.enumerated() where line.strippedLength > width {
                    problems.append("Text('\(sample)') @w\(width) line \(i): \(line.strippedLength) wide: '\(line.stripped)'")
                }
            }
        }
        if !problems.isEmpty {
            print("=== TEXT WIDE-CHAR PROBLEMS (\(problems.count)) ===")
            for problem in problems.prefix(20) { print(problem) }
        }
        #expect(problems.isEmpty)
    }
}
