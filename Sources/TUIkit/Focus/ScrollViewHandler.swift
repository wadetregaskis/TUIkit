//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollViewHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - ScrollViewHandler

/// A focus handler for ``ScrollView``.
///
/// `ScrollViewHandler` owns the scroll-position state and the
/// keyboard-driven scroll navigation for a `ScrollView`. It is a
/// peer of ``ItemListHandler`` for the no-selection,
/// no-row-structure case: there is just a viewport over a taller
/// content area, and the keys and the wheel move where that
/// viewport lands.
///
/// # Interaction model
///
/// - **Mouse wheel** scrolls by ``ViewConstants/mouseWheelScrollLines``
///   lines per tick. Wheel scrolling is independent of focus —
///   the wheel works whether or not the scroll view itself has
///   focus, matching the rest of TUIkit (see ``ItemListHandler``).
/// - **Arrow keys** scroll by one line at a time. **Page Up** /
///   **Page Down** scroll by one viewport height. **Home** /
///   **End** jump to the very top / bottom. All keyboard
///   scrolling requires the scroll view to have focus.
///
/// The handler does not track selection — there is no
/// "currently focused row" concept in a generic scroll view.
///
/// > Note: Like ``ItemListHandler`` and ``TextFieldHandler``,
///   `ScrollViewHandler` isn't marked `@MainActor`. The
///   framework guarantees handlers are only touched from the
///   render loop / event dispatch (both `@MainActor`), so the
///   nonisolated class conforms cleanly to the nonisolated
///   `Focusable` protocol without crossing an isolation
///   boundary.
public final class ScrollViewHandler: Focusable, ScrollableOffsetState {

    /// The unique focus identifier for this scroll view.
    public let focusID: String

    /// Whether this scroll view can currently receive focus.
    ///
    /// Disabled scroll views still scroll on wheel input (clicks
    /// reach them via the hit-test region), but cannot become
    /// the keyboard focus.
    public var canBeFocused: Bool

    /// The current scroll position, measured in lines from the
    /// top of the content. Always in `0...max(0, contentHeight -
    /// viewportHeight)`.
    public var scrollOffset: Int = 0

    /// Grab point within the thumb during a scrollbar drag (``ScrollableOffsetState``).
    public var scrollbarDragGrab: Int?

    /// Held arrow/track auto-repeat action (``ScrollableOffsetState``).
    public var scrollbarRepeat: ScrollbarRepeat?

    /// Wheel-chaining grace state (``ScrollableOffsetState``).
    public var wheelEdgeHold = WheelEdgeHold()

    /// The horizontal scroll axis, used when the ScrollView's `axes` include
    /// `.horizontal`. The handler itself is the vertical axis; this carries the
    /// horizontal offset, content width, and viewport width (plus its own drag /
    /// repeat state) so the same scrollbar machinery serves both axes.
    public let horizontal = ScrollAxis()

    /// A parked ``ScrollViewProxy/scrollTo(_:anchor:)`` request, set at event
    /// time (or from an async context) and consumed — one-shot — by the next
    /// render pass, which carries it to the content via the scroll-window
    /// handshake and adopts the offset the content answers with. Cleared
    /// whether or not the key was found: an unknown id is a no-op, as in
    /// SwiftUI, not a standing intent.
    var pendingScrollTo: ScrollToRequest?

    /// The total natural height of the scroll view's content,
    /// computed during the layout pass.
    ///
    /// Shrinking the content immediately re-bounds ``scrollOffset`` to the
    /// last line — the viewport-independent half of the scroll clamp, safe on
    /// any pass (the full ``clampScrollOffset()`` is render-gated because its
    /// `maxOffset` depends on the offered viewport). Mirrors
    /// `ItemListHandler.itemCount`.
    public var contentHeight: Int = 0 {
        didSet {
            let bound = max(0, contentHeight - 1)
            if scrollOffset > bound {
                scrollOffset = bound
            }
        }
    }

    /// The visible height of the scroll view's viewport.
    public var viewportHeight: Int = 0

    /// Whether ``contentHeight`` came from ESTIMATED geometry (a windowed
    /// stack's unmeasured remainder). The "N more above/below" indicators
    /// read this to present their counts approximately ("~200M") instead of
    /// with false precision. Re-synced every render pass.
    var contentHeightIsEstimate = false

    /// A one-shot "seek to the very bottom" intent (End key, scrollbar
    /// bottom jump, `scrollToBottom()`). Against an ESTIMATED content
    /// height, assigning `maxOffset` once can strand the view short: the
    /// next render's reply refines the total, and the clamp only ever pulls
    /// the offset DOWN. The ScrollView treats this flag like one frame of
    /// bottom glue — re-asserting `maxOffset` after the refinement, whose
    /// tail totals are exact — then clears it.
    var seekingTail = false

    /// How many lines/columns a Shift-accelerated arrow press scrolls. Set from
    /// `environment.shiftStepMultiplier` during render (default 5); a plain arrow
    /// always scrolls one. See ``View/shiftStepMultiplier(_:)``.
    public var shiftStepMultiplier: Int = 5

    /// Creates a scroll-view handler.
    ///
    /// - Parameters:
    ///   - focusID: The unique focus identifier.
    ///   - canBeFocused: Whether the handler can receive focus.
    public init(focusID: String, canBeFocused: Bool = true) {
        self.focusID = focusID
        self.canBeFocused = canBeFocused
    }
}

// MARK: - ScrollableOffsetState conformance

extension ScrollViewHandler {

    /// The extent that ``ScrollableOffsetState`` measures
    /// against. For ``ScrollViewHandler`` that's
    /// ``contentHeight`` — total natural lines.
    public var extent: Int { contentHeight }
}

// MARK: - Convenience

extension ScrollViewHandler {

    /// Jumps to the top of the content.
    public func scrollToTop() { scrollOffset = 0 }

    /// Jumps to the bottom of the content.
    public func scrollToBottom() {
        scrollOffset = maxOffset
        seekingTail = true
    }
}

// MARK: - Key Event Handling

extension ScrollViewHandler {

    /// Handles a key event while the scroll view has focus.
    /// Up / Down scroll one line; Page Up / Page Down scroll one
    /// viewport; Home / End jump to top / bottom. Other keys are
    /// not consumed.
    ///
    /// - Parameter event: The incoming key event.
    /// - Returns: `true` if the key was a scroll command.
    public func handleKeyEvent(_ event: KeyEvent) -> Bool {
        // A plain arrow steps one line/column; Shift accelerates by the
        // (env-configured) multiplier. Page/Home/End are already large jumps and
        // ignore Shift.
        let step = event.shift ? max(1, shiftStepMultiplier) : 1
        switch event.key {
        case .up:
            scroll(by: -step)
            return true
        case .down:
            scroll(by: step)
            return true
        case .pageUp:
            scroll(by: -max(1, viewportHeight))
            return true
        case .pageDown:
            scroll(by: max(1, viewportHeight))
            return true
        case .home:
            scrollToTop()
            return true
        case .end:
            scrollToBottom()
            return true
        case .left:
            // Scroll the horizontal axis (Shift-accelerated). Returns false (not
            // consumed) when it can't move — no horizontal axis, or already at the
            // edge — so the key still bubbles to whatever else might handle
            // Left/Right.
            let before = horizontal.scrollOffset
            horizontal.scroll(by: -step)
            return horizontal.scrollOffset != before
        case .right:
            let before = horizontal.scrollOffset
            horizontal.scroll(by: step)
            return horizontal.scrollOffset != before
        default:
            return false
        }
    }
}
