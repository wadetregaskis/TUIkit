//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MenuTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Menu Terminal Width Tests")
struct MenuTerminalWidthTests {

    private func testContext(width: Int = 80) -> RenderContext {
        RenderContext(
            availableWidth: width,
            availableHeight: 24,
            tuiContext: TUIContext()
        )
    }

    @Test("Menu with CJK labels produces uniform-width lines")
    func cjkMenuItemWidth() {
        // CJK characters occupy 2 terminal cells each
        let menu = Menu(
            items: [
                MenuItem(label: "文件"),  // 4 terminal cells
                MenuItem(label: "AB"),    // 2 terminal cells
            ],
            selectedIndex: 0
        )
        let context = testContext()
        let buffer = renderToBuffer(menu, context: context)

        // Exclude border lines (first and last); content lines should have uniform width
        let contentLines = buffer.lines.dropFirst().dropLast()
        let lineWidths = contentLines.map { $0.strippedLength }
        let uniqueWidths = Set(lineWidths)
        #expect(uniqueWidths.count == 1,
                "All menu content lines should have the same visible width, got widths: \(lineWidths)")
    }

    @Test("MenuItem label terminal width differs from count for CJK")
    func menuItemLabelWidth() {
        let item = MenuItem(label: "設定")
        // "設定" = 2 CJK characters = 4 terminal cells, but .count = 2
        #expect(item.label.count == 2)
        #expect(item.label.strippedLength == 4)
    }
}
