//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RemovalScreen.swift
//
//  Created by Wade Tregaskis
//  License: MIT

@testable import TUIkit

/// A view drawn frame by frame, the frames a clock apart and every one of them
/// under `animation` — what a removal transition is tested on.
///
/// Each frame is one render pass, fenced the way the render loop fences it
/// (`DepartureStore.beginRenderPass` / `endRenderPass`), so a view that is not
/// re-declared is gone and a `nil` can play out what it left behind.
@MainActor
final class RemovalScreen<Content: View> {
    private var context: RenderContext
    private let content: (Bool) -> Content

    /// - Parameters:
    ///   - animation: The animation every frame is drawn under, or `nil` for
    ///     none: a removal then snaps.
    ///   - width: The width the view is offered.
    ///   - content: The view, with what comes and goes there or not.
    init(
        animation: Animation?, width: Int = 8,
        content: @escaping (_ showing: Bool) -> Content
    ) {
        self.content = content
        context = makeRenderContext(width: width, height: 6)
        context.environment.canAnimate = true
        if let animation {
            context.environment.transaction = Transaction(animation: animation)
        }
    }

    /// The view at `millis` on the frame clock, with what comes and goes there
    /// or not, styling stripped.
    func draw(_ showing: Bool, atMillis millis: Int) -> [String] {
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        let storage = context.environment.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return renderToBuffer(content(showing), context: context).lines.map(\.stripped)
    }
}
