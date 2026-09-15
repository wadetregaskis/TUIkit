//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderContext+Animation.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Animation Scheduling

extension RenderContext {
    /// Declares that the view rendering here wants the run loop to re-render it
    /// every `frameTicks` ticks of 1/60 s, at the instants those ticks begin,
    /// counted from tick zero of the frame clock — the demand-driven replacement
    /// for a per-view `Task.sleep`-loop that calls `setNeedsRender()`.
    ///
    /// Every frame the view is on screen it re-declares its request (cheap: a
    /// dictionary touch). A lattice has no anchor, so its renders are the instants
    /// every other animation of whole ticks changes at, and one render serves
    /// all of them. A token that stops re-declaring (the view left the tree, or
    /// stopped animating) is dropped, and a screen with nothing left to animate
    /// renders nothing at all.
    ///
    /// No-ops during a measure pass (no side effects there) and when no scheduler
    /// is wired in (e.g. `ViewRenderer`'s one-off snapshot path).
    ///
    /// - Parameters:
    ///   - token: A stable per-view key. Use the structural identity, never
    ///     user-facing data — e.g. `"scrollbar-\(context.identity.path)"`.
    ///   - frameTicks: The ticks between renders (`>= 1`).
    @MainActor
    func requestAnimation(token: String, frameTicks: Int) {
        guard !isMeasuring else { return }
        // Declare "this subtree's output is time-varying" to any value-memoizing
        // ancestor (_MemoizedRow, EquatableView). Serving a cached buffer of an
        // animating subtree would freeze its visible frame AND skip this method's
        // per-frame re-declaration, so the scheduler would drop the lattice and
        // stop rendering it altogether (issue #1). Recorded before the scheduler
        // guard so scheduler-less one-off renders classify the subtree consistently.
        environment.volatileReadTracker?.recordRenderSideEffect()
        guard let scheduler = environment.animationScheduler else { return }
        scheduler.request(token, AnimationRequest(frameTicks: frameTicks))
    }

    /// Declares that the view rendering here needs one render at a single
    /// instant `delay` seconds from this frame — the one-shot counterpart of
    /// ``requestAnimation(token:frameTicks:)``.
    ///
    /// For a view whose next update is an *instant* rather than a rate: a
    /// ``TimelineView`` following a schedule whose entries need not be evenly
    /// spaced, and whose evenly spaced ones have a phase (the top of the minute)
    /// that a lattice counted from tick zero would not keep. Re-declared every
    /// frame like a lattice, and dropped when it is not, so a finished schedule
    /// lets the screen go idle.
    ///
    /// The delay is measured from the frame's own monotonic clock, so a
    /// wall-clock adjustment between frames cannot strand the wake.
    ///
    /// - Parameters:
    ///   - token: A stable per-view key, from the structural identity — e.g.
    ///     `"timeline-\(context.identity.path)"`.
    ///   - delay: Seconds from this frame. Negative delays are treated as zero
    ///     (a wake that has already passed is not a firing — see
    ///     ``AnimationScheduler/nextFiring(after:)``), and the far end is
    ///     clamped to a horizon of about three years so that a date in the
    ///     distant future cannot overflow the monotonic clock.
    @MainActor
    func requestWake(token: String, afterSeconds delay: Double) {
        let nanos = (max(0, delay) * 1_000_000_000).rounded()
        let clamped = Int64(min(nanos, Self.wakeHorizonNanos))
        requestWake(token: token, atNanos: environment.frameNowNanos &+ clamped)
    }

    /// Declares that the view rendering here needs one render at `instant`, in
    /// nanoseconds on the frame's monotonic clock (the clock `frameNowNanos` reads).
    ///
    /// The counterpart of ``requestWake(token:afterSeconds:)`` for a view that
    /// already knows the instant in whole nanoseconds: a run's next step boundary,
    /// from `AnimationClock.stepEndNanos(atElapsed:frameTicks:)`. Asked in
    /// seconds, that boundary would go through a `Double` and back, and one that
    /// comes back a nanosecond early is a render that finds the step not yet
    /// changed — the trap `CursorTimer.sleepNanoseconds(_:)` exists for.
    ///
    /// Re-declared every frame and dropped when it is not, like the other. An
    /// instant this frame has already reached is not a firing (see
    /// ``AnimationScheduler/nextFiring(after:)``).
    ///
    /// - Parameters:
    ///   - token: A stable per-view key, from the structural identity.
    ///   - instant: When to render, on the frame clock.
    @MainActor
    func requestWake(token: String, atNanos instant: Int64) {
        guard !isMeasuring else { return }
        // Same reason as `requestAnimation`: a memoizing ancestor serving a
        // cached buffer would both freeze the visible frame and skip the
        // per-frame re-declaration below, dropping the wake entirely.
        environment.volatileReadTracker?.recordRenderSideEffect()
        guard let scheduler = environment.animationScheduler else { return }
        scheduler.requestWake(token, at: instant)
    }

    /// The furthest ahead a one-shot wake may be asked for: ~3.2 years in
    /// nanoseconds, comfortably inside `Int64` alongside any uptime the clock
    /// can have reached. A schedule naming a date beyond it wakes early and
    /// re-declares, which costs one frame every three years.
    private static var wakeHorizonNanos: Double { 1e17 }
}
