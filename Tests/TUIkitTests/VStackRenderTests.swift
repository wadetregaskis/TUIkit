//  🖥️ TUIKit — Terminal UI Kit for Swift
//  VStackRenderTests.swift
//
//  Buffer-level render audit for VStack.
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("VStack rendering")
struct VStackRenderTests {

    private func ctx(width: Int = 30, height: Int = 8) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext()).isolatingRenderCache()
    }

    // MARK: - Default stacking

    @Test("Stacks children top-to-bottom, one per line, sized to widest")
    func defaultStacking() {
        let buffer = renderToBuffer(
            VStack {
                Text("A")
                Text("BB")
                Text("CCC")
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 3, "Three children should render on three lines")
        #expect(buffer.height == 3)
        #expect(buffer.width == 3, "Width shrinks to the widest child (CCC)")
        // Default alignment is .center, so narrower lines are centred within width 3.
        #expect(buffer.lines.map { $0.stripped } == [" A ", "BB ", "CCC"])
    }

    // MARK: - Alignment

    @Test("Leading alignment left-justifies children")
    func leadingAlignment() {
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Text("A")
                Text("BB")
            },
            context: ctx()
        )
        #expect(buffer.lines.map { $0.stripped } == ["A ", "BB"])
    }

    @Test("Trailing alignment right-justifies children")
    func trailingAlignment() {
        let buffer = renderToBuffer(
            VStack(alignment: .trailing) {
                Text("A")
                Text("BBB")
            },
            context: ctx()
        )
        #expect(buffer.lines.map { $0.stripped } == ["  A", "BBB"])
    }

    // MARK: - Spacing

    @Test("Spacing inserts blank lines between children, not around them")
    func spacingBetweenChildren() {
        let buffer = renderToBuffer(
            VStack(spacing: 2) {
                Text("A")
                Text("B")
            },
            context: ctx()
        )
        // A, blank, blank, B — no leading/trailing blanks.
        #expect(buffer.lines.count == 4)
        #expect(buffer.lines[0].stripped == "A")
        #expect(buffer.lines[1].stripped.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(buffer.lines[2].stripped.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(buffer.lines[3].stripped == "B")
    }

    @Test("Default spacing is zero — children are flush")
    func defaultSpacingIsZero() {
        let buffer = renderToBuffer(
            VStack {
                Text("A")
                Text("B")
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 2)
        #expect(buffer.lines.map { $0.stripped } == ["A", "B"])
    }

    // MARK: - Empty

    @Test("Empty VStack renders nothing")
    func emptyStack() {
        let buffer = renderToBuffer(VStack {}, context: ctx())
        #expect(buffer.height == 0)
        #expect(buffer.lines.isEmpty)
    }

    @Test("A single child renders as itself with no extra lines")
    func singleChild() {
        let buffer = renderToBuffer(VStack { Text("only") }, context: ctx())
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "only")
    }

    // MARK: - Filtered (empty) children

    @Test("A false `if` branch contributes no row and claims no spacing slot")
    func falseBranchFiltered() {
        let buffer = renderToBuffer(
            VStack(spacing: 1) {
                Text("A")
                if false { Text("B") }
                Text("C")
            },
            context: ctx()
        )
        // Only A and C remain. With spacing 1 between them: A, blank, C.
        #expect(buffer.lines.count == 3, "Expected A, blank, C — the false branch is dropped")
        #expect(buffer.lines[0].stripped == "A")
        #expect(buffer.lines[1].stripped.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(buffer.lines[2].stripped == "C")
    }

    // MARK: - Spacer

    @Test("Spacer expands to push siblings to top and bottom edges")
    func spacerExpands() {
        let buffer = renderToBuffer(
            VStack {
                Text("Top")
                Spacer()
                Text("Bot")
            },
            context: ctx(width: 30, height: 5)
        )
        #expect(buffer.lines.count == 5, "Should fill the full 5-line height")
        #expect(buffer.lines.first?.stripped.contains("Top") == true)
        #expect(buffer.lines.last?.stripped.contains("Bot") == true)
        // The three interior lines are pure spacer fill (blank).
        for index in 1..<4 {
            #expect(buffer.lines[index].stripped.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Narrow width (truncation)

    @Test("A child wider than the stack truncates with an ellipsis")
    func narrowTruncation() {
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Text("HelloWorld")
                Text("Hi")
            },
            context: ctx(width: 5, height: 4)
        )
        #expect(buffer.width == 5)
        #expect(buffer.lines.count == 2)
        #expect(buffer.lines[0].stripped == "Hell…", "Long line truncates to width with ellipsis")
        #expect(buffer.lines[1].stripped == "Hi   ")
    }

    // MARK: - Wide

    @Test("Children never exceed the available width")
    func widthClamped() {
        let buffer = renderToBuffer(
            VStack { Text("hello"); Text("worldwide") },
            context: ctx(width: 40, height: 4)
        )
        #expect(buffer.width <= 40)
        for line in buffer.lines {
            #expect(line.strippedLength <= 40)
        }
    }

    // MARK: - Multi-item count

    @Test("All ten items in a large stack render on their own lines")
    func manyItems() {
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                ForEach(0..<10) { Text("item \($0)") }
            },
            context: ctx(width: 20, height: 12)
        )
        #expect(buffer.lines.count == 10)
        #expect(buffer.lines[0].stripped == "item 0")
        #expect(buffer.lines[9].stripped == "item 9")
    }

    // MARK: - Overflow degrades gracefully (regression)

    @Test("A spaced stack taller than its space clips its tail, never blanks")
    func overflowingSpacedStackClipsNotBlanks() {
        // 12 rows with spacing 1 want 23 lines (12 + 11 gaps). In a 5-row space
        // the inter-child gaps (11) alone exceed the height — the old budget
        // reserved every gap first, starved content to zero, and rendered the
        // whole stack BLANK. It must instead show the leading rows that fit.
        let buffer = renderToBuffer(
            VStack(alignment: .leading, spacing: 1) {
                ForEach(0..<12) { Text("row \($0)") }
            },
            context: ctx(width: 20, height: 5)
        )
        let visible = buffer.lines.map { $0.stripped }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(!visible.isEmpty, "Overflowing spaced stack must not render blank")
        #expect(buffer.lines.first?.stripped == "row 0", "Leading content stays visible")
        #expect(buffer.height <= 5, "Never overflows the space it was given")
    }

    @Test("distributeLinearSpace charges spacing only between placed children")
    func distributeSpacingDoesNotStarve() {
        // 10 fixed rows of height 1, spacing 1, in only 5 cells. Reserving all 9
        // gaps up front would leave 0 for content (every entry 0). Instead the
        // leading rows are placed with one gap each until the 5 cells run out.
        let sizes = distributeLinearSpace(
            naturalSizes: Array(repeating: 1, count: 10),
            isFlexible: Array(repeating: false, count: 10),
            available: 5, spacing: 1)
        #expect(sizes.contains { $0 > 0 }, "Must not collapse every child to zero")
        #expect(sizes[0] == 1, "Leading child placed at its natural size")
        // 5 cells = row,gap,row,gap,row → 3 rows placed (indices 0,1,2), rest 0.
        #expect(sizes.prefix(3).allSatisfy { $0 == 1 })
        #expect(sizes.dropFirst(3).allSatisfy { $0 == 0 })
        // Placed sizes + the gaps between them never exceed the available extent.
        let placed = sizes.filter { $0 > 0 }.count
        #expect(sizes.reduce(0, +) + max(0, placed - 1) * 1 <= 5)
    }

    @Test("distributeLinearSpace leaves the fitting case unchanged")
    func distributeFittingCaseUnchanged() {
        // Three height-1 rows, spacing 1, in 10 cells: all fit (3 + 2 gaps = 5),
        // each keeps its natural size — the common path must be untouched.
        let sizes = distributeLinearSpace(
            naturalSizes: [1, 1, 1], isFlexible: [false, false, false],
            available: 10, spacing: 1)
        #expect(sizes == [1, 1, 1])
    }
}
