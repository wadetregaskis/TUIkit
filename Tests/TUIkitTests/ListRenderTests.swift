//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListRenderTests.swift
//
//  Buffer-level render audit for `List`. Each case renders the view to a
//  FrameBuffer and asserts the visible (ANSI-stripped) lines: content,
//  line counts, continuous borders, alignment, truncation, scroll
//  indicators, and the absence of stray blank lines.
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Helpers

@MainActor
private func listContext(width: Int = 30, height: Int = 8, explicitWidth: Bool = false) -> RenderContext {
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

/// The ANSI-stripped lines of a rendered view.
@MainActor
private func strippedLines(_ view: some View, context: RenderContext) -> [String] {
    renderToBuffer(view, context: context).lines.map { $0.stripped }
}

/// Asserts the bordered box drawn by `lines` is rectangular and closed:
/// every line is the same visible width, the first/last lines are the top
/// and bottom borders, and every interior line begins and ends with a
/// vertical border character.
private func expectClosedBorder(
    _ lines: [String],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(lines.count >= 2, "a bordered box needs at least 2 lines", sourceLocation: sourceLocation)
    guard let first = lines.first, let last = lines.last else { return }

    let width = first.count
    #expect(width >= 2, "border width should be >= 2", sourceLocation: sourceLocation)

    // Uniform width.
    for (index, line) in lines.enumerated() {
        #expect(
            line.count == width,
            "line \(index) width \(line.count) != box width \(width): \(lines)",
            sourceLocation: sourceLocation
        )
    }

    // Top and bottom are solid borders with rounded corners.
    #expect(first.hasPrefix("╭"), "top-left corner: \(first)", sourceLocation: sourceLocation)
    #expect(first.hasSuffix("╮"), "top-right corner: \(first)", sourceLocation: sourceLocation)
    #expect(last.hasPrefix("╰"), "bottom-left corner: \(last)", sourceLocation: sourceLocation)
    #expect(last.hasSuffix("╯"), "bottom-right corner: \(last)", sourceLocation: sourceLocation)

    // Interior lines are walled by verticals (allowing the footer
    // separator's tee joints ├ ┤).
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
@Suite("List rendering")
struct ListRenderTests {

    // MARK: Default / populated

    @Test("Bordered list with items renders each row inside a closed border")
    func defaultPopulated() {
        let lines = strippedLines(
            List(selection: .constant(String?.none)) {
                ForEach(["Alpha", "Beta", "Gamma"], id: \.self) { Text($0) }
            },
            context: listContext()
        )

        expectClosedBorder(lines)
        // Rows render in order, each with the 1-cell left pad.
        #expect(lines[1].contains("Alpha"))
        #expect(lines[2].contains("Beta"))
        #expect(lines[3].contains("Gamma"))
        // No row text leaks past the first three interior lines.
        for line in lines.dropFirst(4).dropLast() {
            #expect(line.allSatisfy { $0 == "│" || $0 == " " }, "expected blank interior row, got: \(line)")
        }
    }

    @Test("Title is drawn into the top border")
    func titledBorder() {
        let lines = strippedLines(
            List("Files", selection: .constant(String?.none)) {
                ForEach(["Alpha", "Beta", "Gamma"], id: \.self) { Text($0) }
            },
            context: listContext()
        )

        expectClosedBorder(lines)
        #expect(lines[0].hasPrefix("╭─ Files "), "title should sit in the top border: \(lines[0])")
        #expect(lines[1].contains("Alpha"))
        #expect(lines[2].contains("Beta"))
        #expect(lines[3].contains("Gamma"))
    }

    @Test("Single-item list still fills its height with a closed border")
    func singleItem() {
        let lines = strippedLines(
            List(selection: .constant(String?.none)) {
                ForEach(["Only"], id: \.self) { Text($0) }
            },
            context: listContext()
        )

        expectClosedBorder(lines)
        #expect(lines[1].contains("Only"))
        // The item appears exactly once.
        #expect(lines.filter { $0.contains("Only") }.count == 1)
    }

    // MARK: Empty state

    @Test("Empty list shows the default placeholder, no stray text")
    func emptyDefaultPlaceholder() {
        let lines = strippedLines(
            List(selection: .constant(String?.none)) { EmptyView() },
            context: listContext(width: 30, height: 8)
        )

        expectClosedBorder(lines)
        let joined = lines.joined()
        #expect(joined.contains("No items"))
        // The placeholder appears on exactly one interior line.
        #expect(lines.filter { $0.contains("No items") }.count == 1)
    }

    @Test("Custom empty placeholder is shown verbatim")
    func customEmptyPlaceholder() {
        let lines = strippedLines(
            List(selection: .constant(String?.none)) { EmptyView() }
                .listEmptyPlaceholder("Nothing here"),
            context: listContext(width: 30, height: 8)
        )

        expectClosedBorder(lines)
        #expect(lines.contains { $0.contains("Nothing here") })
        #expect(!lines.contains { $0.contains("No items") })
    }

    // MARK: Selection

    @Test("Selected row renders a background highlight (visible in ANSI)")
    func selectedRowHasBackground() {
        // We assert on the raw (un-stripped) buffer because the selection is a
        // background colour, invisible after stripping.
        let buffer = renderToBuffer(
            List(selection: .constant("Beta")) {
                ForEach(["Alpha", "Beta", "Gamma"], id: \.self) { Text($0) }
            },
            context: listContext()
        )
        let stripped = buffer.lines.map { $0.stripped }
        // Structure unchanged by selection.
        expectClosedBorder(stripped)
        #expect(stripped[2].contains("Beta"))

        // The selected row carries a truecolor background SGR.
        #expect(buffer.lines[2].contains("[48;2;"), "selected row should carry a background colour")
    }

    @Test("Selecting a row visually distinguishes it from when nothing is selected")
    func selectionChangesTheRow() {
        // The same view, once with a selection and once without. The Beta row
        // (index 2 inside the border) must render differently — that is what
        // "selected" means visually.
        let selected = renderToBuffer(
            List(selection: .constant("Beta")) {
                ForEach(["Alpha", "Beta", "Gamma"], id: \.self) { Text($0) }
            },
            context: listContext()
        )
        let unselected = renderToBuffer(
            List(selection: .constant(String?.none)) {
                ForEach(["Alpha", "Beta", "Gamma"], id: \.self) { Text($0) }
            },
            context: listContext()
        )
        // Same stripped text…
        #expect(selected.lines[2].stripped == unselected.lines[2].stripped)
        // …but different raw ANSI (the selection highlight).
        #expect(
            selected.lines[2] != unselected.lines[2],
            "selected row should differ from the unselected render"
        )
    }

    // MARK: Scrolling / overflow

    @Test("Overflowing list shows a 'more below' scroll indicator")
    func overflowShowsBelowIndicator() {
        let lines = strippedLines(
            List(selection: .constant(String?.none)) {
                ForEach((0..<20).map { "Item \($0)" }, id: \.self) { Text($0) }
            },
            context: listContext(width: 30, height: 8)
        )

        expectClosedBorder(lines)
        // First rows are visible from the top.
        #expect(lines[1].contains("Item 0"))
        // A downward scroll indicator with a remaining count is present.
        let indicator = lines.first { $0.contains("▼") && $0.contains("more below") }
        #expect(indicator != nil, "expected a '▼ N more below' indicator: \(lines)")
        if let indicator {
            #expect(indicator.contains("15 more below"), "wrong hidden-row count: \(indicator)")
        }
        // The bottom rows are NOT shown yet (no upward scroll happened).
        #expect(!lines.contains { $0.contains("Item 19") })
    }

    // MARK: Scrollbar

    @Test("A visible scrollbar draws a block-glyph column inside the List border")
    func scrollbarColumn() {
        let lines = strippedLines(
            List(selection: .constant(String?.none)) {
                ForEach((0..<20).map { "Item \($0)" }, id: \.self) { Text($0) }
            }
            .scrollbarVisibility(.visible),
            context: listContext(width: 30, height: 8)
        )
        expectClosedBorder(lines)
        let joined = lines.joined()
        #expect(joined.contains("▲") && joined.contains("▼"), "scrollbar arrows present: \(lines)")
        let blocks: Set<Character> = ["█", "▁", "▂", "▃", "▄", "▅", "▆", "▇"]
        #expect(joined.contains { blocks.contains($0) }, "scrollbar thumb block present: \(lines)")
        // The bar supersedes the text indicator (no "more below" while a bar shows).
        #expect(!joined.contains("more below"), "bar replaces the text indicator: \(lines)")
    }

    @Test("Lists draw no scrollbar by default")
    func noScrollbarByDefault() {
        let lines = strippedLines(
            List(selection: .constant(String?.none)) {
                ForEach((0..<20).map { "Item \($0)" }, id: \.self) { Text($0) }
            },
            context: listContext(width: 30, height: 8)
        )
        // The "N more below" indicator uses ▼; the telltale of a scrollbar is its
        // block-glyph thumb, which a default list lacks.
        let blocks: Set<Character> = ["█", "▁", "▂", "▃", "▄", "▅", "▆", "▇"]
        #expect(!lines.joined().contains { blocks.contains($0) }, "no scrollbar thumb by default: \(lines)")
    }

    @Test("A List scrollbar measures multi-line rows in lines, not rows")
    func scrollbarLineBased() {
        // Eight rows, each two lines tall (16 lines total) in an 8-line content
        // area. The bar is line-based, so it renders with a closed border and the
        // multi-line rows draw in full alongside it.
        let context = listContext(width: 30, height: 10)
        let view = List(selection: .constant(String?.none)) {
            ForEach((0..<8).map { "Item \($0)" }, id: \.self) { item in
                VStack(alignment: .leading) {
                    Text(item)
                    Text("detail")
                }
            }
        }
        .scrollbarVisibility(.visible)
        let buffer = renderToBuffer(view, context: context)
        let lines = buffer.lines.map { $0.stripped }
        expectClosedBorder(lines)
        let joined = lines.joined()
        #expect(joined.contains("▲") && joined.contains("▼"), "arrows present: \(lines)")
        // This thumb is an exact three cells (8/16 of the area) with no fractional
        // end, so it's drawn purely by background colour — no glyph survives ANSI
        // stripping. Verify it in the raw output via the thumb's filled cell.
        let palette = context.environment.palette
        let thumbCell = ScrollbarRenderer.styledCell(
            .full, thumb: palette.foregroundSecondary, track: palette.foregroundQuaternary)
        #expect(buffer.lines.contains { $0.contains(thumbCell) }, "background-filled thumb present: \(lines)")
        // A two-line row renders both of its lines next to the bar.
        #expect(joined.contains("Item 0") && joined.contains("detail"), "multi-line row renders: \(lines)")
    }

    // MARK: Footer

    @Test("Footer renders below a separator inside the border")
    func footerWithSeparator() {
        let lines = strippedLines(
            List("Files", selection: .constant(String?.none)) {
                ForEach(["A", "B"], id: \.self) { Text($0) }
            } footer: {
                Text("footer")
            },
            context: listContext(width: 30, height: 8, explicitWidth: true)
        )

        expectClosedBorder(lines)
        // A horizontal separator (left/right tees) divides body from footer.
        let separator = lines.first { $0.hasPrefix("├") && $0.hasSuffix("┤") }
        #expect(separator != nil, "expected a ├───┤ footer separator: \(lines)")
        if let separator {
            // Separator is solid between the tees.
            #expect(separator.dropFirst().dropLast().allSatisfy { $0 == "─" }, "separator not solid: \(separator)")
        }
        // Footer text sits on the line below the separator.
        let footerLine = lines.first { $0.contains("footer") }
        #expect(footerLine != nil, "footer text missing: \(lines)")
    }

    // MARK: Width / truncation

    @Test("Explicit-width list fills that width with a uniform border")
    func explicitWidthFills() {
        let lines = strippedLines(
            List("Files", selection: .constant(String?.none)) {
                ForEach(["A", "B"], id: \.self) { Text($0) }
            },
            context: listContext(width: 30, height: 8, explicitWidth: true)
        )

        expectClosedBorder(lines)
        // With an explicit width, a List is greedy and fills the full
        // available width (border included).
        #expect(lines[0].count == 30, "explicit width 30 → border spans 30 cells: \(lines[0])")
        #expect(lines.allSatisfy { $0.count == 30 })
    }

    @Test("Frame width constrains the list and the border tracks it")
    func frameWidthConstrains() {
        let view = List(
            "Items",
            selection: .constant(String?.none)
        ) {
            ForEach(["Alpha", "Beta", "Gamma"], id: \.self) { Text($0) }
        }
        .frame(width: 20)

        let lines = strippedLines(view, context: listContext(width: 80, height: 10))
        expectClosedBorder(lines)
        #expect(lines[0].count == 20, "frame width 20 should size the border to 20: \(lines[0])")
    }

    // MARK: Disabled

    @Test("Disabled list still renders its rows and border")
    func disabledRendersContent() {
        let view = List(selection: .constant(String?.none)) {
            ForEach(["Alpha", "Beta"], id: \.self) { Text($0) }
        }
        .disabled()

        let lines = strippedLines(view, context: listContext())
        expectClosedBorder(lines)
        #expect(lines[1].contains("Alpha"))
        #expect(lines[2].contains("Beta"))
    }

    @Test("Disabled list registers no mouse hit-test region")
    func disabledNoHitRegion() {
        let enabled = renderToBuffer(
            List(selection: .constant(String?.none)) {
                ForEach(["Alpha", "Beta"], id: \.self) { Text($0) }
            },
            context: listContext()
        )
        let disabled = renderToBuffer(
            List(selection: .constant(String?.none)) {
                ForEach(["Alpha", "Beta"], id: \.self) { Text($0) }
            }.disabled(),
            context: listContext()
        )
        // The enabled list installs a container-wide fallback handler; the
        // disabled one must not.
        #expect(enabled.hitTestRegions.count > disabled.hitTestRegions.count,
                "disabled list should drop the container mouse handler")
    }

    // MARK: Multi-line rows

    @Test("Multi-line row content occupies multiple interior lines")
    func multiLineRows() {
        // A two-line row via an explicit VStack inside the row builder.
        let lines = strippedLines(
            List(selection: .constant(String?.none)) {
                ForEach(["x"], id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 0) {
                        Text("line one")
                        Text("line two")
                    }
                }
            },
            context: listContext(width: 30, height: 8)
        )

        expectClosedBorder(lines)
        #expect(lines.contains { $0.contains("line one") })
        #expect(lines.contains { $0.contains("line two") })
        // The two lines are on consecutive rows.
        let i1 = lines.firstIndex { $0.contains("line one") }
        let i2 = lines.firstIndex { $0.contains("line two") }
        if let i1, let i2 {
            #expect(i2 == i1 + 1, "row lines should be consecutive: \(i1), \(i2)")
        }
    }
}
