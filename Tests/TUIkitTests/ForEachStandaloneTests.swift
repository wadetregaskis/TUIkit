//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ForEachStandaloneTests.swift
//
//  Apple's ForEach documentation writes it as an entire body. Ported verbatim
//  that drew NOTHING here: `body` is a @ViewBuilder block, `buildBlock` of one
//  element returns it unchanged, so no container ever called
//  `resolveChildViews` on it and the renderer fell through to its empty-buffer
//  branch. A blank region gets blamed on the data, which is what makes this
//  worse than a wrong layout rather than better.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("ForEach rendered on its own")
struct ForEachStandaloneTests {
    private struct Fonts: View {
        var body: some View {
            ForEach(["Large Title", "Title", "Headline"], id: \.self) { Text($0) }
        }
    }

    private func render<V: View>(_ view: V, width: Int = 20, height: Int = 6) -> [String] {
        let context = makeRenderContext(width: width, height: height)
        return renderToBuffer(view, context: context).lines.map(\.stripped).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    @Test("A ForEach that is a whole body draws its elements, stacked vertically")
    func foreachAsABody() {
        let lines = render(Fonts()).filter { !$0.isEmpty }
        #expect(lines == ["Large Title", "Title", "Headline"], "\(lines)")
    }

    @Test("A modifier on a ForEach no longer swallows the content")
    func modifiedForEachStillDraws() {
        // A modifier is opaque to child resolution, so the whole ForEach
        // arrives at the renderer as one child. That costs the container's
        // axis, but it must not cost the rows themselves.
        let lines = render(
            VStack {
                ForEach(["A", "B"], id: \.self) { Text($0) }.foregroundStyle(.ansi(.red))
            }
        ).filter { !$0.isEmpty }
        #expect(lines == ["A", "B"], "\(lines)")
    }

    @Test("Inside a container the container still decides the axis")
    func containerStillWins() {
        // The Renderable conformance must not shadow ChildViewProvider:
        // `resolveChildViews` asks for children first, so a ForEach in an
        // HStack is still a row.
        let lines = render(HStack { ForEach(["A", "B"], id: \.self) { Text($0) } })
            .filter { !$0.isEmpty }
        #expect(lines == ["A B"], "a row, not a column: \(lines)")
    }

    @Test("Measuring a standalone ForEach agrees with what it renders")
    func measureMatchesRender() {
        let context = makeRenderContext(width: 20, height: 6)
        let size = measureChild(
            Fonts(), proposal: ProposedSize(width: 20, height: 6), context: context)
        let lines = render(Fonts()).filter { !$0.isEmpty }
        #expect(size.height == lines.count, "\(size) vs \(lines)")
        #expect(size.width == 11, "the widest element, \"Large Title\": \(size)")
    }
}
