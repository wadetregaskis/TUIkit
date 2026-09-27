//  🖥️ TUIkit — Terminal UI Kit for Swift
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
    /// Equality and hashing deliberately **exclude** ``reply``.
    ///
    /// That slot is a per-render mailbox — `ScrollContentReply()` is freshly
    /// allocated on every pass — so synthesised conformance made two windows
    /// describing the *same* visible slice compare and hash differently every
    /// frame. Anything keyed on the environment (the render memo) therefore
    /// saw every subtree under a `ScrollView` change on every frame.
    ///
    /// A window is identified by what it *describes* — the offset, the
    /// viewport, whose content it addresses — not by which mailbox happens to
    /// be attached for the reply to travel back through.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.offset == rhs.offset && lhs.viewportHeight == rhs.viewportHeight
            && lhs.contentIdentity == rhs.contentIdentity && lhs.edgeInset == rhs.edgeInset
            && lhs.reportsIDAt == rhs.reportsIDAt && lhs.seek == rhs.seek
            && lhs.linesAbove == rhs.linesAbove && lhs.linesBelow == rhs.linesBelow
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(offset)
        hasher.combine(viewportHeight)
        hasher.combine(contentIdentity)
        hasher.combine(edgeInset)
        hasher.combine(reportsIDAt)
        hasher.combine(seek)
        hasher.combine(linesAbove)
        hasher.combine(linesBelow)
    }

    /// The scroll offset in the coordinates of the stack that consumes this
    /// window: the scroll view's offset less ``linesAbove``. So it is negative
    /// while any line drawn above the stack is on screen, and every stack path
    /// takes a negative offset as "the band starts at row 0".
    var offset: Int
    var viewportHeight: Int

    /// The identity of the ScrollView's direct content. A windowed stack
    /// consumes this window only when its own identity is a single-child
    /// descent from here (`ViewIdentity/isDirectDescent(from:)`): a stack
    /// that is one sibling among several is NOT at the scroll origin, and
    /// windowing there would blank the wrong rows. `nil` (tests, direct
    /// injection) means "trust the publisher" and consume unconditionally.
    var contentIdentity: ViewIdentity?

    /// Whether a view at `identity` is reached from the scroll view's content
    /// by single-child steps (``contentIdentity``), and so is at the content's
    /// origin: a stack there consumes this window, and a view drawing lines
    /// around its content there relays it (`ScrollWindowRelay`).
    func isAtOrigin(_ identity: ViewIdentity) -> Bool {
        guard let contentIdentity else { return true }
        return identity.isDirectDescent(from: contentIdentity)
    }

    /// The render-pass reply slot (Stage 6): the stack reports the compact
    /// slice it actually rendered, so the ScrollView can clip a band
    /// instead of a full-height canvas. `nil` (tests, measure passes) keeps
    /// the stack emitting the classic full-height buffer.
    var reply: ScrollContentReply?

    /// One line of headroom per edge when the "N more above/below" indicators
    /// can replace the viewport's first/last line — the same reservation
    /// ``ScrollToRequest/topInset`` makes for seeks, carried on the window
    /// because a DESIGNATED anchor reveals rows with no request to stamp.
    /// Without it, designating an off-screen row lands it exactly under an
    /// indicator, where it is invisible however correctly it was placed.
    var edgeInset = 0

    /// Where in the viewport to sample the row whose id is reported back
    /// through ``ScrollContentReply/anchorID``, or `nil` to sample nothing.
    ///
    /// The row reported is the first whose bottom lies past the sampled line
    /// (``sampleY(at:contentBelow:)``), on every path a stack takes: a line in
    /// the gap between two rows belongs to the row below it.
    ///
    /// Set only when something is actually listening (a `.scrollPosition(id:)`
    /// binding): the sample costs an `anyID(at:)` per frame, and a scroll view
    /// nobody is asking should not pay it.
    var reportsIDAt: UnitPoint?

    /// The content-space y that `unit` names within the VISIBLE band.
    ///
    /// Not simply `offset + unit.y × height`: the "N more above/below"
    /// indicators overwrite the viewport's first and last line, so those rows
    /// are on the canvas but not on the screen. Reporting one as "the row you
    /// are looking at" would name a row nobody can see — which is exactly the
    /// row a `.top` seek deliberately steps past.
    ///
    /// Only where they DO overwrite, which is what `edgeInset` says. Under
    /// `.visible` the pair is reserved outside this window, whose
    /// `viewportHeight` is then just the lines between them; under three lines
    /// neither is drawn. Either way the inset is `0` and nothing is charged here.
    ///
    /// Each indicator is charged only when it actually SHOWS: the top one
    /// when scrolled down, the bottom one when the caller says content
    /// remains below. At the very bottom the last viewport line is readable
    /// content — charging it anyway sampled one row too high, so a
    /// bottom-anchored `.scrollPosition` never reported the final row.
    ///
    /// Asked in the scroll view's content, not the stack's: the top indicator
    /// shows whenever the CONTENT is scrolled, a section's header included
    /// (``linesAbove``), and `contentBelow` counts a footer below the stack
    /// (``hasContentBelow(stackBottom:)``). The line it returns is the stack's.
    func sampleY(at unit: UnitPoint, contentBelow: Bool) -> Int {
        let topPad = (edgeInset > 0 && offset + linesAbove > 0) ? 1 : 0
        let bottomPad = (edgeInset > 0 && contentBelow) ? 1 : 0
        let usable = max(1, viewportHeight - topPad - bottomPad)
        return offset + topPad + Int((Double(usable - 1) * unit.y).rounded(.down))
    }

    /// A pending programmatic scroll (``ScrollViewProxy/scrollTo(_:anchor:)``).
    /// The stack that locates the key renders AT the request's resolved
    /// offset — so the very frame that carries the request shows the target
    /// — and reports the offset via ``ScrollContentReply/seekResolvedOffset``
    /// for the ScrollView to adopt.
    var seek: ScrollToRequest?

    /// The scroll content's lines above the stack that consumes this window,
    /// and below it: a `Section`'s header and footer, which the section draws
    /// around a lazy stack at its own identity, so the stack is still reached
    /// from the content by single-child steps and still bands itself. `0` for a
    /// stack that is the whole content.
    ///
    /// The section hands its content this window moved into the stack's
    /// coordinates (``beneath(linesAbove:linesBelow:reply:)``) and moves the
    /// reply back into its own. Until it did, the stack banded itself as if it
    /// were all the content: under a header every row was drawn a line below
    /// where the window put it and the content's last line was never shown,
    /// and over a footer the scroll view took the stack's height for the
    /// content's and never showed the footer.
    ///
    /// These are what the stack cannot see and a seek, the read-back sample and
    /// a held row must: whether the content is scrolled at all, whether any of
    /// it lies below the viewport, and how far it can scroll — each asked of
    /// the content (``sampleY(at:contentBelow:)``,
    /// ``offset(realising:targetY:rowHeight:stackHeight:)``,
    /// ``scrollableOffsets(stackHeight:)``). Asked of the stack alone, a `.top`
    /// seek to the first row under a header left it under the "more above"
    /// indicator, and a seek could not scroll the header or the footer into
    /// view. The anchored window reads ``linesBelow`` at its end as well: the
    /// footer, not the viewport's bottom, is where a jump to the end puts the
    /// last row, and a footer taller than the viewport may take that row off
    /// screen.
    var linesAbove = 0
    var linesBelow = 0

    /// Whether any of the scroll content lies below the viewport, for a stack
    /// whose own content ends at `stackBottom` (in its coordinates): its rows,
    /// or what is drawn below it (``linesBelow``).
    func hasContentBelow(stackBottom: Int) -> Bool {
        offset + viewportHeight < stackBottom + linesBelow
    }

    /// The offsets the scroll content can take, in the stack's coordinates:
    /// from the top of what is drawn above the stack to the viewport's last
    /// full screen of what is drawn below it.
    func scrollableOffsets(stackHeight: Int) -> ClosedRange<Int> {
        -linesAbove...max(-linesAbove, stackHeight + linesBelow - viewportHeight)
    }

    /// The offset that realises `seek` for a row of `rowHeight` whose top is at
    /// `targetY`, both in the stack's coordinates — asked of the whole scroll
    /// content (``ScrollToRequest/windowOffset(targetY:rowHeight:currentOffset:viewportHeight:totalHeight:)``,
    /// whose indicator headroom and clamp are the content's) and answered in
    /// the stack's.
    func offset(
        realising seek: ScrollToRequest, targetY: Int, rowHeight: Int, stackHeight: Int
    ) -> Int {
        seek.windowOffset(
            targetY: targetY + linesAbove, rowHeight: rowHeight,
            currentOffset: offset + linesAbove, viewportHeight: viewportHeight,
            totalHeight: linesAbove + stackHeight + linesBelow) - linesAbove
    }

    /// This window as content drawn `above` lines further down, with `below`
    /// lines drawn under it, sees it — a section's content, between its header
    /// and its footer — answering into `reply`.
    func beneath(linesAbove above: Int, linesBelow below: Int, reply: ScrollContentReply?) -> Self {
        var window = self
        window.offset -= above
        window.linesAbove += above
        window.linesBelow += below
        window.reply = reply
        return window
    }
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
    /// Whether the slice starts with the stack's first row, and whether it
    /// ends with its last: what a view drawing lines of its own around the
    /// stack reads to know whether they join the band (`ScrollWindowRelay`).
    /// The origin cannot say it: the anchored window places its rows from an
    /// anchor, by estimate — a row held by `.anchorPosition(.row)` among them
    /// — so its first row need not sit at 0, nor the row at 0 be its first.
    var sliceHoldsFirstRow = false
    var sliceHoldsLastRow = false
    /// The id of the row under ``ScrollContentWindow/reportsIDAt``, when one
    /// was asked for and the provider has ids to give. This is the READ half
    /// of `.scrollPosition(id:)`: the seek machinery matches on stringified
    /// keys, but a binding has to be handed the value back.
    var anchorID: AnyHashable?

    /// The window offset the stack rendered at in answer to
    /// ``ScrollContentWindow/seek`` — the ScrollView adopts it as its
    /// scroll position. `nil` when there was no request or the key wasn't
    /// found (an unknown id is a no-op, as in SwiftUI).
    var seekResolvedOffset: Int?

    /// The content lines a FULL-HEIGHT reply drew for real, when it drew only
    /// some: the full walk under 256 rows (`renderViewportWindow`) returns the
    /// whole canvas, but only the rows around the offset it was given are
    /// drawn and the rest are blank placeholders. A slice needs no such
    /// report — its buffer IS the band — so this is set only when
    /// ``sliceOriginY`` is not.
    ///
    /// What lets the ScrollView see that an offset it moved AFTER the render —
    /// the bottom re-glue on a terminal that shrank, a focus snap — shows lines
    /// the canvas never drew, and draw them (`coverSnappedViewport`). Without
    /// it that frame showed blank lines where the rows belong, and no later
    /// frame came to draw them unless something else changed.
    ///
    /// Open-ended past the last row (`Int.max`): below it there is nothing to
    /// draw, so a line there is drawn correctly by being blank.
    var drawnLines: Range<Int>?

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
    /// (drawn, and drawn OVER the content: not a scrollbar, and not the pair
    /// `.visible` reserves outside it) — without it, a `.top` seek lands
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
