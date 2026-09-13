//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollViewHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - ScrollViewHandler

/// A focus handler for ``ScrollView``.
///
/// `ScrollViewHandler` owns the scroll-position state and the
/// keyboard-driven scroll navigation for a `ScrollView`. It is a
/// peer of `ItemListHandler` for the no-selection,
/// no-row-structure case: there is just a viewport over a taller
/// content area, and the keys and the wheel move where that
/// viewport lands.
///
/// # Interaction model
///
/// - **Mouse wheel** scrolls by ``ViewConstants/mouseWheelScrollLines``
///   lines per tick. Wheel scrolling is independent of focus —
///   the wheel works whether or not the scroll view itself has
///   focus, matching the rest of TUIkit (see `ItemListHandler`).
/// - **Arrow keys** scroll by one line at a time. **Page Up** /
///   **Page Down** scroll by one viewport height. **Home** /
///   **End** jump to the very top / bottom. All keyboard
///   scrolling requires the scroll view to have focus.
///
/// The handler does not track selection — there is no
/// "currently focused row" concept in a generic scroll view.
///
/// > Note: Like `ItemListHandler` and `TextFieldHandler`,
///   `ScrollViewHandler` isn't marked `@MainActor`. The
///   framework guarantees handlers are only touched from the
///   render loop / event dispatch (both `@MainActor`), so the
///   nonisolated class conforms cleanly to the nonisolated
///   `Focusable` protocol without crossing an isolation
///   boundary.
public final class ScrollViewHandler: PersistedFocusable, ScrollableOffsetState {

    /// The offset the reveal's last snap SETTLED on, or `nil` when no reveal
    /// pursuit is in flight.
    ///
    /// The reveal's convergence memory: a focus jump to a far-off row scrolls
    /// to the row's grafted region, whose position is an ESTIMATE — ordinal
    /// distance times the running pitch average — so the hop can land short.
    /// Focus being unchanged, nothing used to re-check, and the viewport
    /// parked one band away from the row it was sent to. While this matches
    /// `scrollOffset` (nobody else has scrolled — a wheel peek clears it, so
    /// peek mode still wins) and the target's region is still outside the
    /// visible band, the snap keeps pursuing; a hop that no longer moves ends
    /// it. See `snapViewportToFocusedControl` / `settleRevealPursuit`.
    ///
    /// Lives here rather than in a `StateStorage` box because this class is
    /// already in hand every frame: the box lookup it replaced was a
    /// measurable slice of the smallest scenarios' frames.
    var revealPursuitOffset: Int?

    /// The vertical scrollbar drawn last time, with everything it was drawn
    /// from — see `_ScrollViewCore.appendVerticalScrollbar`. A focused bar
    /// pulses, and its animated runs are one scrollbar render PER PULSE FRAME,
    /// on every frame: 15.6% of a live `dashboard` frame for a bar whose
    /// inputs had not moved. Compared, not hashed, since one entry is all
    /// there is.
    var verticalScrollbarMemo: VerticalScrollbarMemo?

    /// How many times ``verticalScrollbarMemo`` answered — for the test that
    /// pins it answering.
    var verticalScrollbarMemoHits = 0

    /// The unique focus identifier for this scroll view.
    public var focusID: String

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

    /// One line per edge when the "N more" text indicators are what occupies
    /// the viewport's first and last line, `0` under a bar or hidden
    /// indicators. Published by the render, consumed by ``pageDistance``.
    var textIndicatorInset = 0

    /// The `.scrollPosition` freshness memory: the request token last acted
    /// on, and the row id last written back. On the HANDLER — which persists
    /// across frames — and not on the environment box that carries the
    /// binding: that box is rebuilt with every body evaluation, and freshness
    /// that resets every frame treats a standing target as a brand-new
    /// request each render, undoing the user's scroll on the very next frame.
    var lastAppliedPositionToken: Int?

    /// See ``lastAppliedPositionToken``.
    var lastReportedPositionID: AnyHashable?

    /// One screenful of READABLE lines (``ScrollableOffsetState``
    /// requirement). Under the text indicators the viewport's first and last
    /// line are chrome — "▲ N more" / "▼ N more" — so the protocol's
    /// full-height default skipped the two content lines hidden beneath them
    /// at every boundary: two lines of the document never shown at any point
    /// while paging through it. Where only one indicator happens to show,
    /// this overlaps by a line instead, which is the safe direction.
    public var pageDistance: Int { max(1, viewportHeight - 2 * textIndicatorInset) }

    /// Grab point within the thumb during a scrollbar drag (``ScrollableOffsetState``).
    public var scrollbarDragGrab: Int?

    /// Held arrow/track auto-repeat action (``ScrollableOffsetState``).
    public var scrollbarRepeat: ScrollbarRepeat?

    /// Wheel-chaining grace state (``ScrollableOffsetState``).
    public var wheelEdgeHold = WheelEdgeHold()

    /// Overscroll excursion + allowance (``ScrollableOffsetState``), resolved
    /// from the environment each render.
    public var overscrollState = ScrollOverscrollState()

    /// Drag auto-scroll drive flag (``ScrollableOffsetState``).
    public var isAutoScrolling = false

    /// Whether the user may scroll (``ScrollableOffsetState``), synced from
    /// `environment.isScrollEnabled` each render.
    public var isScrollEnabled = true

    /// The scrollbar cell under the pointer (``ScrollableOffsetState``).
    public var hoveredBarCell: Int?
    /// Bound `.anchorPosition` override, captured each render so a USER scroll
    /// can release it to `.window` at event time. See
    /// `ScrollableOffsetState.releaseAnchorOnUserScroll()`.
    public var anchorPositionBinding: Binding<ScrollAnchor<AnyHashable>?>?

    /// The anchor the view DECLARED (`defaultScrollAnchor`), synced each render
    /// so Home / End can tell "restored the declaration" (write `nil`) from
    /// "departed to the other edge" (write that edge). Mirrors
    /// `ItemListHandler.declaredAnchorMode`.
    var declaredAnchorMode: ScrollAnchorMode = .window

    /// The anchor mode the view declared for the OPENING frame (from
    /// `defaultScrollAnchor(_:for: .initialOffset)`), synced each render beside
    /// ``declaredAnchorMode``.
    ///
    /// `nil` means none was stated, and then the opening frame uses
    /// ``declaredAnchorMode`` like every frame after it — which is exactly what
    /// a view using the unlabelled modifier gets, and what makes the role split
    /// inert for everything written before it.
    var declaredOpeningAnchorMode: ScrollAnchorMode?

    /// Whether this scrollable has rendered a frame yet.
    ///
    /// The opening frame is placed by ``declaredOpeningAnchorMode`` and every
    /// frame after it by ``declaredAnchorMode`` — see
    /// ``ScrollAnchorMode/governing(opening:standing:hasOpened:)``. Set on
    /// render passes only: a measure must not spend the opening frame.
    var hasOpened = false

    /// The declared anchor as an EDGE, for the shared user-scroll path
    /// (``ScrollableOffsetState/declaredEdgeAnchor``). Row and Window name no
    /// edge, so they answer `nil`.
    public var declaredEdgeAnchor: ScrollAnchor<AnyHashable>? {
        switch declaredAnchorMode {
        case .top: return .top
        case .bottom: return .bottom
        case .row, .window: return nil
        }
    }

    /// The bound anchor as of the last render, so a *change* can be detected
    /// and adopted. The outer optional is "never seen yet"; the inner is the
    /// binding's own `nil` ("no departure from the declaration"). Writing
    /// `.top`/`.bottom` into the binding is §3.2's `anchor(to:)`, and it is the
    /// CHANGE that jumps — thereafter the edge is held positionally, so the
    /// user can still scroll away from it.
    var lastBoundAnchor: ScrollAnchor<AnyHashable>??

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
    ///
    /// Cancels any pending tail seek. `scrollToBottom` arms one so an End
    /// pressed while content is still streaming in pins to the tail rather
    /// than to wherever the tail happened to be — but the flag outlived the
    /// intent: a Home straight after an End set the offset to 0 and the seek,
    /// still armed, pulled it back to the bottom on the next frame.
    public func scrollToTop() {
        scrollOffset = 0
        seekingTail = false
        clearOverscroll()
    }

    /// Jumps to the bottom of the content.
    public func scrollToBottom() {
        scrollOffset = maxOffset
        seekingTail = true
        clearOverscroll()
    }

    /// Lands the viewport on `offset` for a programmatic request — a `scrollTo`
    /// seek's resolved offset, or a bound `ScrollPosition`'s edge or row offset —
    /// written as given, since the caller has already resolved or clamped it.
    ///
    /// Like ``scrollToTop()`` and ``scrollToBottom()``, and for the same reason,
    /// it drops any overscroll excursion: a request aims a row at an exact line,
    /// and the slide drawn afterwards would move that row by the push, landing
    /// the request short by exactly that much.
    func jumpProgrammatically(to offset: Int) {
        scrollOffset = offset
        clearOverscroll()
    }

    /// The protocol's user End jump, interposed to keep `seekingTail`: an End
    /// pressed while content is still streaming in must pin to the tail, not
    /// to the offset the tail happened to be at.
    public func userScrollToBottom() {
        engageEdgeAnchor(.bottom)
        scrollToBottom()
    }

    /// The protocol's user Home jump, interposed for the same reason its
    /// bottom twin is: the edge anchor has to be engaged deliberately, and the
    /// tail seek cancelled, before the offset moves.
    public func userScrollToTop() {
        engageEdgeAnchor(.top)
        scrollToTop()
    }
}

// MARK: - Key Event Handling

extension ScrollViewHandler {

    /// Handles a key event while the scroll view has focus.
    /// Up / Down scroll one line; Page Up / Page Down scroll one
    /// viewport; Home / End jump to top / bottom. Other keys are
    /// not consumed.
    ///
    /// Under ``TUIkit/View/scrollDisabled(_:)`` none of them are consumed, so
    /// they bubble on to whatever else might want them — a scroll view that
    /// cannot scroll must not silently swallow Home, End or the arrows.
    ///
    /// - Parameter event: The incoming key event.
    /// - Returns: `true` if the key was a scroll command.
    public func handleKeyEvent(_ event: KeyEvent) -> Bool {
        guard isScrollEnabled else { return false }
        // A plain arrow steps one line/column; Shift accelerates by the
        // (env-configured) multiplier. Page/Home/End are already large jumps and
        // ignore Shift.
        let step = event.shift ? max(1, shiftStepMultiplier) : 1
        switch event.key {
        case .up:
            return userScroll(by: -step)
        case .down:
            return userScroll(by: step)
        // `pageDistance` rather than `viewportHeight` directly: same value
        // here (a ScrollView scrolls by line, and its viewport is lines), but
        // a page has exactly one definition — see `ScrollableOffsetState`.
        case .pageUp:
            return userScroll(by: -pageDistance)
        case .pageDown:
            return userScroll(by: pageDistance)
        case .home:
            // §1.3: Home restores the anchor-to-top default (and End
            // anchor-to-bottom). Note this ENGAGES an edge rather than
            // releasing to `.window` as an ordinary scroll does — jumping
            // deliberately to an edge is the clearest statement a user can make
            // that they want to sit at it.
            userScrollToTop()
            return true
        case .end:
            userScrollToBottom()
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

    /// A keyboard scroll by `delta` lines that behaves like a *user* scroll: it
    /// releases a bound anchor (§1.2 shadow-switch) whenever it actually moves
    /// the viewport, exactly as a wheel tick does. Without the release, an
    /// anchored view re-derives its offset from the anchor every render, so the
    /// arrow key changed `scrollOffset` for one instant and the next frame
    /// pulled it straight back — the keys appeared dead. Always consumed (it is
    /// a scroll command either way), so an at-the-edge press doesn't bubble.
    private func userScroll(by delta: Int) -> Bool {
        // `userScrollFine` rather than `scroll(by:)`: an arrow at the edge should
        // push into an overscroll allowance — and stick to that edge — exactly
        // as a wheel tick does. It owns the anchor bookkeeping too.
        userScrollFine(by: delta)
        return true
    }
}
