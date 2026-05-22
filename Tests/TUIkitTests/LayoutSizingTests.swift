//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LayoutSizingTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Verifies the layout system's size invariants: a view's rendered
//  FrameBuffer must never exceed the width/height it was allocated, and
//  views should degrade gracefully when the terminal is smaller than the
//  space they would like to occupy.

import Testing

@testable import TUIkit

// MARK: - Test Support

/// A view that deliberately renders a buffer of a fixed size, ignoring the
/// space it is given. Used to prove the layout system clamps a misbehaving
/// child rather than letting it corrupt siblings or overflow the terminal.
private struct OversizedView: View, Renderable {
    let renderWidth: Int
    let renderHeight: Int

    var body: Never { fatalError("OversizedView renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let line = String(repeating: "X", count: renderWidth)
        return FrameBuffer(lines: Array(repeating: line, count: renderHeight))
    }
}

// MARK: - FrameBuffer.clamped

@Suite("FrameBuffer clamped")
struct FrameBufferClampedTests {

    @Test("A buffer already within bounds is returned unchanged")
    func withinBoundsUnchanged() {
        let buffer = FrameBuffer(lines: ["abc", "de"])
        #expect(buffer.clamped(toWidth: 10, height: 10) == buffer)
    }

    @Test("Over-wide lines are truncated to the width")
    func truncatesWidth() {
        let buffer = FrameBuffer(lines: ["0123456789", "ab"])
        let clamped = buffer.clamped(toWidth: 4, height: 10)
        #expect(clamped.width == 4)
        #expect(clamped.lines == ["0123", "ab"])
    }

    @Test("Excess lines are dropped to the height")
    func truncatesHeight() {
        let buffer = FrameBuffer(lines: ["a", "b", "c", "d"])
        let clamped = buffer.clamped(toWidth: 10, height: 2)
        #expect(clamped.height == 2)
        #expect(clamped.lines == ["a", "b"])
    }

    @Test("Width and height are clamped together")
    func truncatesBoth() {
        let buffer = FrameBuffer(lines: Array(repeating: "wide content", count: 8))
        let clamped = buffer.clamped(toWidth: 5, height: 3)
        #expect(clamped.width <= 5)
        #expect(clamped.height == 3)
    }

    @Test("Clamping to zero yields an empty buffer")
    func clampToZero() {
        let buffer = FrameBuffer(lines: ["content", "more"])
        let clamped = buffer.clamped(toWidth: 0, height: 0)
        #expect(clamped.width == 0)
        #expect(clamped.height == 0)
    }

    @Test("Negative bounds are treated as zero")
    func negativeBounds() {
        let clamped = FrameBuffer(lines: ["content"]).clamped(toWidth: -5, height: -5)
        #expect(clamped.width == 0)
        #expect(clamped.height == 0)
    }

    @Test("ANSI codes do not count toward the clamped width")
    func ansiAwareWidth() {
        let styled = "\u{1B}[31m0123456789\u{1B}[0m"  // 10 visible cells
        let clamped = FrameBuffer(lines: [styled]).clamped(toWidth: 4, height: 1)
        #expect(clamped.width == 4)
        #expect(clamped.lines[0].stripped == "0123")
    }

    @Test("A wide character is dropped rather than split at the boundary")
    func wideCharacterBoundary() {
        let buffer = FrameBuffer(lines: ["あい"])  // two 2-cell characters == 4 cells
        let clamped = buffer.clamped(toWidth: 3, height: 1)
        #expect(clamped.width <= 3)
    }
}

// MARK: - renderChild clamps to its allocation

@MainActor
@Suite("Stack child clamping")
struct StackChildClampingTests {

    private func context(width: Int, height: Int) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
    }

    @Test("renderChild truncates a child that over-renders its width")
    func childWidthClamped() {
        let buffer = renderChild(
            OversizedView(renderWidth: 200, renderHeight: 3),
            width: 10, height: 5, context: context(width: 80, height: 24)
        )
        #expect(buffer.width <= 10, "child rendered \(buffer.width) wide, allocation was 10")
    }

    @Test("renderChild truncates a child that over-renders its height")
    func childHeightClamped() {
        let buffer = renderChild(
            OversizedView(renderWidth: 4, renderHeight: 99),
            width: 10, height: 5, context: context(width: 80, height: 24)
        )
        #expect(buffer.height <= 5, "child rendered \(buffer.height) tall, allocation was 5")
    }

    @Test("renderChild leaves a well-behaved child untouched")
    func wellBehavedChildUntouched() {
        let buffer = renderChild(
            Text("hello"),
            width: 40, height: 10, context: context(width: 80, height: 24)
        )
        #expect(buffer.width == 5)
        #expect(buffer.height == 1)
    }
}

// MARK: - Size-Matrix Harness

/// Terminal widths probed by ``assertNeverOverflows`` — deliberately includes
/// degenerate sizes (0, 1, 2) and sizes far below/above what a view wants.
private let probeWidths = [0, 1, 2, 3, 5, 8, 13, 21, 40, 80, 200]

/// Terminal heights probed by ``assertNeverOverflows``.
private let probeHeights = [0, 1, 2, 3, 5, 12, 24, 60]

/// Renders `view` across a matrix of terminal sizes and asserts the universal
/// layout invariant: the rendered buffer never exceeds the space it was given,
/// and no individual line is wider than the available width.
@MainActor
private func assertNeverOverflows(
    _ name: String,
    _ view: some View,
    widths: [Int] = probeWidths,
    heights: [Int] = probeHeights,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for width in widths {
        for height in heights {
            let context = RenderContext(
                availableWidth: width, availableHeight: height, tuiContext: TUIContext())
            let buffer = renderToBuffer(view, context: context)
            #expect(
                buffer.height <= height,
                "\(name): height \(buffer.height) exceeds available \(height) at width \(width)",
                sourceLocation: sourceLocation)
            for line in buffer.lines {
                #expect(
                    line.strippedLength <= width,
                    "\(name): a line is \(line.strippedLength) cells wide, exceeds available \(width) at height \(height)",
                    sourceLocation: sourceLocation)
            }
        }
    }
}

// MARK: - HStack sizing

@MainActor
@Suite("HStack sizing")
struct HStackSizingTests {

    @Test("HStack of long texts never overflows")
    func longTextsNeverOverflow() {
        assertNeverOverflows(
            "HStack of 3 long texts",
            HStack {
                Text(String(repeating: "A", count: 40))
                Text(String(repeating: "B", count: 40))
                Text(String(repeating: "C", count: 40))
            })
    }

    @Test("HStack containing a misbehaving child never overflows")
    func misbehavingChildNeverOverflows() {
        assertNeverOverflows(
            "HStack with OversizedView",
            HStack {
                Text("left")
                OversizedView(renderWidth: 300, renderHeight: 40)
                Text("right")
            })
    }

    @Test("HStack with a Spacer never overflows")
    func spacerNeverOverflows() {
        assertNeverOverflows(
            "HStack with Spacer",
            HStack {
                Text("left")
                Spacer()
                Text("right")
            })
    }

    @Test("HStack expands a Spacer to fill the available width")
    func spacerFillsWidth() {
        let view = HStack(spacing: 0) {
            Text("AB")
            Spacer()
            Text("YZ")
        }
        let context = RenderContext(availableWidth: 40, availableHeight: 3, tuiContext: TUIContext())
        let buffer = renderToBuffer(view, context: context)
        #expect(buffer.width == 40, "HStack with a Spacer should fill the width, got \(buffer.width)")
    }

    @Test("HStack keeps a fixed label readable when space is short")
    func fixedContentPrioritised() {
        var text = ""
        let binding = Binding(get: { text }, set: { text = $0 })
        let view = HStack(spacing: 1) {
            Text("Name:")
            TextField("field", text: binding)
        }
        let context = RenderContext(availableWidth: 12, availableHeight: 3, tuiContext: TUIContext())
        let buffer = renderToBuffer(view, context: context)
        #expect(buffer.width <= 12)
        #expect(buffer.lines.first?.contains("Name:") == true, "the fixed label should not be truncated")
    }

    @Test("HStack does not overflow when spacing alone exceeds the width")
    func spacingHeavyNeverOverflows() {
        assertNeverOverflows(
            "HStack spacing 5",
            HStack(spacing: 5) {
                Text("one")
                Text("two")
                Text("three")
            },
            widths: [0, 1, 2, 3, 4, 6, 10])
    }
}

// MARK: - VStack sizing

@MainActor
@Suite("VStack sizing")
struct VStackSizingTests {

    @Test("A tall VStack never overflows")
    func tallStackNeverOverflows() {
        assertNeverOverflows(
            "VStack of 8 rows",
            VStack {
                Text("Row 1"); Text("Row 2"); Text("Row 3"); Text("Row 4")
                Text("Row 5"); Text("Row 6"); Text("Row 7"); Text("Row 8")
            })
    }

    @Test("VStack of long lines never overflows")
    func longLinesNeverOverflow() {
        assertNeverOverflows(
            "VStack of long texts",
            VStack {
                Text(String(repeating: "A", count: 60))
                Text(String(repeating: "B", count: 60))
            })
    }

    @Test("VStack containing a misbehaving child never overflows")
    func misbehavingChildNeverOverflows() {
        assertNeverOverflows(
            "VStack with OversizedView",
            VStack {
                Text("top")
                OversizedView(renderWidth: 300, renderHeight: 50)
                Text("bottom")
            })
    }

    @Test("VStack with a Spacer never overflows")
    func spacerNeverOverflows() {
        assertNeverOverflows(
            "VStack with Spacer",
            VStack {
                Text("top")
                Spacer()
                Text("bottom")
            })
    }

    @Test("VStack expands a Spacer to fill the available height")
    func spacerFillsHeight() {
        let view = VStack(spacing: 0) {
            Text("top")
            Spacer()
            Text("bottom")
        }
        let context = RenderContext(availableWidth: 20, availableHeight: 15, tuiContext: TUIContext())
        let buffer = renderToBuffer(view, context: context)
        #expect(buffer.height == 15, "VStack with a Spacer should fill the height, got \(buffer.height)")
    }

    @Test("VStack keeps the topmost rows when the terminal is too short")
    func tooShortTerminalClamps() {
        let view = VStack(spacing: 0) {
            Text("row 1")
            Text("row 2")
            Text("row 3")
            Text("row 4")
            Text("row 5")
        }
        let context = RenderContext(availableWidth: 20, availableHeight: 3, tuiContext: TUIContext())
        let buffer = renderToBuffer(view, context: context)
        #expect(buffer.height <= 3)
        #expect(buffer.lines.first?.contains("row 1") == true, "the first row should stay visible")
    }
}

// MARK: - Container sizing

@MainActor
@Suite("Container sizing")
struct ContainerSizingTests {

    @Test("Box never overflows")
    func boxNeverOverflows() {
        assertNeverOverflows("Box around text", Box { Text("Hello, world") })
    }

    @Test("Box around long text never overflows")
    func boxLongTextNeverOverflows() {
        assertNeverOverflows("Box around long text", Box { Text(String(repeating: "X", count: 120)) })
    }

    @Test("Box around a tall stack never overflows")
    func boxTallStackNeverOverflows() {
        assertNeverOverflows(
            "Box around tall VStack",
            Box {
                VStack {
                    Text("1"); Text("2"); Text("3"); Text("4")
                    Text("5"); Text("6"); Text("7"); Text("8")
                }
            })
    }

    @Test("Box around a misbehaving child never overflows")
    func boxMisbehavingChildNeverOverflows() {
        assertNeverOverflows(
            "Box around OversizedView",
            Box { OversizedView(renderWidth: 250, renderHeight: 40) })
    }

    @Test("A container with a long title never overflows")
    func longTitleNeverOverflows() {
        assertNeverOverflows(
            "ContainerView long title",
            ContainerView(title: String(repeating: "T", count: 100)) { Text("body") })
    }

    @Test("Box shrinks to wrap short content")
    func boxWrapsContentTightly() {
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext())
        let buffer = renderToBuffer(Box { Text("Hi") }, context: context)
        #expect(buffer.width == 6, "Box should shrink to content width, got \(buffer.width)")
        #expect(buffer.height == 3, "Box should be content height plus borders, got \(buffer.height)")
    }

    @Test("Box stays within a terminal smaller than its content")
    func boxClampsToSmallTerminal() {
        let view = Box {
            VStack {
                Text("line one")
                Text("line two")
                Text("line three")
            }
        }
        let context = RenderContext(availableWidth: 8, availableHeight: 4, tuiContext: TUIContext())
        let buffer = renderToBuffer(view, context: context)
        #expect(buffer.width <= 8)
        #expect(buffer.height <= 4)
    }
}

// MARK: - Universal render clamp

@MainActor
@Suite("Universal render clamp")
struct UniversalClampTests {

    @Test("Any view rendered directly is clamped to its available space")
    func directRenderClamped() {
        for width in [0, 1, 5, 30, 80] {
            for height in [0, 1, 3, 24] {
                let context = RenderContext(
                    availableWidth: width, availableHeight: height, tuiContext: TUIContext())
                let buffer = renderToBuffer(
                    OversizedView(renderWidth: 500, renderHeight: 200), context: context)
                #expect(buffer.width <= width, "width \(buffer.width) exceeds \(width)")
                #expect(buffer.height <= height, "height \(buffer.height) exceeds \(height)")
            }
        }
    }

    @Test("A bouncing Spinner never overflows")
    func bouncingSpinnerNeverOverflows() {
        assertNeverOverflows("Spinner bouncing", Spinner("Processing", style: .bouncing))
    }

    @Test("Divider never overflows")
    func dividerNeverOverflows() {
        assertNeverOverflows("Divider", Divider())
    }
}

// MARK: - Table sizing

private struct SizingRow: Identifiable, Sendable {
    let id: Int
    let name: String
}

@MainActor
@Suite("Table sizing")
struct TableSizingTests {

    private func table(rowCount: Int) -> some View {
        let rows = (0..<rowCount).map { SizingRow(id: $0, name: "Item \($0)") }
        var selection: Int?
        let binding = Binding<Int?>(get: { selection }, set: { selection = $0 })
        return Table(rows, selection: binding) {
            TableColumn("Name", value: \SizingRow.name)
        }
    }

    @Test("Table never overflows")
    func tableNeverOverflows() {
        assertNeverOverflows("Table of 30 rows", table(rowCount: 30))
    }

    @Test("Table shows every row when they all fit, without scrolling")
    func tableUsesAvailableHeightOpportunistically() {
        // 8 rows need 8 + 3 chrome = 11 lines; 12 are available, so all 8
        // rows must be visible and no scroll indicator should appear.
        let context = RenderContext(availableWidth: 40, availableHeight: 12, tuiContext: TUIContext())
        let buffer = renderToBuffer(table(rowCount: 8), context: context)
        let content = buffer.lines.joined(separator: "\n")
        #expect(content.contains("Item 0"), "first row should be visible")
        #expect(content.contains("Item 7"), "last row should be visible without scrolling")
        #expect(buffer.height <= 12)
    }

    @Test("Table scrolls gracefully when rows genuinely exceed the height")
    func tableScrollsWhenTooTall() {
        // 30 rows cannot fit in 10 lines — the table must stay within bounds.
        let context = RenderContext(availableWidth: 40, availableHeight: 10, tuiContext: TUIContext())
        let buffer = renderToBuffer(table(rowCount: 30), context: context)
        #expect(buffer.height <= 10)
        #expect(buffer.lines.allSatisfy { $0.strippedLength <= 40 })
    }
}

// MARK: - List sizing

@MainActor
@Suite("List sizing")
struct ListSizingTests {

    private func list(rowCount: Int) -> some View {
        let rows = (0..<rowCount).map { SizingRow(id: $0, name: "Item \($0)") }
        var selection: Int?
        let binding = Binding<Int?>(get: { selection }, set: { selection = $0 })
        return List(selection: binding) {
            ForEach(rows) { row in
                Text(row.name)
            }
        }
    }

    @Test("List never overflows")
    func listNeverOverflows() {
        assertNeverOverflows("List of 30 rows", list(rowCount: 30))
    }

    @Test("List shows every row when they all fit, without scrolling")
    func listUsesAvailableHeightOpportunistically() {
        // 9 rows + 2 border lines = 11; 12 are available, so all 9 rows must
        // be visible with no scroll indicator.
        let context = RenderContext(availableWidth: 40, availableHeight: 12, tuiContext: TUIContext())
        let buffer = renderToBuffer(list(rowCount: 9), context: context)
        let content = buffer.lines.joined(separator: "\n")
        #expect(content.contains("Item 0"))
        #expect(content.contains("Item 8"), "all rows should be visible without scrolling")
        #expect(buffer.height <= 12)
    }

    @Test("List scrolls gracefully when rows exceed the height")
    func listScrollsWhenTooTall() {
        let context = RenderContext(availableWidth: 40, availableHeight: 8, tuiContext: TUIContext())
        let buffer = renderToBuffer(list(rowCount: 40), context: context)
        #expect(buffer.height <= 8)
        #expect(buffer.lines.allSatisfy { $0.strippedLength <= 40 })
    }
}
