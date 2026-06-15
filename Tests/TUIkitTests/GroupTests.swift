//  🖥️ TUIKit — Terminal UI Kit for Swift
//  GroupTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Group Tests")
struct GroupTests {

    private func context(width: Int = 80, height: Int = 24) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext()).isolatingRenderCache()
    }

    @Test("Group renders its children with no layout of its own")
    func groupRendersChildren() {
        let buffer = renderToBuffer(
            Group {
                Text("First")
                Text("Second")
            },
            context: context()
        )
        #expect(buffer.height == 2, "Group should render both children, got \(buffer.height) lines")
        #expect(buffer.lines[0].stripped == "First")
        #expect(buffer.lines[1].stripped == "Second")
    }

    @Test("A single-view Group renders that view")
    func singleViewGroup() {
        let buffer = renderToBuffer(Group { Text("Only") }, context: context())
        #expect(buffer.lines.first?.stripped == "Only")
    }

    @Test("Group is transparent inside a stack")
    func groupTransparentInStack() {
        // The VStack's spacing must apply between the grouped views, which
        // only happens if Group flattens into the stack rather than nesting.
        let buffer = renderToBuffer(
            VStack(spacing: 1) {
                Group {
                    Text("A")
                    Text("B")
                }
            },
            context: context()
        )
        #expect(buffer.height == 3, "Expected A, blank, B — got \(buffer.height) lines")
        #expect(buffer.lines[0].stripped == "A")
        #expect(buffer.lines[2].stripped == "B")
    }
}
