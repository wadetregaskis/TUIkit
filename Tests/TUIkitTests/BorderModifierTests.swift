//  🖥️ TUIkit — Terminal UI Kit for Swift
//  BorderModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

/// Creates a default render context for testing.
private func testContext(width: Int = 40, height: Int = 24) -> RenderContext {
    makeBareRenderContext(width: width, height: height)
}

// MARK: - BorderModifier Tests

@MainActor
@Suite("BorderModifier Tests")
struct BorderModifierTests {

    @Test(".border() renders with top and bottom borders")
    func borderModifierRenders() {
        let view = Text("Test").border(style: .line)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        // Top border + content + bottom border
        #expect(buffer.height == 3)
        #expect(buffer.lines[0].contains("┌"))
        #expect(buffer.lines[1].contains("Test"))
        #expect(buffer.lines[2].contains("└"))
    }

    @Test(".border() with empty content returns empty")
    func borderModifierEmptyContent() {
        let view = EmptyView().border(style: .line)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        #expect(buffer.isEmpty)
    }

    @Test(".border() with line style uses correct corner characters")
    func borderModifierLineStyle() {
        let view = Text("X").border(style: .line)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        let topLine = buffer.lines[0].stripped
        let bottomLine = buffer.lines[buffer.height - 1].stripped

        #expect(topLine.hasPrefix("┌"))
        #expect(topLine.hasSuffix("┐"))
        #expect(bottomLine.hasPrefix("└"))
        #expect(bottomLine.hasSuffix("┘"))
    }

    @Test(".border() with doubleLine style uses correct characters")
    func borderModifierDoubleLineStyle() {
        let view = Text("X").border(style: .doubleLine)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        let topLine = buffer.lines[0].stripped
        let bottomLine = buffer.lines[buffer.height - 1].stripped

        #expect(topLine.hasPrefix("╔"))
        #expect(topLine.hasSuffix("╗"))
        #expect(bottomLine.hasPrefix("╚"))
        #expect(bottomLine.hasSuffix("╝"))
    }

    @Test(".border() with rounded style uses correct characters")
    func borderModifierRoundedStyle() {
        let view = Text("X").border(style: .rounded)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        let topLine = buffer.lines[0].stripped
        let bottomLine = buffer.lines[buffer.height - 1].stripped

        #expect(topLine.hasPrefix("╭"))
        #expect(topLine.hasSuffix("╮"))
        #expect(bottomLine.hasPrefix("╰"))
        #expect(bottomLine.hasSuffix("╯"))
    }

    @Test(".border() with heavy style uses correct characters")
    func borderModifierHeavyStyle() {
        let view = Text("X").border(style: .heavy)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        let topLine = buffer.lines[0].stripped
        let bottomLine = buffer.lines[buffer.height - 1].stripped

        #expect(topLine.hasPrefix("┏"))
        #expect(topLine.hasSuffix("┓"))
        #expect(bottomLine.hasPrefix("┗"))
        #expect(bottomLine.hasSuffix("┛"))
    }

    @Test(".border() adds 4 to content width (2 border + 2 padding)")
    func borderModifierWidthOverhead() {
        let view = Text("ABCDE").border(style: .line)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        // Content "ABCDE" = 5, + 2 for padding + 2 for borders = 9
        let topLine = buffer.lines[0].stripped
        #expect(topLine.count == 9)
    }

    @Test(".border() content has 1 char padding on each side")
    func borderModifierContentPadding() {
        let view = Text("Hi").border(style: .line)
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)

        // Content line should be: │ Hi │ (with spaces around "Hi")
        let contentLine = buffer.lines[1].stripped
        #expect(contentLine.hasPrefix("│ "))
        #expect(contentLine.hasSuffix(" │"))
        #expect(contentLine.contains(" Hi "))
    }
}

// MARK: - BorderStyle Tests

@MainActor
@Suite("BorderStyle Tests")
struct BorderStyleTests {

    @Test("Custom border style defaults T-junctions to vertical")
    func customBorderStyleDefaultTJunctions() {
        let custom = BorderStyle(
            topLeft: "A",
            topRight: "B",
            bottomLeft: "C",
            bottomRight: "D",
            horizontal: "E",
            vertical: "F"
        )
        #expect(custom.leftT == "F")
        #expect(custom.rightT == "F")
    }
}

// MARK: - SwiftUI spelling

/// `border` was reshaped so SwiftUI's own call site compiles: the colour comes
/// first and unlabelled, as it does in `border(_ content: some ShapeStyle,
/// width: CGFloat = 1)`. The terminal-only part — WHICH box-drawing characters
/// — was added beside it rather than in its place, and a border with no colour
/// named stays available because that is what a themed app wants.
@MainActor
@Suite("border matches SwiftUI's spelling")
struct BorderSpellingTests {

    private func lines(_ view: some View) -> [String] {
        renderToBuffer(view, context: makeBareRenderContext(width: 24, height: 12))
            .lines.map(\.stripped)
    }

    @Test("the colour is the first, unlabelled argument")
    func colourFirst() {
        // The shape SwiftUI teaches. It only has to COMPILE to prove the point;
        // that it also draws a box is the sanity check.
        let drawn = lines(Text(verbatim: "hi").border(.ansi(.red)))
        #expect(drawn.contains { $0.contains("┌") || $0.contains("╭") }, "\(drawn)")
    }

    @Test("style rides alongside the colour, not instead of it")
    func styleBesideColour() {
        let drawn = lines(Text(verbatim: "hi").border(.ansi(.cyan), style: .doubleLine))
        #expect(drawn.contains { $0.contains("╔") }, "the double-line corner: \(drawn)")
    }

    /// The palette-coloured spelling has no SwiftUI equivalent — SwiftUI has no
    /// palette — and is what most call sites want, so it must keep working
    /// without naming a colour at all.
    @Test("a border with no colour named still draws")
    func noColourNamed() {
        #expect(lines(Text(verbatim: "hi").border()).count >= 3)
        #expect(lines(Text(verbatim: "hi").border(style: .rounded))
            .contains { $0.contains("╭") })
    }

    /// A terminal has no fractional stroke, so `width` is the number of
    /// concentric rings. Each one costs two cells of height, which is what
    /// makes the count observable.
    @Test("width draws that many concentric rings")
    func widthNests() {
        let one = lines(Text(verbatim: "hi").border(.ansi(.red), width: 1)).count
        let two = lines(Text(verbatim: "hi").border(.ansi(.red), width: 2)).count
        let three = lines(Text(verbatim: "hi").border(.ansi(.red), width: 3)).count
        #expect(two == one + 2, "one ring adds a row above and below: \(one) → \(two)")
        #expect(three == two + 2, "and again: \(two) → \(three)")
    }

    @Test("width 0 draws no border at all")
    func widthZero() {
        let bare = lines(Text(verbatim: "hi"))
        let zero = lines(Text(verbatim: "hi").border(.ansi(.red), width: 0))
        #expect(zero.count == bare.count, "\(zero) vs \(bare)")
        #expect(!zero.contains { $0.contains("┌") || $0.contains("╭") })
    }
}
