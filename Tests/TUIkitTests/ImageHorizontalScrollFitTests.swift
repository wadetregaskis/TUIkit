//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImageHorizontalScrollFitTests.swift
//
//  An image offered no size — the content of a scroll view that scrolls
//  horizontally, asked how big it would be if nothing stopped it — fits the
//  visible viewport by default (the owner's ruling, 2026-09-23), on every axis
//  nothing inside the scroll view bounded. It used to fit the probe's budget and
//  come back thousands of cells across.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

@MainActor
@Suite("Image in a horizontal scroll view")
struct ImageHorizontalScrollFitTests {
    private func renderContext(width: Int, height: Int) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.stateStorage = StateStorage()
        return RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: TUIContext()).isolatingRenderCache()
    }

    /// A context shaped like a horizontally scrolling scroll view's content:
    /// the viewport published, and the whole-width canvas mark set.
    private func horizontalScrollContext(viewport: (Int, Int), offer: (Int, Int)) -> RenderContext {
        var context = makeScrollContext(viewport: viewport)
        context.environment.asksWholeContentWidth = true
        context.availableWidth = offer.0
        context.availableHeight = offer.1
        return context
    }

    /// The owner's ruling (2026-09-23): under a scroll view that scrolls
    /// horizontally the default fits the viewport. It used to fit the probe's
    /// budget and come back thousands of cells across.
    @Test("Under a horizontal scroll view, the default is capped at the viewport")
    func horizontalScrollCapsAtViewport() {
        let context = horizontalScrollContext(viewport: (20, 10), offer: (4096, 4096))
        let size = measureChild(
            Image(.file("/no/such/image.png")), proposal: ProposedSize(width: nil, height: nil), context: context)
        #expect(size.width == 20, "fits the viewport width (20), not the probe's 4,096: \(size.width)")
        #expect(size.height <= 10, "and its height (10): \(size.height)")
    }

    /// A cap, not a replacement: a real bound inside the scroll view still binds.
    @Test("Under a horizontal scroll view, a frame narrower than the viewport still binds")
    func horizontalScrollKeepsASmallerBound() {
        let context = horizontalScrollContext(viewport: (20, 10), offer: (4096, 4096))
        let size = measureChild(
            Image(.file("/no/such/image.png")), proposal: ProposedSize(width: 8, height: nil), context: context)
        #expect(size.width == 8, "the 8-wide bound was widened to the viewport: \(size.width)")
    }

    /// But not on an axis something inside the scroll view bounded: a
    /// `.frame(width: 60)` offers 60, and is 60 wide however narrow the
    /// viewport; the height it leaves open is still the viewport's.
    @Test("Under a horizontal scroll view, a frame wider than the viewport is honoured")
    func horizontalScrollHonoursAStatedSize() {
        let context = horizontalScrollContext(viewport: (20, 10), offer: (4096, 4096))
        let size = measureChild(
            Image(.file("/no/such/image.png")), proposal: ProposedSize(width: 60, height: nil), context: context)
        #expect(size.width == 60, "the frame's 60 was capped to the viewport: \(size.width)")
        #expect(size.height <= 10, "the unstated axis is still capped: \(size.height)")
    }

    /// A frame around the image states its whole box, and nothing is left to
    /// the viewport — end to end, through a real scroll view that scrolls both
    /// ways, where the frame's 60 makes the canvas scroll.
    @Test("In a two-axis ScrollView, a framed image keeps its frame")
    func twoAxisFramedImageKeepsItsFrame() {
        let view = ScrollView([.horizontal, .vertical]) {
            Image(.file("/no/such/x.png")).frame(width: 60, height: 4)
        }
        .scrollIndicators(.automatic)
        let context = renderContext(width: 24, height: 6)
        _ = renderToBuffer(view, context: context)
        let buffer = renderToBuffer(view, context: context)
        #expect(
            buffer.lines.contains { $0.contains("▶") || $0.contains("◀") },
            "the 60-wide frame was squeezed into the viewport: \(buffer.lines.map(\.stripped))")
    }

    /// And zoom still grows it past the viewport, as it grows `.viewport`.
    @Test("Under a horizontal scroll view, zoom grows the capped size")
    func horizontalScrollZoomGrowsPastTheViewport() {
        let context = horizontalScrollContext(viewport: (20, 10), offer: (4096, 4096))
        let base = measureChild(
            Image(.file("/no/such/image.png")), proposal: ProposedSize(width: nil, height: nil), context: context)
        let zoomed = measureChild(
            Image(.file("/no/such/image.png")).imageZoom(2), proposal: ProposedSize(width: nil, height: nil),
            context: context)
        #expect(zoomed.width == base.width * 2, "zoom 2 doubles the capped width: \(zoomed.width) vs \(base.width)")
    }

    @Test(
        "In a ScrollView that scrolls horizontally, the default image fits the viewport",
        arguments: [Axis.Set.horizontal, [.horizontal, .vertical]])
    func horizontalScrollViewFitsTheViewport(axes: Axis.Set) {
        let view = ScrollView(axes) { Image(.file("/no/such/x.png")) }
            .scrollIndicators(.automatic)
        let context = renderContext(width: 24, height: 6)
        _ = renderToBuffer(view, context: context)
        let buffer = renderToBuffer(view, context: context)
        #expect(buffer.width <= 24 && buffer.height <= 6)
        #expect(
            !buffer.lines.contains { $0.contains("▼") || $0.contains("▶") || $0.contains("▲") || $0.contains("◀") },
            "the image overflowed the viewport, so the scroll view grew bars: \(buffer.lines.map(\.stripped))")
    }
}
