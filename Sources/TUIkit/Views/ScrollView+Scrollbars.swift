//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollView+Scrollbars.swift
//
//  The ScrollView's two scrollbars: attaching their mouse handlers (arrows,
//  track, thumb drag, auto-repeat) and drawing them onto the windowed viewport.
//  Split out of `ScrollView.swift` purely for file length — these five methods
//  are one coherent unit and nothing else in the core calls between them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension _ScrollViewCore {
    /// Registers a mouse handler over the scrollbar's single column so the arrows
    /// step by one, a track click pages or jumps, and the thumb drags. Inserted at
    /// the front of the regions array *before* the viewport handler's own
    /// `insert(at: 0)` pushes it back one, so the bar is hit-tested ahead of the
    /// viewport for its column (the viewport still wins everywhere else).
    func attachScrollbarMouseHandler(
        to buffer: inout FrameBuffer, contentWidth: Int,
        handler: ScrollViewHandler, focusID persistedFocusID: String, context: RenderContext
    ) {
        guard !context.isMeasuring,
              let mouseDispatcher = context.environment.mouseEventDispatcher,
              !isDisabled(in: context)
        else { return }
        // The bar's arrows and thumb answer the pointer, which needs motion.
        mouseDispatcher.requestFeature(.motion)
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
    func attachHorizontalScrollbarMouseHandler(
        to buffer: inout FrameBuffer, contentWidth: Int,
        handler: ScrollViewHandler, focusID persistedFocusID: String, context: RenderContext
    ) {
        guard !context.isMeasuring,
              let mouseDispatcher = context.environment.mouseEventDispatcher,
              !isDisabled(in: context)
        else { return }
        mouseDispatcher.requestFeature(.motion)
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
        let key = VerticalScrollbarMemo.Key(
            height: height, extent: handler.contentHeight, viewport: handler.viewportHeight,
            offset: handler.scrollOffset, arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            isFocused: isFocused, isScrollEnabled: context.environment.isScrollEnabled,
            hoveredCell: handler.hoveredBarCell, palette: ComparablePalette(palette),
            depth: ColorDepth.current, terminalColors: TerminalColors.current,
            cycle: pulse?.cycle)
        let memo: VerticalScrollbarMemo
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
            memo = VerticalScrollbarMemo(key: key, bar: bar, runs: runs)
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
        var bar = ScrollbarRenderer.horizontalScrollbar(
            width: contentWidth,
            extent: handler.horizontal.extent,
            viewport: handler.horizontal.viewportHeight,
            offset: handler.horizontal.scrollOffset,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            colors: .focusIndicating(
                isFocused: isFocused, hoveredCell: handler.horizontal.hoveredBarCell,
                context: context))
        if hasVerticalBar {
            bar.append(" ", cells: 1, ink: nil, field: ScrollbarColors.track(in: palette))
        }
        var lines = buffer.lines
        lines.append(bar.text)
        var result = buffer.replacingLines(
            lines, width: contentWidth + (hasVerticalBar ? 1 : 0), uniformWidth: true)
        result.opacityRegions += bar.claims.map { $0.shifted(byX: 0, y: lines.count - 1) }
        // The bar occupies the row just appended.
        if !context.isMeasuring,
            let pulse = ScrollbarColors.focusPulse(
                isFocused: isFocused, hoveredCell: handler.horizontal.hoveredBarCell,
                context: context),
            let run = ScrollbarRenderer.horizontalScrollbarRun(
                width: contentWidth,
                extent: handler.horizontal.extent,
                viewport: handler.horizontal.viewportHeight,
                offset: handler.horizontal.scrollOffset,
                arrows: context.environment.scrollbarArrows,
                proportional: context.environment.scrollbarProportionalThumb,
                pulse: pulse)
        {
            result.animatedCells.append(run.shifted(byX: 0, y: lines.count - 1))
        }
        return result
    }}

// MARK: - The bar drawn last time

/// A vertical scrollbar and the animated runs that pulse it, with the inputs
/// they were drawn from. See `ScrollViewHandler.verticalScrollbarMemo`.
struct VerticalScrollbarMemo {
    /// Everything the bar's cells and runs are a function of. The palette by
    /// its id and the depth outright, since the cells carry resolved colours;
    /// the pulse cycle whole, since the runs carry one render per frame of it.
    struct Key: Equatable {
        let height: Int
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
    let bar: ClaimingColumn
    let runs: [AnimatedCellRun]
}
