//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HeaderProminenceTests.swift
//
//  `headerProminence(_:)` — how loud a `Section` header is.
//
//  A terminal cannot make a header bigger, so what `.increased` raises is
//  intensity: the standard header is bold-and-dim, the increased one is bold
//  at full strength. The tests pin BOTH halves of that — that the dim goes,
//  and that nothing else does, since a header that changed shape between
//  prominences would reflow the list around it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore
import TUIkitStyling

@testable import TUIkit

@MainActor
@Suite("Section header prominence")
struct HeaderProminenceTests {

    /// The header row of a one-section list, as raw bytes (the difference is a
    /// colour/attribute one, so a stripped comparison would see nothing).
    private func headerRow(_ prominence: Prominence?) -> String {
        let section = Section {
            Text(verbatim: "row")
        } header: {
            Text(verbatim: "TODAY")
        }
        let view = prominence.map { AnyView(section.headerProminence($0)) } ?? AnyView(section)
        let lines = renderToBuffer(view, context: makeRenderContext(width: 30, height: 6)).lines
        return lines.first { $0.contains("TODAY") } ?? ""
    }

    /// SGR 2 is the dim parameter. It arrives netted into one sequence with the
    /// colour, so the assertion looks for the parameter rather than `ESC[2m`.
    private func isDim(_ row: String) -> Bool {
        row.contains("\u{1B}[2;") || row.contains("\u{1B}[2m") || row.contains(";2;38")
    }

    @Test("a standard header is dim, an increased one is not")
    func increasedDropsTheDim() {
        let standard = headerRow(.standard)
        let increased = headerRow(.increased)
        #expect(isDim(standard), "the fixture's standard header really is dim: \(standard)")
        #expect(!isDim(increased), "…and the increased one is not: \(increased)")
    }

    @Test("the default is standard")
    func defaultsToStandard() {
        #expect(headerRow(nil) == headerRow(.standard))
    }

    /// The load-bearing constraint: intensity only. Same glyphs, same width —
    /// so raising a header cannot move anything around it.
    @Test("prominence changes no glyph and no width")
    func shapeIsUnchanged() {
        let standard = headerRow(.standard)
        let increased = headerRow(.increased)
        #expect(standard.stripped == increased.stripped)
        #expect(standard.strippedLength == increased.strippedLength)
    }

    /// The prominence sets the BASELINE, so an app that styles headers
    /// explicitly still wins — otherwise `.increased` would quietly outrank a
    /// deliberate choice.
    @Test("an explicit style still overrides the prominence")
    func explicitStyleWins() {
        let section = Section {
            Text(verbatim: "row")
        } header: {
            Text(verbatim: "TODAY")
        }
        .headerProminence(.increased)
        .style(.chrome(.sectionHeader)) { $0.dim = true }

        let lines = renderToBuffer(
            AnyView(section), context: makeRenderContext(width: 30, height: 6)
        ).lines
        let row = lines.first { $0.contains("TODAY") } ?? ""
        #expect(isDim(row), "the explicit dim survived .increased: \(row)")
    }
}
