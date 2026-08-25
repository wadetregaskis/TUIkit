//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityContinuityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// The properties a fade must hold ACROSS alpha, not at any one value: colours
/// move monotonically, glyph decisions change at most once, and the ends are
/// exact. These are the assertions that catch a regression no single-alpha
/// test can — a pop in the middle of a fade is invisible to every test that
/// only looks at 0.25, 0.5 and 0.75.
@MainActor
@Suite("Opacity continuity")
struct OpacityContinuityTests {

    private func palette() -> any Palette {
        makeRenderContext(width: 24, height: 4).environment.palette
    }

    /// Every `38;2;r;g;b` foreground in `line`, in order.
    private func foregrounds(in line: String) -> [[Int]] {
        matches(in: line, introducer: "38;2;")
    }

    /// Every `48;2;r;g;b` background in `line`, in order.
    private func backgrounds(in line: String) -> [[Int]] {
        matches(in: line, introducer: "48;2;")
    }

    private func matches(in line: String, introducer: String) -> [[Int]] {
        var results: [[Int]] = []
        var rest = Substring(line)
        while let range = rest.range(of: introducer) {
            rest = rest[range.upperBound...]
            let channels = rest.split(separator: ";", maxSplits: 3, omittingEmptySubsequences: false)
                .prefix(3)
                .compactMap { Int($0.prefix(while: \.isNumber)) }
            if channels.count == 3 { results.append(channels) }
        }
        return results
    }

    /// One cell resolved at `alpha` over `destination`.
    private func resolved(
        _ sourceLine: String, over destination: FrameBuffer, alpha: Double
    ) -> String {
        var buffer = FrameBuffer(lines: [sourceLine])
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 1, height: 1, opacity: alpha)
        ]
        return buffer.resolvingOpacity(
            over: destination, surface: .black, palette: palette()
        ).lines[0]
    }

    private let ladder = Array(stride(from: 0.05, through: 0.95, by: 0.05))

    private func expectMonotone(_ series: [[Int]], _ comment: Comment) {
        for channel in 0..<3 {
            let values = series.map { $0[channel] }
            let ascending = (values.last ?? 0) >= (values.first ?? 0)
            let sorted = ascending ? values.sorted() : values.sorted(by: >)
            #expect(values == sorted, comment)
        }
    }

    @Test("An uncontested glyph never vanishes, and its colour moves monotonically")
    func uncontestedFadeIsMonotone() {
        // A single character over a plain pane: the commonest fade there is.
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize(" ", background: .rgb(200, 60, 20))
        ])
        let source = ANSIRenderer.colorize("x", foreground: .rgb(40, 220, 90))

        var series: [[Int]] = []
        for alpha in ladder {
            let line = resolved(source, over: destination, alpha: alpha)
            #expect(line.stripped == "x", "the glyph vanished at \(alpha)")
            let colors = foregrounds(in: line)
            #expect(colors.count == 1, "expected one foreground at \(alpha)")
            series.append(colors[0] + Array(repeating: 0, count: max(0, 3 - colors[0].count)))
        }
        expectMonotone(series, "a channel reversed direction mid-fade")

        // The dark end converges on the field: one step from nothing, the ink
        // is within a few encoded steps of invisible. Not one step — the sRGB
        // transfer curve is steep near black, so 0.4% of linear alpha is
        // legitimately ~2 encoded values on a dark channel.
        let nearZero = foregrounds(in: resolved(source, over: destination, alpha: 0.004))
        if let first = nearZero.first {
            #expect(abs(first[0] - 200) <= 3 && abs(first[1] - 60) <= 3 && abs(first[2] - 20) <= 3)
        }
    }

    @Test("A contested cell swaps its glyph exactly once, at the midpoint")
    func contestedFadeSwapsOnce() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("o", foreground: .rgb(200, 60, 20))
        ])
        let source = ANSIRenderer.colorize("x", foreground: .rgb(40, 220, 90))

        let glyphs = ladder.map { resolved(source, over: destination, alpha: $0).stripped }
        #expect(glyphs.allSatisfy { $0 == "x" || $0 == "o" })
        // "o" for the low half, "x" for the high half — one transition.
        let transitions = zip(glyphs, glyphs.dropFirst()).count { $0 != $1 }
        #expect(transitions == 1, "glyphs: \(glyphs)")
        #expect(glyphs.first == "o")
        #expect(glyphs.last == "x")
    }

    @Test("A matched cell keeps its glyph at every alpha, colours monotone")
    func matchedFadeIsSeamless() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("x", foreground: .rgb(200, 60, 20))
        ])
        let source = ANSIRenderer.colorize("x", foreground: .rgb(40, 220, 90))

        var series: [[Int]] = []
        for alpha in ladder {
            let line = resolved(source, over: destination, alpha: alpha)
            #expect(line.stripped == "x", "the glyph changed at \(alpha)")
            if let first = foregrounds(in: line).first { series.append(first) }
        }
        #expect(series.count == ladder.count)
        expectMonotone(series, "a channel reversed direction mid-crossfade")
    }

    @Test("A veil's tint deepens monotonically over revealed text")
    func veilTintIsMonotone() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("o", foreground: .rgb(240, 240, 240), background: .rgb(10, 10, 10))
        ])
        let source = ANSIRenderer.colorize(" ", background: .rgb(30, 90, 210))

        var series: [[Int]] = []
        for alpha in ladder where alpha < 0.5 {
            let line = resolved(source, over: destination, alpha: alpha)
            #expect(line.stripped == "o", "the text vanished under the veil at \(alpha)")
            if let field = backgrounds(in: line).first { series.append(field) }
        }
        #expect(!series.isEmpty)
        expectMonotone(series, "the veil's field reversed direction")
    }

    @Test("The ends are exact: identity at one, reveal at zero")
    func endsAreExact() {
        let destination = FrameBuffer(lines: [
            ANSIRenderer.colorize("o", foreground: .rgb(200, 60, 20))
        ])
        let source = ANSIRenderer.colorize("x", foreground: .rgb(40, 220, 90))

        let opaque = resolved(source, over: destination, alpha: 1)
        #expect(opaque.stripped == "x")
        #expect(foregrounds(in: opaque).first == [40, 220, 90])

        let transparent = resolved(source, over: destination, alpha: 0)
        #expect(transparent.stripped == "o")
        #expect(foregrounds(in: transparent).first == [200, 60, 20])
    }
}
