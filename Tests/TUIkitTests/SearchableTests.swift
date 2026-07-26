//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SearchableTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("searchable")
struct SearchableTests {
    private final class QueryBox { var query = "" }
    private func binding(_ box: QueryBox) -> Binding<String> {
        Binding(get: { box.query }, set: { box.query = $0 })
    }
    private func render(_ view: some View) -> [String] {
        let context = makeBareRenderContext(width: 40, height: 8)
        return renderToBuffer(view, context: context).lines
    }

    @Test("Presents a search field above the searchable content")
    func presentsFieldAboveContent() {
        let out = render(Text("CONTENT").searchable(text: binding(QueryBox())))
        let joined = out.joined(separator: "\n")
        // No emoji chrome in a bare context, so the icon is omitted (a tiny
        // ⌕ / mis-drawn magnifier would read as noise) — the "Search" prompt
        // carries the affordance instead. Both magnifiers are checked: the
        // placement decides WHICH one is drawn, so asserting only one would
        // silently stop testing anything if the default side ever changed.
        #expect(joined.contains("Search"), "the default prompt renders when the field is empty")
        #expect(!joined.contains("\u{1F50D}"), "no magnifier at all without emoji chrome")
        #expect(!joined.contains("\u{1F50E}"), "no magnifier at all without emoji chrome")
        #expect(joined.contains("CONTENT"), "the searchable content renders too")

        let promptLine = out.firstIndex { $0.contains("Search") } ?? Int.max
        let contentLine = out.firstIndex { $0.contains("CONTENT") } ?? Int.min
        #expect(promptLine < contentLine, "the field sits above the content")
    }

    @Test("Draws a magnifier where the terminal renders emoji chrome")
    func magnifierWithEmojiChrome() {
        let out = render(
            Text("CONTENT")
                .searchable(text: binding(QueryBox()))
                .environment(\.supportsEmojiChrome, true))
        let joined = out.joined(separator: "\n")
        #expect(joined.contains("\u{1F50E}"), "the leading 🔎 magnifier renders under emoji chrome")

        let glyphLine = out.firstIndex { $0.contains("\u{1F50E}") } ?? Int.max
        let contentLine = out.firstIndex { $0.contains("CONTENT") } ?? Int.min
        #expect(glyphLine < contentLine, "the field sits above the content")
    }

    /// The glyph follows the SIDE so the lens always faces the field: 🔎
    /// (right-pointing) leads, 🔍 (left-pointing) trails.
    ///
    /// Both the glyph AND its column are asserted. Checking only the glyph
    /// would pass for a regression that swapped the characters but left the
    /// icon on the same side — which is exactly the half-fix this is guarding.
    @Test("The magnifier's glyph and column follow its placement")
    func magnifierFollowsPlacement() {
        func iconColumn(_ placement: SearchFieldIconPlacement, glyph: String) -> Int? {
            let out = render(
                Text("CONTENT")
                    .searchable(text: binding(QueryBox()))
                    .searchFieldIconPlacement(placement)
                    .environment(\.supportsEmojiChrome, true))
            return out.compactMap { line -> Int? in
                guard let r = line.range(of: glyph) else { return nil }
                return line.distance(from: line.startIndex, to: r.lowerBound)
            }.first
        }

        guard let leading = iconColumn(.leading, glyph: "\u{1F50E}") else {
            Issue.record("leading placement drew no 🔎")
            return
        }
        guard let trailing = iconColumn(.trailing, glyph: "\u{1F50D}") else {
            Issue.record("trailing placement drew no 🔍")
            return
        }
        #expect(leading < trailing, "the trailing icon sits to the right of the leading one")

        // …and each side draws only its own glyph.
        #expect(iconColumn(.leading, glyph: "\u{1F50D}") == nil, "leading must not draw 🔍")
        #expect(iconColumn(.trailing, glyph: "\u{1F50E}") == nil, "trailing must not draw 🔎")
    }

    @Test("The field reflects the bound query text")
    func reflectsBoundText() {
        let box = QueryBox()
        box.query = "apple"
        let out = render(Text("body").searchable(text: binding(box))).joined(separator: "\n")
        #expect(out.contains("apple"), "the current query renders in the field")
    }

    @Test("A custom prompt is displayed")
    func customPrompt() {
        let out = render(Text("body").searchable(text: binding(QueryBox()), prompt: "Find fruit"))
            .joined(separator: "\n")
        #expect(out.contains("Find fruit"))
    }
}
