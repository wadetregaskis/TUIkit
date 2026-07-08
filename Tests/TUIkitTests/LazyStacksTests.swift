//  TUIKit - Terminal UI Kit for Swift
//  LazyStacksTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Test Helpers

@MainActor
private func testContext(width: Int = 40, height: Int = 24) -> RenderContext {
    makeBareRenderContext(width: width, height: height)
}

// MARK: - LazyVStack Tests

@MainActor
@Suite("LazyVStack Tests")
struct LazyVStackTests {

    @Test("LazyVStack renders children vertically")
    func rendersVertically() {
        let stack = LazyVStack {
            Text("Line 1")
            Text("Line 2")
            Text("Line 3")
        }

        let context = testContext()
        let buffer = renderToBuffer(stack, context: context)

        #expect(buffer.height == 3)
        #expect(buffer.lines[0].contains("Line 1"))
        #expect(buffer.lines[1].contains("Line 2"))
        #expect(buffer.lines[2].contains("Line 3"))
    }

    @Test("LazyVStack respects spacing")
    func respectsSpacing() {
        let stack = LazyVStack(spacing: 1) {
            Text("A")
            Text("B")
        }

        let context = testContext()
        let buffer = renderToBuffer(stack, context: context)

        // 1 line + 1 spacing + 1 line = 3 lines
        #expect(buffer.height == 3)
    }

    @Test("LazyVStack respects alignment")
    func respectsAlignment() {
        let stackLeading = LazyVStack(alignment: .leading) {
            Text("Short")
            Text("Much Longer")
        }

        let stackTrailing = LazyVStack(alignment: .trailing) {
            Text("Short")
            Text("Much Longer")
        }

        let context = testContext()
        let leadingBuffer = renderToBuffer(stackLeading, context: context)
        let trailingBuffer = renderToBuffer(stackTrailing, context: context)

        // Leading: "Short" starts at same position as "Much Longer"
        let leadingLine1 = leadingBuffer.lines[0].stripped
        let leadingLine2 = leadingBuffer.lines[1].stripped
        #expect(!leadingLine1.hasPrefix(" ") || leadingLine1.hasPrefix(leadingLine2.prefix(1)))

        // Trailing: "Short" ends at same position as "Much Longer"
        let trailingLine1 = trailingBuffer.lines[0].stripped
        #expect(trailingLine1.hasSuffix("Short"))
    }

    @Test("LazyVStack truncates at availableHeight")
    func truncatesAtAvailableHeight() {
        let stack = LazyVStack {
            Text("Line 1")
            Text("Line 2")
            Text("Line 3")
            Text("Line 4")
            Text("Line 5")
        }

        // Only 3 lines available
        let context = testContext(height: 3)
        let buffer = renderToBuffer(stack, context: context)

        // Should only render 3 lines
        #expect(buffer.height == 3)
        #expect(buffer.lines[0].contains("Line 1"))
        #expect(buffer.lines[1].contains("Line 2"))
        #expect(buffer.lines[2].contains("Line 3"))
    }

    @Test("LazyVStack with empty content returns empty buffer")
    func emptyContent() {
        let stack = LazyVStack {
            EmptyView()
        }

        let context = testContext()
        let buffer = renderToBuffer(stack, context: context)

        #expect(buffer.isEmpty)
    }
}

// MARK: - LazyHStack Tests

@MainActor
@Suite("LazyHStack Tests")
struct LazyHStackTests {

    @Test("LazyHStack renders children horizontally")
    func rendersHorizontally() {
        let stack = LazyHStack {
            Text("A")
            Text("B")
            Text("C")
        }

        let context = testContext()
        let buffer = renderToBuffer(stack, context: context)

        #expect(buffer.height == 1)
        let line = buffer.lines[0].stripped
        #expect(line.contains("A"))
        #expect(line.contains("B"))
        #expect(line.contains("C"))
    }

    @Test("LazyHStack respects spacing")
    func respectsSpacing() {
        let stackNoSpacing = LazyHStack(spacing: 0) {
            Text("A")
            Text("B")
        }

        let stackWithSpacing = LazyHStack(spacing: 3) {
            Text("A")
            Text("B")
        }

        let context = testContext()
        let noSpacingBuffer = renderToBuffer(stackNoSpacing, context: context)
        let withSpacingBuffer = renderToBuffer(stackWithSpacing, context: context)

        // With spacing should be wider
        #expect(withSpacingBuffer.width > noSpacingBuffer.width)
    }

    @Test("LazyHStack truncates at availableWidth")
    func truncatesAtAvailableWidth() {
        let stack = LazyHStack(spacing: 1) {
            Text("AAA")
            Text("BBB")
            Text("CCC")
            Text("DDD")
            Text("EEE")
        }

        // Only 10 chars available (AAA + space + BBB = 7, can't fit CCC)
        let context = testContext(width: 10)
        let buffer = renderToBuffer(stack, context: context)

        let line = buffer.lines[0].stripped
        #expect(line.contains("AAA"))
        #expect(line.contains("BBB"))
        #expect(!line.contains("CCC"))
    }

    @Test("LazyHStack with empty content returns empty buffer")
    func emptyContent() {
        let stack = LazyHStack {
            EmptyView()
        }

        let context = testContext()
        let buffer = renderToBuffer(stack, context: context)

        #expect(buffer.isEmpty)
    }

    @Test("LazyHStack top-aligns children of different heights")
    func topAlignment() {
        // Tall (3 lines) and Short (1 line) side by side, top-aligned
        let tall = LazyVStack {
            Text("T1")
            Text("T2")
            Text("T3")
        }
        let stack = LazyHStack(alignment: .top, spacing: 1) {
            tall
            Text("S")
        }
        let context = testContext()
        let buffer = renderToBuffer(stack, context: context)

        #expect(buffer.height == 3)
        // Row 0: both T1 and S appear
        #expect(buffer.lines[0].stripped.contains("S"), "Short item should appear on row 0 when top-aligned")
    }

    @Test("LazyHStack bottom-aligns children of different heights")
    func bottomAlignment() {
        let tall = LazyVStack {
            Text("T1")
            Text("T2")
            Text("T3")
        }
        let stack = LazyHStack(alignment: .bottom, spacing: 1) {
            tall
            Text("S")
        }
        let context = testContext()
        let buffer = renderToBuffer(stack, context: context)

        #expect(buffer.height == 3)
        // Row 2 (last): both T3 and S appear
        #expect(buffer.lines[2].stripped.contains("S"), "Short item should appear on last row when bottom-aligned")
        // Row 0: S should NOT appear when bottom-aligned
        #expect(!buffer.lines[0].stripped.contains("S"), "Short item should not appear on row 0 when bottom-aligned")
    }

    @Test("LazyHStack center-aligns children of different heights")
    func centerAlignment() {
        let tall = LazyVStack {
            Text("T1")
            Text("T2")
            Text("T3")
            Text("T4")
        }
        let stack = LazyHStack(alignment: .center, spacing: 1) {
            tall
            Text("S")
        }
        let context = testContext()
        let buffer = renderToBuffer(stack, context: context)

        #expect(buffer.height == 4)
        // topPadding = (4 - 1) / 2 = 1, so "S" lands on row 1
        #expect(buffer.lines[1].stripped.contains("S"), "Short item should appear on row 1 when center-aligned with 4-row tall item")
        // Rows 0 and 3 should not contain "S"
        #expect(!buffer.lines[0].stripped.contains("S"), "Short item should not appear on row 0 when center-aligned")
        #expect(!buffer.lines[3].stripped.contains("S"), "Short item should not appear on row 3 when center-aligned")
    }
}

// MARK: - Equatable Tests

@MainActor
@Suite("LazyStack Equatable Tests")
struct LazyStackEquatableTests {

    @Test("LazyVStack is Equatable when content is Equatable")
    func lazyVStackEquatable() {
        let stack1 = LazyVStack(alignment: .leading, spacing: 2) {
            Text("Hello")
        }
        let stack2 = LazyVStack(alignment: .leading, spacing: 2) {
            Text("Hello")
        }
        let stack3 = LazyVStack(alignment: .trailing, spacing: 2) {
            Text("Hello")
        }

        #expect(stack1 == stack2)
        #expect(stack1 != stack3)
    }

    @Test("LazyHStack is Equatable when content is Equatable")
    func lazyHStackEquatable() {
        let stack1 = LazyHStack(alignment: .top, spacing: 3) {
            Text("World")
        }
        let stack2 = LazyHStack(alignment: .top, spacing: 3) {
            Text("World")
        }
        let stack3 = LazyHStack(alignment: .bottom, spacing: 3) {
            Text("World")
        }

        #expect(stack1 == stack2)
        #expect(stack1 != stack3)
    }
}

// MARK: - ForEach Expansion (issue #8)

/// Regression tests for GitHub issue #8: `LazyVStack`/`LazyHStack` (and
/// `ZStack`) rendered nothing when their content was a `ForEach`. The window
/// render path resolved children through the legacy single-pass
/// `resolveChildInfos`, which only expands `ChildInfoProvider`s — and
/// `ForEach` implements only the two-pass `ChildViewProvider` — so the whole
/// `ForEach` fell through the universal `renderToBuffer` (body: Never, not
/// Renderable) and yielded an empty buffer.
@MainActor
@Suite("Lazy stacks expand ForEach (issue #8)")
struct LazyStackForEachTests {

    @Test("LazyVStack renders ForEach content")
    func lazyVStackForEach() {
        let stack = LazyVStack {
            ForEach(0..<5) { Text("Item \($0)") }
        }
        let buffer = renderToBuffer(stack, context: testContext(width: 40, height: 10))
        let lines = buffer.lines.map { $0.stripped }
        #expect(buffer.height == 5, "all five rows render: \(lines)")
        #expect(lines.first?.contains("Item 0") == true)
        #expect(lines.last?.contains("Item 4") == true)
    }

    @Test("LazyHStack renders ForEach content")
    func lazyHStackForEach() {
        let stack = LazyHStack {
            ForEach(0..<4) { Text("C\($0)") }
        }
        let buffer = renderToBuffer(stack, context: testContext(width: 40, height: 5))
        let line = buffer.lines.first?.stripped ?? ""
        #expect(line.contains("C0") && line.contains("C3"), "all four columns render: '\(line)'")
    }

    @Test("A ForEach mixed into a tuple keeps its siblings")
    func lazyVStackMixedTuple() {
        let stack = LazyVStack {
            Text("Header")
            ForEach(0..<3) { Text("Item \($0)") }
        }
        let buffer = renderToBuffer(stack, context: testContext(width: 40, height: 10))
        let joined = buffer.lines.map { $0.stripped }.joined(separator: "\n")
        #expect(joined.contains("Header"))
        #expect(joined.contains("Item 0") && joined.contains("Item 2"))
    }

    @Test("The issue's shape: ScrollView { LazyVStack { ForEach } }")
    func scrollViewWrappedLazyVStack() {
        let view = VStack {
            Text("Hello, TUIkit!")
            ScrollView {
                LazyVStack {
                    ForEach(0..<100) { Text("Item \($0 + 1)") }
                }
            }
        }
        let context = makeRenderContext(width: 60, height: 20)
        let joined = renderToBuffer(view, context: context)
            .lines.map { $0.stripped }.joined(separator: "\n")
        #expect(joined.contains("Item 1"), "scrollable lazy content renders")
        #expect(joined.contains("Item 10"), "the viewport is filled, not blank")
    }

    @Test("Windowing still stops at the first child that would overflow")
    func lazyVStackWindows() {
        let stack = LazyVStack {
            ForEach(0..<50) { Text("Item \($0)") }
        }
        let buffer = renderToBuffer(stack, context: testContext(width: 40, height: 6))
        #expect(buffer.height == 6, "exactly the rows that fit")
        #expect(buffer.lines.last?.stripped.contains("Item 5") == true)
    }

    @Test("Spacer distribution still works alongside a ForEach")
    func lazyVStackSpacerWithForEach() {
        let stack = LazyVStack {
            Text("Top")
            Spacer()
            ForEach(0..<2) { Text("Bottom \($0)") }
        }
        let buffer = renderToBuffer(stack, context: testContext(width: 40, height: 10))
        let lines = buffer.lines.map { $0.stripped }
        #expect(buffer.height == 10, "the spacer expands the column to fill: \(lines)")
        #expect(lines.first?.contains("Top") == true)
        #expect(lines.last?.contains("Bottom 1") == true)
    }
}

// MARK: - True laziness (window stops rendering, not just emitting)

/// A probe that records whether it was ever actually rendered — laziness
/// means children past the first overflow are never rendered at all, not
/// merely dropped from the output.
@MainActor
private final class RenderFlag {
    var rendered = false
    var measured = false
}

private struct FlagProbe: View, Renderable, Layoutable {
    let flag: RenderFlag

    var body: Never { fatalError("probe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if context.isMeasuring {
            flag.measured = true
        } else {
            flag.rendered = true
        }
        return FrameBuffer(text: "PROBE")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        flag.measured = true
        return ViewSize.fixed(5, 1)
    }
}

@MainActor
@Suite("Lazy stack windowing is actually lazy")
struct LazyStackLazinessTests {
    @Test("A LazyVStack child beyond the window is never rendered")
    func vStackStopsRenderingPastTheFold() {
        let flag = RenderFlag()
        let stack = LazyVStack {
            ForEach(0..<10) { Text("Item \($0)") }
            FlagProbe(flag: flag)
        }

        let buffer = renderToBuffer(stack, context: makeBareRenderContext(width: 40, height: 5))

        #expect(buffer.height == 5, "the window fills the available height")
        #expect(!flag.rendered, "a child past the first overflow must not render")
    }

    @Test("A LazyHStack child beyond the window is never rendered")
    func hStackStopsRenderingPastTheFold() {
        let flag = RenderFlag()
        let stack = LazyHStack(spacing: 1) {
            ForEach(0..<10) { Text("Column \($0)") }
            FlagProbe(flag: flag)
        }

        _ = renderToBuffer(stack, context: makeBareRenderContext(width: 30, height: 3))

        #expect(!flag.rendered, "a child past the first overflow must not render")
    }

    @Test("A Spacer keeps the pre-render (its distribution needs every extent)")
    func spacerForfeitsLaziness() {
        let flag = RenderFlag()
        let stack = LazyVStack {
            Text("Top")
            Spacer()
            ForEach(0..<10) { Text("Item \($0)") }
            FlagProbe(flag: flag)
        }

        _ = renderToBuffer(stack, context: makeBareRenderContext(width: 40, height: 5))

        // With a Spacer present every child pre-renders for the distribution
        // arithmetic (the documented trade) even though the probe is past the
        // fold and does not appear in the output.
        #expect(flag.rendered, "spacer distribution pre-renders all children")
    }

    @Test("LazyHStack spacer distribution works alongside a ForEach")
    func hStackSpacerWithForEach() {
        let stack = LazyHStack(spacing: 0) {
            Text("L")
            Spacer()
            ForEach(0..<2) { Text("R\($0)") }
        }

        let buffer = renderToBuffer(stack, context: makeBareRenderContext(width: 20, height: 3))
        let line = buffer.lines.first?.stripped ?? ""

        #expect(line.hasPrefix("L"), "leading content stays left: '\(line)'")
        #expect(line.hasSuffix("R0R1"), "the ForEach columns are pushed to the trailing edge: '\(line)'")
        #expect(line.strippedLength == 20, "the spacer fills the row")
    }
}
