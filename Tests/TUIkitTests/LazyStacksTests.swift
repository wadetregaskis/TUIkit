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
    RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
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
