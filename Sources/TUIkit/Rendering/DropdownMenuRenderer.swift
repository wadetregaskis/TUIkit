//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DropdownMenuRenderer.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Drop-down Menu

/// The shared pop-up list machinery behind every drop-down menu in TUIkit —
/// the menu-style ``Picker``'s option list and a ``TextField``'s input
/// suggestions (``View/textInputSuggestions(_:)``).
///
/// Renders a bordered, vertically-windowed list of rows (options and
/// dividers) with the standard active-control affordances — a pulsing accent
/// highlight and border, plus a scrollbar when the rows overflow the overlay
/// budget — and wires the popup's mouse behaviour: hover moves the highlight
/// (the desktop drop-down model), a click activates a row, the wheel scrolls
/// the window freely, and left-clicks on chrome or empty area are consumed so
/// they never fall through to whatever sits behind the open menu.
///
/// The caller owns the control-specific state (highlight ordinal, open flag,
/// a ``ScrollAxis`` for the window) and attaches the returned buffer as an
/// ``OverlayLayer`` anchored beneath its collapsed control.
@MainActor
enum DropdownMenu {
    /// The caret marking a control whose drop-down is closed (▾).
    static let closedCaret = "\u{25BE}"

    /// The caret marking a control whose drop-down is open (▴).
    static let openCaret = "\u{25B4}"

    /// The marker drawn beside a menu's current value (✓).
    static let selectedMarker = "\u{2713}"

    /// One row of a drop-down menu.
    enum Row {
        /// A selectable option. The string is the row's interior text,
        /// already carrying its leading marker/padding; the renderer fits it
        /// to the menu width and applies the highlight background.
        ///
        /// `claims` is what that text owes the compositor, in ROW-LOCAL
        /// columns — 0 is the interior's first column, and `offsetY` is always
        /// 0 — because the producer knows which cells it painted in a faded
        /// colour and only the renderer knows where the row lands. It places
        /// them through the same window it draws the row with, as it already
        /// does for a divider's rule: a producer that worked out its own line
        /// number would be re-deriving the scroll window, and the two would
        /// part the first time one of them changed.
        case option(String, claims: [OpacityRegion])

        /// A horizontal rule between option groups. Never highlighted,
        /// hovered, or clickable.
        case divider

        /// A row that arrives ALREADY DRAWN — its own ANSI, its own highlight,
        /// its own foreground picked against that highlight.
        ///
        /// This is how a view-composed menu (`Menu`, `.contextMenu`) gets into
        /// the drop-down renderer without giving up being made of views. The
        /// renderer places it and must not repaint it: the highlight background
        /// is already on it, and re-applying one would sit UNDER a foreground
        /// that was chosen for a different backdrop.
        ///
        /// `isSelectable` is false for the rows that are not choices — a
        /// `Divider` the caller drew itself, a heading — which then get no
        /// hover and no click, exactly like ``divider``.
        case rendered(String, isSelectable: Bool)
    }

    /// The number of rows the popup can show at once: every row when they fit
    /// the overlay content area (minus the popup's own top/bottom border),
    /// floored at 4 so a cramped terminal still shows a usable window.
    static func maxVisibleRows(rowCount: Int, context: RenderContext) -> Int {
        min(rowCount, max(4, context.environment.overlayContentHeight - 2))
    }

    /// Whether the popup overflows its window and therefore shows a scrollbar
    /// in its rightmost interior column.
    static func wantsScrollbar(rowCount: Int, context: RenderContext) -> Bool {
        rowCount > maxVisibleRows(rowCount: rowCount, context: context)
    }

    /// Collapses runs of adjacent dividers and drops leading/trailing ones,
    /// so conditional groups (e.g. a "recents" section that is sometimes
    /// empty) never leave a stray rule at the menu's edge.
    static func normalizedEntries<Entry>(
        _ entries: [Entry], isDivider: (Entry) -> Bool
    ) -> [Entry] {
        var result: [Entry] = []
        for entry in entries {
            if isDivider(entry) {
                guard let last = result.last, !isDivider(last) else { continue }
            }
            result.append(entry)
        }
        while let last = result.last, isDivider(last) {
            result.removeLast()
        }
        return result
    }

    /// Everything a control passes to ``popup(_:context:onHover:onActivate:)``.
    struct Configuration {
        /// The menu rows, options and dividers, in display order.
        let rows: [Row]

        /// The highlighted row index, or `nil` for none. Divider rows are
        /// never highlighted; the caller maps its option-ordinal highlight to
        /// a row index.
        let highlightedRow: Int?

        /// The popup's interior width (between the borders).
        let innerWidth: Int

        /// The caller-owned scroll state for the window; its extent and
        /// viewport are synced by the renderer.
        let scroll: ScrollAxis

        /// When `true`, the window scrolls (if needed) to keep
        /// `highlightedRow` visible — set after keyboard navigation moved the
        /// highlight. Wheel/scrollbar movement passes `false` so the window
        /// moves freely, as in a desktop drop-down.
        let followHighlight: Bool

        /// A stable identity for the scrollbar's held-button auto-repeat
        /// (unique per control).
        let autoRepeatToken: String
    }

    /// How this frame's rows are windowed — one answer, worked out once and
    /// handed to everything that has to agree with it. Drawing the rows and
    /// placing their hit regions from separately-derived windows is how a menu
    /// ends up highlighting one row and activating another.
    private struct RowWindow {
        /// The row indices actually on screen.
        let visible: Range<Int>

        /// How many rows the popup can show at once — its interior height,
        /// which is also the height of the scrollbar column.
        let maxVisible: Int

        /// Whether the rows overflow the window, and so whether the rightmost
        /// interior column is the scrollbar's rather than content's.
        let wantsBar: Bool
    }

    /// Renders the bordered popup — windowed against the overlay budget, with
    /// a scrollbar when the rows overflow — and wires its mouse handlers.
    ///
    /// - Parameters:
    ///   - config: The rows, highlight, width, and scroll state.
    ///   - context: The current render context.
    ///   - onHover: Called with the row index when the cursor enters an
    ///     option row.
    ///   - onActivate: Called with the row index when an option row is
    ///     clicked.
    ///   - onDismiss: Called when the user clicks OUTSIDE the popup — close
    ///     the menu (the click itself is consumed, macOS-style) — and when a
    ///     press-and-hold is released anywhere that is not a row, the popup's
    ///     own chrome included.
    /// - Returns: The popup buffer, ready to attach as an ``OverlayLayer``.
    static func popup(
        _ config: Configuration,
        context: RenderContext,
        onHover: @escaping (Int) -> Void,
        onActivate: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) -> FrameBuffer {
        let rows = config.rows
        let scroll = config.scroll
        let maxVisible = maxVisibleRows(rowCount: rows.count, context: context)

        scroll.extent = rows.count
        scroll.viewportHeight = maxVisible
        scroll.wheelEdgeHold.delayNanos =
            context.environment.scrollChainingDelay.clampedNanoseconds
        if config.followHighlight, let highlightedRow = config.highlightedRow {
            // The follow margin keeps that many rows of context visible
            // beyond the highlight (see ScrollFollowMargin); the default
            // zero is the classic edge-triggered follow.
            let margin = context.environment.scrollFollowMargin
                .resolvedLines(viewportLines: maxVisible)
            var offset = scroll.scrollOffset
            if highlightedRow - margin < offset {
                offset = max(0, highlightedRow - margin)
            } else if highlightedRow + margin >= offset + maxVisible {
                offset = min(highlightedRow, highlightedRow + margin - maxVisible + 1)
            }
            scroll.scrollOffset = offset
        }
        scroll.clampScrollOffset()
        let scrollOffset = scroll.scrollOffset
        let window = RowWindow(
            visible: scrollOffset..<min(rows.count, scrollOffset + maxVisible),
            maxVisible: maxVisible,
            wantsBar: rows.count > maxVisible)
        let wantsBar = window.wantsBar

        let palette = context.environment.palette
        var bar: ClaimingColumn? =
            wantsBar
            ? ScrollbarRenderer.verticalScrollbar(
                height: maxVisible, extent: rows.count, viewport: maxVisible,
                offset: scrollOffset, arrows: context.environment.scrollbarArrows,
                proportional: context.environment.scrollbarProportionalThumb,
                // `track(in:)`, like every other bar — the raw quaternary
                // fails the groove floors on six palettes (5f63de4c).
                colors: ScrollbarColors(
                    thumb: palette.foregroundSecondary, track: ScrollbarColors.track(in: palette),
                    arrow: palette.foregroundTertiary))
            : nil
        // One cell per row drawn — an unpainted space past the bar's end, as it
        // always was — so no claim is left over a row the popup does not have.
        bar?.fit(toCount: window.visible.count, field: nil)

        let drawn = animatedLines(
            rows: rows,
            highlightedRow: config.highlightedRow,
            visibleRange: window.visible,
            innerWidth: config.innerWidth,
            barCells: bar?.lines,
            context: context)
        var buffer = FrameBuffer(lines: drawn.lines)
        buffer.animatedCells = drawn.runs
        // The popup's chrome — the frame and the inset rules, in the border's colour,
        // the accent's breath. Both of that breath's ends are spent (`pulseEnds`,
        // §64), so every frame of it is at one alpha, and the claim taken from the
        // frame drawn is every frame's, in the breathing arm as in the still one. The
        // bytes are the opaque spelling: through `BorderRenderer.band`, and
        // `opaqueSpelling` directly for the inset rule.
        let borderColor = drawn.borderColor
        buffer.opacityRegions = BorderRenderer.opacityClaims(
            outerWidth: config.innerWidth + BorderRenderer.borderWidthOverhead,
            height: drawn.lines.count,
            style: context.environment.appearance.borderStyle, color: borderColor)
        // The inset separators, which are neither the frame nor a full-width
        // rule: they span the content column only, stopping short of a
        // scrollbar that is coloured by something else entirely.
        let ruleWidth = wantsBar ? max(1, config.innerWidth - 1) : config.innerWidth
        // Row `local` of the window is line `local + 1` — the same offset the
        // hit regions use, for the same reason: the top border is line 0.
        buffer.opacityRegions += window.visible.enumerated().compactMap { local, index in
            guard case .divider = rows[index] else { return nil }
            return OpacityRegion.claim(
                offsetX: 1, offsetY: local + 1, width: ruleWidth, height: 1,
                ink: borderColor)
        }
        // What the rows themselves owe — a selected option's marker, drawn in a
        // palette accent the user may have faded — placed from row-local columns
        // into the popup's, by the window resolved above. The rows are inside the
        // runs (every line is, since every line carries border cells), and this is
        // sound for the same reason the chrome's claim is: a marker's colour is the
        // same in every frame the breath replays, so one claim is true of them all.
        buffer.opacityRegions += window.visible.enumerated().flatMap { local, index -> [OpacityRegion] in
            guard case .option(_, let claims) = rows[index] else { return [] }
            return claims.map { $0.shifted(byX: 1, y: local + 1) }
        }
        // The scrollbar's claims, in both arms, like the chrome's: the bar does not
        // breathe — its colours are the same in every frame the runs replay — so its
        // claim is true of all of them. It sits in the
        // rightmost interior column, past the wall and the content `lines` fitted to
        // it, and its line 0 is the popup's row 1, under the top border.
        if let bar {
            buffer.opacityRegions += bar.claims(
                atColumn: 1 + max(1, config.innerWidth - 1), row: 1)
        }
        attachMouseHandlers(
            to: &buffer,
            config: config,
            window: window,
            context: context,
            onHover: onHover,
            onActivate: onActivate,
            onDismiss: onDismiss)
        if wantsBar {
            ScrollbarRenderer.driveAutoRepeat(
                state: scroll, token: config.autoRepeatToken, context: context)
        }

        // macOS behaviour: a click OUTSIDE an open menu closes it, and does
        // nothing else — the closing click is consumed. The popup carries a
        // screen-covering backdrop region: inserted FIRST, so every region
        // of the popup itself (rows, scrollbar) wins over it, while overlay
        // regions composite after the page's, so it still beats everything
        // underneath. The generous bounds cover any screen wherever the
        // popup is anchored (region containment is pure arithmetic; nothing
        // clips it to the buffer). Wheel events fall through — the page can
        // still scroll behind an open menu.
        if !context.isMeasuring {
            attachDismissBackdrop(to: &buffer, context: context, onDismiss: onDismiss)
        }
        return buffer
    }

    /// Inserts the screen-covering region that dismisses an open menu on a press
    /// anywhere outside it.
    ///
    /// Inserted FIRST, so every region of the menu itself (rows, scrollbar) wins
    /// over it, while overlay regions composite after the page's, so it still
    /// beats everything underneath. The generous bounds cover any screen
    /// wherever the menu is anchored — region containment is pure arithmetic,
    /// nothing clips it to the buffer. Wheel events fall through, so the page
    /// can still scroll behind an open menu.
    ///
    /// Shared by every menu presentation: the `Picker` drop-down and the combo
    /// box get it from `popup(_:)` above, and `presentMenuPopover` calls it
    /// directly for a pull-down `Menu` and `.contextMenu`.
    @MainActor
    static func attachDismissBackdrop(
        to buffer: inout FrameBuffer, context: RenderContext, onDismiss: @escaping () -> Void
    ) {
        guard let dispatcher = context.environment.mouseEventDispatcher else { return }
        let dismissID = dispatcher.register { event in
            switch event.phase {
            case .pressed where event.button == .right:
                // macOS: a right-click outside an open menu closes it AND is
                // still handled by whatever it landed on — right-clicking a
                // second context-menu target closes the first menu and opens
                // that one, in the one gesture. Declining lets the press bubble
                // to the region underneath (the dispatcher already bubbles a
                // declined right-click, which is how a `.contextMenu` on a
                // container catches a click on a child).
                onDismiss()
                return false
            case .pressed where !event.button.isWheel:
                // A LEFT click is spent entirely on closing the menu.
                onDismiss()
                return true
            case .released where !event.button.isWheel:
                // The end of a press-and-HOLD, away from every row: the user
                // tracked out of the menu and let go, which is how a Mac menu is
                // dismissed without choosing. A release that did not move is the
                // sticky click's — the menu stays up to be picked from.
                if dispatcher.endsHeldGesture(event) { onDismiss() }
                // Eaten either way: a context menu opens on the PRESS, so by the
                // time its release arrives the gesture is spent, and letting it
                // bubble would deliver a release nobody pressed for to the page
                // beneath.
                return true
            default:
                return false
            }
        }
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: -4096, offsetY: -4096, width: 8192, height: 8192, handlerID: dismissID),
            at: 0)
    }

    /// One option row's mouse handler: hover on the way past, and the choice on
    /// the way up.
    ///
    /// Its own function because the popup's handler wiring is otherwise long
    /// enough to hide it, and because the release case answers three separate
    /// questions (was this the opening click, is this a choice, does the menu
    /// close) that read better with nothing else around them.
    @MainActor
    private static func rowHandler(
        index: Int,
        onWheel: @escaping (MouseEvent) -> Bool,
        tracks: @escaping (MouseButton) -> Bool,
        mouseDispatcher: MouseEventDispatcher,
        onHover: @escaping (Int) -> Void,
        onActivate: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) -> HitTestRegion.HandlerID {
        mouseDispatcher.register { event in
            if onWheel(event) { return true }
            switch event.phase {
            case .entered:
                // Hover follows the cursor across the popup: whichever
                // option row is under the cursor becomes highlighted.
                onHover(index)
                return true
            case .exited:
                // Leave the highlight where it is when the cursor leaves.
                return true
            case .dragged where tracks(event.button):
                // The same thing with the button held — a Mac menu tracks
                // press-and-hold, and a terminal reports a held move as a
                // DRAG, not as motion, so `.entered` never fires for it.
                onHover(index)
                return true
            case .pressed where tracks(event.button):
                // The press is not the commitment — the release is. Handing
                // the rest of the gesture back to live hit-testing
                // (``MouseEventDispatcher/handOffGesture()``) is what lets
                // you press one row, slide onto another and get the one you
                // let go on; drag capture would send every later event back
                // to the row you started on, so sliding off the menu
                // entirely would still have run it.
                mouseDispatcher.handOffGesture()
                return true
            case .released where tracks(event.button):
                // Not every release over a row is a choice. A menu tall
                // enough is placed OVER the control that opened it — a Mac
                // pop-up button's menu covers it deliberately — so the
                // release ending the opening click lands on a row it was
                // never aimed at. That click is spent on opening the menu;
                // consumed here, it leaves the menu up to be picked from.
                guard !mouseDispatcher.endsPopupOpeningClick(event) else { return true }
                let endsHold = mouseDispatcher.endsHeldGesture(event)
                onActivate(index)
                // A press-and-HOLD ends here whatever the item's
                // `.menuActionDismissBehavior` says. That modifier keeps a
                // menu of settings up so more than one can be flipped —
                // with CLICKS, which the menu is still there to receive.
                // A held gesture has no such second act: the button is up,
                // the tracking session that opened the menu is over, and
                // leaving it on screen strands it in a state its own
                // gesture no longer supports. macOS does not arbitrate this
                // for us, because it has no stay-open menus to arbitrate:
                // SwiftUI's `MenuActionDismissBehavior.disabled` is
                // `@available(macOS, unavailable)`, and AppKit's tracking
                // model ends every menu session on the mouse-up.
                if endsHold { onDismiss() }
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Line drawing

    /// The two pairs of ends an open popup breathes between.
    ///
    /// Both pairs in one place because both are read together, once per render,
    /// and neither depends on the frame: the highlighted row's background
    /// pulses between a dim and a bright accent — the same affordance ``List``
    /// uses for its focused row, so the arrow keys and Enter visibly drive the
    /// menu rather than whatever sits behind it — and the border echoes that
    /// pulse at lower intensity so the popup's frame reads as part of the same
    /// active control.
    static func pulseEnds(
        palette: any Palette
    ) -> (highlight: (dim: Color, bright: Color), border: (dim: Color, bright: Color)) {
        (
            // A highlight is a FILL with a label on it, which is what
            // `accentFillPulse` means — and asking for the pair keeps both ends
            // agreeing about a translucent accent (§21).
            highlight: palette.accentFillPulse(),
            // The border's pair through `breathEnds`, for the same reason. A dim end
            // composited over the page beside a bright end that kept a faded accent's
            // alpha breathed between two alphas, and no one claim could describe it
            // (§64).
            border: palette.accent.breathEnds(
                dimmedTo: ViewConstants.focusBorderDim, over: palette.background)
        )
    }

    /// Draws the bordered popup lines for the visible window, at one point of
    /// the focus pulse.
    ///
    /// Everything a popup draws moves: the highlighted row's background, and
    /// the border echoing it at lower intensity. So rather than pick apart
    /// which cells those are, ``animatedLines`` calls this once per point of
    /// the cycle and hands the loop one run per line — the frames are then
    /// literally what this renderer produces, which is the strongest form the
    /// "a run must match the cells that were drawn" rule can take.
    ///
    /// The two moving colours arrive already resolved rather than being
    /// derived here from a `SelectionEmphasis`. Resolving them here meant two
    /// pulse ramps built per frame — 32 per open menu — for two ramps that are
    /// the same on every frame; ``pulseEnds(palette:)`` and
    /// `SelectionEmphasisCycle.colors(dim:bright:)` now build each one once.
    private static func lines(
        rows: [Row],
        highlightedRow: Int?,
        visibleRange: Range<Int>,
        innerWidth: Int,
        barCells: [String]?,
        highlightBg: Color,
        borderColor: Color,
        context: RenderContext
    ) -> [String] {
        let borderStyle = context.environment.appearance.borderStyle

        var lines: [String] = [
            BorderRenderer.standardTopBorder(
                style: borderStyle, innerWidth: innerWidth, color: borderColor)
        ]

        // When a scrollbar is shown it takes the rightmost interior column, so
        // content fits the remaining width and each row is composed manually
        // (border + content + bar cell + border).
        let verticalBorder = BorderRenderer.wall(style: borderStyle, color: borderColor)
        let contentInner = barCells == nil ? innerWidth : max(1, innerWidth - 1)

        for (local, index) in visibleRange.enumerated() {
            switch rows[index] {
            case .divider:
                // An inset rule (no T-junctions): it spans the content area
                // but not the scrollbar column, macOS-menu-separator style.
                let rule = ANSIRenderer.colorize(
                    String(repeating: borderStyle.horizontal, count: contentInner),
                    foreground: borderColor.opaqueSpelling)
                if let barCells {
                    let cell = local < barCells.count ? barCells[local] : " "
                    lines.append(verticalBorder + rule + cell + verticalBorder)
                } else {
                    lines.append(verticalBorder + rule + verticalBorder)
                }
            case .rendered(let content, _):
                // Already painted — fitted to the content column and placed,
                // never re-styled. See ``Row/rendered(_:isSelectable:)``.
                let fitted = fit(content, to: contentInner)
                if let barCells {
                    let cell = local < barCells.count ? barCells[local] : " "
                    lines.append(verticalBorder + fitted + ANSIRenderer.reset + cell + verticalBorder)
                } else {
                    lines.append(verticalBorder + fitted + ANSIRenderer.reset + verticalBorder)
                }
            case .option(let content, _):
                let isHighlighted = index == highlightedRow
                if let barCells {
                    let fitted = fit(content, to: contentInner)
                    let styled = fitted.withPersistentBackground(
                        isHighlighted ? highlightBg : nil)
                    let cell = local < barCells.count ? barCells[local] : " "
                    lines.append(
                        verticalBorder + styled + ANSIRenderer.reset + cell + verticalBorder)
                } else {
                    lines.append(
                        BorderRenderer.standardContentLine(
                            content: content,
                            innerWidth: innerWidth,
                            style: borderStyle,
                            color: borderColor,
                            backgroundColor: isHighlighted ? highlightBg : nil))
                }
            }
        }

        lines.append(
            BorderRenderer.standardBottomBorder(
                style: borderStyle, innerWidth: innerWidth, color: borderColor))
        return lines
    }

    /// The popup's lines, plus the runs that let the loop breathe them.
    ///
    /// The whole popup is redrawn per point of the cycle — cheap, because the
    /// row contents are already-rendered strings and this only re-assembles
    /// them — and every line gets a run, because every line carries border
    /// cells and so every line moves.
    @MainActor
    private static func animatedLines(
        rows: [Row],
        highlightedRow: Int?,
        visibleRange: Range<Int>,
        innerWidth: Int,
        barCells: [String]?,
        context: RenderContext
    ) -> (lines: [String], runs: [AnimatedCellRun], borderColor: Color) {
        func draw(_ highlight: Color, _ border: Color) -> [String] {
            lines(
                rows: rows, highlightedRow: highlightedRow, visibleRange: visibleRange,
                innerWidth: innerWidth, barCells: barCells,
                highlightBg: highlight, borderColor: border, context: context)
        }
        // The cycle, not the live phase: reading the phase marks the frame as
        // having consulted the clock, and an open menu would then re-render the
        // entire page behind it ~20 times a second.
        let cycle = context.environment.selectionEmphasis.cycle(true)
        // Two colour tracks, each from ONE ramp: the highlight and the border
        // fade between different pairs of ends, but both pairs are fixed for
        // the whole cycle.
        let ends = Self.pulseEnds(palette: context.environment.palette)
        let highlights = cycle.colors(dim: ends.highlight.dim, bright: ends.highlight.bright)
        let borders = cycle.colors(dim: ends.border.dim, bright: ends.border.bright)
        // One alpha in every frame, or the chrome's claim — taken from the frame drawn —
        // would be wrong for the rest (§64).
        assert(
            borders.allSatisfy { $0.alpha == borders[0].alpha },
            "the popup border's breath disagrees about alpha (§29)")
        let step = cycle.step % max(1, cycle.frames.count)
        let drawn = draw(highlights[step], borders[step])
        guard cycle.isAnimating, !context.isMeasuring else {
            return (drawn, [], borders[step])
        }
        let perStep = zip(highlights, borders).map(draw)
        let runs = drawn.indices.compactMap { row -> AnimatedCellRun? in
            let frames = perStep.map { $0[row] }
            let run = AnimatedCellRun(
                offsetX: 0, offsetY: row, width: drawn[row].strippedLength,
                frames: frames, clock: .cursor)
            // A divider or an unhighlighted row whose border happens to
            // quantise to one colour is a still picture; the loop drops those
            // anyway, and not emitting them keeps the buffer honest.
            return run.isAnimating ? run : nil
        }
        return (drawn, runs, borders[step])
    }

    // MARK: - Mouse wiring

    /// Emits the popup's hit-test regions: a wheel/click-catcher over the
    /// whole popup, the scrollbar (when shown), and one region per *visible*
    /// option row. Order matters under the dispatcher's reverse-iteration:
    /// the wheel catcher goes in first (lowest priority — it only catches the
    /// fall-through wheel and stray clicks), then the bar, then the rows
    /// (highest priority for their cells). Rows start at y=1 (after the top
    /// border). Divider rows get no region — clicks on them land in the
    /// catcher and are consumed.
    private static func attachMouseHandlers(
        to buffer: inout FrameBuffer,
        config: Configuration,
        window: RowWindow,
        context: RenderContext,
        onHover: @escaping (Int) -> Void,
        onActivate: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        guard !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        // Hover-follows-cursor needs motion reports, and press-and-hold
        // tracking needs DRAG reports — a held move is reported as a drag, not
        // as motion. (The collapsed control usually asked for both already;
        // this is idempotent.)
        mouseDispatcher.requestFeature(.motion)
        mouseDispatcher.requestFeature(.drag)
        let rows = config.rows
        let scroll = config.scroll
        let innerWidth = config.innerWidth
        let contentInner = window.wantsBar ? max(1, innerWidth - 1) : innerWidth

        // Wheel over the popup's CHROME — its border, its scrollbar column, the
        // empty space past the last row — scrolls the window and nothing else:
        // there is no row under the pointer there to move the highlight to. A
        // wheel over a row is the row's, and moves it; see `rowHandler`.
        //
        // Left clicks on chrome/empty area are consumed so they don't fall
        // through.
        let wheelID = mouseDispatcher.register { event in
            if scroll.handleWheelEvent(event) { return true }
            // The popup's own chrome — its frame, its padding, a divider — is
            // not a row, so a held gesture ending here ends the way it would
            // over the page behind: no choice, menu closed. The backdrop cannot
            // answer for these cells; they are inside the popup, where its
            // regions win.
            if mouseDispatcher.endsHeldGesture(event) {
                onDismiss()
                return true
            }
            return event.button == .left
        }
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: innerWidth + 2, height: window.maxVisible + 2,
                handlerID: wheelID))

        // The scrollbar column (rightmost interior column over the rows).
        if window.wantsBar {
            let barHandler = ScrollbarRenderer.verticalMouseHandler(
                for: scroll, length: window.maxVisible,
                arrows: context.environment.scrollbarArrows,
                proportional: context.environment.scrollbarProportionalThumb,
                behavior: context.environment.scrollbarClickBehavior)
            let barID = mouseDispatcher.register(barHandler)
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: innerWidth, offsetY: 1, width: 1, height: window.maxVisible,
                    handlerID: barID))
        }

        for (local, index) in window.visible.enumerated() {
            guard isSelectable(rows[index]) else { continue }
            // The wheel over a row scrolls the window like the wheel anywhere
            // else — the highlight does not drag the viewport after it, as a
            // desktop drop-down's does not. But the ROWS move under a pointer
            // that has not, so the row the pointer is on afterwards is a
            // different row, and leaving the highlight behind left the menu
            // showing one answer while holding another: releasing chose what
            // was under the cursor rather than what was lit, which is a wrong
            // answer and not merely an untidy one.
            //
            // Bound per row rather than answered on the popup-wide wheel
            // catcher, because a row's region IS the coordinate mapping: it
            // knows its own position in the visible window without arithmetic
            // on an event's coordinates, whose origin depends on how the popup
            // was composited (a tall one is clamped to the screen, and then the
            // two differ).
            let onWheel: (MouseEvent) -> Bool = { event in
                guard scroll.handleWheelEvent(event) else { return false }
                // Read AFTER the scroll: the offset is the one the next frame
                // will draw with, which is the one the pointer will be over.
                let landed = scroll.scrollOffset + local
                if rows.indices.contains(landed), isSelectable(rows[landed]) {
                    onHover(landed)
                }
                return true
            }
            let mouseHandlerID = rowHandler(
                index: index, onWheel: onWheel,
                tracks: tracks, mouseDispatcher: mouseDispatcher,
                onHover: onHover, onActivate: onActivate, onDismiss: onDismiss)
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: 1,
                    offsetY: 1 + local,
                    width: contentInner,
                    height: 1,
                    handlerID: mouseHandlerID))
        }
    }

    /// Whether a row is something the pointer can be *on*: an option, or a
    /// pre-drawn row that said it is a choice. A divider is neither.
    ///
    /// Shared by the two places that ask — which rows get a hit-test region,
    /// and which row a wheel scroll may move the highlight to — because the two
    /// disagreeing would mean a highlight landing where no click can follow it.
    private static func isSelectable(_ row: Row) -> Bool {
        switch row {
        case .option: return true
        case .rendered(_, let isSelectable): return isSelectable
        case .divider: return false
        }
    }

    /// Whether a button drives menu tracking — highlighting rows as it drags and
    /// choosing one when it lifts.
    ///
    /// Both of them, because a `.contextMenu` is opened by the RIGHT button and
    /// tracked with it still held: press, drag down the rows, release on one.
    /// The other menus are opened with the left, and a menu does not care which
    /// button is carrying the gesture it is already in the middle of.
    private static func tracks(_ button: MouseButton) -> Bool {
        button == .left || button == .right
    }

    /// Truncates or pads a plain string to exactly `width` visible columns.
    ///
    /// A wide character straddling the clip column is excluded by
    /// `ansiAwarePrefix`, leaving the prefix up to a cell SHORT — the shortfall
    /// is padded so the "exactly `width`" promise holds (otherwise the row's
    /// scrollbar cell and right border shift a column left; same pattern as
    /// `_ListCore`'s row clipping).
    static func fit(_ text: String, to width: Int) -> String {
        text.strippedLength > width
            ? text.ansiAwarePrefix(visibleCount: width).padToVisibleWidth(width)
            : text.padToVisibleWidth(width)
    }
}
