//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AnimationReplayTests.swift
//
//  The rule that keeps the cheap animation path safe: a clock may be advanced
//  without rendering ONLY when nothing on screen built its appearance from that
//  clock's phase while rendering. Get that backwards and a half-migrated page
//  freezes its indicator.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@Suite("Animation replay eligibility")
struct AnimationReplayEligibilityTests {

    private func activity(
        pulse: Bool = false, cursor: Bool = false, clocks: Set<AnimationClock> = []
    ) -> RenderActivity {
        RenderActivity(usesPulse: pulse, usesCursor: cursor, animatedClocks: clocks)
    }

    @Test("Runs and no reader: replay")
    func runsWithoutReadersReplay() {
        #expect(activity(clocks: [.pulse]).canReplay(.pulse))
        #expect(activity(clocks: [.cursor]).canReplay(.cursor))
    }

    @Test("No runs: nothing to replay")
    func noRunsNoReplay() {
        // The frame animates nothing on this clock, so a tick has nothing to
        // advance — the caller renders, which is what it did before any of this.
        #expect(!activity().canReplay(.pulse))
        #expect(!activity(pulse: true).canReplay(.pulse))
    }

    @Test("A view still reading the phase forces a render, runs or not")
    func readerBeatsRuns() {
        // The migration rule. Mid-conversion a page has both: some indicator
        // left a run, another still blends colour from the phase as it renders.
        // Replaying would advance the first and freeze the second, so the
        // reader wins and everything renders — exactly today's behaviour, which
        // is the safe direction to be wrong in.
        #expect(!activity(pulse: true, clocks: [.pulse]).canReplay(.pulse))
        #expect(!activity(cursor: true, clocks: [.cursor]).canReplay(.cursor))
    }

    @Test("The clocks are independent")
    func clocksDoNotInterfere() {
        // A focused text field (cursor reader) must not stop the focus ring's
        // runs being replayed, and vice versa.
        let mixed = activity(pulse: false, cursor: true, clocks: [.pulse, .cursor])
        #expect(mixed.canReplay(.pulse))
        #expect(!mixed.canReplay(.cursor))
    }
}

@Suite("Animated run splicing")
struct AnimatedRunSplicingTests {

    @Test("Replacing a run's cells leaves the rest of the line alone")
    func spliceKeepsSurroundings() {
        // This is the operation the loop performs per tick, through the ordinary
        // compositor. The point of the test is the ANSI-awareness: styled text
        // either side must survive, and the visible width must not move.
        let red = "\u{1B}[31m"
        let reset = "\u{1B}[0m"
        let line = "\(red)left\(reset)  MID  \(red)right\(reset)"
        let width = line.strippedLength

        let patched = FrameBuffer(lines: [line])
            .composited(with: FrameBuffer(lines: ["XXX"]), at: (x: 6, y: 0))

        let result = patched.lines[0]
        #expect(result.strippedLength == width, "the row must not change width")
        let visible = result.stripped
        #expect(visible.hasPrefix("left"))
        #expect(visible.hasSuffix("right"))
        #expect(visible.contains("XXX"))
    }

    @Test("A one-frame run is not replayed")
    func stillPicturesAreFilteredOut() {
        // The loop keeps only `isAnimating` runs, so a producer may build one
        // unconditionally — a disabled control, a non-blinking cursor style —
        // without having to decide not to.
        let still = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1, frames: ["●"], clock: .pulse)
        let moving = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1, frames: ["●", "○"], clock: .pulse)
        #expect([still, moving].filter(\.isAnimating) == [moving])
    }

    @Test("Splicing repeatedly must start from the same line every time")
    func repeatedSplicesDoNotAccumulate() {
        // Compositing REPLACES a cell's glyph but keeps the styling context
        // around it, so the colour code of the frame that was there is left
        // behind as an empty run. Splice into your own previous output and
        // those dead escapes pile up — one per tick, forever. The line still
        // LOOKS right (its visible width never changes), so only its byte
        // length shows the leak; it reached the terminal as tens of kilobytes
        // a second to animate two cells.
        //
        // Hence the rule the run loop follows: always patch the pristine line
        // the last render produced, never the patched one.
        let pristine = "\u{1B}[38;5;34m▐\u{1B}[0m Save \u{1B}[38;5;34m▌\u{1B}[0m"
        let frames = (30...45).map { "\u{1B}[38;5;\($0)m▐\u{1B}[0m" }

        var fromPristine: [Int] = []
        var accumulated: [Int] = []
        var running = pristine
        for frame in frames {
            let patch = FrameBuffer(lines: [frame])
            fromPristine.append(
                FrameBuffer(lines: [pristine]).composited(with: patch, at: (x: 0, y: 0))
                    .lines[0].count)
            running = FrameBuffer(lines: [running]).composited(with: patch, at: (x: 0, y: 0))
                .lines[0]
            accumulated.append(running.count)
        }

        // Patching the pristine line is stable: same work, same size, every tick.
        #expect(Set(fromPristine).count == 1, "sizes: \(fromPristine)")
        // Patching your own output is not — and this is the assertion that
        // fails if the loop ever goes back to storing what it patched.
        #expect(
            accumulated.last! > accumulated.first!,
            "compositing no longer leaves the replaced run's escapes behind; if that is now true by construction, this test can go")
    }
}
