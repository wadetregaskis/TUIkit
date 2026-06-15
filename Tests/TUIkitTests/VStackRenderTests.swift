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
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
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
}
