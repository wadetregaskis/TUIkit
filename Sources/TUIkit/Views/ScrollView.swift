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
/// > Note: Only vertical scrolling is supported in this initial
///   version. The `axes:` argument is accepted for SwiftUI API
///   parity but `.horizontal` is silently treated as `.vertical`.
///   Two-axis scrolling is tracked as a follow-up.
public struct ScrollView<Content: View>: View {
    /// The axes along which content scrolls. Currently only
    /// `.vertical` is implemented; `.horizontal` is accepted for
    /// API parity but ignored.
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

/// Internal core that performs the windowing, hit-testing, and
/// keyboard wiring for ``ScrollView``.
private struct _ScrollViewCore<Content: View>: View, Renderable, Layoutable {

    let axes: Axis.Set
    let showsIndicators: Bool
    let content: Content
    let explicitFocusID: String?
    let isDisabled: Bool

    var body: Never { fatalError("_ScrollViewCore renders via Renderable") }

    /// StateStorage property indices for the handler and the
    /// persisted focus ID.
    private enum StateIndex {
        static let handler = 0
        static let focusID = 1
    }

    // MARK: Layout

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // A ScrollView is greedy on both axes: it takes whatever
        // space the parent offers and scrolls if its content
        // doesn't fit.
        return ViewSize(
            width: proposal.width ?? context.availableWidth,
            height: proposal.height ?? context.availableHeight,
            isWidthFlexible: true,
            isHeightFlexible: true
        )
    }

    // MARK: Render

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
        handler.viewportHeight = viewportHeight

        // Render the content at a tall canvas so it lays out at
        // its natural full height without being clipped to the
        // viewport. The canvas is bounded — Int.max risks
        // overflow downstream — but generous enough that any
        // realistic content lays out without truncation.
        let measureHeight = max(viewportHeight * 64, 4096)
        var measureContext = context
        measureContext.availableWidth = viewportWidth
        measureContext.availableHeight = measureHeight
        let fullBuffer = TUIkit.renderToBuffer(content, context: measureContext)

        handler.contentHeight = fullBuffer.height
        // Re-clamp the offset against the now-known content
        // height; the user may have grown / shrunk the content
        // between renders.
        handler.scrollOffset = max(0, min(handler.maxOffset, handler.scrollOffset))

        // Register focus so the dispatchKeyEvent → handler chain
        // is wired up. The handler's own state controls what
        // each key does — we don't read isFocused here because
        // the ScrollView's appearance doesn't change with focus.
        FocusRegistration.register(context: context, handler: handler)

        // Build the windowed buffer.
        var visibleBuffer = windowedBuffer(
            full: fullBuffer,
            scrollOffset: handler.scrollOffset,
            viewportHeight: viewportHeight,
            viewportWidth: viewportWidth
        )

        // Compose the scroll-indicator chrome on top of the
        // windowed content. Indicators replace the first /
        // last line of the visible buffer rather than adding
        // to its height — they're a hint, not extra content.
        if showsIndicators {
            let palette = context.environment.palette
            visibleBuffer = applyScrollIndicators(
                to: visibleBuffer,
                handler: handler,
                width: viewportWidth,
                palette: palette
            )
        }

        // Mouse wheel handler + hit-test region covering the
        // viewport. We don't translate clicks here; click
        // routing to inner controls is handled by their own
        // hit-test regions, which were emitted into the
        // content buffer and shifted up by `windowedBuffer`.
        if !context.isMeasuring,
           let mouseDispatcher = context.environment.mouseEventDispatcher
        {
            let captureHandler = handler
            let mouseHandlerID = mouseDispatcher.register { event in
                switch event.button {
                case .scrollUp:
                    captureHandler.scroll(by: -ViewConstants.mouseWheelScrollLines)
                    return true
                case .scrollDown:
                    captureHandler.scroll(by: ViewConstants.mouseWheelScrollLines)
                    return true
                default:
                    return false
                }
            }
            visibleBuffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: 0,
                    offsetY: 0,
                    width: viewportWidth,
                    height: viewportHeight,
                    handlerID: mouseHandlerID
                )
            )
        }

        return visibleBuffer
    }

    // MARK: Windowing

    /// Builds the visible-window buffer from `full`, dropping
    /// overlays and hit-test regions that fall entirely outside
    /// the viewport and shifting the rest up by `scrollOffset`.
    private func windowedBuffer(
        full: FrameBuffer,
        scrollOffset: Int,
        viewportHeight: Int,
        viewportWidth: Int
    ) -> FrameBuffer {
        guard viewportHeight > 0 else {
            return FrameBuffer(lines: [], width: viewportWidth)
        }

        // Slice the visible lines, padding with blank lines if
        // the content is shorter than the viewport so the
        // ScrollView fills the space it was given.
        var visibleLines = Array(
            full.lines.dropFirst(scrollOffset).prefix(viewportHeight)
        )
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
        let viewportTop = scrollOffset
        let viewportBottom = scrollOffset + viewportHeight
        let visibleOverlays = full.overlays.compactMap { overlay -> OverlayLayer? in
            let topY = overlay.offsetY
            let bottomY = overlay.offsetY + overlay.content.height
            guard bottomY > viewportTop, topY < viewportBottom else { return nil }
            return overlay.shifted(byX: 0, y: -scrollOffset)
        }

        // Filter + shift hit-test regions, same logic.
        let visibleRegions = full.hitTestRegions.compactMap { region -> HitTestRegion? in
            let topY = region.offsetY
            let bottomY = region.offsetY + region.height
            guard bottomY > viewportTop, topY < viewportBottom else { return nil }
            return HitTestRegion(
                offsetX: region.offsetX,
                offsetY: region.offsetY - scrollOffset,
                width: region.width,
                height: region.height,
                handlerID: region.handlerID
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
            let rowsAbove = handler.scrollOffset
            lines[0] = renderScrollIndicator(
                direction: .up,
                count: rowsAbove,
                width: width,
                palette: palette
            )
        }

        if handler.hasContentBelow, lines.count >= 1 {
            let rowsBelow = max(
                0,
                handler.contentHeight
                    - (handler.scrollOffset + handler.viewportHeight)
            )
            lines[lines.count - 1] = renderScrollIndicator(
                direction: .down,
                count: rowsBelow,
                width: width,
                palette: palette
            )
        }

        return buffer.replacingLines(lines)
    }
}
