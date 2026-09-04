//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListStyleTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@Suite("List Style Tests")
struct ListStyleTests {
    // MARK: - Plain List Style Tests

    @Test("PlainListStyle has no border")
    func testPlainListStyleNoBorder() {
        let style = PlainListStyle()
        #expect(!style.showsBorder)
    }

    @Test("PlainListStyle has zero padding")
    func testPlainListStyleZeroPadding() {
        let style = PlainListStyle()
        #expect(style.rowPadding == EdgeInsets(all: 0))
    }

    @Test("PlainListStyle has no alternating rows")
    func testPlainListStyleNoAlternating() {
        let style = PlainListStyle()
        #expect(!style.alternatingRowColors)
    }

    // MARK: - Inset Grouped List Style Tests

    @Test("InsetGroupedListStyle has border")
    func testInsetGroupedListStyleHasBorder() {
        let style = InsetGroupedListStyle()
        #expect(style.showsBorder)
    }

    @Test("InsetGroupedListStyle has no container padding")
    func testInsetGroupedListStylePadding() {
        // Row padding is handled internally by List's renderRow() method,
        // not by ContainerView, so row backgrounds extend to the borders.
        let style = InsetGroupedListStyle()
        let expectedPadding = EdgeInsets(all: 0)
        #expect(style.rowPadding == expectedPadding)
    }

    @Test("InsetGroupedListStyle has no alternating rows by default")
    func testInsetGroupedListStyleAlternating() {
        let style = InsetGroupedListStyle()
        #expect(!style.alternatingRowColors)
    }

    // MARK: - Direct Instantiation Tests

    @Test("PlainListStyle instantiation works")
    func testPlainInstantiation() {
        let style = PlainListStyle()
        #expect(!style.showsBorder)
        #expect(!style.alternatingRowColors)
    }

    @Test("InsetGroupedListStyle instantiation works")
    func testInsetGroupedInstantiation() {
        let style = InsetGroupedListStyle()
        #expect(style.showsBorder)
        #expect(!style.alternatingRowColors)
    }

    // MARK: - Environment Integration

    @Test("List style stores in environment")
    func testListStyleEnvironmentStorage() {
        var env = EnvironmentValues()
        let style = PlainListStyle()
        env.listStyle = style
        #expect(!env.listStyle.showsBorder)
    }

    @Test("Environment list style default is InsetGroupedListStyle")
    func testEnvironmentListStyleDefault() {
        let env = EnvironmentValues()
        #expect(env.listStyle.showsBorder)
        #expect(!env.listStyle.alternatingRowColors)
    }

    @Test("List style environment can be changed")
    func testChangeListStyleEnvironment() {
        var env = EnvironmentValues()
        env.listStyle = PlainListStyle()
        #expect(!env.listStyle.showsBorder)
        env.listStyle = InsetGroupedListStyle()
        #expect(env.listStyle.showsBorder)
    }

    // MARK: - Unfocused Selection Visibility Environment Tests

    @Test("Unfocused selection visibility defaults to .automatic")
    func testUnfocusedSelectionVisibilityDefault() {
        let env = EnvironmentValues()
        #expect(env.unfocusedSelectionVisibility == .automatic)
    }

    @Test("Unfocused selection visibility can be changed")
    func testUnfocusedSelectionVisibilityChange() {
        var env = EnvironmentValues()
        env.unfocusedSelectionVisibility = .hidden
        #expect(env.unfocusedSelectionVisibility == .hidden)
        env.unfocusedSelectionVisibility = .visible
        #expect(env.unfocusedSelectionVisibility == .visible)
    }

    // MARK: - Sendable Tests

    @Test("PlainListStyle is Sendable")
    func testPlainListStyleSendable() {
        let style = PlainListStyle()
        let _: PlainListStyle = style
    }

    @Test("InsetGroupedListStyle is Sendable")
    func testInsetGroupedListStyleSendable() {
        let style = InsetGroupedListStyle()
        let _: InsetGroupedListStyle = style
    }

    // MARK: - Border rendering (plain vs. bordered)

    /// The box-drawing glyphs a bordered container draws — none of which a
    /// borderless (`.plain`) list may emit.
    private static let borderGlyphs: Set<Character> = [
        "┌", "┐", "└", "┘", "├", "┤", "│", "─",
        "╭", "╮", "╰", "╯",
        "╔", "╗", "╚", "╝", "║", "═",
        "┏", "┓", "┗", "┛", "┃", "━",
    ]

    @MainActor
    private func renderedListLines<S: ListStyle>(_ style: S, stripped: Bool = true) -> [String] {
        let list = List {
            ForEach(["Alpha", "Bravo", "Charlie"], id: \.self) { name in
                Text(name)
            }
        }
        .listStyle(style)
        .frame(height: 6)
        let lines = renderToBuffer(list, context: makeRenderContext(width: 30, height: 8)).lines
        return stripped ? lines.map { $0.stripped } : lines
    }

    @Test("PlainListStyle renders no border glyphs")
    @MainActor
    func plainListStyleDrawsNoBorder() {
        let lines = renderedListLines(PlainListStyle())
        let joined = lines.joined()
        let offending = Set(joined).intersection(Self.borderGlyphs)
        #expect(offending.isEmpty, "plain list must draw no border glyphs, found \(offending) in \(lines)")
        // The rows are still rendered (content survives the borderless path).
        #expect(joined.contains("Alpha") && joined.contains("Bravo") && joined.contains("Charlie"))
    }

    @Test("InsetGroupedListStyle renders border glyphs")
    @MainActor
    func insetGroupedListStyleDrawsBorder() {
        let lines = renderedListLines(InsetGroupedListStyle())
        let joined = lines.joined()
        let present = Set(joined).intersection(Self.borderGlyphs)
        #expect(!present.isEmpty, "inset-grouped list must draw a border, found none in \(lines)")
        // Side walls specifically: every interior row is flanked by `│`.
        #expect(joined.contains("│"), "bordered list draws vertical side walls")
        #expect(joined.contains("Alpha") && joined.contains("Charlie"))
    }

    // MARK: - Alternating row backgrounds

    /// A style that turns alternating rows on — which neither built-in style
    /// does, so this is the only way to reach the code that draws them.
    private struct ZebraListStyle: ListStyle {
        let alternatingRowColors: Bool
        var showsBorder: Bool { false }
        var rowPadding: EdgeInsets { EdgeInsets(all: 0) }
    }

    /// The style decides WHETHER rows alternate; the palette decides which
    /// colour. `ListStyle` used to declare an `alternatingColorPair` for a
    /// style to name its own two colours, but nothing ever read it — even
    /// rows always took the palette accent and odd rows always took nothing —
    /// so the pair is gone and this pins the behaviour that remains.
    @Test("alternatingRowColors tints rows, and it is a background only")
    @MainActor
    func alternatingRowColorsTintsRows() {
        let flat = renderedListLines(ZebraListStyle(alternatingRowColors: false), stripped: false)
        let zebra = renderedListLines(ZebraListStyle(alternatingRowColors: true), stripped: false)

        #expect(flat != zebra, "the tint is the only difference between them, and it must show")
        #expect(
            flat.map { $0.stripped } == zebra.map { $0.stripped },
            "a background changes no text: \(zebra.map { $0.stripped })")
    }
}
