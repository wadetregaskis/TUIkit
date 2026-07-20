//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DialogImplicitScrollTests.swift
//
//  Oversized dialogs (modal / alert content taller than the visible area) are
//  implicitly embedded in a height-capped ScrollView so their footer/buttons
//  stay reachable by scrolling, instead of being clipped off the bottom of the
//  screen. A dialog that fits is rendered as-is — no ScrollView, nothing to
//  detect. See `renderPresentedDialog`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

@MainActor
@Suite("dialog implicit scroll")
struct DialogImplicitScrollTests {
    private func context(width: Int, height: Int, tui: TUIContext) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: tui)
    }

    private func rows(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { Text("row \($0)") }
        }
    }

    @Test("A dialog that fits is rendered as-is (no cap, no scroll chrome)")
    func fittingDialogNotWrapped() {
        let tui = TUIContext()
        let ctx = context(width: 40, height: 20, tui: tui)
        tui.stateStorage.beginRenderPass()
        let buffer = renderPresentedDialog(rows(3), context: ctx, capHeight: 12)
        tui.stateStorage.endRenderPass()

        #expect(buffer.height == 3, "a fitting dialog keeps its natural height, got \(buffer.height)")
        let text = buffer.lines.map { $0.stripped }.joined(separator: "\n")
        #expect(!text.contains("more"), "no 'N more' scroll indicator when it fits: \(text)")
    }

    @Test("An over-tall dialog is capped to the visible area and starts at the top")
    func overflowingDialogCappedAtTop() {
        let tui = TUIContext()
        let ctx = context(width: 40, height: 20, tui: tui)
        tui.stateStorage.beginRenderPass()
        // 30 rows of content, only 10 lines of room.
        let buffer = renderPresentedDialog(rows(30), context: ctx, capHeight: 10)
        tui.stateStorage.endRenderPass()

        #expect(
            buffer.height == 10,
            "an over-tall dialog is capped to the visible area, got \(buffer.height)")
        let lines = buffer.lines.map { $0.stripped }
        // Capped from the TOP, not sliced from the bottom: the first content
        // row is visible (the bug was the footer being cut off the bottom while
        // the top showed — here we prove it starts at row 0 and is scrollable).
        #expect(
            lines.first?.contains("row 0") == true,
            "the capped dialog starts at its first row: \(lines.first ?? "")")
        #expect(
            !lines.contains(where: { $0.contains("row 29") }),
            "the last row is initially off-screen (scrollable into view)")
    }
}
