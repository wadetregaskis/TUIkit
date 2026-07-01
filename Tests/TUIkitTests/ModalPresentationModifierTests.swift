//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ModalPresentationModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT  dimming, centering, and arbitrary content.
//

import Testing

@testable import TUIkit

@MainActor
@Suite("ModalPresentationModifier Tests")
struct ModalPresentationModifierTests {

    /// Helper to create a RenderContext with default test settings.
    private func testContext() -> RenderContext {
        RenderContext(
            availableWidth: 80,
            availableHeight: 24,
            tuiContext: TUIContext()
        ).isolatingRenderCache()
    }

    /// Helper to render a view to a FrameBuffer.
    ///
    /// A presented `.modal` now floats to the screen root as an overlay (so it
    /// centres + dims over the whole screen from any attachment), so the test
    /// composites the overlays the way `RenderLoop` does — yielding the final
    /// dimmed-base + centred-modal buffer the tests assert against.
    private func render<V: View>(_ view: V) -> FrameBuffer {
        let context = testContext()
        let buffer = renderToBuffer(view, context: context)
        return buffer.compositingOverlays(
            maxWidth: 80, maxHeight: 24, palette: context.environment.palette)
    }

    @Test("Modal not presented shows only base content")
    func notPresentedShowsBase() {
        let isPresented = Binding.constant(false)
        let view = Text("Base Content")
            .modal(isPresented: isPresented) {
                Text("Modal Content")
            }

        let buffer = render(view)
        let content = buffer.lines.joined(separator: "\n").stripped

        #expect(content.contains("Base Content"))
        #expect(!content.contains("Modal Content"))
    }

    @Test("Modal presented shows dimmed base with modal overlay")
    func presentedShowsModal() {
        let isPresented = Binding.constant(true)
        let view = VStack {
            Text("Base Content")
            Text("More base text")
        }
        .modal(isPresented: isPresented) {
            Text("Modal Content")
        }

        let buffer = render(view)

        // Modal content should be present
        let stripped = buffer.lines.joined(separator: "\n").stripped
        #expect(stripped.contains("Modal Content"))

        // Should have ANSI codes (from dimmed base and compositing)
        let rawContent = buffer.lines.joined(separator: "\n")
        #expect(rawContent.contains("\u{1B}["))  // Contains ANSI codes
    }

    @Test("Modal accepts arbitrary view content")
    func arbitraryContent() {
        let isPresented = Binding.constant(true)
        let view = Text("Base")
            .modal(isPresented: isPresented) {
                VStack {
                    Text("Line 1")
                    Text("Line 2")
                    Text("Line 3")
                }
            }

        let buffer = render(view)
        let content = buffer.lines.joined(separator: "\n").stripped

        #expect(content.contains("Line 1"))
        #expect(content.contains("Line 2"))
        #expect(content.contains("Line 3"))
    }

    @Test("Modal works with Dialog view")
    func modalWithDialog() {
        let isPresented = Binding.constant(true)
        let view = Text("Base")
            .modal(isPresented: isPresented) {
                Dialog(title: "Settings") {
                    Text("Option 1")
                    Text("Option 2")
                }
            }

        let buffer = render(view)
        let content = buffer.lines.joined(separator: "\n").stripped

        #expect(content.contains("Settings"))
        #expect(content.contains("Option 1"))
        #expect(content.contains("Option 2"))
    }

    @Test("Modal works with Alert view")
    func modalWithAlert() {
        let isPresented = Binding.constant(true)
        let view = Text("Base")
            .modal(isPresented: isPresented) {
                Alert(title: "Warning", message: "Sure?") {
                    Button("Yes") {}
                }
            }

        let buffer = render(view)
        let content = buffer.lines.joined(separator: "\n").stripped

        #expect(content.contains("Warning"))
        #expect(content.contains("Sure?"))
        #expect(content.contains("Yes"))
    }

    @Test("Toggle isPresented switches between states")
    func togglePresentation() {
        @State var showModal = false

        let view1 = Text("Content")
            .modal(isPresented: $showModal) {
                Text("Modal")
            }

        let buffer1 = render(view1)
        let content1 = buffer1.lines.joined(separator: "\n").stripped

        // Initially not shown
        #expect(!content1.contains("Modal"))

        // Toggle to show
        showModal = true
        let view2 = Text("Content")
            .modal(isPresented: $showModal) {
                Text("Modal")
            }

        let buffer2 = render(view2)
        let content2 = buffer2.lines.joined(separator: "\n").stripped

        // Now shown
        #expect(content2.contains("Modal"))
    }

    @Test("Modal centers content over base")
    func centersContent() {
        let isPresented = Binding.constant(true)
        let view = VStack {
            Text("Wide base content that spans multiple characters")
            Text("Another line of wide content here")
        }
        .modal(isPresented: isPresented) {
            Text("Small")
        }

        let buffer = render(view)

        // Modal should be rendered (non-empty, contains both base and modal)
        #expect(!buffer.isEmpty)
        let content = buffer.lines.joined(separator: "\n").stripped
        #expect(content.contains("Wide base content"))
        #expect(content.contains("Small"))
    }

    @Test("A modal attached to a small leaf still centres on the whole screen (#95)")
    func leafModalCentersOnScreen() {
        // `.modal` is on a one-character leaf near the top-left, not the page
        // root. It must still centre over the full 80×24 screen, not the leaf's
        // tiny local area.
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("TOPLINE")
            Text("x").modal(isPresented: .constant(true)) {
                Dialog(title: "M") { Text("MODALBODY") }
            }
            Text("BOTLINE")
        }
        let buffer = render(view)  // composites the overlay at 80×24
        let lines = buffer.lines.map { $0.stripped }

        guard let row = lines.firstIndex(where: { $0.contains("MODALBODY") }) else {
            Issue.record("the modal body should be shown: \(lines)")
            return
        }
        let leading = lines[row].prefix { $0 == " " }.count
        // Centred vertically (well below the leaf's row ~1) and horizontally (a big
        // left margin, not flush at the leaf's column 0).
        #expect(row > 4, "modal is centred vertically, not at the leaf's row: \(row)")
        #expect(leading > 15, "modal is centred horizontally, not at the leaf's column: leading=\(leading)")
        // The dimmed base is still visible behind it.
        #expect(lines.contains { $0.contains("TOPLINE") }, "the dimmed base shows through")
    }
}

// MARK: - Focus / input isolation (modal blocks the background)

private final class ClickSink: @unchecked Sendable { var hits: [String] = [] }

@MainActor
@Suite("Modal focus & input isolation")
struct ModalIsolationTests {

    /// Renders the view with a real FocusManager + mouse dispatcher, returns the
    /// buffer and the manager so a test can inspect focus and click hit regions.
    private func renderInteractive<V: View>(
        _ view: V, width: Int = 60, height: Int = 20
    ) -> (buffer: FrameBuffer, fm: FocusManager, tui: TUIContext) {
        let tui = TUIContext()
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.stateStorage = tui.stateStorage
        env.mouseEventDispatcher = tui.mouseEventDispatcher
        let ctx = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)
        fm.beginRenderPass()
        let buffer = renderToBuffer(view, context: ctx)
        fm.endRenderPass()
        // The modal floats to the screen root as an overlay, so composite it the
        // way RenderLoop does: that dims the base (dropping its hit regions, so the
        // background is inert) and lands the modal's hit regions at the centred
        // position — which is exactly the isolation these tests check.
        let composited = buffer.compositingOverlays(
            maxWidth: width, maxHeight: height, palette: ctx.environment.palette)
        return (composited, fm, tui)
    }

    /// Clicks the centre of every hit region in the buffer.
    private func clickAllRegions(_ buffer: FrameBuffer, _ tui: TUIContext) {
        tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
        for region in buffer.hitTestRegions {
            let x = region.offsetX + region.width / 2
            let y = region.offsetY + region.height / 2
            _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
            _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        }
    }

    @Test("A presented modal captures focus and makes the background inert (#6)")
    func modalIsolatesBackground() {
        let sink = ClickSink()
        let view = VStack { Button("bg") { sink.hits.append("bg") } }
            .modal(isPresented: .constant(true)) {
                Dialog(title: "D") { Button("ok") { sink.hits.append("modal") } }
            }
        let (buffer, fm, tui) = renderInteractive(view)

        // (a) The modal received keyboard focus on open — the reported symptom is
        // dialogs that open with nothing focused.
        #expect(fm.currentFocusedID != nil, "the modal received focus on open")

        // (c) The background is inert: the dimmed base contributes no hit regions,
        // so no click anywhere can reach the background control.
        clickAllRegions(buffer, tui)
        #expect(!sink.hits.contains("bg"),
                "the background control can't be clicked while the modal is up: \(sink.hits)")
        #expect(sink.hits.contains("modal"), "the modal's control is clickable")
    }

    @Test("The convenience .modal { } isolates the background too (#6)")
    func convenienceModalIsolates() {
        let sink = ClickSink()
        let view = VStack { Button("bg") { sink.hits.append("bg") } }
            .modal {
                Dialog(title: "D") { Button("ok") { sink.hits.append("modal") } }
            }
        let (buffer, fm, tui) = renderInteractive(view)
        #expect(fm.currentFocusedID != nil, "the always-on modal received focus")
        clickAllRegions(buffer, tui)
        #expect(!sink.hits.contains("bg"), "background inert under the convenience modal: \(sink.hits)")
        #expect(sink.hits.contains("modal"), "the modal's control is clickable")
    }

    @Test("Stacked modals isolate to the topmost; lower layers are inert (#6)")
    func stackedModalsIsolateToTopmost() {
        let sink = ClickSink()
        let view = VStack { Button("page") { sink.hits.append("page") } }
            .modal(isPresented: .constant(true)) {
                Dialog(title: "A") { Button("a") { sink.hits.append("a") } }
                    .modal(isPresented: .constant(true)) {
                        Dialog(title: "B") { Button("b") { sink.hits.append("b") } }
                    }
            }
        let (buffer, _, tui) = renderInteractive(view, height: 24)
        clickAllRegions(buffer, tui)
        #expect(sink.hits.contains("b"), "the topmost modal's control is interactive: \(sink.hits)")
        #expect(!sink.hits.contains("a") && !sink.hits.contains("page"),
                "lower modal + page are inert under the topmost: \(sink.hits)")
    }

    /// The full-width, single-row grab region at the dialog's top (its title bar).
    private func titleRegion(_ buffer: FrameBuffer) -> HitTestRegion? {
        let fullWidth = buffer.hitTestRegions.map(\.width).max() ?? 0
        return buffer.hitTestRegions
            .filter { $0.width == fullWidth && $0.height == 1 }
            .min(by: { $0.offsetY < $1.offsetY })
    }

    @Test("Dragging a modal by its title bar moves it, clamped on screen")
    func draggingTitleMovesModal() {
        let view = VStack { Text("bg") }
            .modal(isPresented: .constant(true)) {
                Dialog(title: "Movable") { Text("body") }
            }

        // Render + composite twice through the SAME context so the drag offset,
        // held in StateStorage, survives between frames.
        let tui = TUIContext()
        let fm = FocusManager()
        var env = EnvironmentValues()
        env.focusManager = fm
        env.stateStorage = tui.stateStorage
        env.mouseEventDispatcher = tui.mouseEventDispatcher
        let width = 60, height = 24
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: env, tuiContext: tui)

        func frame() -> FrameBuffer {
            fm.beginRenderPass()
            let raw = renderToBuffer(view, context: context)
            fm.endRenderPass()
            return raw.compositingOverlays(
                maxWidth: width, maxHeight: height, palette: context.environment.palette)
        }

        let before = frame()
        guard let title = titleRegion(before) else {
            Issue.record("no title grab region")
            return
        }

        // Press on the title bar, drag down-right by (dx, dy), release.
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(before.hitTestRegions)
        let px = title.offsetX + title.width / 2
        let py = title.offsetY
        let dx = 5, dy = 3
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: px, y: py))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .dragged, x: px + dx, y: py + dy))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: px + dx, y: py + dy))

        let after = frame()
        guard let movedTitle = titleRegion(after) else {
            Issue.record("no title grab region after drag")
            return
        }
        #expect(movedTitle.offsetX == title.offsetX + dx, "dialog moved right by \(dx)")
        #expect(movedTitle.offsetY == title.offsetY + dy, "dialog moved down by \(dy)")
    }

    @Test("A plain modal's edge control is not shadowed by the drag grab region")
    func plainModalControlNotShadowedByGrab() {
        let sink = ClickSink()
        // Arbitrary (non-Dialog) content: the Button sits on the modal buffer's
        // own top row, exactly where the title grab region is — the drag grab
        // must not swallow its click.
        let view = VStack { Text("bg") }
            .modal(isPresented: .constant(true)) {
                Button("ok") { sink.hits.append("modal") }
            }
        let (buffer, _, tui) = renderInteractive(view)
        clickAllRegions(buffer, tui)
        #expect(sink.hits.contains("modal"),
                "the modal's control still fires despite the overlapping drag grab region: \(sink.hits)")
    }
}
