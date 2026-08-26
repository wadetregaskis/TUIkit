//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DividerAxisTests.swift
//
//  SwiftUI: "When contained in a stack, the divider extends across the minor
//  axis of the stack, or horizontally when not in a stack." A Divider in an
//  HStack is therefore a vertical rule. TUIkit's was hard-coded horizontal and
//  width-flexible, so it drew a long ─ through the middle of a row AND, being
//  the row's only flexible child, absorbed all its slack and shoved the
//  siblings to the two ends.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("divider axis")
struct DividerAxisTests {
    private func render<V: View>(_ view: V, width: Int = 20, height: Int = 5) -> [String] {
        let context = makeRenderContext(width: width, height: height)
        return renderToBuffer(view, context: context).lines.map(\.stripped)
    }

    @Test("In a row the divider is a vertical rule spanning the row's height")
    func verticalInRow() {
        let lines = render(
            HStack(spacing: 1) {
                VStack { Text("aa"); Text("bb") }
                Divider()
                VStack { Text("cc"); Text("dd") }
            })

        #expect(lines.count >= 2, "the row is as tall as its tallest child: \(lines)")
        for (index, line) in lines.prefix(2).enumerated() {
            #expect(line.contains("│"), "row \(index) carries the rule: \(lines)")
            #expect(!line.contains("─"), "and not a horizontal one: \(lines)")
        }
    }

    @Test("In a row the divider takes one column, not all the slack")
    func doesNotEatTheRowsSlack() {
        // The whole row is 20 wide; the two labels and the rule need 5.
        // A width-flexible divider would take the other 15 and leave
        // "aa" hard against the left edge and "bb" against the right.
        let lines = render(HStack(spacing: 1) { Text("aa"); Divider(); Text("bb") })
        let row = lines[0]
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        #expect(trimmed == "aa │ bb", "the row hugs its content: \(row.debugDescription)")
    }

    @Test("In a column, and outside any stack, it stays horizontal")
    func horizontalElsewhere() {
        let inColumn = render(VStack { Text("aa"); Divider(); Text("bb") })
        #expect(inColumn.contains { $0.contains("─") }, "a column keeps the ─ rule: \(inColumn)")
        #expect(!inColumn.contains { $0.contains("│") }, "and never a │: \(inColumn)")

        // Not in a stack at all: SwiftUI's stated fallback is horizontal.
        let alone = render(Divider())
        #expect(alone[0].contains("─"), "standalone stays horizontal: \(alone)")
    }

    @Test("A custom character is used whichever way the divider draws")
    func customCharacterWins() {
        let inRow = render(HStack { Text("a"); Divider(character: "┃"); Text("b") })
        #expect(inRow[0].contains("┃"), "the caller's glyph is kept in a row: \(inRow)")

        let inColumn = render(VStack { Text("a"); Divider(character: "═"); Text("b") })
        #expect(inColumn.contains { $0.contains("═") }, "and in a column: \(inColumn)")
    }
}
