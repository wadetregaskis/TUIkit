//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollView+Anchor.swift
//
//  How a `ScrollView` honours the EDGE anchor modes of
//  `Documentation/Scroll-anchoring.md` §1.1 — Bottom (follow-the-log) and Top —
//  from the declared `defaultScrollAnchor` and, equally, from a bound
//  `.anchorPosition`, which §3.2 defines as the code-side `anchor(to:)`.
//
//  Both are POSITIONAL policies: engagement is "the offset is already at that
//  edge", never a stored flag, so scrolling away releases them by construction
//  and scrolling back re-engages. The one thing that must be remembered across
//  frames is a *newly written* bound edge — see `adoptWrittenAnchor`.
//
//  Created by Wade Tregaskis
//  License: MIT

extension _ScrollViewCore {

    /// Bottom edge affinity (defaultScrollAnchor(.bottom), §5c/§6c): being
    /// AT the bottom is the engagement — no stored flag. If last frame's
    /// numbers say the offset sits at (or past) maxOffset, the view is
    /// glued: the frame renders at the previous tail, the post-render
    /// re-glue lands on the real new maximum, and `coverSnappedViewport`
    /// re-renders — O(window) — when the band's margin doesn't already
    /// cover the difference (it does for the common one-row append).
    /// Scrolling up breaks the condition (offset < max) and appends stop
    /// moving the view; any scroll that lands back at the bottom
    /// re-engages. The very first frame (contentHeight 0, offset 0) is
    /// glued by construction, giving the initial at-the-tail placement.
    /// Vertical only.
    ///
    /// Deliberately NO pre-render tail estimate: this used to measure the
    /// whole content tree every glued frame to pre-position the offset, and
    /// that estimate systematically disagreed with the post-render reply
    /// total (they come from different estimators), so the coverage
    /// re-render fired EVERY frame — a full measure plus two band renders
    /// per frame, 23% of the scrollfollow profile in the second render
    /// alone.
    func isGluedToBottom(handler: ScrollViewHandler, context: RenderContext) -> Bool {
        // The EFFECTIVE anchor, not just the declaration: a bound
        // `.anchorPosition` of `.bottom` must follow the tail even with no
        // `defaultScrollAnchor` (that is §3.2's `anchor(to:)`), and a bound
        // `.window` / `.top` / `.row` must override a declared `.bottom` — a
        // release the user made by scrolling away has to actually stop the
        // follow, or `.window` would be a read-out with no behaviour behind it.
        let followsBottom = !context.isMeasuring
            && ScrollAnchorMode.effective(
                boundAnchor: context.environment.anchorPosition?.wrappedValue,
                defaultScrollAnchor: context.environment.defaultScrollAnchor) == .bottom
        // A pending scrollTo supersedes the glue this frame: the explicit
        // programmatic scroll is exactly the "scrolling away releases the
        // follow" interaction, expressed in code.
        return followsBottom && handler.pendingScrollTo == nil
            && handler.scrollOffset >= handler.maxOffset
    }

    /// Adopts a bound anchor the app just *wrote*: `.top` jumps to the top,
    /// `.bottom` to the tail. §3.2 promises that writing an edge into the
    /// binding is `anchor(to:)`, and only the CHANGE can mean that — holding
    /// the edge unconditionally every frame would nail an unbound
    /// `.defaultScrollAnchor(.top)` view to the top and make it unscrollable.
    /// After the jump the edge is held positionally, exactly as a declared one
    /// is (bottom re-glues while the offset sits at `maxOffset`; top needs
    /// nothing, since no data change moves an offset of 0).
    ///
    /// Render passes only, and before the glue is evaluated: `.bottom` sets
    /// `seekingTail` rather than an offset, so the post-render re-glue lands on
    /// the real tail instead of a pre-render estimate of it.
    func adoptWrittenAnchor(handler: ScrollViewHandler, context: RenderContext) {
        guard !context.isMeasuring else { return }
        let bound = context.environment.anchorPosition?.wrappedValue
        guard handler.lastBoundAnchor != .some(bound) else { return }
        let isFirstSighting = handler.lastBoundAnchor == nil
        handler.lastBoundAnchor = .some(bound)
        // A first sighting is the view appearing, not the app writing: leave the
        // initial placement to the declared anchor's own machinery.
        guard !isFirstSighting else { return }
        switch bound {
        case .top: handler.scrollOffset = 0
        case .bottom: handler.seekingTail = true
        default: break
        }
    }
}
