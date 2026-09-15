//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FadeOverUnreportedPageTests.swift
//
//  A fade over a page the terminal decides and has not reported. No blend can mix
//  with that page, so a colour below ½ becomes the page itself (Opacity as
//  composition, rule 9). A glyph drawn in the page on the page is invisible, but
//  the foreground slot has no spelling for the page: it emits 39, and the glyph
//  shows at full strength in the terminal's foreground. So such a cell draws no
//  glyph, and a fade over that page is a cut at ½: in the composite `.opacity(_:)`
//  draws, and in the rewrite `.transition(.opacity)` dissolves a drawn line with.
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
@Suite("A fade over a page the terminal has not reported")
struct FadeOverUnreportedPageTests {

    /// One Dark's pair, as the carried-colour tests use.
    private static let reported = TerminalColors(
        foreground: TerminalColors.RGB(red: 171, green: 178, blue: 191),
        background: TerminalColors.RGB(red: 40, green: 44, blue: 52))

    private static let red = Color.rgb(200, 40, 40)

    /// The first row of `view` as the compositor leaves it, over the terminal's page.
    private func screen<V: View>(_ view: V) -> String {
        let context = makeRenderContext(width: 12, height: 1) { environment, _ in
            environment.palette = TerminalPairPalette()
        }
        return ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context).lines[0] }
    }

    /// "ab" in an RGB ink whose own alpha is `alpha`.
    private func inked(_ alpha: Double) -> some View {
        Text("ab").foregroundStyle(Self.red.opacity(alpha))
    }

    private func text(_ line: String) -> String {
        line.stripped.trimmingCharacters(in: .whitespaces)
    }

    /// Whether any visible character of `line` is drawn with an attribute that inks a
    /// blank cell: underline, blink or strike.
    private func inksABlank(_ line: String) -> Bool {
        var state = SGRState()
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, _): state.apply(sequence)
            case .visible: if state.paintsInkOnBlankCell { return true }
            }
        }
        return false
    }

    @Test("Below ½ a label over the unreported page draws nothing", arguments: [0.3, 0.49])
    func belowHalfTheLabelIsGone(opacity: Double) {
        TerminalColors.withCurrent(.unknown) {
            let ink = screen(Text("ab").opacity(opacity))
            #expect(text(ink).isEmpty, "\(ink.debugDescription)")
            let red = screen(Text("ab").foregroundStyle(Self.red).opacity(opacity))
            #expect(text(red).isEmpty, "\(red.debugDescription)")
        }
    }

    @Test("At ½ and above the label draws, in its own ink", arguments: [0.5, 0.6])
    func atHalfTheLabelStays(opacity: Double) {
        TerminalColors.withCurrent(.unknown) {
            let ink = screen(Text("ab").opacity(opacity))
            #expect(text(ink) == "ab", "\(ink.debugDescription)")
            // The terminal's own foreground, which has no RGB to state: 39, never 38.
            #expect(!ink.contains("38;"), "\(ink.debugDescription)")
            let red = screen(Text("ab").foregroundStyle(Self.red).opacity(opacity))
            #expect(text(red) == "ab", "\(red.debugDescription)")
            #expect(red.contains("38;2;200;40;40"), "\(red.debugDescription)")
        }
    }

    /// An underline is ink too (rule 6), so a dropped glyph takes it with it.
    @Test("A dropped glyph leaves no underline behind")
    func aDroppedGlyphLeavesNoUnderline() {
        TerminalColors.withCurrent(.unknown) {
            let faded = screen(Text("a b").underline().opacity(0.3))
            #expect(text(faded).isEmpty, "\(faded.debugDescription)")
            #expect(!inksABlank(faded), "\(faded.debugDescription)")
            let kept = screen(Text("a b").underline().opacity(0.6))
            #expect(inksABlank(kept), "the fixture: an underline that stays must be seen")
        }
    }

    /// The same cell reached through a colour's own alpha: the layer is whole, the ink
    /// below ½ snaps to the page, and the glyph still wins its cell.
    @Test("A translucent ink below ½ draws nothing, over the page or over text")
    func aTranslucentInkBelowHalfIsGone() {
        TerminalColors.withCurrent(.unknown) {
            let bare = screen(inked(0.3))
            #expect(text(bare).isEmpty, "\(bare.debugDescription)")
            // Over text the layer is whole, so the source wins the contest and the
            // text it displaces is not revealed.
            let covering = screen(ZStack { Text("xy"); inked(0.3) })
            #expect(text(covering).isEmpty, "\(covering.debugDescription)")
            let kept = screen(ZStack { Text("xy"); inked(0.6) })
            #expect(text(kept) == "ab", "\(kept.debugDescription)")
        }
    }

    /// Keyed on what can be measured, not on the palette: once the terminal has
    /// reported its page, the label fades toward it as RGB and keeps its glyph.
    @Test("Over a reported page a faded label keeps its glyph")
    func aReportedPageFadesAsBefore() {
        TerminalColors.withCurrent(Self.reported) {
            let faded = screen(Text("ab").opacity(0.3))
            #expect(text(faded) == "ab", "\(faded.debugDescription)")
            #expect(faded.contains("38;2;"), "\(faded.debugDescription)")
            let inkedFaded = screen(inked(0.3))
            #expect(text(inkedFaded) == "ab", "\(inkedFaded.debugDescription)")
            #expect(inkedFaded.contains("38;2;"), "\(inkedFaded.debugDescription)")
        }
    }

    // MARK: - The transition dissolve

    /// `.transition(.opacity)` does not composite. It rewrites the colours a view already
    /// drew (`OpacityFade`, through `SGRColorRewrite`): a pre-rendered SGR 31 is read back
    /// as its slot and a 39 as the palette's ink, and each is faded toward the page with
    /// the same blend. So the same cell arises there, and takes the same rule.
    private func dissolved(_ line: String, _ factor: Double) -> String {
        OpacityFade.fading(
            line, by: factor, over: Color(value: .terminalBackground),
            defaultForeground: Color(value: .terminalForeground))
    }

    /// The first row of `view` as `.transition(.opacity)` draws it at `phase`, over the
    /// terminal's page.
    private func dissolving<V: View>(_ view: V, at phase: Double) -> String {
        let context = makeRenderContext(width: 12, height: 1) { environment, _ in
            environment.palette = TerminalPairPalette()
        }
        return ColorDepth.withCurrent(.truecolor) {
            let drawn = renderToBuffer(view, context: context)
            return AnyTransition.Effect.opacity.apply(to: drawn, phase: phase, context: context).buffer.lines[0]
        }
    }

    /// The visible characters of `line` drawn with an attribute that inks a blank cell.
    private func inkedBlanks(_ line: String) -> String {
        var state = SGRState()
        var inked = ""
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, _): state.apply(sequence)
            case .visible(let character): if state.paintsInkOnBlankCell { inked.append(character) }
            }
        }
        return inked
    }

    @Test("Below ½ a dissolve over the unreported page draws nothing", arguments: [0, 0.3, 0.49])
    func belowHalfTheDissolveIsGone(phase: Double) {
        TerminalColors.withCurrent(.unknown) {
            // A slot, the palette's ink and an RGB ink, each drawn before the fade.
            for line in ["\u{1B}[31mab\u{1B}[0m", "\u{1B}[39mab\u{1B}[0m", "\u{1B}[38;2;200;40;40mab\u{1B}[0m"] {
                let faded = dissolved(line, phase)
                #expect(faded.stripped == "  ", "\(line.debugDescription) → \(faded.debugDescription)")
            }
            // A wide glyph leaves as many cells as it took.
            let wide = dissolved("\u{1B}[31m漢x\u{1B}[0m", phase)
            #expect(wide.stripped == "   ", "\(wide.debugDescription)")
            let view = dissolving(Text("ab").foregroundStyle(Color.ansi(.red)), at: phase)
            #expect(text(view).isEmpty, "\(view.debugDescription)")
        }
    }

    @Test("At ½ and above a dissolve keeps the glyph, in its own ink", arguments: [0.5, 0.6])
    func atHalfTheDissolveStays(phase: Double) {
        TerminalColors.withCurrent(.unknown) {
            let slot = dissolved("\u{1B}[31mab\u{1B}[0m", phase)
            #expect(slot.stripped == "ab" && slot.contains("\u{1B}[31m"), "\(slot.debugDescription)")
            let view = dissolving(Text("ab").foregroundStyle(Color.ansi(.red)), at: phase)
            #expect(text(view) == "ab" && view.contains("31m"), "\(view.debugDescription)")
            #expect(!view.contains("38;"), "\(view.debugDescription)")
        }
    }

    /// Rule 6 on the rewrite. The glyph kept after the dropped one is reversed: a reversed
    /// cell is a fill whatever its glyph, so the rule leaves it, and its underline, which
    /// no sequence restates, has to come back after the dropped glyph's is cleared.
    @Test("A dissolved glyph leaves no underline, and a glyph kept after it keeps its own")
    func aDissolvedGlyphLeavesNoUnderline() {
        TerminalColors.withCurrent(.unknown) {
            let line = "\u{1B}[4;31ma \u{1B}[7mb\u{1B}[0m"
            let faded = dissolved(line, 0.3)
            #expect(faded.stripped == "  b", "\(faded.debugDescription)")
            #expect(inkedBlanks(faded) == "b", "\(faded.debugDescription)")
            #expect(inkedBlanks(dissolved(line, 0.6)) == "a b", "the fixture: underlines that stay must be seen")
        }
    }

    /// Keyed on what can be measured, as the composite is.
    @Test("Over a reported page a dissolve keeps its glyph, in RGB")
    func aReportedPageDissolvesAsBefore() {
        TerminalColors.withCurrent(Self.reported) {
            // The slots are still unreported, so the slot snaps to the page, which is RGB.
            let faded = dissolved("\u{1B}[31mab\u{1B}[0m", 0.3)
            #expect(faded.stripped == "ab" && faded.contains("38;2;40;44;52"), "\(faded.debugDescription)")
            let view = dissolving(Text("ab").foregroundStyle(Color.ansi(.red)), at: 0.3)
            #expect(text(view) == "ab" && view.contains("38;2;40;44;52"), "\(view.debugDescription)")
        }
        TerminalColors.withCurrent(UnreportedANSISlotTests.appleTerminal) {
            let faded = dissolved("\u{1B}[31mab\u{1B}[0m", 0.3)
            let between = Color.ansi(.red).opacity(0.3, over: Color(value: .terminalBackground))
            #expect(Self.isRGB(between), "the fixture: a reported slot over a reported page mixes")
            #expect(faded.stripped == "ab", "\(faded.debugDescription)")
            #expect(faded.contains(between.foregroundCodes().joined(separator: ";")), "\(faded.debugDescription)")
        }
    }

    private static func isRGB(_ colour: Color) -> Bool {
        if case .rgb = colour.value { return true }
        return false
    }
}
