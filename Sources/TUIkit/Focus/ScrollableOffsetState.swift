//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollableOffsetState.swift
//
//  Created by LAYERED.work
//  License: MIT

import Dispatch

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

    /// While a scrollbar thumb is being dragged, the offset (in cells) of the grab
    /// point within the thumb; `nil` when no drag is in progress. Lives on the
    /// persistent handler so it survives the render between the press and the
    /// drag/release that the mouse dispatcher routes back to the same handler.
    var scrollbarDragGrab: Int? { get set }

    /// While a scrollbar arrow (or a `.page`-mode track) is held, the repeat action
    /// to apply on each tick; `nil` when nothing is held. Lives on the persistent
    /// handler so the bar's owner can drive it from the render loop across frames.
    var scrollbarRepeat: ScrollbarRepeat? { get set }

    /// Grace-period state for wheel chaining at this scroller's edges — see
    /// ``WheelEdgeHold`` and ``handleWheelEvent(_:linesPerTick:)``.
    var wheelEdgeHold: WheelEdgeHold { get set }

    /// The largest valid ``scrollOffset`` for the current extent and viewport.
    ///
    /// A protocol *requirement* (with the obvious `extent - viewportHeight`
    /// default below) so a conformer whose rows and viewport are measured in
    /// different units can supply the exact bound — ``ItemListHandler`` counts
    /// its extent in rows but its viewport can be lines when rows span
    /// multiple lines, and the default's mixed-unit subtraction caps the
    /// offset far short of the true bottom. Every helper in the extension
    /// (``clampScrollOffset()``, wheel scrolling, the scrollbar arithmetic)
    /// dispatches through this requirement, so an override applies uniformly.
    var maxOffset: Int { get }
}

// MARK: - Generic single-axis scroll state

/// A plain one-axis scroll position, used for the *horizontal* axis of a
/// ``ScrollView`` (vertical scrolling lives on ``ScrollViewHandler`` itself).
///
/// `ScrollableOffsetState`'s vocabulary is vertical-leaning (`viewportHeight`,
/// `scrollOffset`) but axis-agnostic: for a horizontal axis read `viewportHeight`
/// as the viewport *width* and `extent` as the content *width*, both in columns.
/// Conforming gives the scrollbar renderer, the mouse interaction, and auto-repeat
/// to this axis for free.
public final class ScrollAxis: ScrollableOffsetState {
    public var scrollOffset: Int = 0
    /// The viewport size along this axis (columns, for a horizontal axis).
    public var viewportHeight: Int = 0
    /// The content size along this axis (columns, for a horizontal axis).
    public var extent: Int = 0
    public var scrollbarDragGrab: Int?
    public var scrollbarRepeat: ScrollbarRepeat?
    public var wheelEdgeHold = WheelEdgeHold()

    public init() {}
}

// MARK: - Wheel edge grace period

/// Per-scroller state for the wheel-chaining grace period.
///
/// Hitting a nested scroller's edge mid-scroll used to chain the very next
/// wheel tick to the parent — so finishing a scroll to the bottom of an inner
/// list would fling the whole page. Instead, the first blocked tick at an
/// edge starts a grace period (``delayNanos``, from the
/// ``SwiftUICore/View/scrollChainingDelay(_:)`` environment; default 500 ms):
/// blocked ticks within it are consumed silently, and only once it expires do
/// they chain to the enclosing scroller. Any successful scroll re-arms the
/// grace for the next edge hit. A scroller with nothing to scroll never
/// traps the wheel at all.
public struct WheelEdgeHold {
    /// When the current run of blocked-at-edge wheel ticks began, or `nil`
    /// when the last wheel event moved the viewport.
    var arrivalNanos: UInt64?

    /// The grace duration in nanoseconds; 0 chains immediately (the original
    /// behaviour). Synced from the environment by the owning view each frame.
    var delayNanos: UInt64 = 500_000_000

    /// Monotonic clock, injectable for tests.
    var nowNanos: () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }

    public init() {}
}

// MARK: - Default arithmetic

extension ScrollableOffsetState {

    /// The default ``maxOffset``: uniform units (rows-and-rows, or
    /// lines-and-lines). Zero when the content already fits entirely.
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
    /// A wheel tick that hits the scroller's edge does not chain immediately:
    /// see ``WheelEdgeHold`` for the grace-period model.
    @discardableResult
    public func handleWheelEvent(
        _ event: MouseEvent,
        linesPerTick: Int = ViewConstants.mouseWheelScrollLines
    ) -> Bool {
        switch event.button {
        case .scrollUp:
            let before = scrollOffset
            scroll(by: -linesPerTick)
            return resolveWheelOutcome(moved: scrollOffset != before)
        case .scrollDown:
            let before = scrollOffset
            scroll(by: linesPerTick)
            return resolveWheelOutcome(moved: scrollOffset != before)
        default:
            return false
        }
    }

    /// Maps "did the wheel move the viewport" onto "is the event consumed",
    /// inserting the edge grace period: a moved event is consumed and re-arms
    /// the grace; a blocked event is consumed while the grace runs and chains
    /// (returns `false`) once it expires. A scroller with no overflow never
    /// consumes a blocked event — the user can only mean the parent.
    private func resolveWheelOutcome(moved: Bool) -> Bool {
        if moved {
            wheelEdgeHold.arrivalNanos = nil
            return true
        }
        guard maxOffset > 0, wheelEdgeHold.delayNanos > 0 else { return false }
        let now = wheelEdgeHold.nowNanos()
        if let arrival = wheelEdgeHold.arrivalNanos {
            return now &- arrival < wheelEdgeHold.delayNanos
        }
        wheelEdgeHold.arrivalNanos = now
        return true
    }

    /// Like ``handleWheelEvent(_:linesPerTick:)`` but for a *horizontal* axis:
    /// responds to `.scrollLeft` / `.scrollRight` wheel events. Call it on a
    /// horizontal ``ScrollAxis`` (a native horizontal wheel, or a shift+wheel the
    /// caller has translated, drives it).
    public func handleHorizontalWheelEvent(
        _ event: MouseEvent,
        columnsPerTick: Int = ViewConstants.mouseWheelScrollLines
    ) -> Bool {
        switch event.button {
        case .scrollLeft:
            let before = scrollOffset
            scroll(by: -columnsPerTick)
            return resolveWheelOutcome(moved: scrollOffset != before)
        case .scrollRight:
            let before = scrollOffset
            scroll(by: columnsPerTick)
            return resolveWheelOutcome(moved: scrollOffset != before)
        default:
            return false
        }
    }
}

// MARK: - Environment

private struct ScrollChainingDelayKey: EnvironmentKey {
    static let defaultValue: Duration = .milliseconds(500)
}

extension EnvironmentValues {
    /// How long a nested scroller holds blocked wheel ticks at its edge
    /// before they chain to the enclosing scroller.
    public var scrollChainingDelay: Duration {
        get { self[ScrollChainingDelayKey.self] }
        set { self[ScrollChainingDelayKey.self] = newValue }
    }
}

extension View {
    /// Sets the grace period a nested scroller (List, Table, ScrollView, both
    /// axes) holds blocked wheel ticks at its edge before they chain to the
    /// enclosing scroller — so momentum finishing a scroll inside a child
    /// doesn't immediately fling the parent. `.zero` chains immediately.
    /// The default is 500 ms.
    public func scrollChainingDelay(_ delay: Duration) -> some View {
        environment(\.scrollChainingDelay, delay)
    }
}

extension Duration {
    /// This duration as whole nanoseconds, clamped at zero.
    var wheelDelayNanos: UInt64 {
        guard self > .zero else { return 0 }
        let seconds = UInt64(components.seconds) &* 1_000_000_000
        return seconds &+ UInt64(components.attoseconds / 1_000_000_000)
    }
}
