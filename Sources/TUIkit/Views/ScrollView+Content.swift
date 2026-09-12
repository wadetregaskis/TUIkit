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
        // Each visible line's width from what the content buffer already
        // knows — a stack pads its lines to one width and says so — rather
        // than a scan per line per frame to learn it, and the window's own
        // buffer says what it knows in turn, so the scrollbar and the writer
        // do not scan either. A horizontal slice changes the width, so only
        // the vertical case carries it; the rest measure as before.
        let window = full.lines.dropFirst(scrollOffset).prefix(viewportHeight)
        var visibleLines: [String] = []
        visibleLines.reserveCapacity(viewportHeight)
        var visibleWidths: [Int] = []
        visibleWidths.reserveCapacity(viewportHeight)
        for (offset, line) in window.enumerated() {
            if horizontalEnabled {
                let sliced = line.ansiAwareSlice(
                    visibleStart: horizontalOffset, visibleCount: viewportWidth)
                visibleLines.append(sliced.padToVisibleWidth(viewportWidth))
                visibleWidths.append(max(viewportWidth, sliced.strippedLength))
                continue
            }
            let known: Int? =
                full.linesAreUniformWidth ? full.width : full.lineWidths?[scrollOffset + offset]
            let width = known ?? line.strippedLength
            if width >= viewportWidth {
                visibleLines.append(line)
                visibleWidths.append(width)
            } else {
                visibleLines.append(line.padToVisibleWidth(viewportWidth, knownVisibleWidth: width))
                visibleWidths.append(viewportWidth)
            }
        }
        if visibleLines.count < viewportHeight {
            let blank = String(repeating: " ", count: viewportWidth)
            let missing = viewportHeight - visibleLines.count
            visibleLines.append(contentsOf: Array(repeating: blank, count: missing))
            visibleWidths.append(contentsOf: repeatElement(viewportWidth, count: missing))
        }
        let uniform = visibleWidths.allSatisfy { $0 == viewportWidth }

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
            let shifted = overlay.shifted(byX: dx, y: -scrollOffset)
            // A scroll view clips its CONTENT to its bounds, as SwiftUI's does
            // — `View.scrollClipDisabled(_:)` is the modifier that turns that
            // off, and it documents the default. Until now nothing here clipped
            // a layer at all, so `.offset(x: 7)` on a row of a 12-wide scroller
            // painted three columns of the page beside it.
            //
            // Only the layers that ARE content: a layer that is a surface
            // (`isOpaque`) is a window over the page — a drop-down, a menu, a
            // toast — and SwiftUI does not clip a presentation to the scroller
            // its trigger sits in either. The culling above already lets those
            // through whole, including the flip-above-the-anchor case that
            // needs `anchorHeight`.
            guard !shifted.isOpaque else { return shifted }
            return shifted.clipped(toWidth: viewportWidth, height: viewportHeight)
        }

        // The same filter-and-shift the overlays got, and the same trim — which
        // the overlay pass gets for free from `OverlayLayer.placed()`'s own clip
        // and this one has to ask for.
        let visibleRegions = full.hitTestRegions.compactMap { region -> HitTestRegion? in
            // Into viewport coordinates first, then trimmed to the viewport —
            // which is the SAME clip a region gets from any other clipping
            // container, so it is the shared one rather than a second copy of
            // its arithmetic. The order is safe because a translation records
            // nothing: `topClip`/`leftClip` count cells CUT AWAY, and moving a
            // rectangle cuts none, so `clip(shift(r))` and `shift(clip(r))`
            // agree on both (see `HitTestRegion.shifted(byX:y:)`). This used to
            // be written out here, clipping the Y axis in content coordinates
            // and the X axis in viewport ones, which is why it read as two
            // different pieces of arithmetic for one operation.
            //
            // `shifted` carries `focusID`, and it MUST: reveal-on-focus finds
            // its target by that, and dropping it here — silently, since the
            // initializer defaults it to nil — once made an ENCLOSING
            // ScrollView unable to locate a focused control living inside this
            // one, so nested scroll views could not reveal.
            //
            // And `clipped` accumulates rather than assigns, which is the other
            // thing this has to keep. Where a region BEGINS is not where it can
            // be clicked: a drop destination wrapping a scrolled page starts
            // above the viewport, and a drop point localised against its
            // clipped top came out short by exactly the scroll offset — the
            // poof puff drawn that far up the screen.
            //
            // The trim itself is as final for a region as for a line. A control
            // straddling the top kept its full height at a negative offsetY, so
            // the parent placed it over rows above the ScrollView; one
            // straddling the bottom kept rows past the last visible line. Since
            // regions are hit-tested innermost-first, those phantom rows won —
            // a click on a Button sitting above the scroller reached a
            // half-scrolled-off row inside it instead. The X axis had the twin
            // defect, and the vertical scrollbar was one of its victims.
            region.shifted(byX: dx, y: -scrollOffset)
                .clipped(toColumns: 0..<viewportWidth, rows: 0..<viewportHeight)
        }

        // Animated runs are a claim about single rows, so unlike a region they
        // are not clipped but kept or dropped whole: a run scrolled out of the
        // viewport must stop, or it would repaint on a clock over whatever row
        // took its place. Survivors move into viewport coordinates with the
        // lines they describe.
        // What a run this viewport cannot carry leaves behind — see `droppedRunClaims`
        // below, and §69.1 for why a run must not be the only carrier of an alpha.
        var droppedRunClaims: [OpacityRegion] = []
        let visibleRuns = full.animatedCells.compactMap { run -> AnimatedCellRun? in
            guard run.offsetY >= viewportTop, run.offsetY < viewportBottom else { return nil }
            // Horizontally too, and for the same reason: a run carried past
            // either edge keeps repainting at a column that is no longer its
            // own. Off the left it patches at a negative column, which pads the
            // row out to the run's width and makes the line WIDER than the
            // terminal — it then wraps and smears the row below, and the diff
            // writer, which believes that row is untouched, never repairs it.
            let shiftedX = run.offsetX + dx
            guard shiftedX >= 0, shiftedX + run.width <= viewportWidth else {
                // Dropped on GEOMETRY, while `visibleOpacity` below clips and KEEPS every
                // region — so a run stating its alpha per frame would take the only
                // statement about those cells with it and they would render at full
                // strength. The concrete shape: a bordered box wider than its viewport,
                // whose top and bottom rules are dropped here while its width-1 side
                // walls survive, drawing an opaque rule with faded walls. Its drawn
                // frame degrades to an ordinary claim instead (§69.1).
                droppedRunClaims += run.alpha?
                    .drawnRegions(forRunAt: run.offsetX, offsetY: run.offsetY) ?? []
                return nil
            }
            return run.shifted(byX: dx, y: -scrollOffset)
        }

        // Opacity regions clip like hit regions rather than being dropped like
        // runs: a rectangle of faded cells that straddles the viewport edge is
        // still faded for the part of it that shows, and keeping its full
        // height would fade rows belonging to whatever sits outside the
        // scroller.
        //
        // Which makes it the SAME two-axis trim, through the same shared
        // helper, that the hit regions above already take — not a second piece
        // of arithmetic. It was a second piece, and it clipped only Y. A
        // horizontally-scrolling view renders its content at its NATURAL width
        // (`contentExtents`: `max(contentWidth, natural.width)`) while this
        // function slices the LINES to the window, so a fade over a 60-cell
        // line inside a 20-cell viewport was carried up as a rectangle 60 wide
        // on a buffer declaring 20 — and nothing downstream cut it either,
        // because `clamped`'s fast path only asks whether the buffer's DECLARED
        // width fits. At the root that reached forty columns which were never
        // this scroller's: an `HStack` sibling beside it faded, and so did the
        // view's OWN vertical scrollbar, which `appendVerticalScrollbar` writes
        // at column `contentWidth`. The commit that introduced this block said
        // "a region wider than a row must not reach the scrollbar", and clipped
        // one axis.
        //
        // Trimmed to the buffer's DECLARED width, unconditionally — the rule
        // `clamped` already applies to a region, and the rule the hit regions
        // take here. Not free: the vertical-only path above keeps a line WIDER
        // than the viewport whole rather than slicing it, so there the columns
        // past `viewportWidth` are drawn and now come out unfaded. That is the
        // declared-vs-drawn width defect showing through rather than this trim
        // — a region naming columns its buffer disclaims cannot be placed by
        // anything upstream, and every container that clips would cut it
        // anyway.
        //
        // Shifted first and clipped second, for the reason the hit-region block
        // gives — and here without even that block's caveat: an opacity region
        // carries no clip counters for a translation to disturb.
        let visibleOpacity = (full.opacityRegions + droppedRunClaims)
            .compactMap { region -> OpacityRegion? in
                region.shifted(byX: dx, y: -scrollOffset)
                    .clipped(toColumns: 0..<viewportWidth, rows: 0..<viewportHeight)
            }

        var result = FrameBuffer(
            lines: visibleLines, width: viewportWidth,
            uniformWidth: uniform, lineWidths: uniform ? nil : visibleWidths)
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
    ///
    /// - Parameter always: Whether both lines are drawn whatever is hidden —
    ///   ``EnvironmentValues/alwaysShowsVerticalTextIndicators``. Then the
    ///   viewport gives up its first and last line at every offset, which is the
    ///   point: `.visible` asks for the affordance, not for a hint that comes and
    ///   goes and resizes the content under the reader as it does.
    func applyScrollIndicators(
        to buffer: FrameBuffer,
        handler: ScrollViewHandler,
        width: Int,
        palette: any Palette,
        surface: Color,
        cycle: SelectionEmphasisCycle?,
        locale: Locale,
        always: Bool = false,
        reserving: Bool = false
    ) -> FrameBuffer {
        guard buffer.height > 0 else { return buffer }
        guard always || handler.hasContentAbove || handler.hasContentBelow else {
            return buffer
        }
        if reserving {
            return reservingScrollIndicators(
                around: buffer, handler: handler, width: width, palette: palette,
                surface: surface, cycle: cycle, locale: locale)
        }

        var lines = buffer.lines
        // The indicators' own runs, so a focused scroll view breathes them
        // without the page being rendered again on every tick of the clock.
        var runs: [AnimatedCellRun] = []
        /// The indicators' own claims, on the rows they were drawn on.
        var claims: [OpacityRegion] = []
        /// The rows the indicators overwrite — whatever the content had
        /// animating on them goes with them.
        var replacedRows: Set<Int> = []

        if always || handler.hasContentAbove, !lines.isEmpty {
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
                over: surface,
                locale: locale
            )
            lines[0] = indicator.text.padToVisibleWidth(width)
            replacedRows.insert(0)
            claims += indicator.claims(atRow: 0)
            if let animation = indicator.animation { runs.append(animation) }
        }

        if always || handler.hasContentBelow, lines.count >= 1 {
            let indicator = renderScrollIndicator(
                direction: .down,
                count: handler.rowsBelow,
                unit: .lines,
                width: width,
                palette: palette,
                approximate: handler.contentHeightIsEstimate,
                cycle: cycle,
                over: surface,
                locale: locale
            )
            lines[lines.count - 1] = indicator.text.padToVisibleWidth(width)
            replacedRows.insert(lines.count - 1)
            claims += indicator.claims(atRow: lines.count - 1)
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
        // …and whatever the content CLAIMED on them goes too. Left, a translucent
        // line's claim sat under "▼ 3 more below" and faded the indicator at an
        // alpha nobody painted it with — the run filter above, missing its twin.
        // The replaced rows are only ever the edges, so one clip to the band that
        // survives does it, with no slivers: the trim a clipping container makes.
        let kept =
            (replacedRows.contains(0) ? 1 : 0)
            ..< (replacedRows.contains(lines.count - 1) ? lines.count - 1 : lines.count)
        result.opacityRegions = result.opacityRegions.compactMap {
            kept.isEmpty ? nil : $0.clipped(toColumns: 0..<Int.max, rows: kept)
        }
        // The indicators' own claims go in after that cut, not through it: they are
        // the one thing on those rows that owes anything now.
        result.opacityRegions += claims
        result.animatedCells += runs
        return result
    }

    /// Both indicator lines, around a content window that was made two lines
    /// shorter to hold them.
    ///
    /// The other path OVERWRITES the viewport's first and last line, and can:
    /// under ``ScrollIndicatorVisibility/automatic`` an indicator is there only
    /// when there IS content past it, so the line it covers is one the reader
    /// reaches at a neighbouring offset. Under
    /// ``ScrollIndicatorVisibility/visible`` both lines are drawn at every
    /// offset, and an overwritten line is then one the reader can NEVER see: the
    /// top line is content line `scrollOffset`, so line 0 goes at offset 0 and
    /// nowhere else shows it, and the last content line only ever sits on the
    /// bottom line, at `maxOffset`. The document's first and last lines were
    /// silently and permanently gone.
    ///
    /// `List` and `Table` never had this because they take the two lines out of
    /// their ROW budget — the reservation and the drawing are one answer there.
    /// This is a `ScrollView`'s version of that: the caller shortens the content
    /// window by two lines (so `viewportHeight`, and with it `maxOffset`, follow)
    /// and the content is shifted down one row to sit between them. Everything
    /// riding on those lines — hit regions, animated runs, overlays, opacity —
    /// moves with them, which is what `overlayShiftY` is for.
    private func reservingScrollIndicators(
        around buffer: FrameBuffer,
        handler: ScrollViewHandler,
        width: Int,
        palette: any Palette,
        surface: Color,
        cycle: SelectionEmphasisCycle?,
        locale: Locale
    ) -> FrameBuffer {
        func line(_ direction: ScrollIndicatorDirection, count: Int) -> ScrollIndicatorLine {
            renderScrollIndicator(
                direction: direction, count: count, unit: .lines, width: width,
                palette: palette, approximate: handler.contentHeightIsEstimate,
                cycle: cycle, over: surface, locale: locale)
        }
        let above = line(.up, count: handler.rowsAbove)
        let below = line(.down, count: handler.rowsBelow)
        var result = buffer.replacingLines(
            [above.text.padToVisibleWidth(width)] + buffer.lines
                + [below.text.padToVisibleWidth(width)],
            width: width, uniformWidth: true, overlayShiftY: 1)
        if let run = above.animation { result.animatedCells.append(run) }
        // The renderer builds every run at row 0, so the bottom one moves to the
        // row it was actually drawn on — as the overwriting path does.
        if let run = below.animation {
            result.animatedCells.append(run.shifted(byX: 0, y: result.height - 1))
        }
        // And the claims, the same way. The content's own moved down a row with it
        // in `replacingLines`, so neither line's row carries one of those.
        result.opacityRegions += above.claims(atRow: 0) + below.claims(atRow: result.height - 1)
        return result
    }
}
