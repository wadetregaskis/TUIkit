//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SymbolVariantsTests.swift
//
//  ``SymbolVariants`` — the filled / enclosed / struck-through cut of an SF
//  Symbol, chosen for a whole subtree.
//
//  The composition and the name transform are testable everywhere; the actual
//  glyph lookup only resolves on Apple platforms with the symbol table, so the
//  rendering assertions are gated on that rather than being written to pass
//  vacuously.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("SF Symbol variants")
struct SymbolVariantsTests {

    // MARK: - The name transform

    /// The component order is SF Symbols' own, read off the shipped table:
    /// `bell.slash.circle.fill` exists, `star.fill.circle` does not.
    @Test("the suffix orders slash, then enclosure, then fill")
    func suffixOrder() {
        #expect(SymbolVariants.none.nameSuffix.isEmpty)
        #expect(SymbolVariants.fill.nameSuffix == ".fill")
        #expect(SymbolVariants.circle.nameSuffix == ".circle")
        #expect(SymbolVariants.slash.nameSuffix == ".slash")
        #expect(SymbolVariants.circle.fill.nameSuffix == ".circle.fill")
        #expect(SymbolVariants.slash.fill.nameSuffix == ".slash.fill")
        #expect(SymbolVariants.slash.circle.fill.nameSuffix == ".slash.circle.fill")
        // Chaining is order-independent in the API even though the NAME is not.
        #expect(SymbolVariants.fill.circle.nameSuffix == ".circle.fill")
    }

    /// A symbol is in a circle or a square, never both — so a second enclosure
    /// replaces the first rather than accumulating an impossible name.
    @Test("enclosures are exclusive")
    func enclosuresReplace() {
        #expect(SymbolVariants.circle.square.nameSuffix == ".square")
        #expect(SymbolVariants.square.circle.fill.nameSuffix == ".circle.fill")
    }

    @Test("contains reports the components present")
    func contains() {
        let combined = SymbolVariants.circle.fill
        #expect(combined.contains(.fill))
        #expect(combined.contains(.circle))
        #expect(!combined.contains(.square))
        #expect(!combined.contains(.slash))
        #expect(!SymbolVariants.fill.contains(.circle))
        // `.none` asks for nothing, so nothing can fail to provide it.
        #expect(SymbolVariants.none.contains(.none))
        #expect(combined.contains(.none))
    }

    @Test("variants are equatable and hashable by content")
    func valueSemantics() {
        #expect(SymbolVariants.circle.fill == SymbolVariants.fill.circle)
        #expect(SymbolVariants.fill != SymbolVariants.circle)
        #expect(Set([SymbolVariants.circle.fill, SymbolVariants.fill.circle]).count == 1)
    }

    // MARK: - Resolution

    /// The fallback is the load-bearing part, and it is not hypothetical:
    /// `person.circle.fill` ships, `person.square.fill` does not.
    @Test("an absent variant falls back to the base symbol")
    func fallsBackToBase() throws {
        try #require(SFSymbol.glyph(named: "person") != nil, "needs the symbol table")
        try #require(
            SFSymbol.glyph(named: "person.square.fill") == nil,
            "this test relies on person.square.fill being absent")

        let base = try #require(SFSymbol.glyph(named: "person"))
        #expect(_SymbolIcon.glyph(for: "person", variants: .square.fill) == base)

        // …while a variant that DOES exist is used.
        let circled = try #require(SFSymbol.glyph(named: "person.circle.fill"))
        #expect(_SymbolIcon.glyph(for: "person", variants: .circle.fill) == circled)
        #expect(circled != base, "the variant is a different glyph")
    }

    @Test("no variant resolves the name as written")
    func noVariant() throws {
        let base = try #require(SFSymbol.glyph(named: "star"))
        #expect(_SymbolIcon.glyph(for: "star", variants: .none) == base)
    }

    /// An unknown symbol yields nothing rather than a stray suffix lookup that
    /// happens to hit.
    @Test("an unknown symbol resolves to nothing")
    func unknownSymbol() {
        #expect(_SymbolIcon.glyph(for: "definitely.not.a.symbol", variants: .fill).isEmpty)
    }

    // MARK: - Cascade

    /// The reason it is an environment value: one modifier on a container
    /// re-cuts every symbol beneath it.
    @Test("the variant reaches every label in the subtree")
    func cascades() throws {
        try #require(SFSymbol.isFontAvailable, "needs a terminal font carrying SF Symbols")
        let starFill = try #require(SFSymbol.glyph(named: "star.fill"))

        let drawn = renderToBuffer(
            VStack {
                Label("A", systemImage: "star")
                Label("B", systemImage: "star")
            }
            .symbolVariant(.fill),
            context: makeBareRenderContext(width: 30, height: 6)
        ).lines.map(\.stripped).joined()

        #expect(drawn.contains(starFill), "the filled cut was drawn")
        #expect(drawn.filter { String($0) == starFill }.count == 2, "…for both labels")
    }

    @Test("the innermost variant wins")
    func innermostWins() throws {
        try #require(SFSymbol.isFontAvailable, "needs a terminal font carrying SF Symbols")
        let plain = try #require(SFSymbol.glyph(named: "star"))
        let filled = try #require(SFSymbol.glyph(named: "star.fill"))

        let drawn = renderToBuffer(
            VStack {
                Label("A", systemImage: "star").symbolVariant(.none)
                Label("B", systemImage: "star")
            }
            .symbolVariant(.fill),
            context: makeBareRenderContext(width: 30, height: 6)
        ).lines.map(\.stripped).joined()

        #expect(drawn.contains(plain), "the inner override drew the plain cut")
        #expect(drawn.contains(filled), "the outer variant still applied to the other")
    }

    /// A variant must not change whether the label HAS an icon — that is decided
    /// by the base symbol, precisely because the resolution falls back to it.
    @Test("a variant does not remove the icon")
    func variantKeepsTheIcon() throws {
        try #require(SFSymbol.isFontAvailable, "needs a terminal font carrying SF Symbols")
        func width(_ view: some View) -> Int {
            measureChild(
                view, proposal: ProposedSize(width: 30, height: 4),
                context: makeBareRenderContext(width: 30, height: 4)
            ).width
        }
        // `person.square.fill` does not exist, so this falls back — and the
        // label must still be as wide as the one with a resolvable variant.
        #expect(
            width(Label("P", systemImage: "person").symbolVariant(.square.fill))
                == width(Label("P", systemImage: "person").symbolVariant(.circle.fill)))
    }
}
