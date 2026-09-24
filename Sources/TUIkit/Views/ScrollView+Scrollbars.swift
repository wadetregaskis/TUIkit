//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollView+Scrollbars.swift
//
//  The ScrollView's two scrollbars: attaching their mouse handlers (arrows,
//  track, thumb drag, auto-repeat) and drawing them onto the windowed viewport,
//  and the cell they add to the view's ideal size. Split out of
//  `ScrollView.swift` purely for file length.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension _ScrollViewCore {
    /// The size this scroll view answers along an axis it was offered no extent
    /// on: its content's, plus the bar the render will draw across it.
    ///
    /// A bar is chrome the content knows nothing about — the vertical one takes
    /// a column out of the viewport, the horizontal one a row — so whenever one
    /// is drawn, the content's ideal size is a cell short of the scroll view's.
    /// Answered with the content's alone, a parent that sizes to the answer
    /// handed exactly the content's size back, and the bar took its cell out of
    /// the content on every frame: a `TabView` panel squeezed six-cell rows into
    /// five, and a lazy stack's row cut a horizontal strip's bar off.
    ///
    /// Whether a bar is drawn is asked of the viewport this view gets if the
    /// parent takes the answer: the proposal where there is one, else the
    /// content's extent with room for a bar that could be drawn at all, capped
    /// at what is available. Only `.automatic` has to find out; `.visible`,
    /// `.hidden` and the `.text` style, which takes lines rather than a column,
    /// are read off the environment.
    ///
    /// A proposed extent is never grown: the bar comes out of it, as it always
    /// has. Nor is an answer grown past the available extent — a parent clamps
    /// it there, and content that already fills it gives the bar a cell of its
    /// own, as it does under a proposal — so an axis the content fills is
    /// answered without asking at all.
    ///
    /// A view that also scrolls horizontally asks
    /// ``resolveScrollbars(viewportWidth:viewportHeight:horizontal:textLines:context:)``,
    /// the render's own fixpoint, since there each bar can tip the other. A
    /// vertical one has only the one bar, which leaves its content exactly as
    /// wide either way (the column is what the answer adds), so the question is
    /// only whether the content overflows — and what that costs is the point,
    /// because an eager stack answers it by walking every row. Asked with no
    /// height proposed, which is how a stack and a `TabView` ask, the content is
    /// measured ONCE, as it always was, but offered one row more than is
    /// available: content that comes back past the available height is taller
    /// than any viewport this view can be given, and content that comes back
    /// within it reported the height it chose. So the one measure answers the
    /// size and the bar together. Asked a stated height, the content's answer is
    /// shaped by that height and cannot say, and
    /// ``contentOverflowsVertically(viewportHeight:reported:context:)`` asks
    /// again, only when the content reached it.
    ///
    /// A second measure for the bar every time (the first version of this) was
    /// a whole extra walk of the content wherever the answer is not taken —
    /// which is most places, since a `VStack` lays this view out across its
    /// width whatever width it answers: `scrolleager` (400 eager rows under a
    /// heading) +22.6% per frame, `scrollfollow` +7.2%.
    func idealSize(proposal: ProposedSize, context: RenderContext) -> (width: Int, height: Int) {
        let wantsHorizontal = axes.contains(.horizontal)
        let environment = context.environment
        // Asked at `overflowing: true`: could a bar be drawn at all? That needs
        // no measure, and a view that can draw neither — the common vertical
        // view offered a width — is answered without one.
        let mayDrawVerticalBar = environment.verticalScrollIndicators(overflowing: true).bar
        let mayDrawHorizontalBar =
            wantsHorizontal && environment.showsHorizontalScrollbar(overflowing: true)
        // Whether the content's own measure also asks whether it overflows (see
        // above): a vertical view asked its width with no height stated, whose
        // bar comes and goes with overflow.
        let probesOverflow =
            !wantsHorizontal && proposal.width == nil && proposal.height == nil
            && mayDrawVerticalBar && environment.verticalScrollIndicatorVisibility == .automatic
            && context.availableHeight < Int.max
        var contentContext = idealContentContext(context)
        if probesOverflow { contentContext.availableHeight += 1 }
        let measured = ChildView(content).measure(proposal: proposal, context: contentContext)
        let overflows = probesOverflow && measured.height > context.availableHeight
        // The size is the one the available height alone gives: the extra row
        // asked a question, it is not room the content may take. A report of
        // exactly the offer is what a clamp at the extra row looks like, so it
        // is the clamp at the available height; a report past the offer was
        // never clamped, and stands.
        let content = (
            width: measured.width,
            height: overflows && measured.height == contentContext.availableHeight
                ? context.availableHeight : measured.height)
        let widens =
            proposal.width == nil && mayDrawVerticalBar && content.width < context.availableWidth
        let heightens =
            proposal.height == nil && mayDrawHorizontalBar && content.height < context.availableHeight
        guard widens || heightens else { return content }
        let viewportWidth =
            proposal.width
            ?? min(content.width + (mayDrawVerticalBar ? 1 : 0), context.availableWidth)
        let viewportHeight =
            proposal.height
            ?? min(content.height + (mayDrawHorizontalBar ? 1 : 0), context.availableHeight)
        let bars: (vertical: Bool, horizontal: Bool)
        if wantsHorizontal {
            let resolved = resolveScrollbars(
                viewportWidth: viewportWidth, viewportHeight: viewportHeight,
                horizontal: true, textLines: TextIndicatorLines(environment), context: context)
            bars = (resolved.vertical, resolved.horizontal)
        } else {
            // Only `widens` reaches here, so the content is `content.width`
            // wide with the bar and without it.
            let vertical = environment.verticalScrollIndicators(
                overflowing: probesOverflow
                    ? overflows
                    : contentOverflowsVertically(
                        viewportHeight: viewportHeight, reported: content.height, context: context)
            ).bar
            bars = (vertical, false)
        }
        return (
            width: widens && bars.vertical ? viewportWidth : content.width,
            height: heightens && bars.horizontal ? viewportHeight : content.height)
    }

    /// The context the ideal-size questions measure the content in.
    ///
    /// A windowed stack's width means every row exactly when the view it is
    /// laid out in scrolls horizontally (`asksWholeContentWidth`), which is how
    /// `contentExtents` asks it. A vertical view inside a horizontal one
    /// inherited the outer view's mark here, so its stack answered the
    /// whole-content question — its rows' content, 11 cells — where
    /// `contentExtents` asked the prefix question, 59: one measure key, two
    /// answers, and the pass's memo served the first to the second. So the
    /// inherited mark is cleared on a view that does not scroll horizontally.
    ///
    /// It is NOT set on one that does. There a lazy stack answers the
    /// whole-content question only from a kept width record, and before one is
    /// filed it answers the prefix — so the view's ideal width would depend on
    /// what earlier frames drew, and a horizontally scrolling list of filling
    /// rows shrank to its prefix's width from its third frame.
    func idealContentContext(_ context: RenderContext) -> RenderContext {
        var contentContext = context.withChildIdentity(type: Content.self)
        if !axes.contains(.horizontal) && contentContext.environment.asksWholeContentWidth {
            contentContext.environment.asksWholeContentWidth = false
        }
        return contentContext
    }

    /// Whether the content, which reported `reported` under a stated height, is
    /// taller than `viewportHeight` — the question ``idealSize(proposal:context:)``
    /// answers from its own measure when no height is stated.
    ///
    /// A report below the viewport is a height the content chose, so it fits,
    /// and nothing is measured. A report that reaches it is what a clamp looks
    /// like, and the content is asked once more, offered one row past the
    /// viewport — and UNPROPOSED along the height, as the render lays it out
    /// (``contentExtents(contentWidth:viewportHeight:horizontal:context:)``): a
    /// view that fills a stated height, `.frame(maxHeight: .infinity)`, would
    /// fill a stated `viewportHeight + 1` too and read as overflowing, where the
    /// render sees it report its content. The width is asked as the first
    /// measure asked it, so rows this pass has measured are served from the
    /// memo.
    ///
    /// That is not the render's question in one respect: the render measures
    /// against the natural-extent ladder, thousands of rows, where this offers
    /// one row more than the viewport. The two agree for content whose layout
    /// does not depend on how much height it is offered, and a lazy stack keeps
    /// them agreeing by reporting the budget when it runs past it. Content that
    /// chooses a different layout for a larger budget — `ViewThatFits(in:
    /// .vertical)` — can be judged by a layout the render does not draw.
    func contentOverflowsVertically(
        viewportHeight: Int, reported: Int, context: RenderContext
    ) -> Bool {
        guard reported >= viewportHeight, viewportHeight < Int.max else { return false }
        var probe = idealContentContext(context)
        probe.availableHeight = viewportHeight + 1
        return ChildView(content).measure(
            proposal: ProposedSize(width: nil, height: nil), context: probe
        ).height > viewportHeight
    }

    /// Registers a mouse handler over the scrollbar's single column so the arrows
    /// step by one, a track click pages or jumps, and the thumb drags. Inserted at
    /// the front of the regions array *before* the viewport handler's own
    /// `insert(at: 0)` pushes it back one, so the bar is hit-tested ahead of the
    /// viewport for its column (the viewport still wins everywhere else).
    @MainActor
    func attachScrollbarMouseHandler(
        to buffer: inout FrameBuffer, contentWidth: Int,
        handler: ScrollViewHandler, focusID persistedFocusID: String, context: RenderContext
    ) {
        guard !context.isMeasuring,
              let mouseDispatcher = context.environment.mouseEventDispatcher,
              !isDisabled(in: context)
        else { return }
        // The bar's arrows and thumb answer the pointer, which needs motion.
        mouseDispatcher.requestFeature(.motion, in: context)
        let barHandler = ScrollbarRenderer.verticalMouseHandler(
            for: handler, length: buffer.height,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            behavior: context.environment.scrollbarClickBehavior)
        let barHandlerID = mouseDispatcher.register(
            in: context,
            ScrollbarRenderer.focusing(
                barHandler, focusID: persistedFocusID,
                focusManager: context.environment.focusManager))
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: contentWidth, offsetY: 0, width: 1, height: buffer.height,
                handlerID: barHandlerID),
            at: 0
        )
        // Keep a held arrow / page-track repeating (the press set the repeat; this
        // wakes the loop and ticks it until release clears it).
        ScrollbarRenderer.driveAutoRepeat(
            state: handler, token: "scrollbar-repeat-\(context.identity.path)", context: context)
    }

    /// Puts the ScrollView's own hit region over each "N more above / below"
    /// line it drew, APPENDED so it wins the cells (the dispatcher's contract
    /// is last-registered = innermost): the indicator overwrites a content
    /// row's CELLS but used to leave that row's hit regions in place, so a
    /// click on the chrome pressed whatever control was scrolled exactly
    /// under it — invisible, and still clickable. The indicator is scroll
    /// chrome, so its click PAGES in its direction, the same move the
    /// scrollbar track answers with; the wheel is not consumed and falls
    /// through to the viewport handler as everywhere else.
    @MainActor
    func attachIndicatorMouseHandlers(
        to buffer: inout FrameBuffer, contentWidth: Int,
        handler: ScrollViewHandler, context: RenderContext
    ) {
        guard !context.isMeasuring,
              let mouseDispatcher = context.environment.mouseEventDispatcher,
              !isDisabled(in: context)
        else { return }
        let scroller = handler
        func shield(paging delta: Int, atY y: Int) {
            let handlerID = mouseDispatcher.register(in: context) { event in
                guard event.button == .left else { return false }
                switch event.phase {
                case .pressed:
                    _ = scroller.userScrollFine(by: scroller.pageDelta(delta))
                    return true
                case .released:
                    return true
                default:
                    return false
                }
            }
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: 0, offsetY: y, width: contentWidth, height: 1,
                    handlerID: handlerID))
        }
        let page = scroller.pageDistance
        if handler.hasContentAbove { shield(paging: -page, atY: 0) }
        if handler.hasContentBelow { shield(paging: page, atY: buffer.height - 1) }
    }

    /// Like ``attachScrollbarMouseHandler`` but for the bottom horizontal bar: a
    /// one-row hit region over the bar's track drives the *horizontal* axis (arrows
    /// step, track pages/jumps, thumb drags). The region spans `contentWidth` only,
    /// so the bottom-right corner cell (when the vertical bar is also present) stays
    /// inert. A distinct repeat token lets both axes auto-repeat independently.
    @MainActor
    func attachHorizontalScrollbarMouseHandler(
        to buffer: inout FrameBuffer, contentWidth: Int,
        handler: ScrollViewHandler, focusID persistedFocusID: String, context: RenderContext
    ) {
        guard !context.isMeasuring,
              let mouseDispatcher = context.environment.mouseEventDispatcher,
              !isDisabled(in: context)
        else { return }
        mouseDispatcher.requestFeature(.motion, in: context)
        let barHandler = ScrollbarRenderer.horizontalMouseHandler(
            for: handler.horizontal, length: contentWidth,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            behavior: context.environment.scrollbarClickBehavior)
        let barHandlerID = mouseDispatcher.register(
            in: context,
            ScrollbarRenderer.focusing(
                barHandler, focusID: persistedFocusID,
                focusManager: context.environment.focusManager))
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0, offsetY: max(0, buffer.height - 1), width: contentWidth, height: 1,
                handlerID: barHandlerID),
            at: 0
        )
        ScrollbarRenderer.driveAutoRepeat(
            state: handler.horizontal, token: "scrollbar-h-repeat-\(context.identity.path)",
            context: context)
    }

    /// Appends the trailing vertical scrollbar column to the windowed viewport.
    /// The content keeps its `contentWidth`; the bar occupies the last column,
    /// reflecting the handler's scroll position at sub-cell precision. The
    /// content's hit-test regions sit at `x < contentWidth`, so the appended
    /// column never disturbs them.
    func appendVerticalScrollbar(
        to buffer: FrameBuffer, contentWidth: Int,
        handler: ScrollViewHandler, isFocused: Bool, context: RenderContext
    ) -> FrameBuffer {
        let height = buffer.height
        guard height > 0 else { return buffer }
        let palette = context.environment.palette
        // The same hovered cell the draw lifts. The runs REPLACE those cells
        // from the first tick, so a pulse that does not know about the
        // pointer paints the lift away and it never returns while the pointer
        // sits there.
        let pulse = ScrollbarColors.focusPulse(
            isFocused: isFocused, hoveredCell: handler.hoveredBarCell, context: context)
        let key = ScrollbarMemo<ClaimingColumn>.Key(
            length: height, extent: handler.contentHeight, viewport: handler.viewportHeight,
            offset: handler.scrollOffset, arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            isFocused: isFocused, isScrollEnabled: context.environment.isScrollEnabled,
            hoveredCell: handler.hoveredBarCell, palette: ComparablePalette(palette),
            depth: ColorDepth.current, terminalColors: TerminalColors.current,
            cycle: pulse?.cycle)
        let memo: ScrollbarMemo<ClaimingColumn>
        if let remembered = handler.verticalScrollbarMemo, remembered.key == key {
            handler.verticalScrollbarMemoHits += 1
            memo = remembered
        } else {
            // The bar is the ScrollView's focus indicator: it pulses the
            // accent while focused (see ScrollbarColors.focusIndicating). The
            // runs that pulse it are one scrollbar render PER PULSE FRAME,
            // which is why the bar and its runs are kept with their inputs.
            let bar = ScrollbarRenderer.verticalScrollbar(
                height: height,
                extent: handler.contentHeight,
                viewport: handler.viewportHeight,
                offset: handler.scrollOffset,
                arrows: context.environment.scrollbarArrows,
                proportional: context.environment.scrollbarProportionalThumb,
                colors: .focusIndicating(
                    isFocused: isFocused, hoveredCell: handler.hoveredBarCell, context: context))
            let runs =
                pulse.map { pulse in
                    ScrollbarRenderer.verticalScrollbarRuns(
                        height: height,
                        extent: handler.contentHeight,
                        viewport: handler.viewportHeight,
                        offset: handler.scrollOffset,
                        arrows: context.environment.scrollbarArrows,
                        proportional: context.environment.scrollbarProportionalThumb,
                        pulse: pulse)
                } ?? []
            memo = ScrollbarMemo(key: key, bar: bar, runs: runs)
            handler.verticalScrollbarMemo = memo
        }
        var bar = memo.bar
        // A cell on every line: plain track below a bar shorter than the viewport.
        bar.fit(toCount: height, field: ScrollbarColors.track(in: palette))
        var lines = buffer.lines
        // The pad is what the buffer already knows about its lines where it
        // knows it; a scan of every line for the width it was just rendered
        // at is the fallback, not the rule.
        let uniformPad = buffer.linesAreUniformWidth ? max(0, contentWidth - buffer.width) : nil
        let lineWidths = buffer.lineWidths
        for index in 0..<height {
            let content = index < lines.count ? lines[index] : ""
            let known: Int? =
                index < lines.count
                ? (uniformPad ?? lineWidths.map { max(0, contentWidth - $0[index]) })
                : contentWidth
            let pad = known ?? max(0, contentWidth - content.strippedLength)
            lines[index] = content + String(repeating: " ", count: pad) + bar.lines[index]
        }
        var result = buffer.replacingLines(lines, width: contentWidth + 1, uniformWidth: true)
        result.opacityRegions += bar.claims(atColumn: contentWidth)
        // The bar's own cells, handed to the run loop. Its column is the last
        // one — the content was padded out to `contentWidth` above — and only
        // the rows that actually change earn a run, so a tall bar does not
        // repaint its whole length to move a two-cell thumb.
        if !context.isMeasuring, pulse != nil {
            result.animatedCells += memo.runs.map { $0.shifted(byX: contentWidth, y: 0) }
        }
        return result
    }

    /// Appends the bottom horizontal scrollbar over a reserved row. When the
    /// vertical bar is also present, a track-styled corner cell fills the
    /// bottom-right where the two meet.
    func appendHorizontalScrollbar(
        to buffer: FrameBuffer, contentWidth: Int, hasVerticalBar: Bool,
        handler: ScrollViewHandler, isFocused: Bool, context: RenderContext
    ) -> FrameBuffer {
        let palette = context.environment.palette
        let axis = handler.horizontal
        // Kept as the vertical bar is kept, and for its reason: a focused bar
        // pulses, and the run that pulses it is one bar render per frame of the
        // pulse cycle. Drawn afresh every frame, the horizontal bar was 35.6% of
        // a keystroke in a two-axis editor (`Stress --session editor`).
        let pulse = ScrollbarColors.focusPulse(
            isFocused: isFocused, hoveredCell: axis.hoveredBarCell, context: context)
        let key = ScrollbarMemo<ClaimingRow>.Key(
            length: contentWidth, extent: axis.extent, viewport: axis.viewportHeight,
            offset: axis.scrollOffset, arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            isFocused: isFocused, isScrollEnabled: context.environment.isScrollEnabled,
            hoveredCell: axis.hoveredBarCell, palette: ComparablePalette(palette),
            depth: ColorDepth.current, terminalColors: TerminalColors.current,
            cycle: pulse?.cycle)
        let memo: ScrollbarMemo<ClaimingRow>
        if let remembered = handler.horizontalScrollbarMemo, remembered.key == key {
            handler.horizontalScrollbarMemoHits += 1
            memo = remembered
        } else {
            let bar = ScrollbarRenderer.horizontalScrollbar(
                width: contentWidth,
                extent: axis.extent,
                viewport: axis.viewportHeight,
                offset: axis.scrollOffset,
                arrows: context.environment.scrollbarArrows,
                proportional: context.environment.scrollbarProportionalThumb,
                colors: .focusIndicating(
                    isFocused: isFocused, hoveredCell: axis.hoveredBarCell, context: context))
            let run = pulse.flatMap { pulse in
                ScrollbarRenderer.horizontalScrollbarRun(
                    width: contentWidth,
                    extent: axis.extent,
                    viewport: axis.viewportHeight,
                    offset: axis.scrollOffset,
                    arrows: context.environment.scrollbarArrows,
                    proportional: context.environment.scrollbarProportionalThumb,
                    pulse: pulse)
            }
            memo = ScrollbarMemo(key: key, bar: bar, runs: run.map { [$0] } ?? [])
            handler.horizontalScrollbarMemo = memo
        }
        var bar = memo.bar
        if hasVerticalBar {
            bar.append(" ", cells: 1, ink: nil, field: ScrollbarColors.track(in: palette))
        }
        var lines = buffer.lines
        lines.append(bar.text)
        var result = buffer.replacingLines(
            lines, width: contentWidth + (hasVerticalBar ? 1 : 0), uniformWidth: true)
        result.opacityRegions += bar.claims.map { $0.shifted(byX: 0, y: lines.count - 1) }
        // The bar occupies the row just appended.
        if !context.isMeasuring, pulse != nil {
            result.animatedCells += memo.runs.map { $0.shifted(byX: 0, y: lines.count - 1) }
        }
        return result
    }
}

// MARK: - The bar drawn last time

/// A scrollbar and the animated runs that pulse it, with the inputs they were
/// drawn from — a vertical bar's column or a horizontal bar's row. See
/// `ScrollViewHandler.verticalScrollbarMemo`.
struct ScrollbarMemo<Bar> {
    /// Everything the bar's cells and runs are a function of. The palette by
    /// its id and the depth outright, since the cells carry resolved colours;
    /// the pulse cycle whole, since the runs carry one render per frame of it.
    struct Key: Equatable {
        /// The bar's length along its axis: a vertical bar's height, a
        /// horizontal bar's width.
        let length: Int
        let extent: Int
        let viewport: Int
        let offset: Int
        let arrows: ScrollbarArrows
        let proportional: Bool
        let isFocused: Bool
        let isScrollEnabled: Bool
        let hoveredCell: Int?
        /// The palette by value where it can be, not by its id: a palette edited in
        /// place keeps the id, and a key of the id served the bar drawn before the edit.
        let palette: ComparablePalette
        let depth: ColorDepth
        /// The colours the terminal had reported when the bar was drawn.
        ///
        /// At sixteen colours an RGB colour is emitted as the slot nearest to what that
        /// slot PAINTS — the colour the terminal reported for it, or xterm's value while
        /// it has reported none — so the bar's bytes are a function of the report as well
        /// as of the palette. A palette whose roles are the terminal's own carries the
        /// report through its grounding, which `ComparablePalette` compares; a palette of
        /// RGB colours carries nothing, and without this a bar drawn before a report was
        /// served to every frame after it.
        ///
        /// By value, not by `TerminalColors.generation`, as the image caches are keyed
        /// (b7a2f35d): a task-local pin changes what a slot measures as without moving the
        /// generation. The render cache's clear on a moved generation does not reach this
        /// memo either — it lives on the handler, not in the cache.
        let terminalColors: TerminalColors
        let cycle: SelectionEmphasisCycle?
    }

    let key: Key
    let bar: Bar
    let runs: [AnimatedCellRun]
}
