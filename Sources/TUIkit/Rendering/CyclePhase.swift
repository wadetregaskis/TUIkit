//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CyclePhase.swift
//
//  Where a looping cycle stands, kept so a change of frame length carries on
//  from the frame showing.
//
//  Created by Wade Tregaskis
//  License: MIT

/// How far a looping cycle of frames is turned from the shared clock's phase, and
/// the frame length that turn was taken for.
///
/// A cycle that asks nothing of anyone shows frame `step mod count` at every
/// instant, where `step` is the whole steps of its frame length on the content
/// clock since tick zero: every cycle of one length is then in phase with every
/// other, and a render and a replay agree without being told anything. That is a
/// function of the LENGTH, though, and a new length puts the same instant at a
/// different step of a different lattice. So a cycle whose speed changed jumped,
/// the instant the change was drawn, to wherever the new length happened to land
/// — back a frame, forward two, or nowhere — and on the Spinners page, where the
/// Frame stepper changes one style's length a click at a time, any click could.
///
/// Kept per view, this makes the change continuous: the instant a new length is
/// first drawn, the cycle is turned so that the frame it shows is the frame the old
/// length showed there, and it steps on at the new length from there. The steps
/// stay on the new length's lattice — only which frame each step shows is turned —
/// so a cycle that has changed speed still changes on the same ticks as everything
/// else of its length and costs the run loop no wake of its own. What it gives up is
/// being in phase with the others: a view that has changed speed keeps its own turn
/// until it leaves the tree.
struct CyclePhase: Equatable {
    /// The frame length, in 1/60 s ticks, the turn was taken for.
    var frameTicks: Int

    /// How many frames the cycle is turned by: at step `s` it shows frame
    /// `s + turn`, modulo the frame count.
    var turn: Int64

    /// The shared clock's phase at `frameTicks`: no turn.
    init(frameTicks: Int, turn: Int64 = 0) {
        self.frameTicks = frameTicks
        self.turn = turn
    }

    /// This phase carried to a frame length of `ticks` at `elapsed` seconds on the
    /// content clock, for a cycle of `count` frames: itself when the length has not
    /// changed, and otherwise the turn at which the new length shows, at `elapsed`,
    /// the frame this one shows there.
    func continued(toFrameTicks ticks: Int, atElapsed elapsed: Double, count: Int) -> Self {
        guard ticks != frameTicks, count > 0 else { return self }
        let showing = AnimationClock.step(atElapsed: elapsed, frameTicks: frameTicks) &+ turn
        let step = AnimationClock.step(atElapsed: elapsed, frameTicks: ticks)
        return Self(frameTicks: ticks, turn: Self.wrapped(showing &- step, count: count))
    }

    /// The frame of a cycle of `count` frames this phase shows at `elapsed`: a
    /// whole number in `0..<count`, or 0 for an empty cycle.
    func index(atElapsed elapsed: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let step = AnimationClock.step(atElapsed: elapsed, frameTicks: frameTicks)
        return Int(Self.wrapped(step &+ turn, count: count))
    }

    /// `frames` turned by this phase, for an ``AnimatedCellRun``: a run shows frame
    /// `step mod count` of what it is given, and this puts at that place the frame
    /// the phase shows at `step`, so the run replays what the render drew. `frames`
    /// itself when there is no turn to make.
    func turning<Frame>(_ frames: [Frame]) -> [Frame] {
        guard !frames.isEmpty else { return frames }
        let by = Int(Self.wrapped(turn, count: frames.count))
        guard by != 0 else { return frames }
        return Array(frames[by...] + frames[..<by])
    }

    /// `value` modulo `count`, in `0..<count` whatever its sign.
    private static func wrapped(_ value: Int64, count: Int) -> Int64 {
        let modulus = Int64(count)
        let remainder = value % modulus
        return remainder < 0 ? remainder + modulus : remainder
    }
}
