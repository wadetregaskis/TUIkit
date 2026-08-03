//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollViewClippedHitRegionTests.swift
//
//  A ScrollView's viewport is as final a clip for a hit-test region as it is
//  for a line. A control straddling the top edge used to keep its full height
//  and shift to a NEGATIVE offsetY, so the parent placed it over rows ABOVE the
//  scroller; one straddling the bottom kept rows past the last visible line.
//  Regions are hit-tested innermost-first, so those phantom rows won: a click
//  on a Button sitting above the ScrollView reached a half-scrolled-off row
//  inside it instead. The overlay twin of this seam is
//  ClampedOverlayHitRegionTests.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("ScrollView clips hit regions to its viewport")
struct ScrollViewClippedHitRegionTests {

    /// One 10-row interactive block in a 6-row scroller. At offset 3 it
    /// straddles BOTH edges: 3 rows scrolled off the top, 1 past the bottom.
    /// Scrolled by real wheel ticks through the dispatcher — three lines each,
    /// so one tick lands the block straddling both edges.
    private func regions(wheelTicks: Int) -> [HitTestRegion] {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)

        let view = ScrollView {
            Text((0..<10).map { "row \($0)" }.joined(separator: "\n"))
                // Declines, so the wheel bubbles past it to the viewport
                // and the scroll actually happens.
                .onMouseEvent { _ in false }
        }
        .frame(height: 6)

        func renderOnce() -> FrameBuffer {
            var context = RenderContext(
                availableWidth: 20, availableHeight: 6, environment: environment, tuiContext: tui)
            context.hasExplicitWidth = true
            context.hasExplicitHeight = true
            tui.stateStorage.beginRenderPass()
            return renderToBuffer(view, context: context)
        }

        var buffer = renderOnce()
        for _ in 0..<wheelTicks {
            dispatcher.setRegions(buffer.hitTestRegions)
            _ = dispatcher.dispatch(
                MouseEvent(button: .scrollDown, phase: .scrolled, x: 2, y: 2))
            buffer = renderOnce()
        }
        return buffer.hitTestRegions
    }

    @Test("A region straddling the top is trimmed, not shifted above the viewport")
    func topStraddleIsTrimmed() {
        let published = regions(wheelTicks: 1)
        #expect(!published.isEmpty, "the content still publishes its region")
        for region in published {
            #expect(
                region.offsetY >= 0,
                "a region must not reach rows above the scroller: \(region)")
        }
    }

    @Test("A region straddling the bottom is trimmed to the last visible row")
    func bottomStraddleIsTrimmed() {
        for region in regions(wheelTicks: 1) {
            #expect(
                region.offsetY + region.height <= 6,
                "a region must not reach rows below the scroller: \(region)")
        }
    }

    @Test("An unscrolled viewport is unchanged")
    func unscrolledIsUnchanged() {
        let published = regions(wheelTicks: 0)
        #expect(!published.isEmpty)
        for region in published {
            #expect(region.offsetY >= 0 && region.offsetY + region.height <= 6)
        }
    }
}
