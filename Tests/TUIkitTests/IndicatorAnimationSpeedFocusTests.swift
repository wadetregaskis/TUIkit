//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IndicatorAnimationSpeedFocusTests.swift
//
//  `.indicatorAnimationSpeed(_:for: .focusEmphasis)` reaching the breath and the
//  blink a focused control draws itself with, checked on the runs a focused
//  bracketed button leaves for its two caps. The holds, and the agreement between a
//  live read and a replayed run at other speeds, are in
//  `CursorBlinkRegularityTests`.
//  Durations are compared in whole nanoseconds, the unit a run's steps are counted
//  in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Indicator animation speed on the focus emphasis")
struct IndicatorAnimationSpeedFocusTests {
    /// Each run a focused `view` leaves, as (frames, frame duration in ns, cycle in ns).
    private func runs(_ view: some View) -> [(frames: Int, frameNanos: Int64, cycleNanos: Int64)] {
        focusedRender(view).animatedCells.map {
            (
                $0.frames.count, AnimationClock.nanoseconds($0.frameDuration),
                AnimationClock.nanoseconds($0.cycleDuration)
            )
        }
    }

    /// Every run of a focused button's caps breathes a cycle of `cycleNanos`, in
    /// frames of `frameNanos`, and there are two of them.
    private func expectCaps(
        _ view: some View, cycleNanos: Int64, frameNanos: Int64,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let seen = runs(view)
        #expect(seen.count == 2, "a focused button leaves one run per cap", sourceLocation: sourceLocation)
        #expect(
            seen.allSatisfy { $0.cycleNanos == cycleNanos && $0.frameNanos == frameNanos },
            "\(seen)", sourceLocation: sourceLocation)
    }

    /// The breath is a ramp, sampled one 50 ms cursor tick a frame whatever its
    /// speed, so twice as fast is half as many frames, not shorter ones.
    @Test("A focused button's caps breathe in 0.4 s at twice the speed, in 50 ms frames")
    func breathAtDoubleSpeed() {
        expectCaps(
            Button("Save") {}.indicatorAnimationSpeed(2, for: .focusEmphasis),
            cycleNanos: 400_000_000, frameNanos: 50_000_000)
    }

    @Test("A focused button's caps breathe in 1.6 s at half the speed, in 50 ms frames")
    func breathAtHalfSpeed() {
        expectCaps(
            Button("Save") {}.indicatorAnimationSpeed(.halfSpeed, for: .focusEmphasis),
            cycleNanos: 1_600_000_000, frameNanos: 50_000_000)
        #expect(runs(Button("Save") {}.indicatorAnimationSpeed(.halfSpeed, for: .focusEmphasis)).first?.frames == 32)
    }

    /// A blink is a sequence of two frames, so its frames stretch: 350 ms halves at
    /// the standard speed are 175 ms at twice it.
    @Test("A focused button's caps blink in 175 ms halves at twice the speed")
    func blinkAtDoubleSpeed() {
        let view = Button("Save") {}.selectionIndicatorStyle(.blink).indicatorAnimationSpeed(2, for: .focusEmphasis)
        expectCaps(view, cycleNanos: 350_000_000, frameNanos: 175_000_000)
        #expect(runs(view).allSatisfy { $0.frames == 2 })
    }

    @Test("Unset, a focused button's caps breathe in the standard 0.8 s")
    func unsetIsTheStandardBreath() {
        expectCaps(Button("Save") {}, cycleNanos: 800_000_000, frameNanos: 50_000_000)
    }

    @Test("The nearest setting for the focus emphasis wins, and a setting for another kind leaves it alone")
    func nearestWins() {
        // A speed for spinners does not reach the focus emphasis.
        expectCaps(
            Button("Save") {}.indicatorAnimationSpeed(2, for: .spinners),
            cycleNanos: 800_000_000, frameNanos: 50_000_000)
        // `.all` does.
        expectCaps(
            Button("Save") {}.indicatorAnimationSpeed(2), cycleNanos: 400_000_000, frameNanos: 50_000_000)
        // Inner `.focusEmphasis` at 0.5 inside outer `.all` at 2.
        expectCaps(
            Button("Save") {}.indicatorAnimationSpeed(0.5, for: .focusEmphasis).indicatorAnimationSpeed(2),
            cycleNanos: 1_600_000_000, frameNanos: 50_000_000)
        // A nearer setting for spinners leaves the outer `.all` in force.
        expectCaps(
            Button("Save") {}.indicatorAnimationSpeed(0.5, for: .spinners).indicatorAnimationSpeed(2),
            cycleNanos: 400_000_000, frameNanos: 50_000_000)
    }

    /// 0.8 s at 1.5 is 0.5333 s, which samples to 11 frames. Exact, each is
    /// 48,484,848 ns. At 1.5 ± 0.1, 11 whole 50 ms frames (0.55 s, a rate of 1.4545)
    /// are inside the band, so the breath moves onto them.
    @Test("Within a tolerance the breath moves onto whole cursor ticks, and an exact speed stays exact")
    func toleranceMovesTheBreathOntoTicks() {
        let exact = runs(Button("Save") {}.indicatorAnimationSpeed(1.5, for: .focusEmphasis))
        #expect(exact.count == 2)
        #expect(exact.allSatisfy { $0.frames == 11 && $0.frameNanos == 48_484_848 }, "\(exact)")
        expectCaps(
            Button("Save") {}.indicatorAnimationSpeed(IndicatorAnimationSpeed(1.5, tolerance: 0.1), for: .focusEmphasis),
            cycleNanos: 550_000_000, frameNanos: 50_000_000)
    }
}
