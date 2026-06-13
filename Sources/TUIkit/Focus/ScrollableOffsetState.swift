//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollableOffsetState.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - ScrollableOffsetState

/// The scroll-position arithmetic shared by
/// ``ScrollViewHandler`` and ``ItemListHandler``.
///
/// The two handlers track the same shape of state — a scroll
/// offset, a viewport size, an extent that the offset is
/// clamped against — but measure that extent differently:
///
/// - ``ScrollViewHandler`` counts lines (`contentHeight`).
/// - ``ItemListHandler`` counts rows (`itemCount`).
///
/// This protocol abstracts over the difference by asking each
/// conformer to expose its extent via ``extent``. The
/// default-implementation members below — ``maxOffset``,
/// ``hasContentAbove``, ``hasContentBelow``, ``visibleRange``,
/// ``scroll(by:)``, ``clampScrollOffset()``,
/// ``handleWheelEvent(_:linesPerTick:)`` — then provide every
/// piece of scroll-offset behaviour both handlers were
/// previously open-coding. Conformers are class-typed because
/// both handlers are already classes (they conform to
/// ``Focusable``); the protocol inherits `AnyObject` so the
/// mutating default methods can write through `self` without
/// needing `mutating`.
public protocol ScrollableOffsetState: AnyObject {
    /// The first visible row (`ItemListHandler`) or line
    /// (`ScrollViewHandler`). Always in `0...maxOffset` after
    /// any of the helpers below have run.
    var scrollOffset: Int { get set }

    /// The number of rows / lines visible in the viewport.
    var viewportHeight: Int { get }

    /// The total extent: row count for
    /// ``ItemListHandler``, line count for
    /// ``ScrollViewHandler``. Read by every predicate below.
    var extent: Int { get }
}

// MARK: - Default arithmetic

extension ScrollableOffsetState {

    /// The largest valid ``scrollOffset`` for the current
    /// extent and viewport. Zero when the content already
    /// fits entirely.
    public var maxOffset: Int {
        max(0, extent - viewportHeight)
    }

    /// Whether there is content above the visible viewport —
    /// equivalent to "is the up-arrow indicator warranted right
    /// now?".
    public var hasContentAbove: Bool {
        scrollOffset > 0
    }

    /// Whether there is content below the visible viewport.
    public var hasContentBelow: Bool {
        scrollOffset + viewportHeight < extent
    }

    /// The number of rows / lines above the visible viewport.
    /// Zero when ``hasContentAbove`` is `false`. Used to
    /// populate the count in the "N more above" indicator.
    public var rowsAbove: Int { scrollOffset }

    /// The number of rows / lines below the visible viewport.
    /// Zero when ``hasContentBelow`` is `false`. Used to
    /// populate the count in the "N more below" indicator.
    public var rowsBelow: Int {
        max(0, extent - (scrollOffset + viewportHeight))
    }

    /// The half-open range of indices currently visible — rows
    /// for ``ItemListHandler``, lines for ``ScrollViewHandler``.
    public var visibleRange: Range<Int> {
        guard extent > 0 else { return 0..<0 }
        let end = min(extent, scrollOffset + viewportHeight)
        return scrollOffset..<end
    }

    /// Moves the scroll position by `delta`. Negative scrolls
    /// up, positive scrolls down. Clamped to `0...maxOffset`,
    /// no-op when the content already fits the viewport
    /// entirely.
    public func scroll(by delta: Int) {
        guard delta != 0,
              viewportHeight > 0,
              extent > viewportHeight
        else { return }
        scrollOffset = max(0, min(maxOffset, scrollOffset + delta))
    }

    /// Clamps ``scrollOffset`` to the current valid range.
    ///
    /// Used by callers after mutating ``extent`` or
    /// ``viewportHeight`` so that, e.g., a search field that
    /// narrows the visible items doesn't leave the viewport
    /// pointing past the end of the new shorter list. This is
    /// a bounds check, not a focus-tracking clamp — see
    /// ``ItemListHandler/ensureFocusedItemVisible()`` for the
    /// focus-driven variant.
    public func clampScrollOffset() {
        scrollOffset = max(0, min(maxOffset, scrollOffset))
    }

    /// Routes a mouse event through the wheel-scroll path.
    ///
    /// Returns `true` only if the event was a wheel event that
    /// actually moved the viewport. Returns `false` for non-wheel
    /// events (letting the caller continue with click / drag /
    /// hover handling) **and** for a wheel event that couldn't
    /// scroll — already at the top scrolling up, at the bottom
    /// scrolling down, or content that fits entirely so there is
    /// nothing to scroll.
    ///
    /// That "no-op ⇒ not consumed" rule is what gives nested
    /// scrollers **scroll chaining**: the dispatcher bubbles a
    /// wheel event to the next (enclosing) region only when a
    /// handler returns `false`, so a child list that has hit its
    /// limit passes the wheel up to its parent `ScrollView`
    /// instead of swallowing it — the behaviour every desktop UI
    /// (browsers, Finder, AppKit, SwiftUI) has. Returning `true`
    /// unconditionally — the previous behaviour — trapped the
    /// wheel in whichever scroller the cursor happened to be over,
    /// making the parent's lower content unreachable by wheel.
    @discardableResult
    public func handleWheelEvent(
        _ event: MouseEvent,
        linesPerTick: Int = ViewConstants.mouseWheelScrollLines
    ) -> Bool {
        switch event.button {
        case .scrollUp:
            let before = scrollOffset
            scroll(by: -linesPerTick)
            return scrollOffset != before
        case .scrollDown:
            let before = scrollOffset
            scroll(by: linesPerTick)
            return scrollOffset != before
        default:
            return false
        }
    }
}
