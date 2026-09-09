//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppHeaderPayloadTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

/// Everything the header's content emitted survives the header's rebuild.
///
/// `AppHeader.renderToBuffer` re-lines its content (a border, or nothing) and so
/// builds a fresh `FrameBuffer` — which starts with every side payload empty.
/// Each one therefore has to be carried across by hand, and each one that was
/// not is a feature that silently does nothing inside `.appHeader { … }`. Hit
/// regions were the first to go missing (`e5382a77`: a Button in the header
/// could not be clicked), opacity followed, and animated runs and overlays were
/// still being dropped — a `Spinner` up there was frozen at frame 0, which does
/// not look like a dropped animation. It looks like a still picture.
@MainActor
@Suite("The app header carries its content's payloads", .serialized)
struct AppHeaderPayloadTests {

    /// A content buffer with one of each payload, at a known place, so the shift
    /// a bordered header applies is checkable rather than assumed.
    private func contentBuffer() -> FrameBuffer {
        var buffer = FrameBuffer(lines: ["hello"])
        buffer.hitTestRegions = [
            HitTestRegion(offsetX: 0, offsetY: 0, width: 5, height: 1, handlerID: .init(0))
        ]
        buffer.animatedCells = [
            AnimatedCellRun(
                offsetX: 0, offsetY: 0, width: 5, frames: ["one--", "two--"],
                clock: .content)
        ]
        buffer.overlays = [
            OverlayLayer(offsetX: 0, offsetY: 0, content: FrameBuffer(lines: ["pop"]))
        ]
        return buffer
    }

    private func header(_ style: ChromeStyle) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: 20, availableHeight: style == .bordered ? 3 : 1,
            tuiContext: TUIContext())
        return renderToBuffer(
            AppHeader(contentBuffer: contentBuffer(), style: style), context: context)
    }

    @Test("A compact header carries all four, unmoved")
    func compactCarriesEverything() {
        let drawn = header(.compact)
        #expect(drawn.hitTestRegions.count == 1)
        #expect(drawn.animatedCells.count == 1, "a Spinner in the header would be frozen")
        #expect(drawn.overlays.count == 1, "a Menu in the header would open and draw nothing")
        #expect(drawn.animatedCells.first?.offsetY == 0)
        #expect(drawn.overlays.first?.offsetY == 0)
    }

    /// A box moves its content right by its wall and down by its top rule, so
    /// every payload moves with it — a region or a run left at the old
    /// coordinates describes the border.
    @Test("A bordered header carries all four, shifted by its chrome")
    func borderedShiftsEverything() {
        let drawn = header(.bordered)
        #expect(drawn.hitTestRegions.first?.offsetX == 1)
        #expect(drawn.hitTestRegions.first?.offsetY == 1)
        #expect(drawn.animatedCells.first?.offsetX == 1)
        #expect(drawn.animatedCells.first?.offsetY == 1)
        #expect(drawn.overlays.first?.offsetX == 1)
        #expect(drawn.overlays.first?.offsetY == 1)
    }
}
