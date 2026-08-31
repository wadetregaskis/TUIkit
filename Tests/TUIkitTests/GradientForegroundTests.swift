//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientForegroundTests.swift
//
//  `.foregroundStyle(gradient)` painting a leaf. Every expectation about WHERE
//  the ramp runs was measured against real SwiftUI first — see
//  `Documentation/Gradients where a colour is accepted.md` §1 — because the
//  answer is not the one anyone guesses: the extent is the leaf's own layout
//  block, not the styled subtree and not the line.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Gradient foregrounds")
struct GradientForegroundTests {

    private let red = Color.rgb(255, 0, 0)
    private let blue = Color.rgb(0, 0, 255)

    private func context(width: Int = 40) -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.palette = SystemPalette.green
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: 10, environment: environment, tuiContext: tui)
    }

    /// The truecolor foregrounds of a styled line, in order, one entry per
    /// visible cell — so a run of three cells in one colour is three entries.
    private func inks(_ line: String) -> [String] {
        var out: [String] = []
        var current = "—"
        var rest = Substring(line)
        while let escape = rest.firstIndex(of: "\u{1B}") {
            for character in rest[rest.startIndex..<escape] {
                out.append(contentsOf: repeatElement(current, count: character.terminalWidth))
            }
            rest = rest[escape...]
            guard let end = rest.firstIndex(of: "m") else { break }
            let body = rest[rest.index(rest.startIndex, offsetBy: 2)..<end]
            if let range = body.range(of: "38;2;") {
                current = String(body[range.upperBound...].prefix { $0 != ";" || true })
                current = current.split(separator: ";").prefix(3).joined(separator: ";")
            } else if body == "0" {
                current = "—"
            }
            rest = rest[rest.index(after: end)...]
        }
        for character in rest {
            out.append(contentsOf: repeatElement(current, count: character.terminalWidth))
        }
        return out
    }

    private func render(_ view: some View, width: Int = 40) -> [String] {
        renderToBuffer(view, context: context(width: width)).lines
    }

    /// The inked cells only. A stack pads its children out to the block width
    /// with plain spaces, and that padding carries no colour — it is not part
    /// of what the leaf drew.
    private func painted(_ line: String) -> [String] {
        inks(line).filter { $0 != "—" }
    }

    // MARK: - Where the ramp runs

    /// SwiftUI resolves per LEAF: two texts of different widths under one
    /// gradient each run the whole sweep across their own width. Measured —
    /// an 81px block and a 321px block both went `#E8555A → #4E7DE7`.
    @Test("Each leaf runs the whole ramp across its own width")
    func perLeafExtent() {
        let lines = render(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AA")
                Text(verbatim: "AAAAAAAA")
            }
            .foregroundStyle(
                LinearGradient(colors: [red, blue], startPoint: .leading, endPoint: .trailing)))

        let short = painted(lines[0])
        let long = painted(lines[1])
        #expect(short.count == 2, "\(short)")
        #expect(long.count == 8, "\(long)")
        #expect(short.first == "255;0;0", "the short leaf does not start at the ramp's start")
        #expect(short.last == "0;0;255", "the short leaf does not REACH the ramp's end")
        #expect(long.first == "255;0;0")
        #expect(long.last == "0;0;255")
    }

    /// The other half of per-leaf: it is not one ramp over the stack. If it
    /// were, the two rows of a vertical gradient would differ.
    @Test("A vertical gradient does not run across separate leaves")
    func verticalDoesNotSpanLeaves() {
        let lines = render(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "AAAA")
            }
            .foregroundStyle(
                LinearGradient(colors: [red, blue], startPoint: .top, endPoint: .bottom)))
        // Each leaf is one row tall, so each takes the ramp's midpoint — and
        // both take the SAME one.
        #expect(inks(lines[0]) == inks(lines[1]), "the ramp spanned the stack")
    }

    /// A multi-line `Text` is ONE leaf, and its extent is the block. Measured:
    /// the short first line of a two-line text ends at t ≈ 0.25 — its own
    /// fraction of the block's width — not at the ramp's end.
    @Test("A multi-line Text shares one ramp across its block")
    func blockExtentAcrossLines() {
        let lines = render(
            Text(verbatim: "AA\nAAAAAAAA")
                .foregroundStyle(
                    LinearGradient(colors: [red, blue], startPoint: .leading, endPoint: .trailing)),
            width: 12)
        let first = inks(lines[0])
        let second = inks(lines[1])
        #expect(first.count == 2)
        #expect(second.count == 8)
        #expect(first.first == "255;0;0")
        #expect(
            first.last != "0;0;255",
            "the short line reached the ramp's end — it was measured per LINE, not per block")
        // The short line's cells are the same colours the long line has at the
        // same columns, which is what "one ramp over the block" means.
        #expect(Array(second.prefix(2)) == first, "\(first) vs \(Array(second.prefix(2)))")
    }

    @Test("A vertical gradient over a multi-line Text steps per row")
    func verticalAcrossRows() {
        let lines = render(
            Text(verbatim: "AA\nAA\nAA")
                .foregroundStyle(
                    LinearGradient(colors: [red, blue], startPoint: .top, endPoint: .bottom)),
            width: 12)
        let rows = lines.prefix(3).map { inks($0).first ?? "—" }
        #expect(Set(rows).count == 3, "the rows did not differ: \(rows)")
        #expect(rows.first == "255;0;0")
        #expect(rows.last == "0;0;255")
    }

    // MARK: - Precedence

    @Test("A nearer explicit colour beats the gradient")
    func explicitColourWins() {
        let lines = render(
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "AAAA")
                Text(verbatim: "BBBB").foregroundStyle(Color.rgb(1, 2, 3))
            }
            .foregroundStyle(
                LinearGradient(colors: [red, blue], startPoint: .leading, endPoint: .trailing)))
        #expect(Set(inks(lines[0])).count > 1, "the gradient did not paint the unstyled leaf")
        #expect(Set(inks(lines[1])) == ["1;2;3"], "the ramp overrode a stated colour")
    }

    @Test("A bare Gradient is vertical, a LinearGradient is what it says")
    func bareGradientIsVertical() {
        let horizontal = render(
            Text(verbatim: "AAAA\nAAAA")
                .foregroundStyle(
                    LinearGradient(colors: [red, blue], startPoint: .leading, endPoint: .trailing)),
            width: 12)
        let bare = render(
            Text(verbatim: "AAAA\nAAAA").foregroundStyle(Gradient(colors: [red, blue])),
            width: 12)
        #expect(inks(horizontal[0]) == inks(horizontal[1]), "horizontal rows should match")
        #expect(inks(bare[0]) != inks(bare[1]), "a bare gradient did not run top to bottom")
    }

    // MARK: - Cells, not characters

    /// A two-cell glyph is one glyph: the ramp may not change colour inside it,
    /// and it must advance the ramp by two cells, not one.
    @Test("A wide glyph takes one colour and two cells of the ramp")
    func wideGlyphsAreNotSplit() {
        let lines = render(
            Text(verbatim: "一二三")
                .foregroundStyle(
                    LinearGradient(colors: [red, blue], startPoint: .leading, endPoint: .trailing)),
            width: 12)
        let cells = inks(lines[0])
        #expect(cells.count == 6, "three wide glyphs are six cells: \(cells)")
        for pair in stride(from: 0, to: 6, by: 2) {
            #expect(cells[pair] == cells[pair + 1], "a glyph was split across two colours")
        }
        #expect(cells.first == "255;0;0")
    }

    // MARK: - Nothing when unused

    /// The whole point of the storage being one slot: a page with no gradient
    /// must render exactly as it did.
    @Test("A plain colour still renders as one run")
    func plainColourIsUnchanged() {
        let styled = render(Text(verbatim: "hello").foregroundStyle(Color.rgb(9, 9, 9)))
        #expect(Set(inks(styled[0])) == ["9;9;9"])
        #expect(styled[0].filter { $0 == "\u{1B}" }.count == 2, "more escapes than one run needs")
    }
}
