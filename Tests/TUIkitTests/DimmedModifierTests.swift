//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DimmedModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("DimmedModifier Tests")
struct DimmedModifierTests {

    /// Helper to create a RenderContext with default test settings.
    private func testContext() -> RenderContext {
        RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    /// Helper to render a view to a FrameBuffer.
    private func render<V: View>(_ view: V) -> FrameBuffer {
        renderToBuffer(view, context: testContext())
    }

    @Test("Dimmed text strips original styling and applies uniform colors")
    func dimmedStripsAndRecolors() {
        let view = Text("Hello").dimmed()
        let buffer = render(view)
        #expect(buffer.lines.count == 1)
        // Should NOT contain the old ANSI dim code — we use palette colors now
        #expect(!buffer.lines[0].contains("\u{1B}[2m"))
        // Visible text must survive the stripping
        #expect(buffer.lines[0].stripped.contains("Hello"))
        // Must contain RGB color codes (from palette foregroundTertiary/overlayBackground)
        #expect(buffer.lines[0].contains("\u{1B}["))
    }

    @Test("Dimmed empty view returns empty buffer")
    func dimmedEmptyView() {
        let view = EmptyView().dimmed()
        let buffer = render(view)
        #expect(buffer.isEmpty)
    }

    @Test("Dimmed multi-line view flattens each line uniformly")
    func dimmedMultiLine() {
        let view = VStack {
            Text("Line 1")
            Text("Line 2")
            Text("Line 3")
        }.dimmed()
        let buffer = render(view)
        #expect(buffer.height == 3)
        // Each line should have the visible text and uniform palette-based styling
        for line in buffer.lines {
            #expect(!line.contains("\u{1B}[2m"))
            #expect(!line.stripped.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @Test("Dimmed lines are padded to full buffer width")
    func dimmedPadsToFullWidth() {
        let view = Text("Short").dimmed()
        let buffer = render(view)
        let visibleWidth = buffer.lines[0].strippedLength
        // The dimmed line should be padded to the buffer width
        #expect(visibleWidth == buffer.width)
    }

    @Test(
        "Dimming pads in CELLS, not code units (CJK/emoji/NFD lines keep the buffer width)",
        arguments: [
            "中文标题",  // CJK: 1 UTF-16 unit but 2 cells each — over-padded before
            "hi 🥳 wide",  // SMP emoji: 2 units = 2 cells (the coincidence that hid the bug)
            "caf\u{65}\u{301} narrow",  // NFD é: 2 units but 1 cell — under-padded before
            "⌚ watch",  // BMP wide: 1 unit, 2 cells
        ])
    func dimmedPadsWideContentInCells(text: String) {
        // The backdrop behind a modal is `dimmedAsBackdrop` over the page
        // buffer. Its padding used Foundation's `padding(toLength:)` — UTF-16
        // code units — so CJK lines came out wider than the buffer (and NFD
        // narrower), drifting the backdrop's right edge. Padding must be in
        // terminal CELLS like the rest of the layout.
        let view = VStack(alignment: .leading) {
            Text(text)
            Text("plain second line that is longer")
        }
        .dimmed()
        let buffer = render(view)
        for (i, line) in buffer.lines.enumerated() {
            #expect(
                line.strippedLength == buffer.width,
                "dimmed line \(i) is exactly the buffer width: '\(line.stripped)'")
        }
    }

    @Test("A dimmed line terminates its persistent background (no rightward bleed)")
    func dimmedBackgroundIsTerminated() {
        // The backdrop's persistent background left ACTIVE at the line end
        // bleeds into whatever is composited to the right — the same class as
        // the List `.plain` selection bleed. Every dimmed line must end reset.
        let view = Text("backdrop").dimmed()
        let buffer = render(view)
        for (i, line) in buffer.lines.enumerated() {
            #expect(
                line.hasSuffix(ANSIRenderer.reset),
                "dimmed line \(i) ends with a reset: \(line.debugDescription)")
        }
    }
}
