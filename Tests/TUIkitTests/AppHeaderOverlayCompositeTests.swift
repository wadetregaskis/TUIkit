//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppHeaderOverlayCompositeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A one-row view that emits a drop-down two rows below its own row — the
/// shape of a `Menu`, a `.popover` or a `Picker` anchored to a control.
///
/// A probe rather than a real `Menu` because the question is about the ROUTE a
/// layer takes to the screen, not about what opens one: a `Menu` reaches this
/// same `FrameBuffer.overlays` after a click, a focus move and a state write,
/// and a test built on those would fail for any of a dozen reasons that are not
/// this one.
private struct DropDownProbe: View, Renderable {
    var body: Never { fatalError("DropDownProbe renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var buffer = FrameBuffer(text: "anchor")
        buffer.overlays = [
            OverlayLayer(offsetX: 0, offsetY: 2, content: FrameBuffer(lines: ["POPUP"]))
        ]
        return buffer
    }
}

/// The drop-down is declared in the header.
private struct HeaderDropDownApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("page")
                .appHeader { DropDownProbe() }
        }
    }
}

/// The public feature, rather than the mechanism: a real presentation,
/// declared in the header, already open.
private struct HeaderPopoverApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("page")
                .appHeader {
                    Text("File")
                        .popover(isPresented: .constant(true)) { Text("REVEALED") }
                }
        }
    }
}

/// The control: the same drop-down, declared on the page.
private struct PageDropDownApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            DropDownProbe()
        }
    }
}

@MainActor
@Suite("A layer anchored in the app header reaches the screen", .serialized)
struct AppHeaderOverlayCompositeTests {

    /// The control, and the reason the test below is about the header rather
    /// than about the probe: the identical layer, emitted from the page, draws.
    @Test("The same layer on the page draws")
    func pageLayerDraws() {
        let harness = RenderLoopHarness()
        _ = harness.loop(PageDropDownApp()).render()

        #expect(harness.terminal.allOutput.contains("POPUP"))
    }

    /// `03d0a557` carried the header content's layers through the header's
    /// rebuild; nothing then composited them. The header buffer is written
    /// straight to the terminal, and only the CONTENT buffer went through
    /// `compositingOverlays` — so a `Menu` in `.appHeader { … }` opened,
    /// took the focus, and drew nothing at all.
    @Test("A layer anchored in the header draws")
    func headerLayerDraws() {
        let harness = RenderLoopHarness()
        _ = harness.loop(HeaderDropDownApp()).render()

        #expect(
            harness.terminal.allOutput.contains("POPUP"),
            "a Menu in .appHeader { … } opens and draws nothing")
    }

    /// Where it draws, not merely that it draws: a header-anchored drop-down
    /// belongs OVER THE PAGE, not clipped to the header's rows. The probe
    /// anchors its layer two rows below its own, which on the default bordered
    /// header (a rule, the row, a rule) is the first row of the page.
    @Test("It floats over the page rather than inside the header")
    func headerLayerLandsOnThePage() {
        let harness = RenderLoopHarness()
        _ = harness.loop(HeaderDropDownApp()).render()

        #expect(
            terminalRow(containing: "POPUP", in: harness.terminal.allOutput) == 4,
            "the header is three rows, so the page starts at row 4")
    }

    /// The mechanism above with a real presentation on top of it, so the
    /// feature is pinned and not only the route it takes.
    @Test("A popover presented in the header is on the screen")
    func headerPopoverDraws() {
        let harness = RenderLoopHarness()
        _ = harness.loop(HeaderPopoverApp()).render()

        #expect(harness.terminal.allOutput.contains("REVEALED"))
    }

    /// The 1-based terminal row `needle` was written on, read back out of the
    /// escape stream: the writer emits `ESC [ row ; 1 H` before each line it
    /// touches, so the last one seen before the text is the row it landed on.
    private func terminalRow(containing needle: String, in output: String) -> Int? {
        var row: Int?
        for part in output.components(separatedBy: "\u{1B}[") {
            if let end = part.firstIndex(of: "H") {
                let coordinates = part[part.startIndex..<end].split(separator: ";")
                if coordinates.count == 2, let line = Int(coordinates[0]),
                    Int(coordinates[1]) != nil {
                    row = line
                }
            }
            if part.contains(needle) { return row }
        }
        return nil
    }
}
