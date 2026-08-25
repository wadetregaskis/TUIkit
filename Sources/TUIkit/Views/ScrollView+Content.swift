//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollView+Content.swift
//
//  The content half of `_ScrollViewCore`: measuring the content's natural
//  extents, rendering it through the windowing/slicing machinery, and
//  splicing the "N more" indicator rows. Split from `ScrollView.swift`,
//  which had reached the file-length limit; the position half already lives
//  in `ScrollView+ScrollPosition.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore
import TUIkitView

extension _ScrollViewCore {
    /// The content's natural extents at a candidate viewport, WITHOUT building a
    /// buffer — the same measures `renderedContent` uses to size its render, so the
    /// scrollbar-reservation decision matches what will actually be drawn.
    ///
    /// `height` is the rendered buffer's height, `max(viewportHeight,
    /// naturalHeight)`: the natural height comes from ``measureNaturalExtent`` — a
    /// stack's measure clamps its report to `availableHeight`, so any FIXED budget
    /// is a ceiling on how tall content can be, and the ladder grows the budget
    /// until the content stops filling it instead of guessing one — under an
    /// unspecified height proposal, which collapses a flexible filler such as
    /// `Spacer()` to its minimum. (Rendering into a fixed tall canvas would instead
    /// let a Spacer expand to thousands of lines and report a phantom overflow.)
    /// `width` is the render width: the content's natural width when horizontal
    /// scrolling is on — so it can be wider than the viewport and scroll, rather
    /// than wrapping to fit — else `contentWidth`.
    ///
    /// Measures under the content's OWN child identity, distinct from the
    /// ScrollView's: otherwise a directly-stateful content view would bind its
    /// `@State` (property indices 0, 1, …) at the ScrollView's identity, colliding
    /// with the ScrollView's own state keys (handler, focusID, …). `renderedContent`
    /// uses the same identity, so state hydrates consistently.
    func contentExtents(
        contentWidth: Int, viewportHeight: Int, horizontal: Bool, context: RenderContext
    ) -> (width: Int, height: Int) {
        var measureContext = context.withChildIdentity(type: Content.self)
        // Publish the visible viewport so descendants can fit to it instead of the
        // (unbounded, below) measure canvas — e.g. Image's `.imageFitTarget(.viewport)`.
        measureContext.environment.scrollViewportSize = ScrollViewportSize(
            width: contentWidth, height: viewportHeight)
        measureContext.availableHeight = naturalExtentStartingBudget(forVisible: viewportHeight)

        let renderWidth: Int
        if horizontal {
            let natural = measureNaturalExtent(
                content, along: .horizontal,
                proposal: ProposedSize(width: nil, height: nil),
                context: measureContext,
                startingBudget: naturalExtentStartingBudget(forVisible: contentWidth))
            renderWidth = max(contentWidth, natural.width)
        } else {
            renderWidth = contentWidth
        }

        measureContext.availableWidth = renderWidth
        let natural = measureNaturalExtent(
            content, along: .vertical,
            proposal: ProposedSize(width: renderWidth, height: nil),
            context: measureContext,
            startingBudget: naturalExtentStartingBudget(forVisible: viewportHeight))
        return (width: renderWidth, height: max(viewportHeight, natural.height))
    }

    /// Renders the content to its full (unwindowed) buffer, sized via
    /// ``contentExtents(contentWidth:viewportHeight:horizontal:context:)`` so a
    /// flexible filler behaves well: a Spacer expands only as far as the viewport
    /// (spreading content across the visible area when it fits — e.g.
    /// `VStack { Text; Spacer; Text }` puts the two at top and bottom) and collapses
    /// when the content is taller, so it scrolls without the filler forcing extra
    /// height.
    ///
    /// - Parameter settledExtents: The extents `resolveScrollbars` already
    ///   measured at these exact dimensions, when it has them. Handed down
    ///   rather than re-derived: both this and the reservation loop's final
    ///   round ask ``contentExtents`` the same question with the same numbers,
    ///   and each answer is a walk of the natural-extent budget ladder over the
    ///   whole content. `nil` re-measures, which is what the direct callers
    ///   (tests, and the non-`.automatic` scrollbar path) get.
    func renderedContent(
        contentWidth: Int, viewportHeight: Int, horizontal: Bool,
        verticalScrollOffset: Int, seek: ScrollToRequest? = nil, edgeInset: Int = 0,
        handler: ScrollViewHandler? = nil,
        context: RenderContext, settledExtents: (width: Int, height: Int)? = nil
    ) -> (
        buffer: FrameBuffer,
        slice: (originY: Int, totalHeight: Int, totalIsEstimate: Bool)?,
        seekOffset: Int?
    ) {
        let extents =
            settledExtents
            ?? contentExtents(
                contentWidth: contentWidth, viewportHeight: viewportHeight,
                horizontal: horizontal, context: context)
        var measureContext = context.withChildIdentity(type: Content.self)
        measureContext.environment.scrollViewportSize = ScrollViewportSize(
            width: contentWidth, height: viewportHeight)
        // Publish the visible vertical slice so a direct `LazyVStack` renders only
        // the rows intersecting the viewport (true windowing) rather than every
        // row into the tall canvas. Vertical-only: horizontal scrolling has no
        // row concept (which is also why a `seek` request rides this window and
        // is unsupported on horizontal-capable scroll views). The offset is this
        // frame's already-clamped value; the final clip (`windowedBuffer`) uses
        // the same value, so they agree for stable content. `contentIdentity`
        // restricts consumption to the direct content (a lazy stack under a
        // header is NOT at the scroll origin); the `reply` slot lets the stack
        // return a compact band + metadata (Stage 6) instead of a full-height
        // canvas of mostly blank lines.
        var reply: ScrollContentReply?
        if !horizontal {
            let contentReply = ScrollContentReply()
            reply = contentReply
            measureContext.environment.scrollContentWindow = ScrollContentWindow(
                offset: verticalScrollOffset, viewportHeight: viewportHeight,
                contentIdentity: measureContext.identity,
                reply: contentReply, edgeInset: edgeInset,
                // Only sample when someone is bound to hear it.
                reportsIDAt: context.isMeasuring
                    ? nil : context.environment.scrollPositionBinding?.anchor,
                seek: seek)
        }
        measureContext.availableWidth = extents.width
        measureContext.availableHeight = extents.height
        let buffer = TUIkit.renderToBuffer(content, context: measureContext)
        if let id = reply?.anchorID, let handler, !context.isMeasuring {
            reportVisibleID(id, handler: handler, context: context)
        }
        if let reply, let origin = reply.sliceOriginY, let total = reply.sliceTotalHeight {
            return (buffer, (origin, total, reply.sliceTotalIsEstimate), reply.seekResolvedOffset)
        }
        return (buffer, nil, reply?.seekResolvedOffset)
    }

    // MARK: Windowing

    /// Builds the visible-window buffer from `full`, dropping
    /// overlays and hit-test regions that fall entirely outside
    /// the viewport and shifting the rest up by `scrollOffset`.
    func windowedBuffer(
        full: FrameBuffer,
        scrollOffset: Int,
        viewportHeight: Int,
        viewportWidth: Int,
        horizontalEnabled: Bool,
        horizontalOffset: Int
    ) -> FrameBuffer {
        guard viewportHeight > 0 else {
            return FrameBuffer(lines: [], width: viewportWidth)
        }

        // Slice the visible lines, padding each one to the full
        // viewport width and topping up missing rows so the
        // ScrollView fills the space it was given on BOTH axes.
        // Without the per-line padding the result buffer's
        // effective width would follow the longest line (which
        // might just be a 'N more above' indicator — far
        // shorter than the proposed width). When horizontal scrolling is on, each
        // line is first sliced to the visible column window (carrying SGR state).
        var visibleLines = Array(
            full.lines.dropFirst(scrollOffset).prefix(viewportHeight)
        ).map { line -> String in
            let windowed = horizontalEnabled
                ? line.ansiAwareSlice(visibleStart: horizontalOffset, visibleCount: viewportWidth)
                : line
            return windowed.padToVisibleWidth(viewportWidth)
        }
        if visibleLines.count < viewportHeight {
            let blank = String(repeating: " ", count: viewportWidth)
            visibleLines.append(
                contentsOf: Array(
                    repeating: blank,
                    count: viewportHeight - visibleLines.count
                )
            )
        }

        // Filter + shift overlays. An overlay is kept if its
        // vertical span intersects [scrollOffset, scrollOffset
        // + viewportHeight). Its offsetY is shifted up by
        // scrollOffset so it stays anchored to its content.
        // Centred layers (modals/alerts) are screen-anchored, not
        // content-anchored: they ride through untouched no matter
        // where their attachment point has scrolled to — a presented
        // dialog must not vanish because its trigger scrolled away.
        let viewportTop = scrollOffset
        let viewportBottom = scrollOffset + viewportHeight
        let dx = horizontalEnabled ? -horizontalOffset : 0
        let visibleOverlays = full.overlays.compactMap { overlay -> OverlayLayer? in
            guard !overlay.centered else { return overlay }
            // The overlay's extent includes its ANCHOR (the control spanning
            // `anchorHeight` rows immediately above `offsetY`): a drop-down
            // attached to a control on the LAST visible row starts exactly at
            // `viewportBottom`, and culling it by the popup's own span alone
            // silently discarded it — the root compositor (whose job the
            // flip-above-the-anchor placement is) never saw it, so opening
            // such a picker showed nothing. With no anchor this reduces to
            // the popup's own span, exactly the old test.
            let topY = overlay.offsetY - overlay.anchorHeight
            let bottomY = overlay.offsetY + overlay.content.height
            guard bottomY > viewportTop, topY < viewportBottom else { return nil }
            return overlay.shifted(byX: dx, y: -scrollOffset)
        }

        // Filter + shift hit-test regions, same logic — and TRIM them to the
        // viewport, which the overlay filter above gets for free from
        // `OverlayLayer.placed()`'s own clip but this one has to do itself.
        //
        // The viewport is as final a clip for a region as it is for a line: a
        // control straddling the top edge kept its full height and shifted to a
        // NEGATIVE offsetY, so the parent placed it over rows above the
        // ScrollView, and one straddling the bottom kept rows past the last
        // visible line. Since regions are hit-tested innermost-first, those
        // phantom rows won — a click on a Button sitting above the scroller
        // reached a half-scrolled-off row inside it instead.
        let visibleRegions = full.hitTestRegions.compactMap { region -> HitTestRegion? in
            let topY = region.offsetY
            let bottomY = region.offsetY + region.height
            guard bottomY > viewportTop, topY < viewportBottom else { return nil }
            let clippedTop = max(topY, viewportTop)
            let clippedBottom = min(bottomY, viewportBottom)
            // The X axis clips like the Y axis: a region scrolled part-way
            // off the left kept its full width at a negative offsetX, and
            // one straddling the right kept columns past the viewport —
            // phantom cells that, innermost-first, won clicks meant for
            // whatever actually sat there (the vertical scrollbar included).
            let leftX = region.offsetX + dx
            let rightX = leftX + region.width
            guard rightX > 0, leftX < viewportWidth else { return nil }
            let clippedLeft = max(0, leftX)
            let clippedRight = min(viewportWidth, rightX)
            var clipped = HitTestRegion(
                offsetX: clippedLeft,
                offsetY: clippedTop - scrollOffset,
                width: clippedRight - clippedLeft,
                height: clippedBottom - clippedTop,
                handlerID: region.handlerID,
                // MUST be carried: reveal-on-focus finds its target by
                // focusID, so dropping it here (the parameter defaults to
                // nil, so the omission was silent) made an ENCLOSING
                // ScrollView unable to ever locate a focused control that
                // lives inside THIS one — nested scroll views could not
                // reveal. `OverlayLayer.placed()` carries it for the same
                // reason.
                focusID: region.focusID
            )
            // The clip above throws away where the region BEGINS, which is not
            // the same question as where it can be clicked. A destination that
            // wraps a scrolled page starts above the viewport, and a drop point
            // localised against its clipped top came out short by exactly the
            // scroll offset — the poof puff drawn that far up the screen.
            // Accumulated, so nesting composes.
            clipped.topClip = region.topClip + (clippedTop - topY)
            clipped.leftClip = region.leftClip + (clippedLeft - leftX)
            clipped.revealOutsetTop = region.revealOutsetTop
            clipped.revealOutsetBottom = region.revealOutsetBottom
            return clipped
        }

        // Animated runs are a claim about single rows, so unlike a region they
        // are not clipped but kept or dropped whole: a run scrolled out of the
        // viewport must stop, or it would repaint on a clock over whatever row
        // took its place. Survivors move into viewport coordinates with the
        // lines they describe.
        let visibleRuns = full.animatedCells.compactMap { run -> AnimatedCellRun? in
            guard run.offsetY >= viewportTop, run.offsetY < viewportBottom else { return nil }
            // Horizontally too, and for the same reason: a run carried past
            // either edge keeps repainting at a column that is no longer its
            // own. Off the left it patches at a negative column, which pads the
            // row out to the run's width and makes the line WIDER than the
            // terminal — it then wraps and smears the row below, and the diff
            // writer, which believes that row is untouched, never repairs it.
            let shiftedX = run.offsetX + dx
            guard shiftedX >= 0, shiftedX + run.width <= viewportWidth else { return nil }
            return run.shifted(byX: dx, y: -scrollOffset)
        }

        // Opacity regions clip like hit regions rather than being dropped like
        // runs: a rectangle of faded cells that straddles the viewport edge is
        // still faded for the part of it that shows, and keeping its full
        // height would fade rows belonging to whatever sits outside the
        // scroller.
        let visibleOpacity = full.opacityRegions.compactMap { region -> OpacityRegion? in
            let topY = region.offsetY
            let bottomY = region.offsetY + region.height
            guard bottomY > viewportTop, topY < viewportBottom else { return nil }
            let clippedTop = max(topY, viewportTop)
            let clippedBottom = min(bottomY, viewportBottom)
            var clipped = region
            clipped.offsetY = clippedTop
            clipped.height = clippedBottom - clippedTop
            return clipped.shifted(byX: dx, y: -scrollOffset)
        }

        var result = FrameBuffer(lines: visibleLines, width: viewportWidth)
        result.overlays = visibleOverlays
        result.hitTestRegions = visibleRegions
        result.animatedCells = visibleRuns
        result.opacityRegions = visibleOpacity
        return result
    }

    // MARK: Indicators

    /// Replaces the top and / or bottom lines of `buffer` with
    /// scroll-indicator strings when the content extends past
    /// the visible area. Returns `buffer` unchanged when there
    /// is nothing to scroll to.
    func applyScrollIndicators(
        to buffer: FrameBuffer,
        handler: ScrollViewHandler,
        width: Int,
        palette: any Palette,
        cycle: SelectionEmphasisCycle?,
        locale: Locale
    ) -> FrameBuffer {
        guard buffer.height > 0 else { return buffer }
        guard handler.hasContentAbove || handler.hasContentBelow else {
            return buffer
        }

        var lines = buffer.lines
        // The indicators' own runs, so a focused scroll view breathes them
        // without the page being rendered again on every tick of the clock.
        var runs: [AnimatedCellRun] = []
        /// The rows the indicators overwrite — whatever the content had
        /// animating on them goes with them.
        var replacedRows: Set<Int> = []

        if handler.hasContentAbove, !lines.isEmpty {
            // Indicator rows are padded to full viewport width
            // — without padding the resulting buffer's effective
            // width collapses to the indicator's own length.
            let indicator = renderScrollIndicator(
                direction: .up,
                count: handler.rowsAbove,
                unit: .lines,
                width: width,
                palette: palette,
                approximate: handler.contentHeightIsEstimate,
                cycle: cycle,
                locale: locale
            )
            lines[0] = indicator.text.padToVisibleWidth(width)
            replacedRows.insert(0)
            if let animation = indicator.animation { runs.append(animation) }
        }

        if handler.hasContentBelow, lines.count >= 1 {
            let indicator = renderScrollIndicator(
                direction: .down,
                count: handler.rowsBelow,
                unit: .lines,
                width: width,
                palette: palette,
                approximate: handler.contentHeightIsEstimate,
                cycle: cycle,
                locale: locale
            )
            lines[lines.count - 1] = indicator.text.padToVisibleWidth(width)
            replacedRows.insert(lines.count - 1)
            // The renderer builds every run at row 0 — it does not know which
            // row its caller put the indicator on — so move this one down to
            // the row it was actually drawn on.
            if let animation = indicator.animation {
                runs.append(animation.shifted(byX: 0, y: lines.count - 1))
            }
        }
        var result = buffer.replacingLines(lines)
        // The indicator OVERWROTE those rows, so whatever the content had
        // animating on them is gone with them — a surviving run would repaint a
        // focus ring's cells over the "▲ 3 more above" text, on a clock, for as
        // long as the row stayed the first one.
        result.animatedCells = result.animatedCells.filter { !replacedRows.contains($0.offsetY) }
        result.animatedCells += runs
        return result
    }
}
