//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FramePacer.swift
//
//  Created by LAYERED.work
//  License: MIT

/// The run loop's frame pacing: whether a frame is due now, and how long the
/// loop may sleep before the next one.
///
/// The two questions share one answer, so they share one owner. A frame is owed
/// the moment state changes, but must not render before the frame-rate cap
/// clears; an animation deadline that has passed owes a frame and likewise
/// waits for the cap; and the sleep has to target whichever of those comes
/// first, or the loop wakes to find nothing due and sleeps again. Splitting the
/// three facts across the loop body is what made that interaction impossible to
/// exercise without a live terminal.
///
/// Time is passed in, never read. One monotonic reading drives every decision
/// of a loop iteration, so the render test and the sleep length cannot disagree
/// about whether a deadline has passed.
///
/// Rendering goes through ``renderIfDue(now:_:)`` rather than a "may I?" query
/// the caller answers itself, because adopting the frame's timestamp and its
/// next animation deadline is not something a caller may forget: a deadline
/// left in the past fires on every iteration, which turns a demand-driven loop
/// into a spin.
struct FramePacer {
    /// What one render reports back: when it happened, and the soonest instant
    /// any animation grid it declared next fires (`nil` when nothing animates).
    struct Frame {
        let renderedAtNanos: UInt64
        let animationDeadlineNanos: UInt64?
    }

    /// How long to wait before re-checking the input parser while it holds a
    /// partial (a lone ESC being disambiguated, a split sequence awaiting its
    /// tail). At ~25 ms a bare Escape commits within a few of these (~75 ms) —
    /// well under the "feels instant" threshold — without depending on any other
    /// activity to wake the loop.
    static let pendingInputPollNanos: UInt64 = 25_000_000

    /// The frame-rate cap: two frames are never rendered closer together than
    /// this.
    let frameIntervalNanos: UInt64

    /// Whether something has asked for a frame that has not yet rendered.
    private(set) var isRenderPending = false

    private var lastRenderAtNanos: UInt64
    private var animationDeadlineNanos: UInt64?

    /// - Parameters:
    ///   - maxFrameRate: the app's cap in frames per second; the interval is its
    ///     reciprocal. Clamped to at least 1 FPS, so a nonsense rate cannot
    ///     divide by zero.
    ///   - startedAtNanos: the instant the cap measures from until the first
    ///     frame renders.
    init(maxFrameRate: Int, startedAtNanos: UInt64) {
        self.frameIntervalNanos = 1_000_000_000 / UInt64(max(1, maxFrameRate))
        self.lastRenderAtNanos = startedAtNanos
    }

    /// Notes that a frame is owed. It renders at the next iteration in which the
    /// cap has cleared, so a burst of requests coalesces into one frame.
    mutating func requestRender() {
        isRenderPending = true
    }

    /// Renders now, whatever the cap says, and adopts what the frame reports.
    ///
    /// For the frame that has no earlier one to be paced against — the initial
    /// render, before the loop starts.
    mutating func render(_ body: () -> Frame) {
        let frame = body()
        lastRenderAtNanos = frame.renderedAtNanos
        animationDeadlineNanos = frame.animationDeadlineNanos
        isRenderPending = false
    }

    /// Renders if a frame is owed and the cap has cleared, and reports whether
    /// it did.
    ///
    /// An animation deadline that `now` has reached owes a frame in its own
    /// right. That debt survives a capped-out iteration: the flag stays set, so
    /// the frame renders as soon as the cap clears rather than being dropped
    /// because the deadline had already passed by the time it could have.
    @discardableResult
    mutating func renderIfDue(now: UInt64, _ body: () -> Frame) -> Bool {
        if let deadline = animationDeadlineNanos, now >= deadline {
            isRenderPending = true
        }
        guard isRenderPending, now >= lastRenderAtNanos &+ frameIntervalNanos else {
            return false
        }
        render(body)
        return true
    }

    /// The delay until the next render is due, or `nil` to block until woken.
    ///
    /// Folds the frame-rate cap and the next animation deadline into ONE instant:
    /// a pending render wants a frame as soon as the cap clears; an animation
    /// wants one at its deadline but never sooner than the cap (so `max` there).
    /// Waiting to this single target — rather than to the deadline, waking,
    /// finding the cap not yet cleared, and waiting again — is what holds the
    /// loop to one wait per render. With nothing pending and nothing animating
    /// the target is `nil` and the loop blocks until woken, so a static screen
    /// does no work at all.
    ///
    /// - Parameter pollingPendingInput: `true` while the input parser holds a
    ///   partial. The poll only ever *shortens* the wait — including a `nil` one
    ///   — so a resolving Escape never has to wait on unrelated activity, and an
    ///   already-sooner frame is not delayed to meet it.
    func waitNanos(now: UInt64, pollingPendingInput: Bool = false) -> UInt64? {
        let capDeadline = lastRenderAtNanos &+ frameIntervalNanos
        var target: UInt64?
        if isRenderPending {
            target = capDeadline
        }
        if let deadline = animationDeadlineNanos {
            let animTarget = max(deadline, capDeadline)
            target = min(target ?? animTarget, animTarget)
        }
        let wait = target.map { $0 > now ? $0 &- now : 0 }
        guard pollingPendingInput else { return wait }
        return min(wait ?? Self.pendingInputPollNanos, Self.pendingInputPollNanos)
    }
}
