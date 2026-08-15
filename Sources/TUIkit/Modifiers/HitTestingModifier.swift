//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HitTestingModifier.swift
//
//  Taking the MOUSE away from a view without taking its space or its drawing:
//  `allowsHitTesting(false)` leaves the view exactly as it looked and lets
//  clicks fall through to whatever is beneath.
//
//  `hidden()` belongs here too and is NOT yet shipped — adding it to this
//  module reproducibly broke an unrelated scrollbar test
//  (`ScrollbarModifierWiringTests.visibilityPropagatesButInnerWins`), by a
//  mechanism I could not establish. See the commit that added this file.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - allowsHitTesting()

extension View {
    /// Controls whether this view can be the target of mouse input.
    ///
    /// Mirrors SwiftUI's `allowsHitTesting(_:)`. With `false` the view still
    /// draws and still occupies its space; clicks, drags and wheel events pass
    /// through it to whatever is beneath.
    ///
    /// ```swift
    /// // A decorative overlay that must not swallow clicks.
    /// content.overlay(watermark.allowsHitTesting(false))
    /// ```
    ///
    /// This is not ``View/disabled(_:)``. A disabled control looks disabled and
    /// leaves the focus ring; a non-hit-testable one looks entirely normal and
    /// stays reachable by keyboard. Reach for this when the view is *decoration*
    /// that happens to sit over something interactive — not when an action is
    /// unavailable.
    ///
    /// - Parameter enabled: Whether the view may be hit. Default `true`.
    /// - Returns: A view whose hit regions are kept or dropped.
    public func allowsHitTesting(_ enabled: Bool) -> some View {
        _HitTestingView(content: self, enabled: enabled)
    }
}

/// Drops the hit regions of `content` when disabled.
///
/// - Important: Framework infrastructure, created by
///   ``View/allowsHitTesting(_:)``.
private struct _HitTestingView<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let enabled: Bool

    var body: Never { fatalError("_HitTestingView renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var drawn = TUIkit.renderToBuffer(content, context: context)
        guard !enabled else { return drawn }
        // The regions of any OVERLAY the subtree floated have to go too — a
        // pop-up menu is carried in `overlays` rather than in the buffer's own
        // lines, so clearing only the top level would leave a drop-down
        // clickable underneath a view that just said it was not.
        drawn.hitTestRegions = []
        for index in drawn.overlays.indices {
            drawn.overlays[index].content.hitTestRegions = []
        }
        return drawn
    }
}
