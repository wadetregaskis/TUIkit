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
/// One per ``TUIContext``, published to the environment each frame — the same
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
        /// The frame clock when this became the candidate, for the hover delay.
        var sinceNanos: Int64
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
        _ text: String, handlerID: HitTestRegion.HandlerID?, nowNanos: Int64
    ) {
        // Re-entering the SAME region must not restart the delay: the
        // dispatcher synthesises `.entered` whenever the cursor crosses a
        // boundary, and a region that was re-registered at a different id this
        // frame is still the same view under the pointer. Compared on the text
        // rather than the id for exactly that reason — ids are per-frame.
        if let hovered, hovered.text == text { return }
        hovered = Candidate(text: text, handlerID: handlerID, sinceNanos: nowNanos)
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
    func focusing(_ text: String, handlerID: HitTestRegion.HandlerID?, nowNanos: Int64) {
        focused = Candidate(text: text, handlerID: handlerID, sinceNanos: nowNanos)
    }

    /// Clears the per-frame focus slot. Called by the run loop before the frame,
    /// beside the status bar's own per-frame overrides.
    func beginRenderPass() {
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
    /// - Parameters:
    ///   - nowNanos: The frame's monotonic clock.
    ///   - delaySeconds: How long the pointer must rest before a hover tooltip
    ///     appears. A focus reveal ignores it — a key press has already waited.
    /// - Returns: The text, its source, and the region to anchor a popover to.
    func resolved(
        nowNanos: Int64, delaySeconds: Double
    ) -> (text: String, source: Source, handlerID: HitTestRegion.HandlerID?)? {
        if let hovered {
            let elapsed = max(0, nowNanos - hovered.sinceNanos)
            let needed = Int64(max(0, delaySeconds) * 1_000_000_000)
            guard elapsed >= needed else { return nil }
            return (hovered.text, .hover, hovered.handlerID)
        }
        guard keyboardRevealed, let focused else { return nil }
        return (focused.text, .focus, focused.handlerID)
    }

    /// When the hover delay expires, as a monotonic deadline — `nil` when
    /// nothing is waiting on it.
    ///
    /// The run loop is demand-driven, so a tooltip whose delay expires between
    /// frames appears only if something else happens to redraw. This is what
    /// `HelpModifier` schedules a one-shot wake against.
    func hoverDeadlineNanos(delaySeconds: Double) -> Int64? {
        guard let hovered else { return nil }
        return hovered.sinceNanos &+ Int64(max(0, delaySeconds) * 1_000_000_000)
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
