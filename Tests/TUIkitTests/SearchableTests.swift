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
        #expect(joined.contains("⌕"), "the search glyph renders")
        #expect(joined.contains("Search"), "the default prompt renders when the field is empty")
        #expect(joined.contains("CONTENT"), "the searchable content renders too")

        let glyphLine = out.firstIndex { $0.contains("⌕") } ?? Int.max
        let contentLine = out.firstIndex { $0.contains("CONTENT") } ?? Int.min
        #expect(glyphLine < contentLine, "the field sits above the content")
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
