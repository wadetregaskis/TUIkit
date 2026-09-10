//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TooltipState.swift
//
//  The one tooltip a frame may show, and how it became the candidate.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - TooltipState

/// The help text a frame may show, and where it came from.
///
/// One per `TUIContext`, published to the environment each frame — the same
/// shape as `StatusBarState`, and a service rather than a singleton for the
/// same reason: two renders sharing one would read each other's tooltips.
///
/// ## Two slots, with different lifetimes
///
/// A hover candidate is set by an `.entered` mouse event and survives until
/// `.exited`, because the pointer stays where it is between frames. A focus
/// candidate is republished by whichever view holds the focus on every render
/// and is therefore **cleared at the top of each frame** — exactly as
/// `StatusBarState.activationLabelOverride` is, and for the same reason: its
/// absence has to be the default, or a view that lost the focus would leave its
/// help text behind.
///
/// Keeping them apart is what makes "hover wins over focus" a one-line rule
/// rather than a race between two publishers. The pointer is a deliberate act
/// aimed at one thing; focus is where the keyboard happens to be.
public final class TooltipState: @unchecked Sendable {

    /// What made a tooltip a candidate.
    public enum Source: Sendable, Equatable {
        /// The pointer is over the view's hit region.
        case hover
        /// The view holds the keyboard focus.
        case focus
    }

    /// A tooltip that could be shown.
    struct Candidate {
        /// The help text, already localized.
        var text: String
        /// The view's hit region this frame, for a popover to anchor to. The
        /// RECT is not stored: only the dispatcher knows where the compositor
        /// finally put the region, and it knows it after this is published.
        var handlerID: HitTestRegion.HandlerID?
        /// The frame clock when this became the candidate — the re-entry test,
        /// not the deadline.
        var sinceNanos: Int64
        /// The earliest moment it may be drawn: entry plus the hover delay, or
        /// `sinceNanos` for a focus candidate, which waits on the key instead.
        ///
        /// The DEADLINE rather than the delay, because the delay is a subtree
        /// setting (``EnvironmentValues/tooltipDelay``) and only the view that
        /// carries the help can read it. Resolving against a delay fetched
        /// somewhere else is how the two halves of one number drift apart.
        var showAtNanos: Int64
        /// Whether this candidate shows on its own, without the help key.
        ///
        /// Set from ``TooltipTrigger/revealsOnFocus`` — a subtree setting, so it
        /// rides on the candidate for the same reason ``style`` does. A hover
        /// candidate always shows on its own and leaves this `false`; only the
        /// focus slot consults it.
        var revealsItself = false
        /// How to present it — read from the environment of the view that
        /// carries the help, not from the root's. `tooltipStyle` is a subtree
        /// setting, so a panel asking for a popover inside an app that uses the
        /// bar is answered by the panel; the run loop has only the root
        /// environment and could not tell.
        var style: TooltipStyle
    }

    /// The pointer's candidate. Set on `.entered`, cleared on `.exited`.
    private(set) var hovered: Candidate?

    /// The focused view's candidate, republished every render.
    private(set) var focused: Candidate?

    /// Whether the keyboard has asked for the focused view's tooltip.
    ///
    /// A focus candidate does **not** show on its own — it is revealed by the
    /// help key (`?` by default). That is the whole reason this framework needs
    /// no `focus(id:reason:)`: the design this implements had focus auto-show
    /// the tooltip, which meant it had to know whether the focus arrived from a
    /// click, because popping a tooltip up under every click is intolerable. A
    /// key press is unambiguously the keyboard asking, so the question does not
    /// arise and a shared API did not have to change.
    ///
    /// Cleared when the focused view changes, so the reveal does not follow the
    /// cursor around the page.
    private(set) var keyboardRevealed = false

    /// The focus identity `keyboardRevealed` was granted for.
    private var revealedFocusID: String?

    /// The focus candidate's text and deadline as of the previous frame.
    ///
    /// The focus slot is cleared and refilled every frame, so a candidate that
    /// computed a fresh deadline each time would never reach one — it would sit
    /// permanently `tooltipDelay` in the future and ``TooltipTrigger/onFocus``
    /// would show nothing at all. Only these two fields outlive the frame;
    /// keeping the whole `Candidate` would invite reading last frame's handler
    /// id, which belongs to a dispatcher generation that is gone.
    private var previousFocusText: String?
    private var previousFocusDeadline: Int64 = 0

    /// The key that reveals the focused view's tooltip. `?` by default, `nil` to
    /// claim no key at all.
    ///
    /// Settable for the same reason `StatusBarState.quitShortcut` is: the
    /// framework claiming a bare letter has to be something an app can take
    /// back. An app can also simply bind the key itself — a status-bar item, an
    /// `.onKeyPress`, or a `.keyboardShortcut` all run before this does.
    ///
    /// ## Known caveat: a focused text control swallows `?`
    ///
    /// `?` is punctuation, and `InputHandler`'s layer 0 gives a focused
    /// `TextField`, `SecureField`, `TextEditor` or `DatePicker` first refusal on
    /// every printable key — so inside one, `?` is typed and this is never
    /// reached. That is the correct precedence (a help key must not stop the
    /// reader typing a question mark) and it is a real hole: the controls whose
    /// help most needs explaining are exactly the ones the key cannot reach.
    /// Their tooltips are still available by hovering, and an app that wants a
    /// keyboard route inside a text field should set this to a key text input
    /// does not consume.
    ///
    /// The alternative was an F-key, declined by the project owner because F-keys
    /// are frequently claimed system-wide and would fail differently and less
    /// visibly.
    public var helpKey: Key? = .character("?")

    public init() {}

    // MARK: - Publishing

    /// Records that the pointer has entered a view carrying help text.
    ///
    /// - Parameters:
    ///   - text: The localized help text.
    ///   - handlerID: The view's hit region, for a popover to anchor to.
    ///   - nowNanos: The frame's monotonic clock, which the hover delay is
    ///     measured from.
    func hovering(
        _ text: String, handlerID: HitTestRegion.HandlerID?, nowNanos: Int64,
        style: TooltipStyle = .statusBar, delaySeconds: Double = 0
    ) {
        // Re-entering the SAME region must not restart the delay: the
        // dispatcher synthesises `.entered` whenever the cursor crosses a
        // boundary, and a region that was re-registered at a different id this
        // frame is still the same view under the pointer. Compared on the text
        // rather than the id for exactly that reason — ids are per-frame.
        if let hovered, hovered.text == text { return }
        hovered = Candidate(
            text: text, handlerID: handlerID, sinceNanos: nowNanos,
            showAtNanos: nowNanos &+ Int64(max(0, delaySeconds) * 1_000_000_000),
            style: style)
    }

    /// Records that the pointer has left the view it was over.
    ///
    /// Ignores a stale exit: with nested help (a container and a child), leaving
    /// the child fires `.exited` for it while the pointer is still inside the
    /// container, and the container's own `.entered` may already have replaced
    /// the candidate.
    func leaving(_ text: String) {
        guard hovered?.text == text else { return }
        hovered = nil
    }

    /// Records the focused view's help text for this frame.
    ///
    /// - Parameters:
    ///   - revealsItself: Whether the subtree asked for
    ///     ``TooltipTrigger/onFocus``, so this shows without the help key.
    func focusing(
        _ text: String, handlerID: HitTestRegion.HandlerID?, nowNanos: Int64,
        style: TooltipStyle = .statusBar, delaySeconds: Double = 0,
        revealsItself: Bool = false
    ) {
        // Continuing to hold the focus keeps the ORIGINAL deadline; taking it
        // starts a new one. Compared on the text rather than on a focus id for
        // the same reason `hovering` is — and because the same control can be
        // re-registered under a rebuilt id while plainly still being the thing
        // the reader is looking at.
        let deadline =
            previousFocusText == text
            ? previousFocusDeadline
            : nowNanos &+ Int64(max(0, delaySeconds) * 1_000_000_000)
        focused = Candidate(
            text: text, handlerID: handlerID, sinceNanos: nowNanos,
            showAtNanos: deadline, revealsItself: revealsItself, style: style)
    }

    /// Clears the per-frame focus slot. Called by the run loop before the frame,
    /// beside the status bar's own per-frame overrides.
    func beginRenderPass() {
        previousFocusText = focused?.text
        previousFocusDeadline = focused?.showAtNanos ?? 0
        focused = nil
    }

    // MARK: - The keyboard reveal

    /// Toggles the focused view's tooltip, returning whether anything changed.
    ///
    /// `false` means there was nothing to reveal — no focused view carries help
    /// text — and the caller should let the key fall through to whatever else
    /// wants it rather than swallow it.
    @discardableResult
    func toggleKeyboardReveal(focusID: String?) -> Bool {
        if keyboardRevealed, revealedFocusID == focusID {
            keyboardRevealed = false
            revealedFocusID = nil
            return true
        }
        guard focused != nil else { return false }
        keyboardRevealed = true
        revealedFocusID = focusID
        return true
    }

    /// Drops a reveal that belongs to a view the focus has left.
    ///
    /// Called each frame with the current focus identity. Not folded into
    /// ``beginRenderPass()``: that clears a slot the frame is about to refill,
    /// while this is a comparison against something outside this type.
    func syncReveal(focusID: String?) {
        guard keyboardRevealed, revealedFocusID != focusID else { return }
        keyboardRevealed = false
        revealedFocusID = nil
    }

    // MARK: - Resolution

    /// The tooltip to draw this frame, or `nil`.
    ///
    /// - Parameter nowNanos: The frame's monotonic clock.
    /// - Returns: The text, its source, the region to anchor a popover to, and
    ///   how to present it.
    func resolved(nowNanos: Int64) -> Resolved? {
        if let hovered {
            guard nowNanos >= hovered.showAtNanos else { return nil }
            return Resolved(
                text: hovered.text, source: .hover, handlerID: hovered.handlerID,
                style: hovered.style)
        }
        guard let focused, keyboardRevealed || focused.revealsItself else { return nil }
        // The help key IS the wait — a press has already taken longer than any
        // delay — so only a trigger-granted reveal serves the deadline out.
        guard keyboardRevealed || nowNanos >= focused.showAtNanos else { return nil }
        return Resolved(
            text: focused.text, source: .focus, handlerID: focused.handlerID,
            style: focused.style)
    }

    /// The tooltip a frame is drawing.
    struct Resolved {
        var text: String
        var source: Source
        var handlerID: HitTestRegion.HandlerID?
        var style: TooltipStyle
    }

    /// When a tooltip that is not yet showing would appear, as a monotonic
    /// deadline — `nil` when nothing is waiting on one.
    ///
    /// The run loop is demand-driven, so a tooltip whose delay expires between
    /// frames appears only if something else happens to redraw. This is what
    /// `HelpModifier` schedules a one-shot wake against.
    ///
    /// Both slots, because ``TooltipTrigger/onFocus`` waits out the same delay
    /// and nothing redraws for a focus that is merely still held. Hover first,
    /// matching ``resolved(nowNanos:)`` — the slot that would not be shown even
    /// once its own deadline passed is not worth waking for.
    func pendingDeadlineNanos(nowNanos: Int64) -> Int64? {
        if let hovered {
            return hovered.showAtNanos > nowNanos ? hovered.showAtNanos : nil
        }
        guard let focused, focused.revealsItself, !keyboardRevealed,
            focused.showAtNanos > nowNanos
        else { return nil }
        return focused.showAtNanos
    }
}

// MARK: - Environment

/// Environment key for the app's tooltip state.
private struct TooltipStateKey: EnvironmentKey {
    static let defaultValue: TooltipState? = nil
}

extension EnvironmentValues {
    /// The app's tooltip state, or `nil` outside a running application.
    ///
    /// Optional for the reason every runtime service here is: these are the
    /// app's own objects, and a bare `EnvironmentValues()` has none. Absent
    /// means absent — `help(_:)` on a headless render publishes nowhere and
    /// draws nothing, which is the truth rather than a degraded mode.
    public var tooltipState: TooltipState? {
        get { self[TooltipStateKey.self] }
        set { self[TooltipStateKey.self] = newValue }
    }
}
