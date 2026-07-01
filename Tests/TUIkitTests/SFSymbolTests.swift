//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SFSymbolTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit
@testable import TUIkitView

/// Coverage for SF Symbol support: the Plane-16 PUA width/advance classification
/// (`Character.terminalWidth` / `terminalAppCursorAdvance`, which is
/// cross-platform — a pure range check), the Apple-only name → glyph resolver
/// (``SFSymbol``), and ``Label/init(_:systemImage:)``.
///
/// Codepoint anchors (`star.fill` = U+1002C3, `checkmark` = U+100185) come
/// straight from the SF Symbols app's own table — the same values the generator
/// bakes — so these lock the data in too.
@MainActor
@Suite("SF Symbols")
struct SFSymbolTests {

    // MARK: - Layer 1: width + Terminal.app cursor advance (cross-platform)

    @Test("An SF Symbol PUA scalar is a width-2, advance-1 under-advancer")
    func puaWidthAndAdvance() {
        // star.fill — well inside the Plane-16 PUA SF Symbols range.
        let glyph = Character(Unicode.Scalar(0x10_02C3)!)
        #expect(glyph.terminalWidth == 2)
        #expect(glyph.terminalAppCursorAdvance == 1)
    }

    @Test("The PUA-B range is classified at its boundaries, not beyond")
    func puaBoundaries() {
        #expect(Character(Unicode.Scalar(0x10_0000)!).terminalWidth == 2)  // first PUA-B
        #expect(Character(Unicode.Scalar(0x10_FFFD)!).terminalWidth == 2)  // last PUA-B
        // Just below the plane — a plain ideograph-less codepoint stays 1 cell.
        #expect(Character(Unicode.Scalar(0x0F_FFFD)!).terminalWidth == 1)
    }

    @Test("A line carrying a symbol glyph gets a CUF(1) Terminal.app compensation")
    func compensationInjectsCUF() {
        let line = "x" + String(Unicode.Scalar(0x10_02C3)!) + "y"
        // The glyph claims 2 cells but advances 1, so a CUF(1) is injected to
        // push the cursor to the glyph's visual end (same path as VS-16 emoji).
        #expect(line.withTerminalAppCursorCompensation().contains("\u{1B}[1C"))
    }

    // MARK: - Resolver

    @Test("glyph(named:) resolves a known symbol to its PUA glyph (Apple), nil elsewhere")
    func resolverKnownSymbol() {
        #if canImport(AppKit)
        #expect(SFSymbol.glyph(named: "star.fill") == String(Unicode.Scalar(0x10_02C3)!))
        #expect(SFSymbol.glyph(named: "checkmark") == String(Unicode.Scalar(0x10_0185)!))
        #expect(!SFSymbol.all.isEmpty)
        #else
        #expect(SFSymbol.glyph(named: "star.fill") == nil)
        #expect(SFSymbol.all.isEmpty)
        #endif
    }

    @Test("glyph(named:) returns nil for an unknown symbol name")
    func resolverUnknownSymbol() {
        #expect(SFSymbol.glyph(named: "definitely.not.a.real.symbol.xyzzy") == nil)
    }

    #if canImport(AppKit)
    @Test("Binary search resolves an exact name that is a prefix of others")
    func resolverPrefixBoundary() {
        // `star` is a prefix of `star.fill`, `star.circle`, … — the binary
        // search must return star's own glyph (U+1002C2), not a neighbour's.
        #expect(SFSymbol.glyph(named: "star") == String(Unicode.Scalar(0x10_02C2)!))
        #expect(SFSymbol.glyph(named: "star.fill") == String(Unicode.Scalar(0x10_02C3)!))
        #expect(SFSymbol.glyph(named: "star") != SFSymbol.glyph(named: "star.fill"))
        // An almost-match that isn't a real name still misses.
        #expect(SFSymbol.glyph(named: "star.fil") == nil)
    }
    #endif

    #if canImport(AppKit)
    @Test("The baked table is well-formed: PUA glyphs, sorted, unique names")
    func tableWellFormed() {
        let all = SFSymbol.all
        #expect(all.count > 5000)
        #expect(all == all.sorted { $0.name < $1.name })  // sorted ascending by name
        #expect(Set(all.map(\.name)).count == all.count)  // names unique
        // Every glyph is exactly one Plane-16 PUA scalar.
        for entry in all {
            let scalars = Array(entry.glyph.unicodeScalars)
            #expect(scalars.count == 1)
            if let value = scalars.first?.value {
                #expect((0x10_0000...0x10_FFFD).contains(value))
            }
        }
    }
    #endif

    // MARK: - Label

    @Test("Label(_:systemImage:) always renders its title")
    func labelRendersTitle() {
        let text = renderToBuffer(
            Label("Favourites", systemImage: "star.fill"), context: makeBareRenderContext()
        ).lines.map { $0.stripped }.joined()
        #expect(text.contains("Favourites"))
    }

    #if canImport(AppKit)
    @Test("Label shows the symbol glyph before the title on Apple platforms")
    func labelShowsGlyph() {
        let text = renderToBuffer(
            Label("Star", systemImage: "star.fill"), context: makeBareRenderContext()
        ).lines.map { $0.stripped }.joined()
        #expect(text.contains(String(Unicode.Scalar(0x10_02C3)!)))
        #expect(text.contains("Star"))
    }
    #endif

    @Test("Label with an unresolvable symbol renders title-only, no leading gap")
    func labelUnresolvedTitleOnly() {
        // An unknown name resolves to nothing on every platform → just the title,
        // with no icon column and no stray leading space.
        let lines = renderToBuffer(
            Label("Plain", systemImage: "definitely.not.a.real.symbol.xyzzy"),
            context: makeBareRenderContext()
        ).lines.map { $0.stripped }
        #expect(lines.joined().contains("Plain"))
        #expect(lines.first?.hasPrefix(" ") == false)
    }

    @Test("Label(title:icon:) composes a custom icon and title")
    func labelCustomIconTitle() {
        let text = renderToBuffer(
            Label { Text("Inbox") } icon: { Text("@") }, context: makeBareRenderContext()
        ).lines.map { $0.stripped }.joined()
        #expect(text.contains("@"))
        #expect(text.contains("Inbox"))
    }
}
