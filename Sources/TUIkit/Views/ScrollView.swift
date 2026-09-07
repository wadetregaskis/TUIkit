//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollView.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - ScrollView

/// A scrollable view that displays content larger than its
/// viewport, with a scroll position that the user controls via
/// the mouse wheel and arrow keys.
///
/// `ScrollView` is the generic counterpart to ``List``: it
/// scrolls arbitrary content (text, forms, nested layouts) the
/// same way `List` scrolls rows of items. It does **not** model
/// a selection or a row structure — there is just a viewport
/// that windows into a taller buffer.
///
/// # Interaction model
///
/// - **Mouse wheel** scrolls by 3 lines per tick by default (see
///   ``ViewConstants/mouseWheelScrollLines``). The wheel works
///   regardless of focus.
/// - **Arrow keys** scroll one line at a time, **Page Up** /
///   **Page Down** scroll one viewport, and **Home** / **End**
///   jump to the very top / bottom. All keyboard scrolling
///   requires the scroll view to have focus.
/// - The two axes are independent: this matches every desktop
///   list-view convention. A focused inner control (e.g. a
///   `TextField`) keeps its own keyboard handling; the wheel
///   still scrolls the surrounding `ScrollView` because mouse
///   routing follows the cursor position, not the focus.
///
/// # Indicators
///
/// When content extends beyond the viewport an indicator appears:
/// a scrollbar beside the content by default, or the "N more above" /
/// "N more below" lines under `.scrollIndicatorStyle(.text)`, matching
/// the indicators used by `List`. `.scrollIndicators(.hidden)` suppresses
/// them — note that scrolling itself still works, it's only the visual
/// indicator that disappears.
///
/// # Example
///
/// ```swift
/// ScrollView {
///     VStack(alignment: .leading) {
///         ForEach(0..<1000) { i in
///             Text("Line \(i)")
///         }
///     }
/// }
/// ```
///
/// # Very tall content
///
/// There is no ceiling on how tall the content may be: it is measured
/// against a budget that grows until the content stops filling it, so a
/// hundred thousand rows scroll as readily as ten.
///
/// What that costs is a buffer as tall as the content, rebuilt every
/// frame. Past a few thousand rows, reach for ``LazyVStack`` — inside a
/// `ScrollView` it reports its extent without laying every row out and
/// renders only the band the viewport shows, so the per-frame cost stops
/// tracking the row count.
///
/// > Note: Both axes are supported. Pass `.vertical` (the default),
///   `.horizontal`, or `[.horizontal, .vertical]`. When horizontal
///   scrolling is enabled the view also renders a bottom scrollbar and
///   responds to a native horizontal wheel (or shift + vertical wheel).
public struct ScrollView<Content: View>: View {
    /// The axes along which content scrolls (`.vertical`, `.horizontal`,
    /// or both). Both are fully implemented.
    public let axes: Axis.Set

    /// The content of the scroll view.
    public let content: Content

    /// An explicit focus identifier, or `nil` to auto-generate.
    var explicitFocusID: String?

    /// Whether the scroll view is disabled.
    var isDisabled: Bool

    /// Creates a scroll view.
    ///
    /// - Parameters:
    ///   - axes: The scrollable axes (default `.vertical`).
    ///   - content: A ViewBuilder that defines the content to
    ///     scroll.
    ///
    /// - Note: SwiftUI's `showsIndicators:` variant is deliberately absent —
    ///   it is soft-deprecated there in favour of `scrollIndicators(_:)`, and
    ///   TUIkit does not carry deprecated spellings (see
    ///   `Documentation/SwiftUI-compatibility.md`). It was also a second,
    ///   hidden answer to the question `\.verticalScrollIndicatorVisibility`
    ///   already answers, which is exactly the confusion that splitting
    ///   visibility from style set out to end.
    public init(
        _ axes: Axis.Set = .vertical,
        @ViewBuilder content: () -> Content
    ) {
        self.axes = axes
        self.content = content()
        self.explicitFocusID = nil
        self.isDisabled = false
    }

    public var body: some View {
        // `.disabled(isDisabled)` as well as the stored flag, because the two
        // answer different questions. The flag decides whether this scroll view
        // is a Tab stop; SwiftUI's `.disabled(_:)` is defined on the subtree —
        // "disables interaction in this view and its child views" — and the
        // concrete `disabled(_:) -> ScrollView` below wins overload resolution
        // over `View.disabled(_:)`, so without this a `Button` inside a
        // disabled scroll view stayed focusable, clickable and actionable.
        // `.disabled(false)` is a no-op: the modifier ANDs, so it can never
        // re-enable a subtree an ancestor disabled.
        _ScrollViewCore(
            axes: axes,
            content: content,
            explicitFocusID: explicitFocusID,
            isDisabled: isDisabled
        )
        .disabled(isDisabled)
    }
}

// MARK: - Convenience Modifiers

extension ScrollView {
    /// Sets an explicit focus identifier on this scroll view.
    public func focusID(_ id: String) -> ScrollView<Content> {
        var copy = self
        copy.explicitFocusID = id
        return copy
    }

    /// Creates a disabled version of this scroll view. Wheel
    /// scrolling continues to work (the user can still inspect
    /// content); keyboard focus is suppressed.
    public func disabled(_ disabled: Bool = true) -> ScrollView<Content> {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }
}

// MARK: - Equatable

extension ScrollView: @preconcurrency Equatable where Content: Equatable {
    public static func == (lhs: ScrollView<Content>, rhs: ScrollView<Content>) -> Bool {
        lhs.axes == rhs.axes
            && lhs.content == rhs.content
            && lhs.explicitFocusID == rhs.explicitFocusID
            && lhs.isDisabled == rhs.isDisabled
    }
}

// MARK: - _ScrollViewCore (internal rendering)

/// StateStorage property indices for ``_ScrollViewCore``.
/// Lifted out of the generic struct because Swift does not
/// allow static stored properties in generic types.
enum ScrollViewStateIndex {
    static let handler = 0
    static let focusID = 1
    static let lastFocusedID = 2
    static let lastInteractionGen = 3
    static let lastViewport = 4
}

/// A lightweight String-box used by ``_ScrollViewCore`` to track
/// which focusable was focused at the previous render, so it can
/// detect focus *changes* and scroll the new focused control into
/// view. Class-typed so a StateBox can hold it mutably across
/// renders.
final class LastFocusedIDBox: @unchecked Sendable {
    var value: String?
}

/// Tracks the ``FocusManager/focusedInteractionGeneration`` value
/// seen at the previous render so ``_ScrollViewCore`` can detect
/// "the focused control just consumed a key event" between
/// frames. Class-typed for the same reason as
/// ``LastFocusedIDBox``.
final class LastInteractionGenBox: @unchecked Sendable {
    var value: UInt64 = 0
}

/// The content rect this scroller was last laid out into, on a RENDER pass.
///
/// A viewport that changes size — the terminal resized, a split-view divider
/// moved, a disclosure opened above — invalidates the scroll offset's meaning
/// while leaving its number intact, which is how a focused control ends up off
/// screen with nothing to bring it back. See
/// ``_ScrollViewCore/snapViewportToFocusedControl(handler:fullBuffer:viewportHeight:regionOriginY:indicatorsActive:suppressed:context:)``.
/// `nil` until the first render: there was nothing on screen to keep in view.
final class LastViewportBox: @unchecked Sendable {
    var value: (width: Int, height: Int)?
}

/// Internal core that performs the windowing, hit-testing, and
/// keyboard wiring for ``ScrollView``.
struct _ScrollViewCore<Content: View>: View, Renderable, Layoutable {

    let axes: Axis.Set
    let content: Content
    let explicitFocusID: String?
    let isDisabled: Bool

    var body: Never { fatalError("_ScrollViewCore renders via Renderable") }

    typealias StateIndex = ScrollViewStateIndex

    // MARK: Layout

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // A ScrollView takes whatever size the parent *proposes* and scrolls if
        // its content doesn't fit — so it stays width/height-flexible, and a
        // parent that constrains it (a too-short modal) makes it scroll. But its
        // *ideal* size (an unproposed axis) is its content's size, not the whole
        // viewport — so a parent that sizes to fit (a TabView, a Dialog) sizes to
        // the content it wraps and only scrolls when space is actually short.
        // Matches SwiftUI, where a ScrollView's ideal size is its content's.
        let childSize: ViewSize? =
            (proposal.width == nil || proposal.height == nil)
            ? ChildView(content).measure(
                proposal: proposal, context: context.withChildIdentity(type: Content.self)) : nil
        return ViewSize(
            width: proposal.width ?? (childSize?.width ?? context.availableWidth),
            height: proposal.height ?? (childSize?.height ?? context.availableHeight),
            isWidthFlexible: true,
            isHeightFlexible: true
        )
    }

    // MARK: Render

    /// Syncs the horizontal axis to the rendered content width and clamps
    /// its offset (render passes only).
    private func syncHorizontalAxis(
        handler: ScrollViewHandler, wantsHorizontal: Bool,
        bufferWidth: Int, contentWidth: Int, context: RenderContext
    ) {
        guard wantsHorizontal else { return }
        handler.horizontal.extent = bufferWidth
        handler.horizontal.viewportHeight = contentWidth
        if !context.isMeasuring {
            handler.horizontal.clampScrollOffset()
        }
    }

    /// Hydrates the persistent ``ScrollViewHandler`` for this scroll view and
    /// re-syncs every render-captured field (Shift acceleration, wheel-chaining
    /// delays — captured at render so event-time code can read them when the
    /// environment is no longer reachable).
    private func resolvedHandler(persistedFocusID: String, context: RenderContext) -> ScrollViewHandler {
        let handlerKey = StateStorage.StateKey(
            identity: context.identity,
            propertyIndex: StateIndex.handler
        )
        let handlerBox: StateBox<ScrollViewHandler> = context.stateStorage!.storage(
            for: handlerKey,
            default: ScrollViewHandler(
                focusID: persistedFocusID,
                canBeFocused: !isDisabled(in: context)
            )
        )
        let handler = handlerBox.value
        handler.canBeFocused = !isDisabled(in: context)
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier
        // Captured at render so a USER scroll can release a bound anchor to
        // `.window` at event time (the environment is out of reach there).
        handler.anchorPositionBinding = context.environment.anchorPosition
        (handler.declaredAnchorMode, handler.declaredOpeningAnchorMode) =
            context.environment.declaredAnchorModes
        handler.wheelEdgeHold.delayNanos = context.environment.scrollChainingDelay.clampedNanoseconds
        handler.horizontal.wheelEdgeHold.delayNanos = context.environment.scrollChainingDelay.clampedNanoseconds
        // Both axes: `.scrollDisabled` pins the view, not one direction of it.
        handler.isScrollEnabled = context.environment.isScrollEnabled
        handler.horizontal.isScrollEnabled = context.environment.isScrollEnabled
        return handler
    }

    /// The parked scrollTo request to carry down this frame — render passes
    /// only (a measure pass must neither resolve nor clear it). When the
    /// edge indicators are active they replace the viewport's first/last
    /// line, so the request is stamped with one row of headroom per edge.
    private func consumedSeek(
        handler: ScrollViewHandler, drawsTextIndicators: Bool, context: RenderContext
    ) -> ScrollToRequest? {
        guard !context.isMeasuring else { return nil }
        // A `.scrollPosition` write is the same request a `scrollTo` makes; it
        // just arrives as state rather than as a call, so it rides the same
        // machinery rather than a second one beside it.
        guard var seek = handler.pendingScrollTo ?? positionSeek(handler: handler, context: context)
        else {
            return nil
        }
        seek.topInset = edgeInset(drawsTextIndicators: drawsTextIndicators)
        seek.bottomInset = seek.topInset
        return seek
    }

    /// Whether the "N more above / below" lines are this view's vertical
    /// indicator — the other half of ``ScrollIndicatorVisibility``'s question,
    /// and the reason a `.hidden` scroll view now draws nothing at all rather
    /// than falling back to these.
    ///
    /// Asked at `overflowing: true`: the indicators gate themselves on whether
    /// there IS content above or below, so what is being decided here is which
    /// indicator this view uses — and deciding it must not trigger the content
    /// measure `.automatic` would otherwise need.
    private func drawsTextIndicators(_ context: RenderContext) -> Bool {
        context.environment.verticalScrollIndicators(overflowing: true).text
    }

    /// One line per edge when the "N more" indicators are what occupies the
    /// viewport's first and last line. Shared by the seek path and the
    /// designated-anchor reveal so a row cannot be placed under an indicator
    /// by one and not the other.
    private func edgeInset(drawsTextIndicators: Bool) -> Int {
        drawsTextIndicators ? 1 : 0
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let viewportWidth = context.availableWidth
        let viewportHeight = max(0, context.availableHeight)

        // Resolve the persistent focus ID and the handler.
        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: explicitFocusID,
            defaultPrefix: "scrollview",
            propertyIndex: StateIndex.focusID
        )
        let handler = resolvedHandler(persistedFocusID: persistedFocusID, context: context)

        // Rendezvous with an enclosing ScrollViewReader, refreshed every
        // render pass so the proxy always reaches the LIVE handler set.
        if !context.isMeasuring {
            context.environment.scrollToRegistry?.register(
                handler: handler, identity: context.identity, renderCache: context.renderCache)
        }

        // Scrollbar reservation. Each bar steals one cell across the viewport — the
        // vertical bar a trailing column, the horizontal bar a bottom row. The
        // decisions use the prior frame's measured extents (persisted on the
        // handler) so the content is laid out at the reduced size in a single
        // render; on the very first frame nothing has overflowed yet, so an
        // automatic bar appears one frame after the content first overflows.
        let wantsHorizontal = axes.contains(.horizontal)

        // Decide scrollbar reservation from THIS frame's measured content (not the
        // previous frame's persisted extents), so a bar appears / disappears on the
        // same frame the content crosses the viewport edge — no one-frame lag, and
        // the "N more below" hint never flashes a frame without its bar. See
        // `resolveScrollbars` for the monotonic fixpoint (which also prevents the
        // reserve-bar → content-fits → drop-bar → overflows → … oscillation).
        let bars = resolveScrollbars(
            viewportWidth: viewportWidth, viewportHeight: viewportHeight,
            horizontal: wantsHorizontal, context: context)
        let wantsScrollbar = bars.vertical
        let wantsHorizontalBar = bars.horizontal
        let contentWidth = max(1, viewportWidth - (wantsScrollbar ? 1 : 0))
        let contentViewportHeight = max(1, viewportHeight - (wantsHorizontalBar ? 1 : 0))
        let textIndicators = drawsTextIndicators(context)
        handler.viewportHeight = contentViewportHeight
        handler.textIndicatorInset = edgeInset(drawsTextIndicators: textIndicators)
        // §1.5: how far past its edges this view may be pushed. Re-resolved every
        // frame because a `.viewport`-relative allowance moves with the terminal,
        // and an existing excursion is pulled back inside a shrunken one.
        handler.overscrollState.resolve(
            top: context.environment.scrollOverscrollTop,
            bottom: context.environment.scrollOverscrollBottom,
            viewportHeight: contentViewportHeight)

        // A freshly WRITTEN edge anchor jumps to that edge (see the helper);
        // must precede the glue check, whose `seekingTail` read is one-shot.
        adoptWrittenAnchor(handler: handler, context: context)

        // A one-shot End/scrollToBottom intent converges exactly like a
        // glued frame (see ScrollViewHandler.seekingTail).
        // A bound position's edge/offset target moves the scroll view BEFORE
        // the content renders, so the frame carrying the request already shows
        // the destination — `.bottom` by raising the tail-seek flag the End key
        // uses, so the glue below pins it exactly against the real height.
        if !context.isMeasuring { applyPositionOffset(handler: handler, context: context) }
        let seekingTail = handler.seekingTail
        if !context.isMeasuring { handler.seekingTail = false }
        let wasGluedToBottom =
            isGluedToBottom(handler: handler, context: context) || seekingTail
        // The opening frame is now spent: from here on the `.sizeChanges`
        // anchor governs. Render passes only — a measure must not consume it.
        if !context.isMeasuring { handler.hasOpened = true }

        let pendingSeek = consumedSeek(handler: handler, drawsTextIndicators: textIndicators, context: context)
        var (fullBuffer, contentSlice, seekOffset) = renderedContent(
            contentWidth: contentWidth, viewportHeight: contentViewportHeight,
            horizontal: wantsHorizontal, verticalScrollOffset: handler.scrollOffset,
            seek: pendingSeek, edgeInset: edgeInset(drawsTextIndicators: textIndicators),
            handler: handler, context: context, settledExtents: bars.settled)
        if !context.isMeasuring { handler.pendingScrollTo = nil }
        // A sliced reply (Stage 6): the buffer holds only the rendered band;
        // the content height comes from the metadata (estimated suffixes and
        // all — the §3 scrollbar trade), and every content-space consumer
        // below rebases by the slice origin. An estimated total is surfaced
        // in the indicators as an approximate count.
        handler.contentHeight = contentSlice?.totalHeight ?? fullBuffer.height
        handler.contentHeightIsEstimate = contentSlice?.totalIsEstimate ?? false
        if let seekOffset {
            // The content rendered AT the request's offset; adopt it. (The
            // bottom re-glue below must not fight it — scrolling away IS
            // the release, expressed programmatically.)
            handler.scrollOffset = seekOffset
        } else if wasGluedToBottom {
            // Re-glue against the REAL rendered height (the pre-render
            // number was an estimate); the band's margin absorbs small
            // differences and the next frame lands exactly.
            handler.scrollOffset = handler.maxOffset
        }
        syncHorizontalAxis(
            handler: handler, wantsHorizontal: wantsHorizontal,
            bufferWidth: fullBuffer.width, contentWidth: contentWidth, context: context)
        // Re-clamp the offset against the now-known content height — but only on
        // the real render pass. A measure pass may be offered a larger height
        // than the ScrollView finally renders into (e.g. when it shares space
        // with fixed siblings like a trailing footer), so clamping against that
        // measure-time viewport computes too small a `maxOffset` and pulls the
        // offset back every frame, making the content's last screenful
        // unreachable. The render pass runs last and clamps with the true
        // viewport, so legitimate clamping (content grew/shrank) still happens.
        // Mirrors _ListCore / Table.
        if !context.isMeasuring {
            handler.clampScrollOffset()
        }

        // "Follow the focused control": snap the viewport to the focused
        // control when focus moved or it just consumed a key. A render-pass-
        // only side effect; the helper documents the full rationale and the
        // measure-pass gate.
        let pursuitArmed = snapViewportToFocusedControl(
            handler: handler,
            fullBuffer: fullBuffer,
            viewportHeight: contentViewportHeight,
            regionOriginY: contentSlice?.originY ?? 0,
            indicatorsActive: drawsTextIndicators(context),
            suppressed: seekOffset != nil,
            context: context)
        coverSnappedViewport(
            handler: handler, fullBuffer: &fullBuffer, contentSlice: &contentSlice,
            contentWidth: contentWidth, viewportHeight: contentViewportHeight,
            horizontal: wantsHorizontal, context: context)
        if wasGluedToBottom, seekOffset == nil {
            reglueToRefinedTail(
                handler: handler, fullBuffer: &fullBuffer, contentSlice: &contentSlice,
                contentWidth: contentWidth, viewportHeight: contentViewportHeight,
                horizontal: wantsHorizontal, context: context)
        }
        // Settle the pursuit AFTER coverage/re-glue, when the frame's offset
        // is final — see the helper.
        settleRevealPursuit(armed: pursuitArmed, handler: handler, context: context)
        let sliceOriginY = contentSlice?.originY ?? 0

        // Only be a Tab stop when there is actually something to scroll.
        // Registering unconditionally made a non-overflowing ScrollView an
        // invisible focus trap between the real controls (Tab would land on it
        // with no visible indicator). Overflow is known now the content is
        // measured.
        let hasVerticalOverflow = handler.contentHeight > contentViewportHeight
        let hasHorizontalOverflow = wantsHorizontal && fullBuffer.width > contentWidth
        // `.scrollDisabled` leaves no scroll command for the keys to run, so the
        // view drops out of the Tab ring for the same reason a non-overflowing
        // one does: a stop that can do nothing is only an obstacle.
        handler.canBeFocused =
            !isDisabled(in: context) && handler.isScrollEnabled
            && (hasVerticalOverflow || hasHorizontalOverflow)

        // Register so the dispatchKeyEvent → handler chain is wired up; the
        // handler's `canBeFocused` (above) keeps a non-scrollable view out of
        // the Tab ring. When it IS focused + scrollable we highlight the
        // scrollbar (below) so there's a visible focus indicator.
        FocusRegistration.register(context: context, handler: handler)
        let isFocused = FocusRegistration.isFocused(context: context, focusID: persistedFocusID)

        // Build the windowed buffer. With a sliced reply the buffer's own
        // coordinates start at the slice origin, so the clip offset rebases
        // into slice space (clamped: a snap can propose an offset a row
        // above the slice; the next frame's slice covers it).
        var visibleBuffer = windowedBuffer(
            full: fullBuffer,
            scrollOffset: max(0, handler.scrollOffset - sliceOriginY),
            viewportHeight: contentViewportHeight,
            viewportWidth: contentWidth,
            horizontalEnabled: wantsHorizontal,
            horizontalOffset: handler.horizontal.scrollOffset
        )

        visibleBuffer = applyOverscroll(to: visibleBuffer, handler: handler, width: contentWidth)

        applyScrollChrome(
            to: &visibleBuffer, handler: handler, contentWidth: contentWidth,
            wantsScrollbar: wantsScrollbar, wantsHorizontalBar: wantsHorizontalBar,
            isFocused: isFocused, focusID: persistedFocusID, context: context)

        attachViewportMouseHandler(
            to: &visibleBuffer, context: context, handler: handler,
            persistedFocusID: persistedFocusID, viewportWidth: viewportWidth,
            viewportHeight: viewportHeight, wantsHorizontal: wantsHorizontal)

        return visibleBuffer
    }

    /// Slides the windowed content by the overscroll excursion, blank-filling the
    /// gap that opens and clipping the far side — the render of §1.5.
    ///
    /// Applied to the CONTENT only, before the chrome: pushing the content past
    /// an edge must not carry the scrollbar or the "N more" indicators with it,
    /// which describe the content's position rather than sitting in it. And it
    /// is a post-hoc slide rather than an adjusted window origin precisely so
    /// that no windowing or data-indexing arithmetic has to admit an
    /// out-of-range offset (see ``ScrollOverscrollState``).
    ///
    /// `replacingLines` carries the hit-test regions and overlays along by the
    /// same shift, so a control pushed down the screen is still clickable where
    /// it is drawn — and one pushed off it stops being clickable at all.
    private func applyOverscroll(
        to buffer: FrameBuffer, handler: ScrollViewHandler, width: Int
    ) -> FrameBuffer {
        let excursion = handler.overscrollState.excursion
        guard excursion != 0, !buffer.lines.isEmpty else { return buffer }
        let blank = String(repeating: " ", count: max(0, width))
        let gap = min(abs(excursion), buffer.lines.count)
        let lines: [String] =
            excursion < 0
            ? Array(repeating: blank, count: gap) + buffer.lines.dropLast(gap)
            : Array(buffer.lines.dropFirst(gap)) + Array(repeating: blank, count: gap)
        var slid = buffer.replacingLines(
            lines, width: width, uniformWidth: true, overlayShiftY: -excursion)
        // `replacingLines` shifts the runs with everything else, but a slide
        // pushes rows OUT of the viewport: a run that went with them would keep
        // repainting, on a clock, over whatever now occupies that row — or off
        // the buffer entirely. Kept or dropped whole, the same rule the window
        // applies.
        slid.animatedCells = slid.animatedCells.filter {
            $0.offsetY >= 0 && $0.offsetY < lines.count
        }
        return slid
    }

    /// Composes the scroll chrome over the windowed content: the "N more
    /// above/below" indicators — which replace the first/last line rather
    /// than adding height (they're a hint, not extra content), and which a
    /// scrollbar supersedes (it shows the same thing more precisely, so the
    /// two are mutually exclusive) — then the trailing vertical scrollbar
    /// column and the bottom horizontal bar, each made interactive (arrows /
    /// track / thumb drag).
    private func applyScrollChrome(
        to visibleBuffer: inout FrameBuffer, handler: ScrollViewHandler, contentWidth: Int,
        wantsScrollbar: Bool, wantsHorizontalBar: Bool, isFocused: Bool,
        focusID persistedFocusID: String, context: RenderContext
    ) {
        // Indicators REPLACE viewport lines, so a 1-2 line viewport scrolled
        // mid-content would be 100% chrome — "▼ N more below" as the entire
        // view, with the content it advertises never visible at any offset.
        // Content always wins the last lines: indicators need 3+ rows (both
        // may show and at least one content line survives).
        if drawsTextIndicators(context), visibleBuffer.height >= 3 {
            visibleBuffer = applyScrollIndicators(
                to: visibleBuffer,
                handler: handler,
                width: contentWidth,
                palette: context.environment.palette,
                // A CYCLE, not this tick's colour: the indicator hands its
                // cells to the run loop and reads no clock (see
                // `AnimatedCellRun`). Still only when one will be drawn —
                // building a cycle is cheap but not free, and a scroll view
                // that scrolls only horizontally has no vertical indicators.
                cycle: handler.hasContentAbove || handler.hasContentBelow
                    ? scrollIndicatorCycle(isFocused: isFocused, context: context) : nil,
                locale: context.environment.locale
            )
            attachIndicatorMouseHandlers(
                to: &visibleBuffer, contentWidth: contentWidth,
                handler: handler, context: context)
        }
        if wantsScrollbar {
            visibleBuffer = appendVerticalScrollbar(
                to: visibleBuffer, contentWidth: contentWidth, handler: handler,
                isFocused: isFocused, context: context)
            attachScrollbarMouseHandler(
                to: &visibleBuffer, contentWidth: contentWidth, handler: handler,
                focusID: persistedFocusID, context: context)
        }
        if wantsHorizontalBar {
            visibleBuffer = appendHorizontalScrollbar(
                to: visibleBuffer, contentWidth: contentWidth,
                hasVerticalBar: wantsScrollbar, handler: handler,
                isFocused: isFocused, context: context)
            attachHorizontalScrollbarMouseHandler(
                to: &visibleBuffer, contentWidth: contentWidth, handler: handler,
                focusID: persistedFocusID, context: context)
        }
    }

    /// Registers the viewport-wide mouse handler + its hit region. The handler:
    ///   - scrolls on the wheel — vertically, and horizontally (a native
    ///     horizontal wheel, or shift + vertical wheel) when horizontal is enabled;
    ///   - focuses the ScrollView on a left release so the keyboard scroll keys
    ///     reach it without the user having to Tab to it.
    /// The region is inserted at the front of the array so any interactive child
    /// inside the content still wins its clicks (this is the fall-through).
    private func attachViewportMouseHandler(
        to buffer: inout FrameBuffer, context: RenderContext, handler: ScrollViewHandler,
        persistedFocusID: String, viewportWidth: Int, viewportHeight: Int, wantsHorizontal: Bool
    ) {
        guard !context.isMeasuring,
              let mouseDispatcher = context.environment.mouseEventDispatcher,
              !isDisabled(in: context)
        else { return }
        let captureHandler = handler
        let focusManager = context.environment.focusManager
        let captureFocusID = persistedFocusID
        let captureHorizontal = wantsHorizontal
        let mouseHandlerID = mouseDispatcher.register { event in
            // Shift + vertical wheel IS the horizontal gesture, decided before
            // the vertical capture gets a look: the vertical handler consumes
            // .scrollUp/.scrollDown without ever reading the shift bit, so
            // ordering this after it made the documented gesture unreachable
            // whenever the vertical axis could still move — the user could
            // only pan sideways by first riding the vertical axis to an edge.
            // Rewritten onto the horizontal wheel path, not scrolled by hand,
            // so the edge-chaining and no-op-not-consumed rules hold for it.
            if captureHorizontal, event.shift,
                event.button == .scrollUp || event.button == .scrollDown
            {
                let sideways = MouseEvent(
                    button: event.button == .scrollUp ? .scrollLeft : .scrollRight,
                    phase: event.phase, x: event.x, y: event.y,
                    shift: event.shift, ctrl: event.ctrl, meta: event.meta,
                    clickCount: event.clickCount)
                return captureHandler.horizontal.handleHorizontalWheelEvent(sideways)
            }
            if captureHandler.handleWheelEvent(event) { return true }
            if captureHorizontal {
                if captureHandler.horizontal.handleHorizontalWheelEvent(event) { return true }
            }
            if event.button == .left {
                switch event.phase {
                case .pressed:
                    return true
                case .released:
                    focusManager?.focus(id: captureFocusID)
                    return true
                default:
                    return false
                }
            }
            return false
        }
        // The ScrollView's focusID rides on this region: it is how an
        // ENCLOSING ScrollView locates a focused embedded ScrollView to
        // scroll it into view (`snapViewportToFocusedControl` scans regions
        // by focusID — the same rule Table and List follow).
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: viewportWidth, height: viewportHeight,
                handlerID: mouseHandlerID,
                focusID: persistedFocusID),
            at: 0
        )
        // Register this viewport as a drag auto-scroll zone (sharing the region
        // id, so the driver can read its absolute rect): a drag hovering near an
        // edge scrolls the content to bring an off-screen drop target into view.
        // Auto-scroll is a gesture, so `.scrollDisabled` withholds the zone —
        // the drop targets that are visible stay droppable, the rest stay out of
        // reach, which is what pinning the view means.
        guard context.environment.isScrollEnabled else { return }
        context.environment.dragAndDropSession?.registerAutoScrollZone(
            DragAndDropSession.AutoScrollZone(
                handlerID: mouseHandlerID,
                vertical: handler,
                horizontal: wantsHorizontal ? handler.horizontal : nil,
                delayNanos: context.environment.dragAutoScrollDelay.clampedNanoseconds,
                    shiftStep: context.environment.shiftStepMultiplier))
    }

    /// Resolves which scrollbars to reserve this frame, from the CURRENT content's
    /// measured extents, to a monotonic fixpoint.
    ///
    /// Each bar steals one cell (vertical → trailing column, horizontal → bottom
    /// row), shrinking the area the content lays into — which, for a `.viewport`-fit
    /// image, resizes the image and can tip the OTHER axis over — so we re-measure
    /// after each reservation. Bars are only ever ADDED within the pass, never
    /// dropped because the content then fits the reduced area: dropping is exactly
    /// what oscillates (bar → fits → no bar → overflows → bar → …). Measuring is
    /// side-effect-free (`measureChild`), so this never double-fires the content's
    /// effects; the content is rendered once, afterwards, at the resolved size.
    /// `.visible` forces that axis's bar on, `.hidden`/`.never` force it off.
    ///
    /// Also returns the extents it settled on, when they were measured against
    /// the dimensions the reservation finally chose. That is the same question
    /// `renderedContent` asks next, at the same numbers, and answering it is a
    /// walk of ``measureNaturalExtent``'s budget ladder over the whole content
    /// — the single most expensive thing a scrolling page does. `nil` when the
    /// loop ran out of rounds with the flags still moving (its extents then
    /// describe dimensions that are no longer the answer), and on the
    /// non-`.automatic` path, which measures nothing.
    private func resolveScrollbars(
        viewportWidth: Int, viewportHeight: Int, horizontal: Bool, context: RenderContext
    ) -> (vertical: Bool, horizontal: Bool, settled: (width: Int, height: Int)?) {
        let verticalPolicy = context.environment.verticalScrollIndicatorVisibility
        let horizontalPolicy = context.environment.horizontalScrollIndicatorVisibility
        // Only the scrollbar style reserves anything on the vertical axis; the
        // text indicators replace a viewport line rather than a column, and
        // decide themselves, after the render, from what is actually hidden.
        // The horizontal axis has no text form, so its bar stands whatever the
        // style says.
        let verticalBar = context.environment.scrollIndicatorStyle == .scrollbar
        var wantsScrollbar = verticalBar && verticalPolicy == .visible
        var wantsHorizontalBar = horizontal && horizontalPolicy == .visible
        // Only an axis that asked to be told whether it overflows is worth
        // measuring for, and measuring is the expensive part — so a view with
        // `.visible` down one side and nothing on the other still measures
        // nothing at all, and neither does one whose bars are hidden or whose
        // vertical indicator is the text form.
        let measuresVertical = verticalBar && verticalPolicy == .automatic
        let measuresHorizontal = horizontal && horizontalPolicy == .automatic
        guard measuresVertical || measuresHorizontal else {
            return (wantsScrollbar, wantsHorizontalBar, nil)
        }
        var settled: (width: Int, height: Int)?
        // ≤2 reservations (one per axis) ⇒ converges in ≤3 measure rounds.
        for _ in 0..<3 {
            let probeWidth = max(1, viewportWidth - (wantsScrollbar ? 1 : 0))
            let probeHeight = max(1, viewportHeight - (wantsHorizontalBar ? 1 : 0))
            let extents = contentExtents(
                contentWidth: probeWidth, viewportHeight: probeHeight,
                horizontal: horizontal, context: context)
            var changed = false
            if measuresVertical, !wantsScrollbar, extents.height > probeHeight {
                wantsScrollbar = true
                changed = true
            }
            if measuresHorizontal, !wantsHorizontalBar, extents.width > probeWidth {
                wantsHorizontalBar = true
                changed = true
            }
            // Only a round that changed nothing measured the dimensions the
            // caller is about to render at.
            if !changed {
                settled = extents
                break
            }
        }
        return (wantsScrollbar, wantsHorizontalBar, settled)
    }
}

// MARK: - Viewport size publication

/// The size, in cells, of the innermost enclosing ``ScrollView``'s visible viewport
/// — its content area, excluding any scrollbar column.
///
/// ``ScrollView`` publishes this into the environment so a descendant can size
/// itself relative to the *visible* area rather than the (deliberately unbounded
/// on the scroll axis) proposed size. ``Image`` consumes it for
/// ``ImageFitTarget/viewport``. `nil` when there is no enclosing scroll view.
struct ScrollViewportSize: Sendable, Hashable {
    var width: Int
    var height: Int
}

private struct ScrollViewportSizeKey: EnvironmentKey {
    static let defaultValue: ScrollViewportSize? = nil
}

extension EnvironmentValues {
    /// The innermost enclosing ``ScrollView``'s visible viewport size — see
    /// ``ScrollViewportSize``.
    var scrollViewportSize: ScrollViewportSize? {
        get { self[ScrollViewportSizeKey.self] }
        set { self[ScrollViewportSizeKey.self] = newValue }
    }
}

// MARK: - Scroll Content Window

/// The vertical slice of the scroll content that is currently visible: the
/// scroll `offset` (in content lines) and the viewport `height`. A vertical
/// ``ScrollView`` publishes this so its *direct* content — specifically a
/// ``LazyVStack`` — can render only the rows intersecting the viewport (true
/// viewport windowing) rather than materialising every row into the ScrollView's
/// tall measure canvas. `nil` when there is no enclosing vertical scroll view.
///
/// Consumed once: the responding stack clears it for its children, so it only
/// affects a `LazyVStack` sitting at the scroll content's origin. A `LazyVStack`
/// nested below other content isn't at `offset == 0` in the ScrollView's
/// coordinate space, so it is left un-windowed (renders normally).
private struct ScrollContentWindowKey: EnvironmentKey {
    static let defaultValue: ScrollContentWindow? = nil
}

extension EnvironmentValues {
    /// The visible vertical slice a ``LazyVStack`` should window to — see
    /// ``ScrollContentWindow``.
    var scrollContentWindow: ScrollContentWindow? {
        get { self[ScrollContentWindowKey.self] }
        set { self[ScrollContentWindowKey.self] = newValue }
    }
}

// MARK: - Disabled state

extension _ScrollViewCore {
    /// Whether this scroll view is disabled, counting an ancestor's
    /// `.disabled(true)`.
    ///
    /// The third of the three containers that read neither `\.isEnabled` nor
    /// anything derived from it — see ``_ListCore/isDisabled(in:)`` for why
    /// their own concrete `disabled(_:)` overload hid it.
    func isDisabled(in context: RenderContext) -> Bool {
        isDisabled || !context.environment.isEnabled
    }
}
