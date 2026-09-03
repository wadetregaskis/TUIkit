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

    // The two that follow read the baked name→glyph table, which is compiled in
    // only under `#if canImport(AppKit)` (see `SFSymbol.glyph(named:)`). Off
    // Apple there is nothing to look up and nothing to assert, so they are
    // elided the same way `SFSymbolTests` and `LinkTests` elide theirs — a
    // compile-time fact deserves a compile-time gate. The FONT-dependent tests
    // below are a different condition and take a runtime one.
    #if canImport(AppKit)

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

    #endif

    /// An unknown symbol yields nothing rather than a stray suffix lookup that
    /// happens to hit.
    @Test("an unknown symbol resolves to nothing")
    func unknownSymbol() {
        #expect(_SymbolIcon.glyph(for: "definitely.not.a.symbol", variants: .fill).isEmpty)
    }

    // MARK: - Cascade

    /// The reason it is an environment value: one modifier on a container
    /// re-cuts every symbol beneath it.
    /// Gated rather than asserted: it counts glyph occurrences, and off-font
    /// there are no glyphs to count, so on Linux it would pass vacuously — the
    /// thing this file's header says not to do. `.enabled(if:)` reports a skip
    /// with its reason; a `#require` would report a failure.
    ///
    /// - Note: The condition closure is `@Sendable` and non-isolated, so it can
    ///   only read non-isolated state. `SFSymbol` is a plain `enum` and
    ///   `isFontAvailable` a `static let`, which is why this compiles; were the
    ///   package to adopt default-`MainActor` isolation, these traits would be
    ///   the first thing to break.
    @Test(
        "the variant reaches every label in the subtree",
        .enabled(if: SFSymbol.isFontAvailable, "needs a terminal font carrying SF Symbols"))
    func cascades() throws {
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

    /// Gated for the same reason as ``cascades()``: it distinguishes two
    /// *different* glyphs, which cannot exist where none can be drawn.
    @Test(
        "the innermost variant wins",
        .enabled(if: SFSymbol.isFontAvailable, "needs a terminal font carrying SF Symbols"))
    func innermostWins() throws {
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
    ///
    /// Ungated, because width is observable on every host. Three variants of one
    /// symbol all measure the same everywhere, which alone would pass vacuously
    /// off-font — so the claim that carries the Linux half is the last one: the
    /// icon column exists exactly when a cut can be drawn. That is the AGREEMENT
    /// shape `ImageTests.symbolDrawsWhenRenderable` uses, and it fails on a host
    /// that leaves a stray gap where it suppressed an icon.
    @Test("a variant does not remove the icon")
    func variantKeepsTheIcon() {
        func width(_ view: some View) -> Int {
            measureChild(
                view, proposal: ProposedSize(width: 30, height: 4),
                context: makeBareRenderContext(width: 30, height: 4)
            ).width
        }
        // `person.square.fill` does not exist and `person.circle.fill` does, so
        // the first falls back — and both must still be as wide as the plain cut.
        let bare = width(Label("P", systemImage: "person").symbolVariant(.none))
        let squared = width(Label("P", systemImage: "person").symbolVariant(.square.fill))
        let circled = width(Label("P", systemImage: "person").symbolVariant(.circle.fill))
        #expect(squared == circled, "a fallback measures as the variant it fell back from")
        #expect(squared == bare, "…and as the base symbol it fell back to")
        #expect(
            (squared > width(Text("P"))) == SFSymbol.canRender(named: "person"),
            "an icon column appears exactly where an icon can be drawn")
    }
}
