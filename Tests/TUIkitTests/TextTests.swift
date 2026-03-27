//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Text Terminal Width Tests")
struct TextTerminalWidthTests {

    private func testContext(width: Int = 80) -> RenderContext {
        RenderContext(
            availableWidth: width,
            availableHeight: 24,
            tuiContext: TUIContext()
        )
    }

    @Test("Text with CJK characters reports correct terminal width")
    func cjkTextWidth() {
        // Each CJK character occupies 2 terminal cells
        let text = Text("你好")  // 2 CJK chars = 4 terminal cells
        let context = testContext(width: 80)
        let size = text.sizeThatFits(proposal: ProposedSize(width: 80, height: nil), context: context)
        #expect(size.width == 4, "CJK text '你好' should report width 4 (2 cells per character), got \(size.width)")
    }

    @Test("Text with ASCII characters reports correct terminal width")
    func asciiTextWidth() {
        let text = Text("Hello")
        let context = testContext(width: 80)
        let size = text.sizeThatFits(proposal: ProposedSize(width: 80, height: nil), context: context)
        #expect(size.width == 5, "ASCII text 'Hello' should report width 5")
    }

    @Test("Text with mixed ASCII and CJK reports correct terminal width")
    func mixedTextWidth() {
        // "Hi你好" = 2 ASCII (2 cells) + 2 CJK (4 cells) = 6 terminal cells
        let text = Text("Hi你好")
        let context = testContext(width: 80)
        let size = text.sizeThatFits(proposal: ProposedSize(width: 80, height: nil), context: context)
        #expect(size.width == 6, "Mixed text 'Hi你好' should report width 6, got \(size.width)")
    }

    @Test("Text word-wraps CJK text at correct terminal width boundary")
    func cjkWordWrap() {
        // "你好 世界" = word1 "你好" (4 cells) + space + word2 "世界" (4 cells) = 9 cells
        // With maxWidth 6, should wrap to 2 lines
        let text = Text("你好 世界")
        let context = testContext(width: 6)
        let size = text.sizeThatFits(proposal: ProposedSize(width: 6, height: nil), context: context)
        #expect(size.height == 2, "CJK text should wrap to 2 lines at width 6, got \(size.height)")
        #expect(size.width == 4, "Each line should be 4 cells wide, got \(size.width)")
    }
}
