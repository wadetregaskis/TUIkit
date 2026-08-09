//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListRowStyleTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// `.listRowInsets(_:)` and `.listRowBackground(_:)` — the two list-row
/// modifiers a grid of character cells can actually honour.
///
/// The property that matters for the background is that it fills the **row**,
/// not the text: a fill that stopped where the words stop would read as a
/// highlight around them, which is the opposite of what a row background is
/// for.
@MainActor
@Suite("List row styling")
struct ListRowStyleTests {

    private func lines(_ view: some View, width: Int = 20, height: Int = 6) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map(\.stripped)
    }

    // MARK: - Insets

    @Test("Insets move the row's content")
    func insetsPadContent() {
        let bare = lines(Text("row"))
        let inset = lines(Text("row").listRowInsets(EdgeInsets(horizontal: 3, vertical: 0)))
        #expect(bare[0].hasPrefix("row"))
        #expect(inset[0].hasPrefix("   row"))
    }

    @Test("Vertical insets add lines above and below")
    func verticalInsets() {
        let inset = lines(Text("row").listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0)))
        #expect(inset.count == 3)
        #expect(inset[0].trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(inset[1].contains("row"))
    }

    @Test("nil insets mean the list's default, which is no change")
    func nilInsetsAreIdentity() {
        // SwiftUI's `nil` is "use the default"; an unmodified row already gets
        // the default, so the modifier has to be the identity — NOT zero.
        #expect(lines(Text("row").listRowInsets(nil)) == lines(Text("row")))
    }

    // MARK: - Background

    @Test("A background fills the row, not just the text")
    func backgroundSpansTheRow() {
        let width = 20
        let buffer = renderToBuffer(
            Text("hi").listRowBackground(Color.blue),
            context: makeRenderContext(width: width, height: 3))
        // The text is 2 cells; the painted row is the full width.
        #expect(buffer.lines[0].stripped.count == width)
        #expect(buffer.lines[0].stripped.hasPrefix("hi"))
        // …and it really is painted, not just space-padded.
        #expect(buffer.lines[0].contains("\u{1B}["))
    }

    @Test("A background covers every line of a multi-line row")
    func backgroundCoversTallRows() {
        let buffer = renderToBuffer(
            VStack(spacing: 0) {
                Text("one")
                Text("two")
                Text("three")
            }
            .listRowBackground(Color.blue),
            context: makeRenderContext(width: 20, height: 6))
        #expect(buffer.lines.count == 3)
        for line in buffer.lines.prefix(3) {
            #expect(line.contains("\u{1B}["))
            #expect(line.stripped.count == 20)
        }
    }

    @Test("A view background is repeated to cover the row")
    func viewBackgroundTiles() {
        // The generic (View) overload, not the Color one: a one-line view
        // behind a three-line row has to cover all three, or the row shows
        // through where the background ran out.
        let buffer = renderToBuffer(
            VStack(spacing: 0) {
                Text("one")
                Text("two")
                Text("three")
            }
            .listRowBackground(Text("~~~~~~~~~~~~~~~~~~~~")),
            context: makeRenderContext(width: 20, height: 6))
        #expect(buffer.lines.count == 3)
        // The content wins where it draws (the VStack centres its rows within
        // its own width, hence `contains` rather than `hasPrefix`), and the
        // background fills the row out to its full width either side.
        #expect(buffer.lines[0].stripped.contains("one"))
        #expect(buffer.lines[0].stripped.hasSuffix("~"))
        #expect(buffer.lines[2].stripped.contains("three"))
        #expect(buffer.lines[2].stripped.hasSuffix("~"))
        #expect(buffer.lines[0].stripped.count == 20)
    }

    @Test("A nil background leaves the row alone")
    func nilBackgroundIsIdentity() {
        let plain = lines(Text("row"))
        let nilBacked = lines(Text("row").listRowBackground(Color?.none))
        #expect(plain == nilBacked)
    }

    @Test("The row still measures as its content")
    func backgroundDoesNotResizeTheRow() {
        // A background is behind the row, not beside it: it must not make the
        // row taller, or a list of them would stretch to the viewport.
        let context = makeRenderContext(width: 20, height: 10)
        let bare = measureChild(Text("row"), proposal: .unspecified, context: context)
        let backed = measureChild(
            Text("row").listRowBackground(Color.blue), proposal: .unspecified, context: context)
        #expect(bare.height == backed.height)
    }

    @Test("A control in a backed row is still clickable")
    func backgroundKeepsHitRegions() {
        // Compositing merges cells; the interactive metadata has to be carried
        // deliberately, and it is the content's that matters.
        let context = makeRenderContext(width: 20, height: 3) { environment, _ in
            environment.mouseEventDispatcher = MouseEventDispatcher()
        }
        let plain = renderToBuffer(Button("Tap") {}, context: context)
        let backed = renderToBuffer(
            Button("Tap") {}.listRowBackground(Color.blue), context: context)
        #expect(!plain.hitTestRegions.isEmpty)
        #expect(backed.hitTestRegions.count == plain.hitTestRegions.count)
    }

    // MARK: - In a real List

    @Test("Both work on rows inside a List")
    func insideAList() {
        let rendered = lines(
            List {
                Text("alpha")
                    .listRowInsets(EdgeInsets(horizontal: 2, vertical: 0))
                    .listRowBackground(Color.blue)
                Text("beta")
            },
            width: 24, height: 8)
        #expect(rendered.contains { $0.contains("alpha") })
        #expect(rendered.contains { $0.contains("beta") })
    }
}
