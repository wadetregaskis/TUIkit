//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ViewportReadMemoTests.swift
//
//  A view that sizes itself to the enclosing `ScrollView`'s VIEWPORT
//  (`scrollViewportSize` — `Image`'s `.imageFitTarget(.viewport)`) depends on a
//  value no memo keys on. Under a two-axis view whose content is wider than the
//  viewport, the canvas width — which the keys do see — stays put when the
//  terminal is resized, so the memos served the image the size and the picture
//  it had at the old viewport.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// A 120-cell line, which makes the canvas wider than any viewport here, and a
/// viewport-fit image (a missing file, so its placeholder, sized to the fit
/// box) in a row of its own, then a row below it. The viewport is tall, so the
/// placeholder's height follows its width — half of it, the cell aspect — and
/// the row under it moves with the viewport's width.
private struct ViewportRows: View {
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    switch index {
                    case 0: Text(String(repeating: "0", count: 120))
                    case 1: Image(.file("/no/such/image.png")).imageFitTarget(.viewport)
                    default: Text("x")
                    }
                }
            }
        }
    }
}

@MainActor
@Suite("A size that depends on the viewport")
struct ViewportReadMemoTests {
    /// Every line of the frame drawn at `width`, after the frames at `before`,
    /// through one cache as the render loop drives it.
    private func frame(at width: Int, after before: [Int]) -> [String] {
        let tuiContext = TUIContext()
        var last: [String] = []
        for columns in before + [width] {
            var environment = EnvironmentValues()
            environment.applyRuntimeServices(from: tuiContext)
            environment.installVolatileReadTracker(VolatileReadTracker())
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            last = renderToBuffer(
                AnyView(ViewportRows()),
                context: RenderContext(
                    availableWidth: columns, availableHeight: 50,
                    environment: environment, tuiContext: tuiContext)
            ).lines
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
        }
        return last
    }

    /// Widened from 40 columns to 60, the image fits the new viewport — as it
    /// does in a view drawn at 60 from the start. Served from the size memo,
    /// its row kept the 40-column placeholder's height, and the row under it
    /// was placed by that while the image drew at 60: the canvas is the
    /// 120-cell line's either way, so no key moved. One frame at 40 is not
    /// enough to show it — its measures are pruned with it — two are.
    @Test("A viewport-fit image follows a resize", arguments: [[40], [40, 40]])
    func aViewportFitImageFollowsAResize(before: [Int]) {
        #expect(frame(at: 60, after: before) == frame(at: 60, after: []))
    }
}
