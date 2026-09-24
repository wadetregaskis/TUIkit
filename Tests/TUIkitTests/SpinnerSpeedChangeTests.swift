//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SpinnerSpeedChangeTests.swift
//
//  A spinner whose speed changes carries on from the frame it is showing.
//
//  A spinner's frame is the step its frame length has reached on the shared
//  content clock, counted from tick zero. Change the length and the same instant
//  is a different step of a different lattice: at tick 37, `.line` at 8 ticks a
//  frame is on its first glyph and at 5 ticks a frame on its last, so the new
//  speed took effect by jumping the spinner BACK a frame. On the Example's
//  Spinners page, where the Frame stepper changes one style's speed a click at a
//  time, every click jumped that spinner to wherever the new length happened to
//  land — backwards, forwards by two, or not at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// The frame lengths a key press steps a `.line` spinner through, in ticks.
private let frameLengths = [8, 5, 13, 3, 8]

/// One `.line` spinner whose speed moves to the next of `frameLengths` on each
/// press of `s`, and a second, `.line` too, that never changes speed.
private struct SpeedSteppingApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { SpeedSteppingPage() }
    }
}

private struct SpeedSteppingPage: View {
    @State private var presses = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spinner("stepped", style: .line)
                .indicatorAnimationSpeed(Self.speed(ticks: frameLengths[presses % frameLengths.count]), for: .spinners)
            Spinner("steady", style: .line)
                .indicatorAnimationSpeed(Self.speed(ticks: frameLengths[0]), for: .spinners)
        }
        .onKeyPress(.character("s")) { presses += 1 }
    }

    /// The speed that shows `.line`'s frames for exactly `ticks` ticks — the
    /// Spinners page's Frame stepper's own arithmetic.
    static func speed(ticks: Int) -> IndicatorAnimationSpeed {
        IndicatorAnimationSpeed(SpinnerStyle.line.interval / AnimationClock.seconds(forTicks: ticks))
    }
}

/// The same pair as rows of a `ForEach` over `Equatable` elements, the Spinners
/// page's shape: each row's identity is its name, and its value — which the row
/// memo compares — carries its speed, so a change re-renders the row where it is.
private struct SpeedRow: Identifiable, Equatable {
    let name: String
    let ticks: Int
    var id: String { name }
}

private struct MemoizedRowsApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { MemoizedRowsPage() }
    }
}

private struct MemoizedRowsPage: View {
    @State private var presses = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach([
                SpeedRow(name: "stepped", ticks: frameLengths[presses % frameLengths.count]),
                SpeedRow(name: "steady", ticks: frameLengths[0]),
            ]) { row in
                Spinner(row.name, style: .line)
                    .indicatorAnimationSpeed(SpeedSteppingPage.speed(ticks: row.ticks), for: .spinners)
            }
        }
        .onKeyPress(.character("s")) { presses += 1 }
    }
}

@MainActor
@Suite("A spinner whose speed changes")
struct SpinnerSpeedChangeTests {
    /// Which of `.line`'s frames the row labelled `label` shows.
    private func frame(of label: String, on screen: [String]) -> Int? {
        guard let line = screen.map(\.stripped).first(where: { $0.contains(label) }),
            let glyph = line.first(where: { SpinnerStyle.line.frames.contains(String($0)) })
        else { return nil }
        return SpinnerStyle.line.frames.firstIndex(of: String(glyph))
    }

    /// Every tick for four seconds, with the speed changed at four of them —
    /// instants at which the old and new lattices disagree, backwards and by
    /// two as well as by nothing. Rendering every tick draws what the run loop
    /// replays between renders, so the sequence is what is on screen.
    @Test("Each tick shows the frame before it or the one after, through every change of speed")
    func carriesOnFromTheFrameShowing() {
        expectContinuous(HeadlessApp(SpeedSteppingApp(), width: 30, height: 8))
    }

    /// The same, where the spinner sits in a memoized row whose value changes with
    /// the speed: the row misses, re-renders at the identity it had, and its spinner
    /// is the spinner it was.
    @Test("A spinner in a memoized row carries on too when its row's speed changes")
    func carriesOnInAMemoizedRow() {
        expectContinuous(HeadlessApp(MemoizedRowsApp(), width: 30, height: 8))
    }

    private func expectContinuous<A: App>(_ app: HeadlessApp<A>) {
        let changes: Set<Int> = [37, 90, 141, 200]
        var shown: [Int] = []
        for tick in 0..<240 {
            if changes.contains(tick) { app.send(KeyEvent(key: .character("s"))) }
            app.frame(atNanos: AnimationClock.nanoseconds(atTick: Int64(tick)))
            guard let index = frame(of: "stepped", on: app.screen) else {
                Issue.record("no spinner on screen at tick \(tick): \(app.screen.map(\.stripped))")
                return
            }
            shown.append(index)
        }
        let count = SpinnerStyle.line.frames.count
        var jumps: [String] = []
        for tick in 1..<shown.count {
            let advance = (shown[tick] - shown[tick - 1] + count) % count
            if advance > 1 { jumps.append("tick \(tick): \(shown[tick - 1]) → \(shown[tick])") }
        }
        #expect(jumps.isEmpty, "the spinner jumped: \(jumps)")
        // And it did keep moving, at each speed in turn: 240 ticks at 3 to 13 a
        // frame is dozens of steps, not a spinner stuck on one glyph.
        let steps = (1..<shown.count).filter { shown[$0] != shown[$0 - 1] }.count
        #expect(steps > 20, "only \(steps) steps in 240 ticks")
    }

    /// The price of the above, pinned so it is a decision rather than an accident:
    /// a spinner that has changed speed keeps its own phase, and one that never has
    /// stays on the shared clock's, in phase with every other spinner of its style.
    @Test("A spinner that never changes speed stays on the shared clock's phase")
    func anUnchangedSpinnerKeepsTheSharedPhase() {
        let app = HeadlessApp(SpeedSteppingApp(), width: 30, height: 8)
        for tick in 0..<120 {
            if tick == 37 { app.send(KeyEvent(key: .character("s"))) }
            let now = AnimationClock.nanoseconds(atTick: Int64(tick))
            app.frame(atNanos: now)
            let shared = Int(AnimationClock.step(atElapsed: Double(now) / 1_000_000_000, frameTicks: 8) % 4)
            #expect(frame(of: "steady", on: app.screen) == shared, "tick \(tick)")
        }
    }
}
