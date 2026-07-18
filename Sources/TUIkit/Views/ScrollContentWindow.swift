//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollContentWindow.swift
//
//  The ScrollView ↔ windowed-stack handshake: the visible slice travels
//  down as an environment value; the Stage-6 slice report travels back up
//  through the reply reference within the same render call.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

struct ScrollContentWindow: Sendable, Hashable {
    var offset: Int
    var viewportHeight: Int

    /// The identity of the ScrollView's direct content. A windowed stack
    /// consumes this window only when its own identity is a single-child
    /// descent from here (`ViewIdentity/isDirectDescent(from:)`): a stack
    /// that is one sibling among several is NOT at the scroll origin, and
    /// windowing there would blank the wrong rows. `nil` (tests, direct
    /// injection) means "trust the publisher" and consume unconditionally.
    var contentIdentity: ViewIdentity?

    /// The render-pass reply slot (Stage 6): the stack reports the compact
    /// slice it actually rendered, so the ScrollView can clip a band
    /// instead of a full-height canvas. `nil` (tests, measure passes) keeps
    /// the stack emitting the classic full-height buffer.
    var reply: ScrollContentReply?

    /// A pending programmatic scroll (``ScrollViewProxy/scrollTo(_:anchor:)``).
    /// The stack that locates the key renders AT the request's resolved
    /// offset — so the very frame that carries the request shows the target
    /// — and reports the offset via ``ScrollContentReply/seekResolvedOffset``
    /// for the ScrollView to adopt.
    var seek: ScrollToRequest?
}

/// The Stage-6 reply channel from a windowed stack back to its ScrollView:
/// reference semantics deliberately — the environment value travels down,
/// the slice report travels back up within the same render call. Main-loop
/// rendering only (`@unchecked`: never crosses threads).
final class ScrollContentReply: @unchecked Sendable, Hashable {
    /// Content-space y of the first line the buffer holds.
    var sliceOriginY: Int?
    /// The full content height the slice was cut from (estimated for
    /// never-measured suffixes — the §3 scrollbar trade).
    var sliceTotalHeight: Int?
    /// Whether ``sliceTotalHeight`` involves ESTIMATED extents (the anchored
    /// path's unmeasured remainder at the running pitch average, and its
    /// estimate-drifted absolute origin). The ScrollView surfaces this in
    /// the "N more" indicators — "~200M more below" — so the chrome doesn't
    /// assert precision the geometry doesn't have. The uniform path's
    /// arithmetic totals are hypothesis-exact and leave this `false`.
    var sliceTotalIsEstimate = false
    /// The window offset the stack rendered at in answer to
    /// ``ScrollContentWindow/seek`` — the ScrollView adopts it as its
    /// scroll position. `nil` when there was no request or the key wasn't
    /// found (an unknown id is a no-op, as in SwiftUI).
    var seekResolvedOffset: Int?

    static func == (lhs: ScrollContentReply, rhs: ScrollContentReply) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

// MARK: - Scroll-To Requests

/// One programmatic scroll request: the target row's stable identity key
/// (a `ForEach` element id, stringified exactly as identity keys are) and
/// the SwiftUI-parity anchor. Created by ``ScrollViewProxy/scrollTo(_:anchor:)``,
/// parked on the ``ScrollViewHandler`` until the next render pass, then
/// carried down inside ``ScrollContentWindow``.
struct ScrollToRequest: Sendable, Hashable {
    /// The target row's stable identity key.
    var key: String

    /// Where the target lands in the viewport: `nil` is SwiftUI's "minimal
    /// movement to make it visible — none if it already is"; otherwise the
    /// anchor's `y` aligns the row's unit point with the viewport's
    /// (0 = top, 0.5 = centre, 1 = bottom).
    var anchor: UnitPoint?

    /// One row of headroom per edge when the ScrollView's "N more
    /// above/below" indicators can replace the viewport's first/last line
    /// (indicators active, no scrollbar) — without it, a `.top` seek lands
    /// the target exactly under the indicator. Stamped by the ScrollView;
    /// the reveal snap applies the same reservation.
    var topInset = 0
    var bottomInset = 0

    /// The window offset that realises this request for a row of
    /// `rowHeight` cells whose top sits at content-space `targetY`,
    /// clamped to the scrollable range. Shared by every seek path so the
    /// anchor semantics cannot drift between them.
    func windowOffset(
        targetY: Int, rowHeight: Int, currentOffset: Int,
        viewportHeight: Int, totalHeight: Int
    ) -> Int {
        // Indicator headroom mirrors the reveal snap: a pad is charged only
        // when that edge's indicator will actually show at the destination
        // (offset 0 has no "more above"; the very bottom no "more below").
        let topPad = (topInset > 0 && targetY > 0) ? 1 : 0
        let bottomBase = targetY + rowHeight - viewportHeight
        let bottomPad = (bottomInset > 0 && bottomBase + viewportHeight < totalHeight) ? 1 : 0
        let raw: Int
        if let anchor {
            let slack = viewportHeight - topPad - bottomPad - rowHeight
            raw = targetY - topPad - Int((Double(slack) * anchor.y).rounded())
        } else {
            // Minimal movement: visible means within the CURRENT frame's
            // indicator-clipped band, exactly as the reveal fire condition
            // defines it.
            let topShown = (topInset > 0 && currentOffset > 0) ? 1 : 0
            let bottomShown =
                (bottomInset > 0 && currentOffset + viewportHeight < totalHeight) ? 1 : 0
            if targetY < currentOffset + topShown {
                raw = targetY - topPad
            } else if targetY + rowHeight > currentOffset + viewportHeight - bottomShown {
                raw = bottomBase + bottomPad
            } else {
                raw = currentOffset
            }
        }
        return max(0, min(raw, max(0, totalHeight - viewportHeight)))
    }
}
