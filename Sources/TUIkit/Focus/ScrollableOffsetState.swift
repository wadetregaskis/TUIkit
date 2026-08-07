//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ScrollableOffsetState.swift
//
//  Created by LAYERED.work
//  License: MIT

import Dispatch

// MARK: - ScrollableOffsetState

/// The scroll-position arithmetic shared by
/// ``ScrollViewHandler`` and `ItemListHandler`.
///
/// The two handlers track the same shape of state — a scroll
/// offset, a viewport size, an extent that the offset is
/// clamped against — but measure that extent differently:
///
/// - ``ScrollViewHandler`` counts lines (`contentHeight`).
/// - `ItemListHandler` counts rows (`itemCount`).
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
    ///
    /// Not necessarily the offset the rows were DRAWN from — see
    /// ``drawnOffset``, and use that for anything the user is told or shown.
    var scrollOffset: Int { get set }

    /// How far one page-sized jump moves, in whatever unit this conformer's
    /// ``scrollFine(by:)`` steps in.
    ///
    /// **One screenful, no overlap**: the row that was one past the bottom
    /// becomes the top. Every pager in TUIkit uses this — the focused-scrollable
    /// keys, a `ScrollView`'s own keys, the List/Table focus cursor, and both
    /// mid-drag navigators. They are deliberately not allowed their own idea of
    /// a page; two of them once carried a `viewportHeight - 1` of their own and
    /// the only thing it produced was a Backlog that needed two Page Downs to
    /// cross six rows.
    ///
    /// Two traps live here, which is why this is a member rather than arithmetic
    /// at the call sites:
    ///
    /// - **Unit.** ``scrollFine(by:)`` steps ROWS under `.row` granularity and
    ///   LINES under `.line`. A page expressed in rows and handed to the line
    ///   stepper moves a fraction of a screen over multi-line rows. Conformers
    ///   answer in their own unit.
    /// - **Staleness.** `viewportHeight` is written during render, and the app
    ///   drains up to 128 input events between renders (see `App.swift`), so a
    ///   held Page Down sees one value for every repeat. The visible row count
    ///   is not constant — it shrinks by a line when an "▲ N more" indicator
    ///   appears — so a page measured from a stale viewport SKIPS a row on the
    ///   press that leaves the top edge. Conformers whose count varies must
    ///   compute it from the current offset, not read the last frame's.
    ///
    /// The default is ``viewportHeight``, which is correct for a conformer whose
    /// viewport does not change size as it scrolls — every one of them but
    /// `ItemListHandler`.
    var pageDistance: Int { get }

    /// The offset the viewport was last drawn FROM, which near the top edge is
    /// not always ``scrollOffset``.
    ///
    /// A viewport one line down from the top draws from the top anyway, because
    /// announcing that one hidden line ("▲ 1 more row above") costs the very
    /// line it reports. `ScrollWindowOrigin.absorbing` resolves that per frame
    /// without touching the offset, so offsets 0 and 1 can draw the SAME
    /// PICTURE. `ItemListHandler.settleRestingOffset` normally collapses the
    /// duplicate by snapping 1 down to 0 — but not while a drag is being
    /// steered, because stepping needs 1 to be a distinct position it can pass
    /// through (snapping it back stalled a mid-drag Down key at 0↔1 forever).
    ///
    /// So for the length of a drag, two offsets mean one picture, and anything
    /// derived from the offset must choose which it means:
    ///
    /// - **Counting and paging** describe what the user SEES → ``drawnOffset``.
    ///   See ``pageDelta(_:)``, and `ItemListHandler.rowsBelow`.
    /// - **Stepping** moves the position itself → ``scrollOffset``. A step
    ///   measured from the drawn origin could never leave the phantom.
    ///
    /// Defaults to ``scrollOffset`` for conformers that never absorb, which is
    /// every one of them but `ItemListHandler` — a `ScrollView` scrolls by
    /// line, so it has no whole row to hide in the first place.
    var drawnOffset: Int { get }

    /// The number of rows / lines visible in the viewport.
    var viewportHeight: Int { get }

    /// The total extent: row count for
    /// `ItemListHandler`, line count for
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

    /// How far past an edge this viewport is currently pushed, and the allowance
    /// bounding it. See ``TUIkit/View/scrollOverscroll(top:bottom:)``. Zero
    /// throughout unless an allowance is configured, so every scrollable that
    /// does not opt in behaves exactly as before.
    var overscrollState: ScrollOverscrollState { get set }

    /// Whether drag auto-scroll is currently driving this viewport — set and
    /// cleared by `DragAndDropSession.driveAutoScroll(nowNanos:)`.
    ///
    /// A scroll position that is being *driven* is not a resting position, and
    /// views that tidy up where the viewport comes to rest have to leave it
    /// alone until the gesture ends (see `_ListCore`'s offset-1 snap).
    var isAutoScrolling: Bool { get set }

    /// Whether the **user** may move this viewport — `false` under
    /// ``TUIkit/View/scrollDisabled(_:)``, captured from the environment each
    /// render so event-time code can read it.
    ///
    /// It gates *gestures* only. Every programmatic move — a `scrollTo` seek, an
    /// anchor hold, the reveal that keeps a focused control on screen, the clamp
    /// that runs after the data shrank — goes through ``scroll(by:)`` /
    /// ``scrollOffset`` directly and is deliberately unaffected.
    var isScrollEnabled: Bool { get set }

    /// The bound ``TUIkit/View/anchorPosition(_:)`` override, captured from the
    /// environment during render so a *user* scroll can release it at event
    /// time (when the environment is out of reach). `nil` when the app bound
    /// nothing. See ``releaseAnchorOnUserScroll()``.
    var anchorPositionBinding: Binding<ScrollAnchor<AnyHashable>?>? { get set }

    /// The edge this scrollable *declared* (`defaultScrollAnchor`), or `nil` when
    /// it declared none — Row and Window name no edge.
    ///
    /// Deliberately typed with the public ``ScrollAnchor`` rather than the
    /// resolved-policy enum, which stays internal until §3.2's deferred
    /// "read-only effective mode" question is actually asked. The shared
    /// user-scroll path needs only this much: whether an edge it is about to
    /// engage is the one already declared, in which case engaging means writing
    /// `nil` ("no departure") rather than the edge.
    var declaredEdgeAnchor: ScrollAnchor<AnyHashable>? { get }

    /// The largest valid ``scrollOffset`` for the current extent and viewport.
    ///
    /// A protocol *requirement* (with the obvious `extent - viewportHeight`
    /// default below) so a conformer whose rows and viewport are measured in
    /// different units can supply the exact bound — `ItemListHandler` counts
    /// its extent in rows but its viewport can be lines when rows span
    /// multiple lines, and the default's mixed-unit subtraction caps the
    /// offset far short of the true bottom. Every helper in the extension
    /// (``clampScrollOffset()``, wheel scrolling, the scrollbar arithmetic)
    /// dispatches through this requirement, so an override applies uniformly.
    var maxOffset: Int { get }

    /// ``maxOffset``, resolved precisely enough to clamp `offset`.
    ///
    /// A requirement for the one conformer whose bound is expensive to know
    /// exactly: `ItemListHandler` finds the last row-aligned top by walking
    /// real row heights back from the tail, and short-circuits to a cheap
    /// UNDER-estimate for any offset that could not reach it — so a *jump* has
    /// to say where it is going, or it is clamped by a bound computed for
    /// somewhere else and lands short of the bottom. (That was End and Page
    /// Down needing two presses to arrive.) Every other conformer's bound is
    /// arithmetic, and takes the default: ``maxOffset``, whatever was asked.
    ///
    /// A requirement rather than an extension method so it dispatches through
    /// `any ScrollableOffsetState` — the mid-drag navigators move whatever the
    /// pointer is over, which is resolved as an existential.
    func resolvedMaxOffset(reaching offset: Int) -> Int

    /// Moves the scroll position by `delta` *fine* steps — the unit a wheel
    /// tick or scrollbar arrow click moves — returning whether the viewport
    /// actually moved.
    ///
    /// A requirement (defaulted to ``scroll(by:)``, one row/line per step) so
    /// a conformer with a finer unit than its offset can interpose:
    /// `ItemListHandler` under ``ScrollGranularity/line`` steps by terminal
    /// LINES through multi-line rows — its row-based ``scrollOffset`` plus a
    /// top clip — while offset, extent and ``maxOffset`` stay row-based (an
    /// O(1) model even for 50k-row lists). The wheel path dispatches through
    /// this requirement, so the override applies to every wheel event.
    @discardableResult
    func scrollFine(by delta: Int) -> Bool

    /// Jumps to an absolute offset — the Home / End of a scrollable, and the
    /// only mover that must also discard any *partial* scroll within a row.
    ///
    /// A requirement rather than an extension method so it dispatches through
    /// `any ScrollableOffsetState`: mid-drag navigators move whatever the
    /// pointer is over, which is resolved as an existential.
    func scrollToOffset(_ offset: Int)

    /// A **user** jump to the very top — Home. Engages the top edge anchor
    /// (§1.3: deliberately travelling to an edge is the clearest request to
    /// sit at it) and drops any overscroll excursion.
    ///
    /// A requirement (with the obvious default) so a conformer with extra
    /// tail state — ``ScrollViewHandler``'s `seekingTail` — can interpose,
    /// and so it dispatches through `any ScrollableOffsetState`.
    func userScrollToTop()

    /// A **user** jump to the very bottom — End. Engages the bottom edge
    /// anchor and drops any overscroll excursion. See ``userScrollToTop()``.
    func userScrollToBottom()
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
    /// Overscroll excursion + allowance (``ScrollableOffsetState``).
    public var overscrollState = ScrollOverscrollState()
    /// Drag auto-scroll drive flag (``ScrollableOffsetState``).
    public var isAutoScrolling = false
    /// Whether the user may scroll this axis (``ScrollableOffsetState``).
    public var isScrollEnabled = true
    /// A horizontal axis is never anchored (anchoring is a vertical, row-wise
    /// notion), so this stays `nil`.
    public var anchorPositionBinding: Binding<ScrollAnchor<AnyHashable>?>?
    /// …and it therefore declares no edge either.
    public var declaredEdgeAnchor: ScrollAnchor<AnyHashable>? { nil }

    public init() {}
}

// MARK: - Wheel edge grace period

/// Per-scroller state for the wheel-chaining grace period.
///
/// Hitting a nested scroller's edge mid-scroll used to chain the very next
/// wheel tick to the parent — so finishing a scroll to the bottom of an inner
/// list would fling the whole page. Instead, the first blocked tick at an
/// edge starts a grace period (`delayNanos`, from the
/// ``View/scrollChainingDelay(_:)`` environment; default 500 ms):
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

    /// The default ``resolvedMaxOffset(reaching:)``: the bound is arithmetic,
    /// so where the caller is headed makes no difference to it.
    public func resolvedMaxOffset(reaching offset: Int) -> Int { maxOffset }

    /// ``maxOffset``, resolved exactly — the bottom, whatever it costs to find.
    ///
    /// What "scroll to the end" means, and the value to clamp against when a
    /// mover has no particular target short of the tail. On every conformer but
    /// `ItemListHandler` this is just ``maxOffset``.
    public var settledMaxOffset: Int { resolvedMaxOffset(reaching: .max) }

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
    /// for `ItemListHandler`, lines for ``ScrollViewHandler``.
    ///
    /// Total for ANY state, not just clamped state: the persistent
    /// ``scrollOffset`` outlives the data it was clamped against (rows can be
    /// added or removed between frames, and a measure pass deliberately skips
    /// the viewport-dependent clamp), so this must not assume
    /// `scrollOffset < extent`. A stale offset is bounded to the last
    /// row/line here — building `scrollOffset..<min(extent, …)` raw would
    /// construct an inverted range (e.g. `1300..<2`) and trap.
    public var visibleRange: Range<Int> {
        guard extent > 0 else { return 0..<0 }
        let start = max(0, min(scrollOffset, extent - 1))
        let end = min(extent, start + max(0, viewportHeight))
        return start..<end
    }

    /// Moves the scroll position by `delta`. Negative scrolls
    /// up, positive scrolls down. Clamped to `0...maxOffset`,
    /// no-op when the content already fits the viewport
    /// entirely.
    /// One screenful, in this conformer's own stepping unit. See the protocol
    /// requirement — overriding is for viewports that change size as they
    /// scroll, or that step lines rather than rows.
    public var pageDistance: Int { max(1, viewportHeight) }

    /// The offset the rows were drawn from — ``scrollOffset`` unless the
    /// conformer overrides it. See the protocol requirement for why they can
    /// differ.
    public var drawnOffset: Int { scrollOffset }

    /// Re-bases a **page-sized** delta on ``drawnOffset``, so a page moves the
    /// PICTURE by a page rather than the offset by a page.
    ///
    /// Near the top edge those differ. Offsets 0 and 1 can draw identically
    /// (see ``drawnOffset``), and during a drag both are reachable — Home lands
    /// on 0, Page Up lands on 1. Without this, one Page Down from a screen that
    /// LOOKS like the top went two rows or three depending on which key got you
    /// there, which is indistinguishable from a bug because the two screens are
    /// indistinguishable, full stop.
    ///
    /// `scrollOffset + pageDelta(d) == drawnOffset + d`, and outside the absorb
    /// window that is just `scrollOffset + d`.
    ///
    /// **Only for page-sized jumps.** A single step must NOT be re-based: from
    /// a phantom offset of 1 it would compute `0 + 1 = 1` and never move, which
    /// is precisely the stall that keeping 1 reachable exists to avoid. Home
    /// and End need it no more than steps do — they name absolute positions, so
    /// there is no departure point to re-base.
    public func pageDelta(_ delta: Int) -> Int {
        let rebased = delta + (drawnOffset - scrollOffset)
        // Never re-base a jump into a no-op or a reversal. In a viewport with
        // room for one row the page IS one, and subtracting the absorbed row
        // left zero — Page Down went dead one row from the top, forever. A
        // page that cannot be honoured exactly still has to move.
        return rebased.signum() == delta.signum() ? rebased : delta
    }

    public func scroll(by delta: Int) {
        guard delta != 0,
              viewportHeight > 0,
              extent > viewportHeight
        else { return }
        // Clamped against the bound *at the destination*, not at the departure
        // — a page-sized step reaches the tail in one go, and asking about
        // where it started would stop it short of the bottom.
        let target = scrollOffset + delta
        scrollOffset = max(0, min(resolvedMaxOffset(reaching: target), target))
    }

    /// Jumps to an absolute offset, clamped to the valid range. A conformer
    /// with a sub-row scroll unit overrides this to discard it too.
    public func scrollToOffset(_ offset: Int) {
        scrollOffset = max(0, min(resolvedMaxOffset(reaching: offset), offset))
    }

    /// Clamps ``scrollOffset`` to the current valid range.
    ///
    /// Used by callers after mutating ``extent`` or
    /// ``viewportHeight`` so that, e.g., a search field that
    /// narrows the visible items doesn't leave the viewport
    /// pointing past the end of the new shorter list. This is
    /// a bounds check, not a focus-tracking clamp — see
    /// `ItemListHandler.ensureFocusedItemVisible()` for the
    /// focus-driven variant.
    public func clampScrollOffset() {
        scrollOffset = max(0, min(maxOffset, scrollOffset))
    }

    /// The default fine step: one offset unit, via ``scroll(by:)``.
    @discardableResult
    public func scrollFine(by delta: Int) -> Bool {
        let before = scrollOffset
        scroll(by: delta)
        return scrollOffset != before
    }

    /// A **user** fine step: like ``scrollFine(by:)``, but it also unwinds and
    /// extends the overscroll excursion (see
    /// ``TUIkit/View/scrollOverscroll(top:bottom:)``).
    ///
    /// Three cases, in order:
    ///
    /// 1. **Unwinding.** A step back toward the content returns from the
    ///    excursion before the content itself moves — so coming out of an
    ///    overscroll always lands on the edge, never skips past it. Any part of
    ///    the step left over after the excursion reaches zero scrolls normally.
    /// 2. **Ordinary movement**, unchanged.
    /// 3. **Blocked at an edge**, so the step is spent on the allowance there.
    ///
    /// The ordering is what gives §1.3 its graze-versus-push distinction for
    /// free: a step that merely *reaches* the edge is consumed by case 2, and
    /// only the next one — which case 2 can no longer satisfy — pushes past. A
    /// scroll that happens to land on the edge therefore never overscrolls, and
    /// pushing into the excursion is unambiguously deliberate.
    ///
    /// With no allowance configured (the default) case 3 moves nothing, so the
    /// *scrolling* here is exactly ``scrollFine(by:)``.
    ///
    /// This is also the one place that maintains the §1.2/§1.3 shadow anchor,
    /// so every user-scroll entry point gets the same rule and none can drift:
    /// ordinary movement **releases** to `.window`, and reaching case 3 —
    /// a step the content could not absorb — **engages** that edge (§1.3's
    /// sticky edges). Case 3 is exactly the spec's "deliberate push": the step
    /// that merely reached the edge was spent by case 2, so a graze can never
    /// stick. Note the engage happens whether or not an overscroll allowance
    /// exists — being blocked at the edge is the signal, and the excursion is
    /// only how far the push is then allowed to show.
    @discardableResult
    public func userScrollFine(by delta: Int) -> Bool {
        guard delta != 0 else { return false }
        let excursion = overscrollState.excursion

        // 1. Returning from an excursion.
        if excursion != 0, (excursion < 0) == (delta > 0) {
            let unwind = min(abs(delta), abs(excursion))
            overscrollState.excursion = excursion + (delta > 0 ? unwind : -unwind)
            let leftover = delta > 0 ? delta - unwind : delta + unwind
            if leftover != 0 { scrollFine(by: leftover) }
            releaseAnchorOnUserScroll()
            return true
        }

        // 2. Ordinary movement.
        if scrollFine(by: delta) {
            releaseAnchorOnUserScroll()
            return true
        }

        // 3. Blocked: a deliberate push. Stick to that edge — but only if there
        //    IS one to speak of. A view whose content fits sits at its top and
        //    its bottom at once, so "pushing past the bottom" of it names
        //    nothing, and engaging an edge there would drop an anchor the user
        //    never departed from. Sticking and overscrolling are separable: a
        //    fitting view may still be pushed (owner's decision), it just has no
        //    edge to become anchored to.
        if maxOffset > 0 { engageEdgeAnchor(delta < 0 ? .top : .bottom) }
        guard overscrollState.isAllowed else { return false }
        let limit = delta < 0 ? -overscrollState.top : overscrollState.bottom
        let target = excursion + delta
        let clamped = delta < 0 ? max(limit, target) : min(limit, target)
        guard clamped != excursion else { return false }
        overscrollState.excursion = clamped
        return true
    }

    /// The default user Home jump: engage, land row-aligned at the top, drop
    /// any excursion. See the requirement's doc.
    public func userScrollToTop() {
        engageEdgeAnchor(.top)
        scrollToOffset(0)
        clearOverscroll()
    }

    /// The default user End jump — the bottom-edge counterpart.
    public func userScrollToBottom() {
        engageEdgeAnchor(.bottom)
        scrollToOffset(settledMaxOffset)
        clearOverscroll()
    }

    /// Drops any overscroll excursion, putting the content back against its
    /// edges.
    ///
    /// Called wherever the viewport is moved *programmatically* — a `scrollTo`
    /// seek, an anchor hold, the reveal that keeps a focused control on screen.
    /// Those position the content precisely; leaving a leftover excursion under
    /// them would offset the very row they just aimed at.
    func clearOverscroll() {
        overscrollState.excursion = 0
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
    ///
    /// Under ``TUIkit/View/scrollDisabled(_:)`` a tick is *not consumed*, so it
    /// chains straight to the enclosing scroller — a pinned inner pane must not
    /// trap the wheel over the page behind it, which is the same reasoning that
    /// makes a scroller with nothing to scroll pass ticks through.
    @discardableResult
    public func handleWheelEvent(
        _ event: MouseEvent,
        linesPerTick: Int = ViewConstants.mouseWheelScrollLines
    ) -> Bool {
        guard isScrollEnabled else { return false }
        switch event.button {
        case .scrollUp:
            // The anchor rule (release, or stick at an edge) lives inside
            // `userScrollFine` so every entry point shares it.
            return resolveWheelOutcome(moved: userScrollFine(by: -linesPerTick))
        case .scrollDown:
            return resolveWheelOutcome(moved: userScrollFine(by: linesPerTick))
        default:
            return false
        }
    }

    /// Records that the **user** moved this viewport, releasing a bound anchor
    /// to ``ScrollAnchor/window`` — the spec's §1.2 shadow-switch
    /// ("Scrolling → shadow-switches to Window").
    ///
    /// Only genuine user input may call this. A programmatic move — a
    /// `scrollTo` seek, a focus-driven reveal, a clamp after the data shrank —
    /// must NOT, or an app would appear to have "scrolled away" from its own
    /// declared anchor without the user touching anything.
    ///
    /// Writing `.window` (rather than clearing to `nil`) is what keeps
    /// "released" distinguishable from "never departed" — see
    /// ``TUIkit/View/anchorPosition(_:)``. Idempotent: a second release while
    /// already `.window` writes nothing, so a held wheel doesn't churn `@State`.
    public func releaseAnchorOnUserScroll() {
        guard let binding = anchorPositionBinding, binding.wrappedValue != .window else {
            return
        }
        binding.wrappedValue = .window
    }

    /// Records that this viewport is now anchored to `edge` — the §1.3 user-side
    /// restore ("**Home** restores an anchor-to-top default; **End** restores
    /// anchor-to-bottom"), and the counterpart of
    /// ``releaseAnchorOnUserScroll()``.
    ///
    /// Writes **`nil` when the view's own declaration already names that edge**,
    /// and the explicit edge otherwise. That is not a micro-optimisation: `nil`
    /// means *no departure from the declaration*, so pressing End on a
    /// `.defaultScrollAnchor(.bottom)` log must restore `nil`, or the app's
    /// "am I still following the log?" test (`anchor == nil`) would answer no
    /// while the view demonstrably is. Departing to an edge the view did not
    /// declare is a real departure, and says so.
    ///
    /// A no-op when nothing is bound: an unbound scrollable has no shadow state
    /// to keep, and its edge behaviour is positional already.
    ///
    /// Internal (not `public` like its sibling) because the shadow-anchor model
    /// is not yet public surface — see ``declaredEdgeAnchor``, which exists so
    /// this can compare against the declaration without exposing the internal
    /// resolved-policy enum.
    func engageEdgeAnchor(_ edge: ScrollAnchor<AnyHashable>) {
        guard let binding = anchorPositionBinding else { return }
        let engaged: ScrollAnchor<AnyHashable>? = edge == declaredEdgeAnchor ? nil : edge
        // Idempotent: a held End key must not churn `@State` every repeat.
        if binding.wrappedValue != engaged { binding.wrappedValue = engaged }
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
        guard isScrollEnabled else { return false }
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

private struct DragAutoScrollDelayKey: EnvironmentKey {
    // One second. 300 ms read as trigger-happy in use: crossing the edge region
    // on the way to a drop target that is already visible would start scrolling
    // before the user arrived, so the target moved out from under them. Dwell is
    // a deliberate gesture — it should take deliberately long.
    static let defaultValue: Duration = .seconds(1)
}

extension EnvironmentValues {
    /// How long a nested scroller holds blocked wheel ticks at its edge
    /// before they chain to the enclosing scroller.
    public var scrollChainingDelay: Duration {
        get { self[ScrollChainingDelayKey.self] }
        set { self[ScrollChainingDelayKey.self] = newValue }
    }

    /// How long the drag cursor must dwell near a scrollable's edge before it
    /// starts auto-scrolling toward an off-screen drop target.
    public var dragAutoScrollDelay: Duration {
        get { self[DragAutoScrollDelayKey.self] }
        set { self[DragAutoScrollDelayKey.self] = newValue }
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

    /// Sets how long the drag cursor must dwell near a scrollable's edge before
    /// that scrollable begins auto-scrolling to bring an off-screen drop target
    /// into view (macOS's drag auto-scroll). The rate then ramps with how far
    /// past the edge the cursor is dragged. `.zero` scrolls immediately; the
    /// default is 1 second.
    ///
    /// Only scrollables the drag could actually land in ever move: one holding
    /// a `dropDestination` that accepts the payload, or the one the gesture
    /// began in (a row reorder can only land in its own list). A page that
    /// scrolled away under a payload it would refuse is just the view running
    /// off — there is nothing there to reveal.
    public func dragAutoScrollDelay(_ delay: Duration) -> some View {
        environment(\.dragAutoScrollDelay, delay)
    }
}

extension Duration {
    /// This duration as whole nanoseconds, clamped at zero.
    var clampedNanoseconds: UInt64 {
        guard self > .zero else { return 0 }
        let seconds = UInt64(components.seconds) &* 1_000_000_000
        return seconds &+ UInt64(components.attoseconds / 1_000_000_000)
    }
}
