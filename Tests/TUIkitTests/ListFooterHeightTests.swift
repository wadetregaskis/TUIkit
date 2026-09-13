//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListFooterHeightTests.swift
//
//  A footered List fills its body with exactly as many row lines as it
//  budgets, and the container that draws the footer clips that body to what it
//  has left — from the bottom. `_ListCore` budgeted a flat two lines for
//  "footer + separator"; the container MEASURES its footer and draws the rule
//  only when asked to. So the two disagreed whenever a footer was not exactly
//  one line under a rule: a footer that wraps cost the list its last content
//  line at every scroll position (at the end, the last row, never drawn while
//  the cursor could sit on it), and `.listFooterSeparator(false)` left the box
//  a line short of its slot.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("A List's footer costs the lines it draws")
struct ListFooterHeightTests {

    private static let rows = (0..<20).map { "row \($0)" }

    private func lines(_ view: some View, in context: RenderContext) -> [String] {
        renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    @Test("A footer that wraps to two lines does not hide the last row")
    func wrappingFooterKeepsTheLastRow() throws {
        // 30 wide: a 28-cell interior, less the footer's own cell of padding
        // each side, wraps this after "press".
        let context = makeRenderContext(width: 30, height: 12)
        let list = List("Files", selection: .constant(String?.none)) {
            ForEach(Self.rows, id: \.self) { Text($0) }
        } footer: {
            Text(verbatim: "Select a row and press Return to open it")
        }

        let first = lines(list, in: context)  // registers the list, and focuses it
        let footerLines = first.filter { $0.contains("Select a row") || $0.contains("open it") }.count
        try #require(footerLines == 2, "the footer must wrap, or this tests nothing: \(first)")

        _ = context.environment.focusManager?.dispatchKeyEvent(KeyEvent(key: .end))
        let atEnd = lines(list, in: context)
        let drawsLastRow = atEnd.contains { $0.contains("row 19") }
        #expect(
            drawsLastRow,
            "scrolled to the end, the last row is drawn:\n\(atEnd.joined(separator: "\n"))")
        #expect(atEnd.count == 12, "the box still fills its slot: \(atEnd.count) lines")
    }

    @Test("A footer drawn without its rule is not charged for one")
    func unruledFooterFillsTheSlot() {
        let context = makeRenderContext(width: 30, height: 12)
        let list = List("Files", selection: .constant(String?.none)) {
            ForEach(Self.rows, id: \.self) { Text($0) }
        } footer: {
            Text(verbatim: "FOOT")
        }
        .listFooterSeparator(false)

        let drawn = lines(list, in: context)
        #expect(drawn.count == 12, "the box occupies the whole slot, got \(drawn.count): \(drawn)")
        // Two border rows and a one-line footer leave nine.
        let rowCount = drawn.filter { $0.contains("row ") }.count
        #expect(rowCount == 9, "\(rowCount) rows: \(drawn)")
    }
}
