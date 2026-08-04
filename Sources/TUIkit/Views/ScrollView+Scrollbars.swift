//  🖥️ TUIKit — Terminal UI Kit for Swift
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
              !isDisabled
        else { return }
        let barHandler = ScrollbarRenderer.verticalMouseHandler(
            for: handler, length: buffer.height,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            behavior: context.environment.scrollbarClickBehavior)
        let barHandlerID = mouseDispatcher.register(
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
              !isDisabled
        else { return }
        let barHandler = ScrollbarRenderer.horizontalMouseHandler(
            for: handler.horizontal, length: contentWidth,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            behavior: context.environment.scrollbarClickBehavior)
        let barHandlerID = mouseDispatcher.register(
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
        let bar = ScrollbarRenderer.verticalScrollbar(
            height: height,
            extent: handler.contentHeight,
            viewport: handler.viewportHeight,
            offset: handler.scrollOffset,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            // The bar is the ScrollView's focus indicator: it pulses the
            // accent while focused (see ScrollbarColors.focusIndicating).
            colors: .focusIndicating(isFocused: isFocused, context: context))
        let emptyCell = ANSIRenderer.colorize(" ", background: palette.foregroundQuaternary)
        var lines = buffer.lines
        for index in 0..<height {
            let content = index < lines.count ? lines[index] : ""
            let pad = max(0, contentWidth - content.strippedLength)
            let cell = index < bar.count ? bar[index] : emptyCell
            lines[index] = content + String(repeating: " ", count: pad) + cell
        }
        return buffer.replacingLines(lines, width: contentWidth + 1, uniformWidth: true)
    }

    /// Appends the bottom horizontal scrollbar over a reserved row. When the
    /// vertical bar is also present, a track-styled corner cell fills the
    /// bottom-right where the two meet.
    func appendHorizontalScrollbar(
        to buffer: FrameBuffer, contentWidth: Int, hasVerticalBar: Bool,
        handler: ScrollViewHandler, isFocused: Bool, context: RenderContext
    ) -> FrameBuffer {
        let palette = context.environment.palette
        let bar = ScrollbarRenderer.horizontalScrollbar(
            width: contentWidth,
            extent: handler.horizontal.extent,
            viewport: handler.horizontal.viewportHeight,
            offset: handler.horizontal.scrollOffset,
            arrows: context.environment.scrollbarArrows,
            proportional: context.environment.scrollbarProportionalThumb,
            colors: .focusIndicating(isFocused: isFocused, context: context))
        let corner =
            hasVerticalBar
            ? ANSIRenderer.colorize(" ", background: palette.foregroundQuaternary)
            : ""
        var lines = buffer.lines
        lines.append(bar + corner)
        return buffer.replacingLines(
            lines, width: contentWidth + (hasVerticalBar ? 1 : 0), uniformWidth: true)
    }}
