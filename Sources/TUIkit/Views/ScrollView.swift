//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollView.swift
//
//  Created by LAYERED.work
//  License: MIT

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
/// When content extends beyond the viewport, "N more above" /
/// "N more below" indicators appear at the top and bottom edges
/// of the visible area, matching the indicators used by `List`.
/// Pass `showsIndicators: false` to suppress them — note that
/// scrolling itself still works, it's only the visual indicator
/// that disappears.
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
/// > Note: Both axes are supported. Pass `.vertical` (the default),
///   `.horizontal`, or `[.horizontal, .vertical]`. When horizontal
///   scrolling is enabled the view also renders a bottom scrollbar and
///   responds to a native horizontal wheel (or shift + vertical wheel).
public struct ScrollView<Content: View>: View {
    /// The axes along which content scrolls (`.vertical`, `.horizontal`,
    /// or both). Both are fully implemented.
    public let axes: Axis.Set

    /// Whether to show "N more above / below" indicators at the
    /// viewport edges when content extends beyond them.
    public let showsIndicators: Bool

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
    ///   - showsIndicators: Whether to show edge indicators
    ///     (default `true`).
    ///   - content: A ViewBuilder that defines the content to
    ///     scroll.
    public init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
        self.explicitFocusID = nil
        self.isDisabled = false
    }

    public var body: some View {
        _ScrollViewCore(
            axes: axes,
            showsIndicators: showsIndicators,
            content: content,
            explicitFocusID: explicitFocusID,
            isDisabled: isDisabled
        )
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
            && lhs.showsIndicators == rhs.showsIndicators
            && lhs.content == rhs.content
            && lhs.explicitFocusID == rhs.explicitFocusID
            && lhs.isDisabled == rhs.isDisabled
    }
}

// MARK: - _ScrollViewCore (internal rendering)

/// StateStorage property indices for ``_ScrollViewCore``.
/// Lifted out of the generic struct because Swift does not
/// allow static stored properties in generic types.
private enum ScrollViewStateIndex {
    static let handler = 0
    static let focusID = 1
    static let lastFocusedID = 2
    static let lastInteractionGen = 3
}

/// A lightweight String-box used by ``_ScrollViewCore`` to track
/// which focusable was focused at the previous render, so it can
/// detect focus *changes* and scroll the new focused control into
/// view. Class-typed so a StateBox can hold it mutably across
/// renders.
private final class LastFocusedIDBox: @unchecked Sendable {
    var value: String?
}

/// Tracks the ``FocusManager/focusedInteractionGeneration`` value
/// seen at the previous render so ``_ScrollViewCore`` can detect
/// "the focused control just consumed a key event" between
/// frames. Class-typed for the same reason as
/// ``LastFocusedIDBox``.
private final class LastInteractionGenBox: @unchecked Sendable {
    var value: UInt64 = 0
}

/// Internal core that performs the windowing, hit-testing, and
/// keyboard wiring for ``ScrollView``.
private struct _ScrollViewCore<Content: View>: View, Renderable, Layoutable {

    let axes: Axis.Set
    let showsIndicators: Bool
    let content: Content
    let explicitFocusID: String?
    let isDisabled: Bool

    var body: Never { fatalError("_ScrollViewCore renders via Renderable") }

    private typealias StateIndex = ScrollViewStateIndex

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
    private func snapViewportToFocusedControl(
        handler: ScrollViewHandler,
        fullBuffer: FrameBuffer,
        viewportHeight: Int,
        regionOriginY: Int = 0,
        indicatorsActive: Bool = true,
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

        if shouldSnap,
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
            let topIndicatorShows =
                indicatorsActive && showsIndicators && viewportTop > 0
            let bottomIndicatorShows =
                indicatorsActive && showsIndicators
                && viewportBottom < handler.contentHeight
            let visibleTop = viewportTop + (topIndicatorShows ? 1 : 0)
            let visibleBottom = viewportBottom - (bottomIndicatorShows ? 1 : 0)

            if regionTop < visibleTop {
                // Scroll-up: align the region's top with viewportTop, leaving
                // 1 row of headroom for the top indicator when one appears.
                let proposed = regionTop
                let topIndicatorRow = (showsIndicators && proposed > 0) ? 1 : 0
                handler.scrollOffset =
                    max(0, min(handler.maxOffset, proposed - topIndicatorRow))
            } else if regionBottom > visibleBottom {
                // Scroll-down: align the region's bottom with viewportBottom,
                // leaving 1 row for the bottom indicator if one appears.
                let proposed = regionBottom - viewportHeight
                let bottomIndicatorWouldAppear =
                    showsIndicators
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

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let viewportWidth = context.availableWidth
        let viewportHeight = max(0, context.availableHeight)
        let stateStorage = context.environment.stateStorage!

        // Resolve the persistent focus ID and the handler.
        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: explicitFocusID,
            defaultPrefix: "scrollview",
            propertyIndex: StateIndex.focusID
        )
        let handlerKey = StateStorage.StateKey(
            identity: context.identity,
            propertyIndex: StateIndex.handler
        )
        let handlerBox: StateBox<ScrollViewHandler> = stateStorage.storage(
            for: handlerKey,
            default: ScrollViewHandler(
                focusID: persistedFocusID,
                canBeFocused: !isDisabled
            )
        )
        let handler = handlerBox.value
        handler.canBeFocused = !isDisabled
        // Captured at render so Shift+arrow can accelerate at event time, when the
        // environment is no longer reachable.
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier
        handler.wheelEdgeHold.delayNanos = context.environment.scrollChainingDelay.wheelDelayNanos
        handler.horizontal.wheelEdgeHold.delayNanos = context.environment.scrollChainingDelay.wheelDelayNanos

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
        handler.viewportHeight = contentViewportHeight

        let (fullBuffer, contentSlice) = renderedContent(
            contentWidth: contentWidth, viewportHeight: contentViewportHeight,
            horizontal: wantsHorizontal, verticalScrollOffset: handler.scrollOffset,
            context: context)
        // A sliced reply (Stage 6): the buffer holds only the rendered band;
        // the content height comes from the metadata (estimated suffixes and
        // all — the §3 scrollbar trade), and every content-space consumer
        // below rebases by the slice origin.
        let sliceOriginY = contentSlice?.originY ?? 0
        handler.contentHeight = contentSlice?.totalHeight ?? fullBuffer.height
        // Sync the horizontal axis to the rendered content width and clamp.
        if wantsHorizontal {
            handler.horizontal.extent = fullBuffer.width
            handler.horizontal.viewportHeight = contentWidth
            if !context.isMeasuring {
                handler.horizontal.clampScrollOffset()
            }
        }
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
        snapViewportToFocusedControl(
            handler: handler,
            fullBuffer: fullBuffer,
            viewportHeight: contentViewportHeight,
            regionOriginY: sliceOriginY,
            indicatorsActive: !wantsScrollbar,
            context: context)

        // Only be a Tab stop when there is actually something to scroll.
        // Registering unconditionally made a non-overflowing ScrollView an
        // invisible focus trap between the real controls (Tab would land on it
        // with no visible indicator). Overflow is known now the content is
        // measured.
        let hasVerticalOverflow = handler.contentHeight > contentViewportHeight
        let hasHorizontalOverflow = wantsHorizontal && fullBuffer.width > contentWidth
        handler.canBeFocused = !isDisabled && (hasVerticalOverflow || hasHorizontalOverflow)

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

        // Compose the scroll-indicator chrome on top of the windowed content.
        // Indicators replace the first / last line of the visible buffer rather
        // than adding to its height — they're a hint, not extra content. A
        // scrollbar supersedes the text indicators (it shows the same thing more
        // precisely), so they are mutually exclusive.
        if showsIndicators && !wantsScrollbar {
            let palette = context.environment.palette
            visibleBuffer = applyScrollIndicators(
                to: visibleBuffer,
                handler: handler,
                width: contentWidth,
                palette: palette
            )
        }

        // Append the trailing scrollbar column over the reserved width, then make
        // it interactive (arrows / track / thumb drag).
        if wantsScrollbar {
            visibleBuffer = appendVerticalScrollbar(
                to: visibleBuffer, contentWidth: contentWidth, handler: handler,
                isFocused: isFocused, context: context)
            attachScrollbarMouseHandler(
                to: &visibleBuffer, contentWidth: contentWidth, handler: handler, context: context)
        }

        // Append the bottom horizontal scrollbar over the reserved row (with a
        // corner cell where it meets the vertical bar), then make it interactive.
        if wantsHorizontalBar {
            visibleBuffer = appendHorizontalScrollbar(
                to: visibleBuffer, contentWidth: contentWidth,
                hasVerticalBar: wantsScrollbar, handler: handler,
                isFocused: isFocused, context: context)
            attachHorizontalScrollbarMouseHandler(
                to: &visibleBuffer, contentWidth: contentWidth, handler: handler, context: context)
        }

        attachViewportMouseHandler(
            to: &visibleBuffer, context: context, handler: handler,
            persistedFocusID: persistedFocusID, viewportWidth: viewportWidth,
            viewportHeight: viewportHeight, wantsHorizontal: wantsHorizontal)

        return visibleBuffer
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
              !isDisabled
        else { return }
        let captureHandler = handler
        let focusManager = context.environment.focusManager
        let captureFocusID = persistedFocusID
        let captureHorizontal = wantsHorizontal
        let mouseHandlerID = mouseDispatcher.register { event in
            if captureHandler.handleWheelEvent(event) { return true }
            if captureHorizontal {
                if captureHandler.horizontal.handleHorizontalWheelEvent(event) { return true }
                if event.shift, event.button == .scrollUp {
                    captureHandler.horizontal.scroll(by: -ViewConstants.mouseWheelScrollLines)
                    return true
                }
                if event.shift, event.button == .scrollDown {
                    captureHandler.horizontal.scroll(by: ViewConstants.mouseWheelScrollLines)
                    return true
                }
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
        buffer.hitTestRegions.insert(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: viewportWidth, height: viewportHeight,
                handlerID: mouseHandlerID),
            at: 0
        )
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
    /// `.visible` forces both bars on, `.hidden` forces them off.
    private func resolveScrollbars(
        viewportWidth: Int, viewportHeight: Int, horizontal: Bool, context: RenderContext
    ) -> (vertical: Bool, horizontal: Bool) {
        let barVisibility = context.environment.scrollbarVisibility
        var wantsScrollbar = barVisibility == .visible
        var wantsHorizontalBar = horizontal && barVisibility == .visible
        guard barVisibility == .automatic else {
            return (wantsScrollbar, wantsHorizontalBar)
        }
        // ≤2 reservations (one per axis) ⇒ converges in ≤3 measure rounds.
        for _ in 0..<3 {
            let probeWidth = max(1, viewportWidth - (wantsScrollbar ? 1 : 0))
            let probeHeight = max(1, viewportHeight - (wantsHorizontalBar ? 1 : 0))
            let extents = contentExtents(
                contentWidth: probeWidth, viewportHeight: probeHeight,
                horizontal: horizontal, context: context)
            var changed = false
            if !wantsScrollbar, extents.height > probeHeight {
                wantsScrollbar = true
                changed = true
            }
            if horizontal, !wantsHorizontalBar, extents.width > probeWidth {
                wantsHorizontalBar = true
                changed = true
            }
            if !changed { break }
        }
        return (wantsScrollbar, wantsHorizontalBar)
    }

    /// The content's natural extents at a candidate viewport, WITHOUT building a
    /// buffer — the same measures `renderedContent` uses to size its render, so the
    /// scrollbar-reservation decision matches what will actually be drawn.
    ///
    /// `height` is the rendered buffer's height, `max(viewportHeight,
    /// naturalHeight)`: the natural height is measured with a generous height budget
    /// (a stack's measure clamps its report to `availableHeight`, so a small budget
    /// would cap tall content) and an unspecified height proposal, which collapses a
    /// flexible filler such as `Spacer()` to its minimum. (Rendering into a fixed
    /// tall canvas would instead let a Spacer expand to thousands of lines and
    /// report a phantom overflow.) `width` is the render width: the content's
    /// natural width when horizontal scrolling is on — so it can be wider than the
    /// viewport and scroll, rather than wrapping to fit — else `contentWidth`.
    ///
    /// Measures under the content's OWN child identity, distinct from the
    /// ScrollView's: otherwise a directly-stateful content view would bind its
    /// `@State` (property indices 0, 1, …) at the ScrollView's identity, colliding
    /// with the ScrollView's own state keys (handler, focusID, …). `renderedContent`
    /// uses the same identity, so state hydrates consistently.
    private func contentExtents(
        contentWidth: Int, viewportHeight: Int, horizontal: Bool, context: RenderContext
    ) -> (width: Int, height: Int) {
        var measureContext = context.withChildIdentity(type: Content.self)
        // Publish the visible viewport so descendants can fit to it instead of the
        // (unbounded, below) measure canvas — e.g. Image's `.imageFitTarget(.viewport)`.
        measureContext.environment.scrollViewportSize = ScrollViewportSize(
            width: contentWidth, height: viewportHeight)
        measureContext.availableHeight = max(viewportHeight * 64, 4096)

        let renderWidth: Int
        if horizontal {
            measureContext.availableWidth = max(contentWidth * 64, 4096)
            let naturalWidth = measureChild(
                content, proposal: ProposedSize(width: nil, height: nil), context: measureContext
            ).width
            renderWidth = max(contentWidth, naturalWidth)
        } else {
            renderWidth = contentWidth
        }

        measureContext.availableWidth = renderWidth
        let naturalHeight = measureChild(
            content,
            proposal: ProposedSize(width: renderWidth, height: nil),
            context: measureContext
        ).height
        return (width: renderWidth, height: max(viewportHeight, naturalHeight))
    }

    /// Renders the content to its full (unwindowed) buffer, sized via
    /// ``contentExtents(contentWidth:viewportHeight:horizontal:context:)`` so a
    /// flexible filler behaves well: a Spacer expands only as far as the viewport
    /// (spreading content across the visible area when it fits — e.g.
    /// `VStack { Text; Spacer; Text }` puts the two at top and bottom) and collapses
    /// when the content is taller, so it scrolls without the filler forcing extra
    /// height.
    private func renderedContent(
        contentWidth: Int, viewportHeight: Int, horizontal: Bool,
        verticalScrollOffset: Int, context: RenderContext
    ) -> (buffer: FrameBuffer, slice: (originY: Int, totalHeight: Int)?) {
        let extents = contentExtents(
            contentWidth: contentWidth, viewportHeight: viewportHeight,
            horizontal: horizontal, context: context)
        var measureContext = context.withChildIdentity(type: Content.self)
        measureContext.environment.scrollViewportSize = ScrollViewportSize(
            width: contentWidth, height: viewportHeight)
        // Publish the visible vertical slice so a direct `LazyVStack` renders only
        // the rows intersecting the viewport (true windowing) rather than every
        // row into the tall canvas. Vertical-only: horizontal scrolling has no
        // row concept. The offset is this frame's already-clamped value; the
        // final clip (`windowedBuffer`) uses the same value, so they agree for
        // stable content. `contentIdentity` restricts consumption to the direct
        // content (a lazy stack under a header is NOT at the scroll origin);
        // the `reply` slot lets the stack return a compact band + metadata
        // (Stage 6) instead of a full-height canvas of mostly blank lines.
        var reply: ScrollContentReply?
        if !horizontal {
            let contentReply = ScrollContentReply()
            reply = contentReply
            measureContext.environment.scrollContentWindow = ScrollContentWindow(
                offset: verticalScrollOffset, viewportHeight: viewportHeight,
                contentIdentity: measureContext.identity, reply: contentReply)
        }
        measureContext.availableWidth = extents.width
        measureContext.availableHeight = extents.height
        let buffer = TUIkit.renderToBuffer(content, context: measureContext)
        if let reply, let origin = reply.sliceOriginY, let total = reply.sliceTotalHeight {
            return (buffer, (origin, total))
        }
        return (buffer, nil)
    }

    /// Registers a mouse handler over the scrollbar's single column so the arrows
    /// step by one, a track click pages or jumps, and the thumb drags. Inserted at
    /// the front of the regions array *before* the viewport handler's own
    /// `insert(at: 0)` pushes it back one, so the bar is hit-tested ahead of the
    /// viewport for its column (the viewport still wins everywhere else).
    private func attachScrollbarMouseHandler(
        to buffer: inout FrameBuffer, contentWidth: Int,
        handler: ScrollViewHandler, context: RenderContext
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
        let barHandlerID = mouseDispatcher.register(barHandler)
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
    private func attachHorizontalScrollbarMouseHandler(
        to buffer: inout FrameBuffer, contentWidth: Int,
        handler: ScrollViewHandler, context: RenderContext
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
        let barHandlerID = mouseDispatcher.register(barHandler)
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
    private func appendVerticalScrollbar(
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
            colors: ScrollbarColors(
                // The thumb is the focus indicator: accent when the ScrollView
                // holds keyboard focus, quiet otherwise.
                thumb: isFocused ? palette.accent : palette.foregroundSecondary,
                track: palette.foregroundQuaternary,
                arrow: isFocused ? palette.accent : palette.foregroundTertiary))
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
    private func appendHorizontalScrollbar(
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
            colors: ScrollbarColors(
                thumb: isFocused ? palette.accent : palette.foregroundSecondary,
                track: palette.foregroundQuaternary,
                arrow: isFocused ? palette.accent : palette.foregroundTertiary))
        let corner =
            hasVerticalBar
            ? ANSIRenderer.colorize(" ", background: palette.foregroundQuaternary)
            : ""
        var lines = buffer.lines
        lines.append(bar + corner)
        return buffer.replacingLines(
            lines, width: contentWidth + (hasVerticalBar ? 1 : 0), uniformWidth: true)
    }

    // MARK: Windowing

    /// Builds the visible-window buffer from `full`, dropping
    /// overlays and hit-test regions that fall entirely outside
    /// the viewport and shifting the rest up by `scrollOffset`.
    private func windowedBuffer(
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
            let topY = overlay.offsetY
            let bottomY = overlay.offsetY + overlay.content.height
            guard bottomY > viewportTop, topY < viewportBottom else { return nil }
            return overlay.shifted(byX: dx, y: -scrollOffset)
        }

        // Filter + shift hit-test regions, same logic.
        let visibleRegions = full.hitTestRegions.compactMap { region -> HitTestRegion? in
            let topY = region.offsetY
            let bottomY = region.offsetY + region.height
            guard bottomY > viewportTop, topY < viewportBottom else { return nil }
            return HitTestRegion(
                offsetX: region.offsetX + dx,
                offsetY: region.offsetY - scrollOffset,
                width: region.width,
                height: region.height,
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
        }

        var result = FrameBuffer(lines: visibleLines, width: viewportWidth)
        result.overlays = visibleOverlays
        result.hitTestRegions = visibleRegions
        return result
    }

    // MARK: Indicators

    /// Replaces the top and / or bottom lines of `buffer` with
    /// scroll-indicator strings when the content extends past
    /// the visible area. Returns `buffer` unchanged when there
    /// is nothing to scroll to.
    private func applyScrollIndicators(
        to buffer: FrameBuffer,
        handler: ScrollViewHandler,
        width: Int,
        palette: any Palette
    ) -> FrameBuffer {
        guard buffer.height > 0 else { return buffer }
        guard handler.hasContentAbove || handler.hasContentBelow else {
            return buffer
        }

        var lines = buffer.lines

        if handler.hasContentAbove, !lines.isEmpty {
            // Indicator rows are padded to full viewport width
            // — without padding the resulting buffer's effective
            // width collapses to the indicator's own length.
            lines[0] = renderScrollIndicator(
                direction: .up,
                count: handler.rowsAbove,
                width: width,
                palette: palette
            ).padToVisibleWidth(width)
        }

        if handler.hasContentBelow, lines.count >= 1 {
            lines[lines.count - 1] = renderScrollIndicator(
                direction: .down,
                count: handler.rowsBelow,
                width: width,
                palette: palette
            ).padToVisibleWidth(width)
        }

        return buffer.replacingLines(lines)
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
struct ScrollContentWindow: Sendable, Hashable {
    var offset: Int
    var viewportHeight: Int

    /// The identity of the ScrollView's direct content. A windowed stack
    /// consumes this window only when its own identity is a single-child
    /// descent from here (`ViewIdentity/isDirectDescent(from:)`): a stack
    /// that is one sibling among several is NOT at the scroll origin, and
    /// windowing there would blank the wrong rows. `nil` (tests, direct
    /// injection) means "trust the publisher" and consume unconditionally.
    var contentIdentity: ViewIdentity?

    /// The render-pass reply slot (Stage 6): the stack reports the compact
    /// slice it actually rendered, so the ScrollView can clip a band
    /// instead of a full-height canvas. `nil` (tests, measure passes) keeps
    /// the stack emitting the classic full-height buffer.
    var reply: ScrollContentReply?
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

    static func == (lhs: ScrollContentReply, rhs: ScrollContentReply) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

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
