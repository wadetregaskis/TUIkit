//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ContainerViewTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Alert Tests")
struct AlertTests {

    @Test("Alert renders with border")
    func alertRendering() {
        let alert = Alert(title: "Warning", message: "Something happened")
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(alert, context: context)
        #expect(buffer.height > 2)
        // Should have border characters
        let allContent = buffer.lines.joined()
        #expect(allContent.contains("Warning"))
        #expect(allContent.contains("Something happened"))
    }
}

@MainActor
@Suite("Dialog Tests")
struct DialogTests {

    @Test("Dialog renders with panel styling")
    func dialogRendering() {
        let dialog = Dialog(title: "Test Dialog") {
            Text("Content here")
        }
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(dialog, context: context)
        #expect(buffer.height > 1)
        // Should contain title and content
        let allContent = buffer.lines.joined()
        #expect(allContent.contains("Test Dialog"))
        #expect(allContent.contains("Content here"))
    }
}

@MainActor
@Suite("ContainerView CJK Title Width Tests")
struct ContainerViewCJKTitleTests {

    @Test("Panel with CJK title has consistent border width")
    func panelCJKTitleBorderWidth() {
        let panel = Panel("你好世界") {
            Text("Content")
        }
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(panel, context: context)

        // All lines in the rendered panel should have the same visual width
        let lineWidths = buffer.lines.map(\.strippedLength)
        let uniqueWidths = Set(lineWidths)
        #expect(
            uniqueWidths.count == 1,
            "All panel lines should have uniform width, got widths: \(lineWidths)"
        )
    }

    @Test("Panel border is wide enough for CJK title")
    func panelBorderWidthForCJKTitle() {
        // "你好世界" = 4 CJK chars × 2 cells = 8 terminal cells
        // Title with padding: " 你好世界 " = 10 cells
        // Border must be at least: corner(1) + leading─(1) + title(10) + trailing─(0) + corner(1) = 13
        let panel = Panel("你好世界") {
            Text("X")
        }
        let context = RenderContext(availableWidth: 80, availableHeight: 24, tuiContext: TUIContext()).isolatingRenderCache()
        let buffer = renderToBuffer(panel, context: context)

        let topLine = buffer.lines.first!
        #expect(
            topLine.stripped.contains("你好世界"),
            "Top border should contain the CJK title"
        )
    }
}
