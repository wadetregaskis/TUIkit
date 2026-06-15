//  🖥️ TUIKit — Terminal UI Kit for Swift
//  GroupRenderTests.swift
//
//  Buffer-level render audit for Group. Group imposes no layout of its
//  own: it must be transparent, flattening its children into the
//  surrounding container.
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Group rendering")
struct GroupRenderTests {

    private func ctx(width: Int = 30, height: Int = 8) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext()).isolatingRenderCache()
    }

    // MARK: - Transparency

    @Test("A bare Group stacks its children vertically like an implicit VStack")
    func bareGroupStacksChildren() {
        let buffer = renderToBuffer(
            Group {
                Text("First")
                Text("Second")
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 2)
        #expect(buffer.lines[0].stripped == "First")
        #expect(buffer.lines[1].stripped == "Second")
    }

    @Test("A single-view Group renders exactly that view")
    func singleViewGroup() {
        let buffer = renderToBuffer(Group { Text("only") }, context: ctx())
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "only")
    }

    // MARK: - Flattening into a VStack

    @Test("Group flattens into a VStack so spacing applies between grouped views")
    func flattensIntoVStack() {
        // If Group nested instead of flattening, the VStack spacing would
        // not appear between A and B.
        let buffer = renderToBuffer(
            VStack(spacing: 1) {
                Group {
                    Text("A")
                    Text("B")
                }
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 3, "Expected A, blank, B")
        #expect(buffer.lines[0].stripped == "A")
        #expect(buffer.lines[1].stripped.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(buffer.lines[2].stripped == "B")
    }

    @Test("Group siblings interleave with non-grouped siblings in a VStack")
    func interleavesInVStack() {
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Group {
                    Text("one")
                    Text("two")
                }
                Text("three")
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 3)
        // The VStack pads shorter lines to the widest line's width ("three").
        #expect(
            buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
                == ["one", "two", "three"]
        )
    }

    // MARK: - Flattening into an HStack

    @Test("Group flattens into an HStack so children lay out horizontally")
    func flattensIntoHStack() {
        let buffer = renderToBuffer(
            HStack(spacing: 1) {
                Group {
                    Text("A")
                    Text("B")
                }
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "A B", "Grouped children spaced like direct HStack children")
    }

    // MARK: - Modifier propagation

    @Test("A modifier on a Group applies to all grouped children")
    func modifierAppliesToChildren() {
        // foregroundColor should not change the stripped text, but must
        // not collapse or drop children either.
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Group {
                    Text("x")
                    Text("y")
                }
                .foregroundStyle(.red)
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 2)
        #expect(buffer.lines.map { $0.stripped } == ["x", "y"])
    }

    // MARK: - Exceeding the ViewBuilder limit

    @Test("Group renders all children when used to exceed the 10-view limit")
    func manyChildren() {
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Group {
                    Text("0"); Text("1"); Text("2"); Text("3"); Text("4")
                    Text("5"); Text("6"); Text("7"); Text("8"); Text("9")
                }
            },
            context: ctx(width: 10, height: 12)
        )
        #expect(buffer.lines.count == 10)
        #expect(buffer.lines.first?.stripped == "0")
        #expect(buffer.lines.last?.stripped == "9")
    }
}
