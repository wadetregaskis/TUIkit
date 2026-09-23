//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollViewReveal.swift
//
//  Reveal-on-focus for ``_ScrollViewCore``: when focus moves (or the focused
//  control consumes a key), snap the viewport so the focused control is
//  actually visible — accounting for the indicator rows that replace the
//  viewport's edge lines, and for Stage-6 sliced content whose regions are
//  band-local.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension _ScrollViewCore {

    /// "Follow the focused control" — snap the viewport back to the focused
    /// control when focus just moved (Tab / click / programmatic) or the
    /// focused control just consumed a key (it was poked via the keyboard
    /// while wheel-scrolled off-screen). Focus moves are detected by comparing
    /// `focusManager.currentFocusedID`, keyboard pokes by comparing
    /// `focusManager.focusedInteractionGeneration` (bumped inside
    /// `FocusManager.dispatchKeyEvent` when the focused handler consumes a
    /// key), each against the value seen at the previous render. Wheel
    /// scrolling changes neither, so peek mode (scroll the focused control
    /// off-screen, no snap-back) is preserved naturally.
    ///
    /// This is a render-pass-only side effect and is skipped while measuring:
    /// `renderToBuffer` runs several times per frame in measuring mode, and
    /// during those passes the inner controls do NOT emit their hit-test
    /// regions (they gate on `!isMeasuring`), so the focused control's region
    /// is absent. If the detection ran while measuring it would see "focus
    /// changed", update its bookkeeping WITHOUT being able to scroll, and the
    /// real render would then see no change and never snap — so a focused
    /// control below the fold (a Slider after some Buttons, say) would never
    /// scroll into view. Gating keeps the signal intact for the one render
    /// that can act on it.
    /// `suppressed` skips the snap itself while still updating the change-
    /// detection baselines: on a `scrollTo` frame the programmatic scroll
    /// must win over the reveal heuristic (the triggering Button both holds
    /// focus and just consumed a key — the classic snap conditions — and an
    /// un-suppressed snap would yank the viewport straight back to it), but
    /// the baselines must advance or the NEXT frame would fire the deferred
    /// snap and undo the scroll anyway.
    /// - Returns: Whether the snap MOVED the offset this frame — the caller
    ///   stamps the pursuit with the frame's final, settled offset via
    ///   ``settleRevealPursuit(armed:handler:context:)`` once coverage,
    ///   re-glue, and clamping have all had their say. Stamping here, with
    ///   the raw write, made the pursuit read its own clamped-next-frame
    ///   offset as a foreign scroll and cancel one hop in.
    @discardableResult
    func snapViewportToFocusedControl(
        handler: ScrollViewHandler,
        fullBuffer: FrameBuffer,
        viewportHeight: Int,
        regionOriginY: Int = 0,
        indicatorsActive: Bool = true,
        suppressed: Bool = false,
        context: RenderContext
    ) -> Bool {
        let stateStorage = context.stateStorage!
        let lastFocusedKey = StateStorage.StateKey(
            identity: context.identity,
            propertyIndex: StateIndex.lastFocusedID
        )
        let lastFocusedBox: StateBox<LastFocusedIDBox> = stateStorage.storage(
            for: lastFocusedKey, default: LastFocusedIDBox())

        let lastInteractionKey = StateStorage.StateKey(
            identity: context.identity,
            propertyIndex: StateIndex.lastInteractionGen
        )
        let lastInteractionBox: StateBox<LastInteractionGenBox> = stateStorage.storage(
            for: lastInteractionKey, default: LastInteractionGenBox())

        guard !context.isMeasuring else { return false }

        // No focus system → nothing to reveal-on-focus.
        guard let focusManager = context.environment.focusManager else { return false }
        // Usually "what has the focus", but a subtree may name its own target
        // instead — an open pop-up menu owns an ordinal rather than a focus id,
        // and its highlighted row still has to be scrolled into view.
        let currentFocusedID = context.environment.revealTargetID ?? focusManager.currentFocusedID
        let currentInteractionGen = focusManager.focusedInteractionGeneration

        // The third trigger: the viewport itself changed size. A terminal
        // resize (or a split-view divider moving, or a disclosure opening
        // above — hence GEOMETRY, not SIGWINCH) leaves `scrollOffset` a valid
        // number that now means something else, and the focused control can
        // end up off screen with nothing to bring it back.
        //
        // Deliberately the minimum deviation: the reveal already scrolls as
        // little as it can, and everything else about a resize keeps its
        // soft top-left pin. Content only moves when it must — and then only
        // as far as it must — rather than everything shifting to preserve a
        // proportional position that means little once the content re-flows
        // at a new width.
        let viewportKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.lastViewport)
        let lastViewportBox: StateBox<LastViewportBox> = stateStorage.storage(
            for: viewportKey, default: LastViewportBox())
        let viewport = (width: context.availableWidth, height: viewportHeight)
        // The first sighting is not a change: nothing was on screen to keep.
        let viewportJustChanged = lastViewportBox.value.value.map { $0 != viewport } ?? false
        lastViewportBox.value.value = viewport

        let focusJustChanged = currentFocusedID != lastFocusedBox.value.value
        let interactionJustFired = currentInteractionGen != lastInteractionBox.value.value

        // The pursuit (see ``ScrollViewHandler/revealPursuitOffset``): a snap toward an off-band row
        // scrolls to an ESTIMATED position and can land short, and with focus
        // unchanged nothing used to re-check — the viewport parked one band
        // away. Pursue while the last snap's own write is still the offset
        // (any other writer — a wheel peek, a scrollTo — wins and ends it)
        // and the target remains outside the visible band.
        let pursuing = handler.revealPursuitOffset == handler.scrollOffset
        if handler.revealPursuitOffset != nil, !pursuing {
            handler.revealPursuitOffset = nil
        }
        if suppressed { handler.revealPursuitOffset = nil }

        let shouldSnap =
            focusJustChanged || interactionJustFired || viewportJustChanged || pursuing

        if shouldSnap, !suppressed,
           let focusedID = currentFocusedID,
           let region = fullBuffer.revealTarget(
               focusID: focusedID, wholeControl: focusJustChanged)
        {
            // Sliced content (Stage 6): the buffer's regions are band-local;
            // rebase them into content space before comparing to the offset.
            let regionTop = region.top + regionOriginY
            let regionBottom = regionTop + region.height
            let viewportTop = handler.scrollOffset
            let viewportBottom = handler.scrollOffset + viewportHeight

            // With the text indicator style the visible buffer overwrites its
            // top and / or bottom rows with the 'N more above / below' chrome
            // whenever there's content off-screen in that direction. Reserve a
            // row for those indicators when computing the target scrollOffset,
            // else the snap puts the focused control on the row the indicator
            // then covers. The decision is bidirectional: after snapping there
            // is still content above iff scrollOffset > 0 and below iff
            // scrollOffset + viewportHeight < contentHeight.
            //
            // The FIRE condition must be indicator-aware too: a region whose
            // only line lands exactly on the viewport's first/last row is
            // inside the viewport by cell math yet INVISIBLE — that row is
            // replaced by the indicator. Without this, a focused row could
            // rest stably hidden behind "▼ N more below" and, focus being
            // unchanged, no later frame would ever re-snap.
            // Indicators need 3+ viewport rows (content always wins the
            // last lines — see applyScrollChrome), and the snap's
            // visibility math must agree or it reserves headroom for
            // chrome that never renders.
            let indicatorsFit = viewportHeight >= 3
            let topIndicatorShows =
                indicatorsActive && indicatorsFit && viewportTop > 0
            let bottomIndicatorShows =
                indicatorsActive && indicatorsFit
                && viewportBottom < handler.contentHeight
            // The follow margin widens both the fire condition and the snap
            // targets below, so the revealed control keeps that much context
            // visible beyond it (see ScrollFollowMargin). Regions as tall as
            // the viewport skip it — they fill the window regardless.
            let margin =
                region.height >= viewportHeight
                ? 0
                : context.environment.scrollFollowMargin
                    .resolvedLines(viewportLines: viewportHeight)
            let visibleTop = viewportTop + (topIndicatorShows ? 1 : 0) + margin
            let visibleBottom = viewportBottom - (bottomIndicatorShows ? 1 : 0) - margin

            let offsetBeforeSnap = handler.scrollOffset
            if regionTop < visibleTop || (regionBottom > visibleBottom && region.height >= viewportHeight) {
                // Scroll-up: align the region's top with viewportTop, leaving
                // 1 row of headroom for the top indicator when one appears.
                // A region TALLER than the viewport (a focused Table/List
                // bigger than the visible area) also top-aligns when reached
                // by scrolling down: its header row is what identifies the
                // control, so show its top rather than its tail.
                // Headroom is gated on `indicatorsActive` like the fire
                // condition above: a scrollbar supersedes the text
                // indicators, so reserving a row for them would over-scroll
                // every reveal by exactly one line.
                let proposed = regionTop - margin
                let topIndicatorRow =
                    (indicatorsActive && indicatorsFit && proposed > 0) ? 1 : 0
                handler.scrollOffset =
                    max(0, min(handler.maxOffset, proposed - topIndicatorRow))
            } else if regionBottom > visibleBottom {
                // Scroll-down: align the region's bottom with viewportBottom,
                // leaving 1 row for the bottom indicator if one appears.
                let proposed = regionBottom - viewportHeight + margin
                let bottomIndicatorWouldAppear =
                    indicatorsActive && indicatorsFit
                    && (proposed + viewportHeight < handler.contentHeight)
                handler.scrollOffset = max(
                    0,
                    min(
                        handler.maxOffset,
                        proposed + (bottomIndicatorWouldAppear ? 1 : 0)
                    )
                )
            }
            // The overscroll slide (`applyOverscroll`) is drawn on the finished
            // viewport AFTER this, and every number above is unslid geometry,
            // so an excursion left standing moves the control just placed. A
            // push past the top hides the viewport's LAST rows, which is where
            // a scroll-down reveal aims; one past the bottom hides the first,
            // where a scroll-up reveal aims. A Tab after a push revealed its
            // control straight off the screen — and with the unslid target
            // reading as visible, no later frame re-snapped. `List` and `Table`
            // clear in `ensureFocusedItemVisible`; this twin never did.
            //
            // Not on every snap, though. A resize, or a Tab to a control the
            // push leaves on screen, is no reason to cancel a push the user
            // still holds (`ScrollOverscrollState.resolve` keeps a legal one
            // through a resize on purpose). Dropped when the snap MOVED the
            // offset, which aimed the target at an exact line, or when the
            // rows the slide pushes off include the target — whether or not
            // the snap itself saw anything to do: a target inside the unslid
            // window fires nothing above and is still slid out of sight.
            let overscroll = handler.overscrollState
            if overscroll.excursion != 0,
                handler.scrollOffset != offsetBeforeSnap
                    || overscroll.pushesOff(
                        top: regionTop, bottom: regionBottom,
                        shownTop: viewportTop + (topIndicatorShows ? 1 : 0),
                        shownBottom: viewportBottom - (bottomIndicatorShows ? 1 : 0))
            {
                handler.clearOverscroll()
            }
            // A FOCUS-JUMP snap that MOVED arms (or continues) the pursuit
            // for the next frame, where refined estimates may relocate the
            // target; one that did not — the target is visible, or the clamp
            // has no further to give — is convergence, and the pursuit ends.
            // Ending on a stalled hop is also what keeps this from
            // re-rendering forever against an unreachable estimate. An
            // INTERACTION snap never arms: its target rendered this frame
            // and the hop is exact — pursuing it made the reveal re-snap a
            // focused List/Table to its own top every frame, fighting the
            // control's internal cursor-follow.
            lastFocusedBox.value.value = currentFocusedID
            lastInteractionBox.value.value = currentInteractionGen
            return (focusJustChanged || pursuing) && handler.scrollOffset != offsetBeforeSnap
        }
        lastFocusedBox.value.value = currentFocusedID
        lastInteractionBox.value.value = currentInteractionGen
        return false
    }

    /// A coverage render refines the content-height estimate, which can move
    /// maxOffset out from under the earlier re-glue — leaving the view off the
    /// tail, where the NEXT frame's glue condition (offset >= maxOffset) would
    /// silently release the follow. Re-glue against the refined number, and
    /// again after the render that number calls for, until the tail holds
    /// still.
    ///
    /// Once used to be enough when the refined estimate was close: the guard
    /// render's band then reaches the tail, whose totals are exact (§3:
    /// estimates cover only what was never rendered). A burst of wrapped lines
    /// is not close. The band at the refined tail reaches only a row past the
    /// viewport, the rows beyond it are still estimates, the total grows again,
    /// and the view was left short of the end. The follow then let go, and a
    /// log stopped following itself mid-burst. Each pass measures rows the last
    /// one estimated, so this converges; the bound only guards against an
    /// estimator that never does, and costs nothing on the usual frame, which
    /// stops after one pass because its band already covered the tail.
    func reglueToRefinedTail(
        handler: ScrollViewHandler, fullBuffer: inout FrameBuffer,
        contentSlice: inout (originY: Int, totalHeight: Int, totalIsEstimate: Bool)?,
        contentWidth: Int, viewportHeight: Int,
        horizontal: Bool, context: RenderContext
    ) {
        for _ in 0..<Self.reglueLimit {
            handler.scrollOffset = handler.maxOffset
            coverSnappedViewport(
                handler: handler, fullBuffer: &fullBuffer, contentSlice: &contentSlice,
                contentWidth: contentWidth, viewportHeight: viewportHeight,
                horizontal: horizontal, context: context)
            if handler.scrollOffset >= handler.maxOffset { return }
        }
    }

    /// How many times ``reglueToRefinedTail`` re-renders chasing a tail whose
    /// estimate keeps growing, before it settles for the next frame.
    static var reglueLimit: Int { 4 }

    /// Records the reveal pursuit's memory for the next frame: the offset the
    /// frame SETTLED on when the snap moved it, or nothing when it did not.
    ///
    /// Called after ``coverSnappedViewport``, the tail re-glue, and a final
    /// clamp — everything that legitimately adjusts the offset within the
    /// frame — so that next frame's "did anyone else scroll?" comparison sees
    /// the number that will actually still be there. See ``ScrollViewHandler/revealPursuitOffset``.
    func settleRevealPursuit(armed: Bool, handler: ScrollViewHandler, context: RenderContext) {
        guard !context.isMeasuring else { return }
        guard armed else {
            // The overwhelmingly common frame: no pursuit, nothing to record.
            // Touch nothing — the extra unconditional clamp this used to do
            // showed up as ~1% of megalist's frame.
            if handler.revealPursuitOffset != nil { handler.revealPursuitOffset = nil }
            return
        }
        // The clamp against the coverage-refined content height is part of
        // what this frame's offset really is.
        handler.clampScrollOffset()
        handler.revealPursuitOffset = handler.scrollOffset
    }

    /// Re-renders the content at the (post-snap) scroll offset when the
    /// rendered band no longer covers the visible rows.
    ///
    /// A snap can jump beyond the band: a far focus target renders OFF-band
    /// (only its hit regions are grafted in, `graftOffBandRow`) precisely so
    /// the band stays compact, which means the snapped offset may land in a
    /// gap the band never materialised. Rendering once more at the new
    /// offset — O(window), and only on focus-jump frames — lets this same
    /// frame show the revealed row. One frame of blank viewport is not an
    /// acceptable alternative: with no new event arriving, the render loop
    /// would not redraw, and the blank would simply stay.
    func coverSnappedViewport(
        handler: ScrollViewHandler,
        fullBuffer: inout FrameBuffer,
        contentSlice: inout (originY: Int, totalHeight: Int, totalIsEstimate: Bool)?,
        contentWidth: Int, viewportHeight: Int, horizontal: Bool,
        context: RenderContext
    ) {
        guard !context.isMeasuring, let slice = contentSlice else { return }
        let bandEnd = slice.originY + fullBuffer.height
        let visibleEnd = min(handler.scrollOffset + viewportHeight, handler.contentHeight)
        guard handler.scrollOffset < slice.originY || visibleEnd > bandEnd else { return }
        let recovered = renderedContent(
            contentWidth: contentWidth, viewportHeight: viewportHeight,
            horizontal: horizontal, verticalScrollOffset: handler.scrollOffset,
            context: context)
        (fullBuffer, contentSlice) = (recovered.buffer, recovered.slice)
        handler.contentHeight = contentSlice?.totalHeight ?? fullBuffer.height
        handler.contentHeightIsEstimate = contentSlice?.totalIsEstimate ?? false
        handler.clampScrollOffset()
    }
}

// MARK: - Overriding what gets revealed

private struct RevealTargetIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The hit-test region a scroller in this subtree should keep on screen,
    /// instead of whatever holds the focus.
    ///
    /// Set by a presentation whose "selected thing" is not a focus stop — today
    /// only an open pop-up menu, whose highlight is an ordinal (see
    /// ``MenuPopupController``). Everything downstream of the reveal is
    /// unchanged: it is still a region id matched against the rendered buffer,
    /// so a subtree that sets this gets exactly the scrolling behaviour a
    /// focused control would have got.
    var revealTargetID: String? {
        get { self[RevealTargetIDKey.self] }
        set { self[RevealTargetIDKey.self] = newValue }
    }
}
