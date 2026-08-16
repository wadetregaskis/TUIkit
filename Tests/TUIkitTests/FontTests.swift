//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FontTests.swift
//
//  Semantic font styles — `.font(.headline)` on a medium with one typeface.
//
//  The interesting assertions are not "headline is bold" (a mapping table can
//  be read) but the three properties that make the mapping USABLE: that the
//  tiers are actually told apart in the output, that a font can never change a
//  glyph or a cell count, and that the mapping really is a default the cascade
//  can override — otherwise `.font(.headline)` would be a decree rather than a
//  starting point, and a theme could not exist.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Semantic font styles")
struct FontTests {

    /// Every SGR *attribute* code present in a rendered buffer — "1" is bold,
    /// "2" is faint, "4" underline.
    ///
    /// Codes arrive netted into one sequence with the colour, and an extended
    /// colour spells itself `38;2;r;g;b` — so a naive split reports a faint "2"
    /// for every truecolour run. This consumes the colour operands, which is the
    /// difference between these tests measuring intensity and measuring nothing.
    private func sgrCodes(_ buffer: FrameBuffer) -> Set<String> {
        var codes: Set<String> = []
        for line in buffer.lines {
            var rest = Substring(line)
            while let start = rest.range(of: "\u{1B}[") {
                rest = rest[start.upperBound...]
                guard let terminator = rest.firstIndex(of: "m") else { break }
                let parameters = rest[..<terminator].split(
                    separator: ";", omittingEmptySubsequences: false)
                var index = 0
                while index < parameters.count {
                    let parameter = String(parameters[index])
                    if parameter == "38" || parameter == "48" {
                        // 5;n (indexed) or 2;r;g;b (truecolour) follows.
                        let form = index + 1 < parameters.count ? parameters[index + 1] : ""
                        index += form == "2" ? 5 : 3
                        continue
                    }
                    codes.insert(parameter)
                    index += 1
                }
                rest = rest[rest.index(after: terminator)...]
            }
        }
        return codes
    }

    private func codes(_ view: some View) -> Set<String> {
        sgrCodes(renderToBuffer(view, context: makeRenderContext(width: 30, height: 3)))
    }

    private func line(_ view: some View) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 30, height: 3)).lines.first ?? ""
    }

    // MARK: - The three tiers

    /// The whole point of the collapse: eleven styles, but the tiers a reader
    /// can actually tell apart must actually differ in the output.
    @Test("titular styles render bold, captions faint, body neither")
    func tiersAreDistinct() {
        for style in [Font.largeTitle, .title, .title2, .title3, .headline] {
            #expect(codes(Text(verbatim: "Hi").font(style)).contains("1"), "\(style) should be bold")
        }
        for style in [Font.footnote, .caption, .caption2] {
            #expect(codes(Text(verbatim: "Hi").font(style)).contains("2"), "\(style) should be faint")
        }
        for style in [Font.body, .callout, .subheadline] {
            let rendered = codes(Text(verbatim: "Hi").font(style))
            #expect(!rendered.contains("1") && !rendered.contains("2"), "\(style) should be plain")
        }
    }

    /// A terminal has one size, so a font selects intensity and nothing else.
    /// If this ever failed, applying a font could reflow the layout around it.
    @Test("a font changes no glyph and no cell count")
    func geometryIsUntouched() {
        let plain = line(Text(verbatim: "Deploy"))
        for style in Font.TextStyle.allCases {
            let styled = line(Text(verbatim: "Deploy").font(Font.body.tier(style)))
            #expect(styled.stripped == plain.stripped, "\(style) changed the glyphs")
            #expect(styled.strippedLength == plain.strippedLength, "\(style) changed the width")
        }
    }

    /// `.font(nil)` is SwiftUI's reset, and it has to reach through the
    /// environment — otherwise a font applied to a container could never be
    /// escaped from inside it.
    @Test("nil clears an inherited font")
    func nilResets() {
        let inherited = codes(VStack { Text(verbatim: "Hi") }.font(.headline))
        let cleared = codes(VStack { Text(verbatim: "Hi").font(nil) }.font(.headline))
        #expect(inherited.contains("1"), "the fixture really does inherit bold")
        #expect(!cleared.contains("1"), "…and nil undoes it")
    }

    /// Semantic styling has to work through control labels too, or half of a
    /// ported SwiftUI screen would silently opt out.
    @Test("a font applies to a control's label")
    func reachesControlLabels() {
        let plain = codes(Toggle("Notify", isOn: .constant(true)))
        let faint = codes(Toggle("Notify", isOn: .constant(true)).font(.caption))
        #expect(!plain.contains("2"), "the fixture is not faint on its own")
        #expect(faint.contains("2"), "the caption reached the label")
    }

    // MARK: - Weight

    /// The weight is an override, not an addition — a bold caption is bold, not
    /// a faint one that also claims boldness.
    @Test("an explicit weight overrides the style's own intensity")
    func weightOverridesTheTier() {
        let bolded = codes(Text(verbatim: "Hi").font(.caption.weight(.bold)))
        #expect(bolded.contains("1"), "the weight won")
        #expect(!bolded.contains("2"), "…and the caption's faintness lost")

        let lightened = codes(Text(verbatim: "Hi").font(.headline.weight(.light)))
        #expect(lightened.contains("2"), "a light headline is faint")
        #expect(!lightened.contains("1"), "…and not bold")
    }

    @Test("bold() is the weight shorthand")
    func boldIsWeightBold() {
        #expect(Font.caption.bold() == Font.caption.weight(.bold))
    }

    /// `bold(false)` has to be able to say "not bold", or a headline could
    /// never be quietened without abandoning the semantic style.
    @Test("bold(false) clears the tier's own bold")
    func boldFalseClearsTheTier() {
        #expect(!codes(Text(verbatim: "Hi").font(.headline.bold(false))).contains("1"))
    }

    // MARK: - Italic

    /// Italic is not a metric — SGR 3 exists — so unlike size it is carried
    /// for real rather than mapped onto something else.
    @Test("italic is a real attribute, and composes with the tier")
    func italicIsCarried() {
        let italicised = codes(Text(verbatim: "Hi").font(.headline.italic()))
        #expect(italicised.contains("3"), "italic applied")
        #expect(italicised.contains("1"), "…and the headline is still bold")
        #expect(!codes(Text(verbatim: "Hi").font(.headline)).contains("3"), "not by default")
    }

    /// The identity trio, kept honest the same way the `View` spellings are:
    /// every cell is one column, so there is nothing for these to change.
    @Test("the monospaced trio returns the font unchanged")
    func monospacedIsIdentity() {
        #expect(Font.body.monospaced() == Font.body)
        #expect(Font.body.monospaced(false) == Font.body)
        #expect(Font.body.monospacedDigit() == Font.body)
    }

    /// SwiftUI's `Font.TextStyle` is `Codable`; a round-trip is the only way to
    /// show ours is too, since the conformance is synthesized.
    @Test("TextStyle round-trips through Codable")
    func textStyleIsCodable() throws {
        let encoded = try JSONEncoder().encode(Font.TextStyle.allCases)
        let decoded = try JSONDecoder().decode([Font.TextStyle].self, from: encoded)
        #expect(decoded == Font.TextStyle.allCases)
    }

    // MARK: - The mapping is a default

    /// The load-bearing property behind "themeable": the mapping is a baseline,
    /// so a theme can say what a headline looks like in THIS app.
    @Test("a theme can redefine a semantic style")
    func themeOverridesTheMapping() {
        let themed = codes(
            Text(verbatim: "Hi").font(.headline)
                .style(.font(.headline)) { $0.bold = false; $0.underline = true })
        #expect(themed.contains("4"), "the theme's underline applied")
        #expect(!themed.contains("1"), "…and it turned the default bold off")
    }

    /// …and it only redefines the style it names. A theme that recoloured every
    /// semantic style at once would be a bug, not a theme.
    @Test("redefining one style leaves the others alone")
    func themeScopeIsNarrow() {
        let themed = codes(
            Text(verbatim: "Hi").font(.caption)
                .style(.font(.headline)) { $0.underline = true })
        #expect(!themed.contains("4"), "the headline entry must not reach a caption")
        #expect(themed.contains("2"), "…which still renders faint")
    }

    /// An ordinary explicit attribute outranks the font baseline, the same way
    /// it outranks a `Section` header's chrome default. Without this,
    /// `.font(.headline)` could not be un-bolded by `.bold(false)`.
    @Test("an explicit attribute still beats the font's default")
    func explicitAttributeWins() {
        let unbolded = codes(Text(verbatim: "Hi").font(.headline).bold(false))
        #expect(!unbolded.contains("1"))
    }

    /// The other half of that ordering: a font sits ABOVE a chrome default, so
    /// asking for a caption on a section header gets you a caption.
    @Test("a font outranks a chrome-role default")
    func fontBeatsChromeDefault() {
        let header = Section {
            Text(verbatim: "row")
        } header: {
            Text(verbatim: "TODAY").font(.body)
        }
        let lines = renderToBuffer(
            AnyView(header), context: makeRenderContext(width: 30, height: 6)
        ).lines
        let row = lines.first { $0.contains("TODAY") } ?? ""
        #expect(!row.contains("\u{1B}[1;2"), "body cleared the header's bold+dim: \(row)")
    }
}

extension Font {
    /// Test-only: the font for a given tier, so a test can sweep
    /// `TextStyle.allCases` without an eleven-way switch.
    fileprivate func tier(_ style: Font.TextStyle) -> Font {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption
        case .caption2: return .caption2
        }
    }
}
