//  🖥️ TUIKit — Terminal UI Kit for Swift
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
    func snapViewportToFocusedControl(
        handler: ScrollViewHandler,
        fullBuffer: FrameBuffer,
        viewportHeight: Int,
        regionOriginY: Int = 0,
        indicatorsActive: Bool = true,
        suppressed: Bool = false,
        context: RenderContext
    ) {
        let stateStorage = context.environment.stateStorage!
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

        guard !context.isMeasuring else { return }

        // No focus system → nothing to reveal-on-focus.
        guard let focusManager = context.environment.focusManager else { return }
        let currentFocusedID = focusManager.currentFocusedID
        let currentInteractionGen = focusManager.focusedInteractionGeneration

        let focusJustChanged = currentFocusedID != lastFocusedBox.value.value
        let interactionJustFired = currentInteractionGen != lastInteractionBox.value.value
        let shouldSnap = focusJustChanged || interactionJustFired

        if shouldSnap, !suppressed,
           let focusedID = currentFocusedID,
           let region = fullBuffer.hitTestRegions.first(where: { $0.focusID == focusedID })
        {
            // Sliced content (Stage 6): the buffer's regions are band-local;
            // rebase them into content space before comparing to the offset.
            let regionTop = region.offsetY + regionOriginY
            let regionBottom = regionTop + region.height
            let viewportTop = handler.scrollOffset
            let viewportBottom = handler.scrollOffset + viewportHeight

            // When showsIndicators is true, the visible buffer overwrites its
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
                indicatorsActive && showsIndicators && indicatorsFit && viewportTop > 0
            let bottomIndicatorShows =
                indicatorsActive && showsIndicators && indicatorsFit
                && viewportBottom < handler.contentHeight
            let visibleTop = viewportTop + (topIndicatorShows ? 1 : 0)
            let visibleBottom = viewportBottom - (bottomIndicatorShows ? 1 : 0)

            if regionTop < visibleTop || (regionBottom > visibleBottom && region.height >= viewportHeight) {
                // Scroll-up: align the region's top with viewportTop, leaving
                // 1 row of headroom for the top indicator when one appears.
                // A region TALLER than the viewport (a focused Table/List
                // bigger than the visible area) also top-aligns when reached
                // by scrolling down: its header row is what identifies the
                // control, so show its top rather than its tail.
                let proposed = regionTop
                let topIndicatorRow =
                    (showsIndicators && indicatorsFit && proposed > 0) ? 1 : 0
                handler.scrollOffset =
                    max(0, min(handler.maxOffset, proposed - topIndicatorRow))
            } else if regionBottom > visibleBottom {
                // Scroll-down: align the region's bottom with viewportBottom,
                // leaving 1 row for the bottom indicator if one appears.
                let proposed = regionBottom - viewportHeight
                let bottomIndicatorWouldAppear =
                    showsIndicators && indicatorsFit
                    && (proposed + viewportHeight < handler.contentHeight)
                handler.scrollOffset = max(
                    0,
                    min(
                        handler.maxOffset,
                        proposed + (bottomIndicatorWouldAppear ? 1 : 0)
                    )
                )
            }
        }
        lastFocusedBox.value.value = currentFocusedID
        lastInteractionBox.value.value = currentInteractionGen
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
