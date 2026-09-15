//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationRequest.swift
//
//  Created by LAYERED.work
//  License: MIT

/// What a view asks for when it wants the run loop to re-render it periodically:
/// a render every `frameTicks` ticks of 1/60 s, at the instants those ticks begin,
/// counted from tick zero of the frame clock
/// (`AnimationClock.nanoseconds(ofNextTickMultiple:after:)`).
///
/// A request has no anchor and nothing to negotiate. Every request, and every run
/// whose frames are whole ticks, already meets every other wherever their
/// multiples do, so one render at those instants serves all of them, and the
/// scheduler keeps a request exactly as it was declared.
///
/// A request was once a rate in hertz, placed on a grid of whole nanoseconds
/// anchored where it was first asked for, with a frequency and a phase tolerance
/// that let the scheduler lock it onto a live grid near that rate. With every
/// request on the tick lattice there was nothing left for the lock to decide.
struct AnimationRequest: Equatable, Sendable {
    /// The ticks of 1/60 s between renders, `>= 1`.
    let frameTicks: Int

    /// A render every `frameTicks` ticks of 1/60 s. `frameTicks` must be `>= 1`.
    init(frameTicks: Int) {
        precondition(frameTicks >= 1, "AnimationRequest.frameTicks must be >= 1")
        self.frameTicks = frameTicks
    }
}

// MARK: - The run loop's own requests

extension AnimationRequest {
    /// How often an interpolation is re-rendered: every 2 ticks, 30 Hz.
    ///
    /// A terminal cell has no sub-pixel to reveal, so the visible resolution of a
    /// moving thing is far below a display's: at 30 Hz a quarter-second ease gets
    /// eight distinct pictures, which is past the point where more of them look
    /// smoother.
    ///
    /// A lattice, so its renders are the instants a 2-tick frame begins: where an
    /// indeterminate bar steps, a toast's fade is drawn and a drag's flight is,
    /// rather than beside them. It was 30 Hz on a grid anchored at the frame that
    /// first asked, with a ±6 Hz band to lock onto a grid already running near
    /// that rate; a grid anchored anywhere else could meet the lattice only by
    /// luck.
    static let viewAnimations = AnimationRequest(frameTicks: 2)

    /// How often a drag's lift is re-rendered while the picture travels from the
    /// row to the cursor: every 2 ticks, as a view animation is, which the lift
    /// is in all but name.
    static let dragLift = AnimationRequest(frameTicks: 2)

    /// How often a cancelled drag's walk home is re-rendered: every 2 ticks, like
    /// the lift it reverses.
    static let dragReturn = AnimationRequest(frameTicks: 2)

    /// How often a drag held at a scrollable's edge is re-rendered, so it keeps
    /// scrolling while the pointer holds still: every 3 ticks, the lattice its
    /// steps are due on (`DragAndDropSession.AutoScroll.intervalTicks`).
    static let dragAutoScroll = AnimationRequest(frameTicks: DragAndDropSession.AutoScroll.intervalTicks)
}
