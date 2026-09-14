//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndicatorCycleTiming.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// When a focus indicator's or a caret's cycle steps: how long each frame is
/// shown, and the clock the steps are counted on.
///
/// The cycle carries it (`SelectionEmphasisCycle`, `TextFieldContentRenderer.CursorCycle`,
/// `AnimatedColor`), and every run built from a cycle takes both from it. Producers
/// used to write `clock: .cursor` and leave the frame duration to the run's default,
/// which is right only while every cycle is laid out one cursor tick a frame.
/// Nothing on a producer's side of a cycle should know what its frames are laid out
/// on.
struct IndicatorCycleTiming: Equatable, Sendable {
    /// How long each frame is shown, in seconds.
    var frameDuration: Double

    /// The clock the steps are counted on, and the one a run built from the cycle
    /// replays on.
    var clock: AnimationClock

    /// One cursor tick a frame, on the focus-relative clock: a still cycle's timing,
    /// and a pulse's standard frame.
    static let cursorTick = Self(
        frameDuration: AnimationClock.cursor.tickInterval, clock: .cursor)

    /// Which frame of a cycle laid out on this timing shows at `timer`'s last
    /// snapshot, or 0 without a timer.
    ///
    /// Counted through `AnimationClock.step(atElapsed:frameDuration:)`, the one
    /// conversion a run's own frame index goes through, so the frame a render draws
    /// and the frame a replay splices at the same instant are the same frame. A plain
    /// read: it does not mark the frame as having consulted the clock, so a producer
    /// that asks stays replayable.
    @MainActor
    func step(on timer: CursorTimer?) -> Int {
        guard let timer else { return 0 }
        // Clamped rather than narrowed: `Int` is 32 bits on wasm32.
        return Int(
            clamping: AnimationClock.step(
                atElapsed: timer.elapsed(for: clock), frameDuration: frameDuration))
    }
}

private struct IndicatorCycleTimingKey: EnvironmentKey {
    static let defaultValue: IndicatorCycleTiming? = nil
}

extension EnvironmentValues {
    /// A timing to build every focus-emphasis and caret cycle on, in place of the
    /// one its animation is laid out on (`CursorTimer.cycleLayout(of:speed:)`).
    ///
    /// Always `nil` in an app: nothing public sets it. A test sets one, to see which
    /// producer assumes a timing instead of carrying its cycle's.
    var indicatorCycleTiming: IndicatorCycleTiming? {
        get { self[IndicatorCycleTimingKey.self] }
        set { self[IndicatorCycleTimingKey.self] = newValue }
    }
}
