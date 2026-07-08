//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderContext+Animation.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Animation Scheduling

extension RenderContext {
    /// Declares that the view rendering here wants the run loop to re-render it
    /// periodically — the demand-driven replacement for a per-view
    /// `Task.sleep`-loop that calls `setNeedsRender()`.
    ///
    /// Every frame the view is on screen it re-declares its rate (cheap: a
    /// dictionary touch). The scheduler resolves the *first* such declaration for
    /// a `token` into a frozen ``AnimationGrid`` — coalescing it onto an existing
    /// grid when ``frequencyTolerance`` and ``phaseTolerance`` allow — so that one
    /// render serves every animation sharing that grid. A token that stops
    /// re-declaring (the view left the tree, or stopped animating) is dropped, and
    /// a screen with nothing left to animate renders nothing at all.
    ///
    /// No-ops during a measure pass (no side effects there) and when no scheduler
    /// is wired in (e.g. `ViewRenderer`'s one-off snapshot path).
    ///
    /// - Parameters:
    ///   - token: A stable per-view key. Use the structural identity, never
    ///     user-facing data — e.g. `"spinner-\(context.identity.path)"`.
    ///   - frequency: The desired re-render rate, in hertz (`> 0`).
    ///   - frequencyTolerance: The ± rate band, in hertz, the view will accept to
    ///     align with an existing timer. `0` (default) means the rate is exact and
    ///     coalesces only with other timers at the very same rate.
    ///   - phaseTolerance: How long, in nanoseconds, the view will let its *first*
    ///     firing be delayed so its grid lands on an existing one. `nil` (default)
    ///     uses one full period — enough for a new timer to align onto any live
    ///     same-rate grid. Pass `0` to start exactly now.
    @MainActor
    func requestAnimation(
        token: String,
        frequency: Double,
        frequencyTolerance: Double = 0,
        phaseTolerance: Int64? = nil
    ) {
        guard !isMeasuring else { return }
        // Declare "this subtree's output is time-varying" to any value-memoizing
        // ancestor (_MemoizedRow, EquatableView). Serving a cached buffer of an
        // animating subtree would freeze its visible frame AND skip this method's
        // per-frame re-declaration, so the scheduler would drop the grid and stop
        // ticking it altogether (issue #1). Recorded before the scheduler guard
        // so scheduler-less one-off renders classify the subtree consistently.
        environment.volatileReadTracker?.recordAnimationRequest()
        guard let scheduler = environment.animationScheduler else { return }
        let onePeriod = Int64((1_000_000_000.0 / frequency).rounded())
        let request = AnimationRequest(
            frequency: frequency,
            frequencyTolerance: frequencyTolerance,
            phaseTolerance: phaseTolerance ?? onePeriod
        )
        scheduler.request(token, request, now: environment.frameNowNanos)
    }
}
