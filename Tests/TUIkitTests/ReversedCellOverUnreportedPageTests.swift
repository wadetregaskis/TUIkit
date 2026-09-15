//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReversedCellOverUnreportedPageTests.swift
//
//  A reversed cell composited over a page the terminal decides and has not reported.
//  The compositor reads a cell in the colours it DISPLAYS (Opacity as composition,
//  rule 6): a reversed cell's colours are exchanged and its 7 dropped. With the
//  terminal's own pair unreported, the exchanged pair has no spelling without the 7:
//  the page as ink emits 39 and the terminal's foreground as a field emits 49, which
//  draws the cell un-reversed. So such a cell is spelled with the 7 again.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

/// The page and ink the terminal decides, stated as roles, with RGB elsewhere.
private struct TerminalPairPalette: Palette {
    let id = "terminal-pair"
    let name = "Terminal pair"
    let background = Color(value: .terminalBackground)
    let foreground = Color(value: .terminalForeground)
    let accent = Color.rgb(0, 122, 255)
    let success = Color.rgb(40, 200, 40)
    let warning = Color.rgb(220, 200, 40)
    let error = Color.rgb(220, 40, 40)
    let info = Color.rgb(40, 120, 220)
    let border = Color.rgb(120, 120, 130)
}

@MainActor
@Suite("A reversed cell over a page the terminal has not reported")
struct ReversedCellOverUnreportedPageTests {

    /// The pair the plan names: a dark page and a white ink.
    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 255, green: 255, blue: 255),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52))

    private static let red = Color.rgb(200, 40, 40)

    /// The first row of `view` as the compositor leaves it, over the terminal's page.
    private func screen<V: View>(_ view: V) -> String {
        let context = makeRenderContext(width: 12, height: 1) { environment, _ in
            environment.palette = TerminalPairPalette()
        }
        return ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context).lines[0] }
    }

    private func text(_ line: String) -> String {
        line.stripped.trimmingCharacters(in: .whitespaces)
    }

    /// Each visible character of `line` with whether reverse video is in force on it.
    private func reversals(_ line: String) -> [(character: Character, reversed: Bool)] {
        var state = SGRState()
        var result: [(character: Character, reversed: Bool)] = []
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, true): state.apply(sequence)
            case .ansi: continue
            case .visible(let character): result.append((character, state.reversesVideo))
            }
        }
        return result
    }

    /// The characters of `line` drawn reversed, spaces included.
    private func reversedCharacters(_ line: String) -> String {
        String(reversals(line).filter(\.reversed).map(\.character))
    }

    @Test("At ½ and above a reversed label keeps its 7, with its glyphs", arguments: [0.5, 0.6])
    func atHalfTheReversalStays(opacity: Double) {
        TerminalColors.withCurrent(.unknown) {
            let line = screen(Text("ab").inverted().opacity(opacity))
            #expect(text(line) == "ab", "\(line.debugDescription)")
            #expect(reversedCharacters(line) == "ab", "\(line.debugDescription)")
            // The terminal's own pair, which has no RGB to state.
            #expect(!line.contains("38;") && !line.contains("48;"), "\(line.debugDescription)")
        }
    }

    @Test("Below ½ what is behind a reversed label shows", arguments: [0.3, 0.49])
    func belowHalfTheDestinationShows(opacity: Double) {
        TerminalColors.withCurrent(.unknown) {
            let bare = screen(Text("ab").inverted().opacity(opacity))
            #expect(text(bare).isEmpty, "\(bare.debugDescription)")
            #expect(reversedCharacters(bare).isEmpty, "\(bare.debugDescription)")
            let covering = screen(ZStack { Text("xy"); Text("ab").inverted().opacity(opacity) })
            #expect(text(covering) == "xy", "\(covering.debugDescription)")
            #expect(reversedCharacters(covering).isEmpty, "\(covering.debugDescription)")
        }
    }

    /// A reversed space is a fill in the terminal's foreground, and the text under it is
    /// that colour too, so at ½ and above nothing of the text can be seen.
    @Test("A reversed space over text wins at ½ and above, and yields below")
    func aReversedSpaceOverText() {
        TerminalColors.withCurrent(.unknown) {
            let won = screen(ZStack { Text("xy"); Text("  ").inverted().opacity(0.6) })
            #expect(text(won).isEmpty, "\(won.debugDescription)")
            #expect(reversedCharacters(won) == "  ", "\(won.debugDescription)")
            let yielded = screen(ZStack { Text("xy"); Text("  ").inverted().opacity(0.3) })
            #expect(text(yielded) == "xy", "\(yielded.debugDescription)")
            #expect(reversedCharacters(yielded).isEmpty, "\(yielded.debugDescription)")
        }
    }

    /// The other side of the blend: a label over a reversed row sits on the row's fill,
    /// the terminal's foreground, which only the 7 can state.
    @Test("A label over a reversed row is drawn on the row's fill")
    func aLabelOverAReversedRow() {
        TerminalColors.withCurrent(.unknown) {
            let over = screen(ZStack { Text("xy").inverted(); Text("ab").foregroundStyle(Self.red).opacity(0.6) })
            #expect(text(over) == "ab", "\(over.debugDescription)")
            #expect(reversedCharacters(over) == "ab", "\(over.debugDescription)")
            // Reversed, the label's ink is stated in the background slot.
            #expect(over.contains("48;2;200;40;40"), "\(over.debugDescription)")
            let under = screen(ZStack { Text("xy").inverted(); Text("ab").foregroundStyle(Self.red).opacity(0.3) })
            #expect(text(under) == "xy", "\(under.debugDescription)")
            #expect(reversedCharacters(under) == "xy", "\(under.debugDescription)")
        }
    }

    /// A column no region covers passes the source through, re-emitted from the
    /// exchanged colours, so it takes the same spelling.
    @Test("A reversed cell between two faded regions stays reversed")
    func anUncoveredReversedCellStaysReversed() {
        TerminalColors.withCurrent(.unknown) {
            var buffer = FrameBuffer(lines: ["\u{1B}[7mABCDEF\u{1B}[0m"])
            buffer.opacityRegions = [
                OpacityRegion(offsetX: 0, offsetY: 0, width: 2, height: 1, opacity: 0.6),
                OpacityRegion(offsetX: 4, offsetY: 0, width: 2, height: 1, opacity: 0.6),
            ]
            let resolved = ColorDepth.withCurrent(.truecolor) {
                buffer.resolvingOpacity(
                    over: FrameBuffer(), surface: Color(value: .terminalBackground),
                    palette: TerminalPairPalette())
            }
            let line = resolved.lines[0]
            #expect(line.stripped == "ABCDEF", "\(line.debugDescription)")
            #expect(reversedCharacters(line) == "ABCDEF", "\(line.debugDescription)")
        }
    }

    /// Keyed on what can be measured: once the terminal has reported its pair, the
    /// exchanged colours have RGB spellings, and a reversed cell composites as before.
    @Test("Over a reported page a reversed label is drawn in its exchanged colours, as before")
    func aReportedPageComposites() {
        TerminalColors.withCurrent(Self.reported) {
            let page = Color(value: .terminalBackground)
            let ink = Color(value: .terminalForeground)
            let line = screen(Text("ab").inverted().opacity(0.6))
            #expect(text(line) == "ab", "\(line.debugDescription)")
            #expect(reversedCharacters(line).isEmpty, "\(line.debugDescription)")
            #expect(line.contains(page.foregroundCodes().joined(separator: ";")), "\(line.debugDescription)")
            let field = ink.opacity(0.6, over: page)
            #expect(line.contains(field.backgroundCodes().joined(separator: ";")), "\(line.debugDescription)")
        }
    }
}
