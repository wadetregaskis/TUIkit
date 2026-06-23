//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TableRenderTests.swift
//
//  Buffer-level render audit for `Table`. Each case renders the view to a
//  FrameBuffer and asserts the visible (ANSI-stripped) lines: the column
//  header, row layout, alignment, per-cell truncation, the selection
//  indicator, scroll indicators, the empty placeholder, and a closed
//  border throughout.
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Fixtures

private struct Row: Identifiable, Sendable {
    let id: String
    let name: String
    let size: String
}

private let sampleRows: [Row] = [
    Row(id: "1", name: "Alpha", size: "10K"),
    Row(id: "2", name: "Beta", size: "200K"),
    Row(id: "3", name: "Gamma", size: "3K"),
]

// MARK: - Helpers

@MainActor
private func tableContext(width: Int = 30, height: Int = 8, explicitWidth: Bool = false) -> RenderContext {
    let focusManager = FocusManager()
    var environment = EnvironmentValues()
    environment.focusManager = focusManager
    var context = RenderContext(
        availableWidth: width,
        availableHeight: height,
        environment: environment,
        tuiContext: TUIContext()
    ).isolatingRenderCache()
    context.hasExplicitWidth = explicitWidth
    return context
}

@MainActor
private func strippedLines(_ view: some View, context: RenderContext) -> [String] {
    renderToBuffer(view, context: context).lines.map { $0.stripped }
}

/// Asserts the rendered box is rectangular and closed (uniform width,
/// rounded corners, vertical walls down both sides).
private func expectClosedBorder(
    _ lines: [String],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(lines.count >= 2, "a bordered box needs at least 2 lines", sourceLocation: sourceLocation)
    guard let first = lines.first, let last = lines.last else { return }

    let width = first.count
    for (index, line) in lines.enumerated() {
        #expect(
            line.count == width,
            "line \(index) width \(line.count) != box width \(width): \(lines)",
            sourceLocation: sourceLocation
        )
    }

    #expect(first.hasPrefix("╭"), "top-left corner: \(first)", sourceLocation: sourceLocation)
    #expect(first.hasSuffix("╮"), "top-right corner: \(first)", sourceLocation: sourceLocation)
    #expect(last.hasPrefix("╰"), "bottom-left corner: \(last)", sourceLocation: sourceLocation)
    #expect(last.hasSuffix("╯"), "bottom-right corner: \(last)", sourceLocation: sourceLocation)

    for line in lines.dropFirst().dropLast() {
        let firstChar = line.first.map(String.init) ?? ""
        let lastChar = line.last.map(String.init) ?? ""
        #expect(
            firstChar == "│" || firstChar == "├",
            "interior left wall: \(line)",
            sourceLocation: sourceLocation
        )
        #expect(
            lastChar == "│" || lastChar == "┤",
            "interior right wall: \(line)",
            sourceLocation: sourceLocation
        )
    }
}

// MARK: - Suite

@MainActor
@Suite("Table rendering")
struct TableRenderTests {

    // MARK: Default

    @Test("Header and data rows render inside a closed border")
    func defaultLayout() {
        let lines = strippedLines(
            Table(sampleRows, selection: .constant(String?.none)) {
                TableColumn("Name", value: \Row.name)
                TableColumn("Size", value: \Row.size)
            },
            context: tableContext(width: 30, height: 8)
        )

        expectClosedBorder(lines)

        // Strip the border walls to inspect the interior payload.
        let interior = lines.map { line -> String in
            guard line.count >= 2 else { return line }
            return String(line.dropFirst().dropLast())
        }

        // Header line: bold column titles, indented past the indicator gutter.
        #expect(interior[1].contains("Name"))
        #expect(interior[1].contains("Size"))
        // Column order preserved: Name before Size.
        let nameIdx = interior[1].range(of: "Name").map { interior[1].distance(from: interior[1].startIndex, to: $0.lowerBound) }
        let sizeIdx = interior[1].range(of: "Size").map { interior[1].distance(from: interior[1].startIndex, to: $0.lowerBound) }
        if let nameIdx, let sizeIdx { #expect(nameIdx < sizeIdx, "Name column should precede Size") }

        // Data rows, in order.
        #expect(interior[2].contains("Alpha"))
        #expect(interior[2].contains("10K"))
        #expect(interior[3].contains("Beta"))
        #expect(interior[3].contains("200K"))
        #expect(interior[4].contains("Gamma"))
        #expect(interior[4].contains("3K"))
    }

    @Test("Unselected, unfocused rows carry no selection indicator glyph")
    func defaultNoIndicator() {
        let buffer = renderToBuffer(
            Table(sampleRows, selection: .constant(String?.none)) {
                TableColumn("Name", value: \Row.name)
                TableColumn("Size", value: \Row.size)
            },
            context: tableContext(width: 30, height: 8)
        )
        let stripped = buffer.lines.map { $0.stripped }
        // The ● selection glyph never appears when nothing is selected; the
        // indicator gutter stays blank.
        #expect(!stripped.contains { $0.contains("●") }, "no row is selected → no ● indicator")
    }

    // MARK: Selection

    @Test("Selected row gets a ● indicator and a background highlight")
    func selectedRow() {
        let buffer = renderToBuffer(
            Table(sampleRows, selection: .constant("2")) {
                TableColumn("Name", value: \Row.name)
                TableColumn("Size", value: \Row.size)
            },
            context: tableContext(width: 30, height: 8)
        )
        let stripped = buffer.lines.map { $0.stripped }
        expectClosedBorder(stripped)

        // The Beta row (id 2) carries the selection indicator.
        let betaLine = stripped.first { $0.contains("Beta") }
        #expect(betaLine != nil)
        if let betaLine { #expect(betaLine.contains("●"), "selected row should show ●: \(betaLine)") }

        // Exactly one row is marked selected.
        #expect(stripped.filter { $0.contains("●") }.count == 1)

        let raw = buffer.lines.joined()
        let hasBackground =
            raw.contains("[48;2;") || raw.contains("[48;5;") || raw.contains("[4")
        #expect(hasBackground, "selected row should carry a background colour")
    }

    // MARK: Empty

    @Test("Empty table shows the placeholder, header retained")
    func emptyPlaceholder() {
        let empty: [Row] = []
        let lines = strippedLines(
            Table(empty, selection: .constant(String?.none)) {
                TableColumn("Name", value: \Row.name)
                TableColumn("Size", value: \Row.size)
            },
            context: tableContext(width: 30, height: 8)
        )

        expectClosedBorder(lines)
        // Column header still present.
        #expect(lines.contains { $0.contains("Name") && $0.contains("Size") })
        // Placeholder present exactly once.
        #expect(lines.filter { $0.contains("No items") }.count == 1)
    }

    @Test("Custom empty placeholder is honoured")
    func customEmptyPlaceholder() {
        let empty: [Row] = []
        let lines = strippedLines(
            Table(empty, selection: .constant(String?.none), emptyPlaceholder: "Nothing to show") {
                TableColumn("Name", value: \Row.name)
                TableColumn("Size", value: \Row.size)
            },
            context: tableContext(width: 30, height: 8)
        )

        expectClosedBorder(lines)
        #expect(lines.contains { $0.contains("Nothing to show") })
        #expect(!lines.contains { $0.contains("No items") })
    }

    // MARK: Alignment / width

    @Test("Fixed-width trailing column right-aligns its cells")
    func fixedTrailingColumn() {
        // Trailing alignment pushes the value to the right of its column, so a
        // short value like "10K" gains leading pad inside the fixed(6) cell:
        // "   10K". Compare against the default (leading) alignment, where the
        // same value hugs the left of the column.
        func sizeColumn(_ alignment: HorizontalAlignment) -> [String] {
            strippedLines(
                Table(sampleRows, selection: .constant(String?.none)) {
                    TableColumn("Name", value: \Row.name)
                    TableColumn("Size", value: \Row.size).width(.fixed(6)).alignment(alignment)
                },
                context: tableContext(width: 30, height: 8)
            )
        }

        let trailing = sizeColumn(.trailing)
        let leading = sizeColumn(.leading)
        expectClosedBorder(trailing)

        // In the trailing render, "10K" (3 chars in a 6-wide column) is padded
        // on the left → "   10K". In the leading render it is "10K   ".
        let trailingAlpha = trailing.first { $0.contains("Alpha") }
        let leadingAlpha = leading.first { $0.contains("Alpha") }
        #expect(trailingAlpha != nil && leadingAlpha != nil)
        if let trailingAlpha, let leadingAlpha {
            #expect(trailingAlpha.contains("   10K"), "trailing column not right-aligned: '\(trailingAlpha)'")
            #expect(leadingAlpha.contains("10K   "), "leading column not left-aligned: '\(leadingAlpha)'")
            #expect(trailingAlpha != leadingAlpha, "alignment should change the rendering")
        }
    }

    @Test(".fit sizes a column to its widest value, so nothing in it is truncated")
    func fitColumn() {
        let rows = [
            Row(id: "1", name: "Hi", size: "1"),
            Row(id: "2", name: "Wiiiiiiide", size: "2"),  // 10 cells — the widest value
        ]
        // A `.fit` Name column sizes to "Wiiiiiiide" (10) so it shows in full,
        // even though the header "Name" is only 4 wide.
        let fit = strippedLines(
            Table(rows, selection: .constant(String?.none)) {
                TableColumn("Name", value: \Row.name).width(.fit)
                TableColumn("Size", value: \Row.size).width(.fixed(4))
            },
            context: tableContext(width: 40, height: 8)
        )
        expectClosedBorder(fit)
        #expect(fit.contains { $0.contains("Wiiiiiiide") }, "fit must show the widest value in full: \(fit)")
        #expect(!fit.contains { $0.contains("…") }, "fit must not truncate its content: \(fit)")

        // The same data in a fixed(4) Name column DOES truncate the long value —
        // confirming the fit width is genuinely derived from the content.
        let fixed = strippedLines(
            Table(rows, selection: .constant(String?.none)) {
                TableColumn("Name", value: \Row.name).width(.fixed(4))
                TableColumn("Size", value: \Row.size).width(.fixed(4))
            },
            context: tableContext(width: 40, height: 8)
        )
        #expect(fixed.contains { $0.contains("…") }, "fixed(4) should truncate the long value: \(fixed)")
        #expect(!fixed.contains { $0.contains("Wiiiiiiide") }, "fixed(4) cannot show the value in full")
    }

    @Test("Narrow columns truncate cell values with an ellipsis")
    func narrowTruncation() {
        let lines = strippedLines(
            Table(sampleRows, selection: .constant(String?.none)) {
                TableColumn("Filename", value: \Row.name)
                TableColumn("Size", value: \Row.size)
            },
            context: tableContext(width: 14, height: 8)
        )

        expectClosedBorder(lines)
        // The header title "Filename" cannot fit a narrow column → ellipsis.
        #expect(lines.contains { $0.contains("…") }, "expected ellipsis truncation: \(lines)")
        // A long value ("200K") gets clipped with an ellipsis too.
        let joined = lines.joined()
        #expect(joined.contains("…"))
        // No interior line overflows the 14-cell box.
        #expect(lines.allSatisfy { $0.count == 14 }, "rows must not overflow the box: \(lines)")
    }

    @Test("Columns stay aligned: every data row shares the box width")
    func columnsStayAligned() {
        let lines = strippedLines(
            Table(sampleRows, selection: .constant(String?.none)) {
                TableColumn("Name", value: \Row.name)
                TableColumn("Size", value: \Row.size)
            },
            context: tableContext(width: 30, height: 8)
        )
        let widths = Set(lines.map { $0.count })
        #expect(widths.count == 1, "all lines should share one width, got \(widths)")
    }

    // MARK: Scrolling / overflow

    @Test("Overflowing table shows a 'more below' indicator and keeps the header")
    func overflowIndicator() {
        let many = (0..<20).map { Row(id: "\($0)", name: "Row \($0)", size: "\($0)K") }
        let lines = strippedLines(
            Table(many, selection: .constant(String?.none)) {
                TableColumn("Name", value: \Row.name)
                TableColumn("Size", value: \Row.size)
            },
            context: tableContext(width: 30, height: 8)
        )

        expectClosedBorder(lines)
        // Header stays pinned at the top.
        #expect(lines[1].contains("Name") && lines[1].contains("Size"))
        // First data rows visible.
        #expect(lines.contains { $0.contains("Row 0") })
        // Downward scroll indicator with remaining count.
        let indicator = lines.first { $0.contains("▼") && $0.contains("more below") }
        #expect(indicator != nil, "expected '▼ N more below': \(lines)")
        if let indicator { #expect(indicator.contains("16 more below"), "wrong hidden count: \(indicator)") }
        // Last rows not yet revealed.
        #expect(!lines.contains { $0.contains("Row 19") })
    }

    // MARK: Disabled

    @Test("Disabled table still renders header + rows")
    func disabledRenders() {
        let lines = strippedLines(
            Table(sampleRows, selection: .constant(String?.none)) {
                TableColumn("Name", value: \Row.name)
                TableColumn("Size", value: \Row.size)
            }.disabled(),
            context: tableContext(width: 30, height: 8)
        )
        expectClosedBorder(lines)
        #expect(lines.contains { $0.contains("Name") })
        #expect(lines.contains { $0.contains("Alpha") })
    }

    @Test("Disabled table installs no mouse hit-test region")
    func disabledNoHitRegion() {
        let enabled = renderToBuffer(
            Table(sampleRows, selection: .constant(String?.none)) {
                TableColumn("Name", value: \Row.name)
                TableColumn("Size", value: \Row.size)
            },
            context: tableContext(width: 30, height: 8)
        )
        let disabled = renderToBuffer(
            Table(sampleRows, selection: .constant(String?.none)) {
                TableColumn("Name", value: \Row.name)
                TableColumn("Size", value: \Row.size)
            }.disabled(),
            context: tableContext(width: 30, height: 8)
        )
        #expect(enabled.hitTestRegions.count > disabled.hitTestRegions.count,
                "disabled table should drop the container mouse handler")
    }

    // MARK: Single column

    @Test("Single-column table renders one column of values")
    func singleColumn() {
        let lines = strippedLines(
            Table(sampleRows, selection: .constant(String?.none)) {
                TableColumn("Name", value: \Row.name)
            },
            context: tableContext(width: 20, height: 8)
        )
        expectClosedBorder(lines)
        #expect(lines.contains { $0.contains("Name") })
        #expect(lines.contains { $0.contains("Alpha") })
        #expect(lines.contains { $0.contains("Beta") })
        #expect(lines.contains { $0.contains("Gamma") })
    }
}
