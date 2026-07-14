//  🖥️ TUIKit — Terminal UI Kit for Swift
//  CardRenderTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

/// Creates a render context with a fresh FocusManager for isolated testing.
@MainActor
private func createTestContext(width: Int = 30, height: Int = 8) -> RenderContext {
    makeRenderContext(width: width, height: height)
}

/// Convenience: render a view and return its visible (ANSI-stripped) lines.
@MainActor
private func strippedLines<V: View>(_ view: V, width: Int = 30, height: Int = 8) -> [String] {
    renderToBuffer(view, context: createTestContext(width: width, height: height))
        .lines.map { $0.stripped }
}

// MARK: - Card Rendering Tests

@MainActor
@Suite("Card rendering")
struct CardRenderTests {

    // MARK: Default (no title, no footer)

    @Test("Bare card wraps content in a continuous rounded border with padding")
    func bareCardRoundedBorder() {
        // Default appearance is `.rounded` → ╭╮╰╯, with default padding 1 on
        // all sides: one blank row above and below the content.
        let lines = strippedLines(Card { Text("Hello") })

        #expect(lines.count == 5)
        #expect(lines[0] == "╭───────╮")
        #expect(lines[1] == "│       │")
        #expect(lines[2] == "│ Hello │")
        #expect(lines[3] == "│       │")
        #expect(lines[4] == "╰───────╯")
    }

    @Test("Every card line shares one width (clean rectangle)")
    func cardLinesUniformWidth() {
        let buffer = renderToBuffer(Card { Text("Hello") }, context: createTestContext())
        let widths = Set(buffer.lines.map { $0.stripped.count })
        #expect(widths.count == 1, "All lines must be the same visible width")
    }

    @Test("Top and bottom borders have matching rounded corners")
    func cardCornersMatch() {
        let lines = strippedLines(Card { Text("X") })
        let top = lines.first!
        let bottom = lines.last!
        #expect(top.hasPrefix("╭"))
        #expect(top.hasSuffix("╮"))
        #expect(bottom.hasPrefix("╰"))
        #expect(bottom.hasSuffix("╯"))
        // The horizontal runs between corners are the same length.
        #expect(top.dropFirst().dropLast() == bottom.dropFirst().dropLast())
    }

    // MARK: Title

    @Test("Title renders inline in the top border")
    func cardTitleInTopBorder() {
        let lines = strippedLines(Card(title: "Profile") { Text("Name: John") })

        #expect(lines.count == 5)
        #expect(lines[0] == "╭─ Profile ──╮")
        #expect(lines[1] == "│            │")
        #expect(lines[2] == "│ Name: John │")
        #expect(lines[3] == "│            │")
        #expect(lines[4] == "╰────────────╯")
    }

    @Test("Titled card: title row width equals body row width")
    func cardTitleRowWidthMatchesBody() {
        let buffer = renderToBuffer(Card(title: "Profile") { Text("Name: John") }, context: createTestContext())
        let widths = Set(buffer.lines.map { $0.stripped.count })
        #expect(widths.count == 1)
    }

    // MARK: Footer

    @Test("Footer is separated from the body by a T-junction divider")
    func cardFooterSeparator() {
        let lines = strippedLines(Card(title: "Form") { Text("Body") } footer: { Text("[OK]") })

        #expect(lines.count == 7)
        #expect(lines[0] == "╭─ Form ─╮")
        #expect(lines[2] == "│ Body   │")
        // Divider uses left/right T-junctions, not corners.
        #expect(lines[4] == "├────────┤")
        #expect(lines[5] == "│ [OK]   │")
        #expect(lines[6] == "╰────────╯")
    }

    @Test("Footer divider aligns with the side borders")
    func cardFooterDividerAligned() {
        let buffer = renderToBuffer(
            Card(title: "Form") { Text("Body") } footer: { Text("[OK]") },
            context: createTestContext())
        let widths = Set(buffer.lines.map { $0.stripped.count })
        #expect(widths.count == 1, "Divider, borders, and content rows share one width")
    }

    // MARK: Multi-line content

    @Test("Multi-line content renders one bordered row per line, in order")
    func cardMultilineContent() {
        let lines = strippedLines(Card(title: "T") {
            Text("L1")
            Text("L2")
            Text("L3")
        }, width: 30, height: 10)

        #expect(lines.count == 7)
        #expect(lines[0] == "╭─ T ─╮")
        #expect(lines[1] == "│     │")
        #expect(lines[2] == "│ L1  │")
        #expect(lines[3] == "│ L2  │")
        #expect(lines[4] == "│ L3  │")
        #expect(lines[5] == "│     │")
        #expect(lines[6] == "╰─────╯")
        // No stray blank rows between the content lines.
        #expect(!lines[2...4].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    // MARK: Border styles

    @Test("Double-line border uses double-line glyphs on every edge")
    func cardDoubleLineBorder() {
        let lines = strippedLines(Card(title: "D", borderStyle: .doubleLine) { Text("x") })

        #expect(lines.count == 5)
        #expect(lines[0] == "╔═ D ═╗")
        #expect(lines[2] == "║ x   ║")
        #expect(lines[4] == "╚═════╝")
    }

    @Test("Explicit line border uses square corners")
    func cardLineBorder() {
        let lines = strippedLines(Card(borderStyle: .line) { Text("y") })
        #expect(lines.first!.hasPrefix("┌"))
        #expect(lines.first!.hasSuffix("┐"))
        #expect(lines.last!.hasPrefix("└"))
        #expect(lines.last!.hasSuffix("┘"))
    }

    // MARK: Empty content

    @Test("Card with EmptyView content still renders a padded bordered box")
    func cardEmptyContent() {
        // Padding(1) gives an empty body real size, so the border survives
        // rather than collapsing to nothing.
        let lines = strippedLines(Card { EmptyView() })

        #expect(lines.count == 4)
        #expect(lines[0] == "╭──╮")
        #expect(lines[1] == "│  │")
        #expect(lines[2] == "│  │")
        #expect(lines[3] == "╰──╯")
        let widths = Set(lines.map { $0.count })
        #expect(widths.count == 1)
    }

    // MARK: Narrow width / truncation

    @Test("Narrow card truncates a too-long title and keeps the border intact")
    func cardNarrowTitleTruncates() {
        let lines = strippedLines(Card(title: "VeryLongTitleHere") {
            Text("Content that is wide")
        }, width: 12, height: 6)

        // Title is clipped to fit; top border still closes with ╮.
        #expect(lines[0] == "╭─ VeryLon ╮")
        #expect(lines.first!.hasSuffix("╮"))
        #expect(lines.last! == "╰──────────╯")
        // The whole card respects the 12-cell width budget.
        #expect(lines.allSatisfy { $0.count == 12 })
    }

    @Test("Narrow card wraps and ellipsises over-long body text")
    func cardNarrowBodyTruncates() {
        let lines = strippedLines(Card(title: "VeryLongTitleHere") {
            Text("Content that is wide")
        }, width: 12, height: 6)

        // Body wraps; the clipped line ends with an ellipsis, not mid-word
        // overflow past the right border.
        #expect(lines.contains { $0.contains("…") })
        #expect(lines.allSatisfy { !$0.contains("│ Content that is wide") })
    }

    @Test("No line ever overflows the available width")
    func cardNeverOverflows() {
        let widthBudget = 12
        let buffer = renderToBuffer(
            Card(title: "VeryLongTitleHere") { Text("Content that is wide") },
            context: createTestContext(width: widthBudget, height: 6))
        #expect(buffer.lines.allSatisfy { $0.stripped.count <= widthBudget })
    }

    // MARK: Wide

    @Test("Wide context: card is sized to its content, not stretched to fill")
    func cardWideStaysContentSized() {
        // Card should hug its content rather than expanding to the full 60.
        let buffer = renderToBuffer(Card(title: "Hi") { Text("short") }, context: createTestContext(width: 60, height: 8))
        #expect(buffer.width < 60)
        #expect(buffer.width > 0)
        let widths = Set(buffer.lines.map { $0.stripped.count })
        #expect(widths.count == 1)
    }
}
