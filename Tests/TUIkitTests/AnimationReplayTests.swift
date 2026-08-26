//  🖥️ TUIkit — Terminal UI Kit for Swift
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
        #expect(activity(clocks: [.cursor]).canReplay(.cursor))
    }

    @Test("No runs: nothing to replay")
    func noRunsNoReplay() {
        // The frame animates nothing, so a tick has nothing to advance — the
        // caller renders, which is what it did before any of this.
        #expect(!activity().canReplay(.cursor))
        #expect(!activity(pulse: true).canReplay(.cursor))
    }

    @Test("A view still reading the phase forces a render, runs or not")
    func readerBeatsRuns() {
        // The migration rule. Mid-conversion a page has both: some indicator
        // left a run, another still blends colour from the phase as it renders.
        // Replaying would advance the first and freeze the second, so the
        // reader wins and everything renders — exactly today's behaviour, which
        // is the safe direction to be wrong in.
        #expect(!activity(pulse: true, clocks: [.cursor]).canReplay(.cursor))
        #expect(!activity(cursor: true, clocks: [.cursor]).canReplay(.cursor))
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
            offsetX: 0, offsetY: 0, width: 1, frames: ["●"], clock: .cursor)
        let moving = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1, frames: ["●", "○"], clock: .cursor)
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

    // MARK: - The background under an animated run

    /// The line a real frame hands the replay: the diff writer's background code
    /// and erase, then a foreground-only glyph, then the rest of the row.
    private func styledRow(background: String = "\u{1B}[48;5;16m") -> String {
        "\(background)\u{1B}[2K\u{1B}[38;5;46m□\u{1B}[0m\(background) Enable\u{1B}[0m\(background)   "
    }

    @Test("A foreground-only frame keeps the background it was drawn over")
    func patchKeepsTheLineBackground() {
        // The regression this exists for: a focus indicator's frames come from
        // colouring a glyph, so they state a foreground and nothing else. The
        // ordinary render draws them inside a line whose background was set at
        // its start; the replay redraws that cell on its own, and reset the
        // background out from under it — a white box around a breathing
        // checkbox on any terminal whose default background is light.
        let patched = FrameBuffer.patchingAnimatedCells(
            in: styledRow(), with: "\u{1B}[38;5;77m□\u{1B}[0m", atColumn: 0, width: 1)

        let glyph = patched.range(of: "□")!
        let before = String(patched[patched.startIndex..<glyph.lowerBound])
        #expect(
            before.hasSuffix("\u{1B}[38;5;77m"),
            "the frame's own foreground must be the last thing set: \(before.debugDescription)")
        #expect(
            before.contains("\u{1B}[48;5;16m"),
            "the line's background must survive to the patched cell: \(before.debugDescription)")
    }

    @Test("The patch takes the background and nothing else")
    func patchDoesNotInheritTextAttributes() {
        // Only the SURFACE is inherited. Bold, underline and the foreground in
        // force at that column belong to the glyph being replaced — carrying
        // them over would make an indicator inside a bold section header bold,
        // which is not what the render drew.
        let bolded = "\u{1B}[1;4;48;5;16m\u{1B}[38;5;46m□\u{1B}[0m rest"
        let patched = FrameBuffer.patchingAnimatedCells(
            in: bolded, with: "\u{1B}[38;5;77m□\u{1B}[0m", atColumn: 0, width: 1)

        let before = String(patched[patched.startIndex..<patched.range(of: "□")!.lowerBound])
        #expect(before.contains("48;5;16"), "background: \(before.debugDescription)")
        // The prefix at column 0 is empty, so the only escapes here are the ones
        // the patch put there — a `1` or `4` among them could only have leaked.
        #expect(!before.contains("[1m") && !before.contains("1;"), "\(before.debugDescription)")
        #expect(!before.contains("[4m") && !before.contains("4;"), "\(before.debugDescription)")
    }

    @Test("A run away from column 0 gets the same treatment")
    func patchMidLineKeepsTheBackground() {
        // Buttons, scroll indicators and text cursors sit inside chrome, so
        // their runs start at a column the prefix reaches — which changes which
        // escapes `insertOverlay` keeps, and changed nothing about the hole:
        // it resets before the overlay either way.
        let patched = FrameBuffer.patchingAnimatedCells(
            in: styledRow(), with: "\u{1B}[38;5;77mX\u{1B}[0m", atColumn: 3, width: 1)

        let marker = patched.range(of: "X")!
        let before = String(patched[patched.startIndex..<marker.lowerBound])
        // The last background stated before the patched cell must be the line's.
        #expect(
            before.ansiSGRStateAt(visibleColumn: 3).renderedBackground == "\u{1B}[48;5;16m",
            "\(before.debugDescription)")
    }

    /// A frame is usually several coloured pieces, and each piece ends with a
    /// reset — `colorize(arrow) + colorize(label)` for a scroll indicator,
    /// `colorize("●") + " "` for a button's focus gutter, `colorize("[") + mark
    /// + colorize("]")` for an ASCII toggle. A background stated only in FRONT
    /// of all that survives to the first reset and no further, so the first
    /// piece kept the line's surface and every piece after it punched through:
    /// the "N more above" arrow was right and its label was white, the `●` was
    /// right and the cell beside it was white, `[` was right and `x]` was white.
    @Test("The background survives every reset inside the frame")
    func patchRestatesTheBackgroundAfterInnerResets() {
        let reset = "\u{1B}[0m"
        let frame = "\u{1B}[38;5;77m▲\(reset)\u{1B}[38;5;77m 3 more lines above \(reset)"
        let patched = FrameBuffer.patchingAnimatedCells(
            in: styledRow(), with: frame, atColumn: 0, width: frame.strippedLength)

        // Every visible cell of the run must have the line's background in force.
        let runCells = patched.ansiAwarePrefix(visibleCount: frame.strippedLength)
        for column in 0..<frame.strippedLength {
            #expect(
                runCells.ansiSGRStateAt(visibleColumn: column).renderedBackground
                    == "\u{1B}[48;5;16m",
                "column \(column) lost the surface: \(runCells.debugDescription)")
        }
    }

    /// The same thing with a frame the framework actually builds, rather than
    /// one written to have an inner reset: the focus gutter every plain button
    /// and disclosure row opens with is `colorize("●") + " "`, so the reset
    /// lands between the two cells and the blank one is what went white.
    @MainActor
    @Test("A real focus-gutter frame keeps its surface across both cells")
    func realFocusGutterFrameKeepsItsSurface() {
        let palette = SystemPalette(.green)
        let frame = BorderRenderer.focusIndicatorPrefix(
            isFocused: true, emphasis: .steady(isFocused: true), palette: palette)
        #expect(frame.strippedLength == BorderRenderer.focusIndicatorWidth)

        let patched = FrameBuffer.patchingAnimatedCells(
            in: styledRow(), with: frame, atColumn: 0,
            width: BorderRenderer.focusIndicatorWidth)
        let runCells = patched.ansiAwarePrefix(visibleCount: BorderRenderer.focusIndicatorWidth)
        #expect(
            runCells.ansiSGRStateAt(visibleColumn: 1).renderedBackground == "\u{1B}[48;5;16m",
            "the cell after the bullet lost the surface: \(runCells.debugDescription)")
    }

    @Test("A frame's trailing reset is left bare")
    func patchDoesNotAppendADeadBackground() {
        // Nothing follows it inside the run, and `insertOverlay` restores the
        // line's own styling where the suffix begins — so a background there
        // would be bytes per tick, per run, for no change on screen.
        let frame = "\u{1B}[38;5;77m□\u{1B}[0m"
        let patched = FrameBuffer.patchingAnimatedCells(
            in: styledRow(), with: frame, atColumn: 0, width: 1)
        #expect(
            !patched.contains("\u{1B}[0m\u{1B}[48;5;16m\u{1B}[48;5;16m"),
            "\(patched.debugDescription)")
    }

    @Test("A line with no background of its own gains none")
    func patchAddsNothingOnADefaultBackground() {
        // The terminal's own background is a legitimate answer — a bare
        // `renderOnce` tree paints no surface at all — and the patch must not
        // invent one, or every unstyled app would grow a black box.
        let plain = "\u{1B}[38;5;46m□\u{1B}[0m rest"
        let patched = FrameBuffer.patchingAnimatedCells(
            in: plain, with: "\u{1B}[38;5;77m□\u{1B}[0m", atColumn: 0, width: 1)
        #expect(!patched.contains("\u{1B}[4"), "\(patched.debugDescription)")
    }
}

@Suite("SGR state at a column")
struct ANSIStateAtColumnTests {

    @Test("Column 0 sees the escapes that open the line")
    func columnZeroSeesLeadingEscapes() {
        // `ansiStateBefore` answers "what to restore where a suffix BEGINS", so
        // escapes sitting at that boundary are excluded — they travel with the
        // suffix. At column 0 that makes its answer unconditionally empty,
        // which is right for its own caller and useless for a cell being
        // redrawn in place. Hence the second, inclusive query.
        let line = "\u{1B}[48;5;16m\u{1B}[38;5;46mX\u{1B}[0m rest"
        #expect(line.ansiStateBefore(visibleColumn: 0).isEmpty)
        #expect(line.ansiSGRStateAt(visibleColumn: 0).renderedBackground == "\u{1B}[48;5;16m")
    }

    @Test("An escape after the cell does not reach it")
    func laterEscapesAreExcluded() {
        // The cell at column 0 is drawn before the second background is set, so
        // it must report the first.
        let line = "\u{1B}[48;5;16mX\u{1B}[48;5;40mY"
        #expect(line.ansiSGRStateAt(visibleColumn: 0).renderedBackground == "\u{1B}[48;5;16m")
        #expect(line.ansiSGRStateAt(visibleColumn: 1).renderedBackground == "\u{1B}[48;5;40m")
    }

    @Test("A wide glyph is one cell boundary, not two")
    func wideGlyphsAdvanceByTheirWidth() {
        // 🥳 occupies two columns, so the escape after it applies from column 2.
        let line = "\u{1B}[48;5;16m🥳\u{1B}[48;5;40mZ"
        #expect(line.ansiSGRStateAt(visibleColumn: 0).renderedBackground == "\u{1B}[48;5;16m")
        #expect(line.ansiSGRStateAt(visibleColumn: 1).renderedBackground == "\u{1B}[48;5;16m")
        #expect(line.ansiSGRStateAt(visibleColumn: 2).renderedBackground == "\u{1B}[48;5;40m")
    }
}

// MARK: - Sleeping through the ticks that change nothing

@Suite("Animation wake scheduling")
struct AnimationTickStrideTests {

    /// The clock's own interval, which is what a run gets when it names none.
    private let tick = AnimationClock.cursor.tickInterval

    private func expect(_ actual: Double, _ expected: Double, _ label: String) {
        #expect(abs(actual - expected) < 1e-9, "\(label): \(actual) vs \(expected)")
    }

    @Test("A run says how long until it looks different")
    func runReportsItsNextChange() {
        // A blink: two frames, each held for half the cycle. From the start of a
        // frame there are three frames to wait, from the last, one.
        let blink = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1,
            frames: ["a", "a", "a", "b", "b", "b"], clock: .cursor)
        expect(blink.timeUntilChange(afterElapsed: 0), 3 * tick, "at 0")
        expect(blink.timeUntilChange(afterElapsed: tick), 2 * tick, "one frame in")
        expect(blink.timeUntilChange(afterElapsed: 2 * tick), tick, "two frames in")
        expect(blink.timeUntilChange(afterElapsed: 3 * tick), 3 * tick, "the switch")
        // And PART way through a frame it is the remainder, not a whole frame:
        // the answer is a time, so it need not land on any grid.
        expect(blink.timeUntilChange(afterElapsed: 2.5 * tick), 0.5 * tick, "mid-frame")
    }

    @Test("Every frame counts when every frame differs")
    func smoothRunsNeverSkip() {
        // Truecolor: the ramp moves on every frame, so nothing may be skipped.
        let smooth = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1, frames: ["a", "b", "c", "d"], clock: .cursor)
        for step in 0..<8 {
            expect(smooth.timeUntilChange(afterElapsed: Double(step) * tick), tick, "step \(step)")
        }
    }

    /// The point of the whole redesign: a run's rate is ITS OWN, and a screen
    /// holding several of them wakes on each one's schedule rather than on a
    /// grid coarse enough for all of them or fine enough to serve none well.
    @Test("A run keeps its own rate, whatever else is on screen")
    func runsKeepTheirOwnRate() {
        let fast = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1, frames: ["a", "b"],
            frameDuration: 1.0 / 30, clock: .cursor)
        let slow = AnimatedCellRun(
            offsetX: 0, offsetY: 1, width: 1, frames: ["x", "y"],
            frameDuration: 0.11, clock: .cursor)
        expect(fast.timeUntilChange(afterElapsed: 0), 1.0 / 30, "fast")
        expect(slow.timeUntilChange(afterElapsed: 0), 0.11, "slow")
        // Together, the loop takes the soonest — so the fast one is not slowed
        // and the slow one is not woken for frames it does not have.
        let soonest = [fast, slow].map { $0.timeUntilChange(afterElapsed: 0) }.min()!
        expect(soonest, 1.0 / 30, "soonest")
        // A third of a second in, the fast run has moved ten times and the slow
        // one three; neither has been resampled onto the other.
        #expect(fast.index(atElapsed: 1.0 / 3) == 10 % 2)
        #expect(slow.index(atElapsed: 1.0 / 3) == 3 % 2)
    }

    @Test("A frame duration finer than the floor is clamped, not honoured")
    func absurdRatesAreFloored() {
        // A producer naming a two-millisecond frame would spin a core to animate
        // cells no terminal repaints that fast.
        let silly = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1, frames: ["a", "b"],
            frameDuration: 0.002, clock: .cursor)
        #expect(silly.frameDuration == AnimationClock.minimumFrameDuration)
    }

    @Test("A run that names no rate gets the clock's own")
    func defaultRateIsTheClock() {
        let plain = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1, frames: ["a", "b"], clock: .cursor)
        #expect(plain.frameDuration == AnimationClock.cursor.tickInterval)
    }

    @Test("Frames that are all the same picture are not an animation")
    func identicalFramesAreStill() {
        // Real, not theoretical: on a 256-colour terminal a pulse walks the
        // shades the cube can paint, and on a dim palette in a narrow hue that
        // can come to one shade. Such a run would hold the clock open forever
        // to repaint a picture that cannot change.
        let still = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1, frames: ["●", "●", "●"], clock: .cursor)
        #expect(!still.isAnimating)
        let moving = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1, frames: ["●", "●", "○"], clock: .cursor)
        #expect(moving.isAnimating)
    }

    @Test("A run that never changes may be waited out entirely")
    func stillRunsWaitACycle() {
        // Not an animation at all (`isAnimating` filters these out before the
        // loop sees them) — the answer must still be finite.
        let still = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1, frames: ["a", "a"], clock: .cursor)
        expect(still.timeUntilChange(afterElapsed: 0), still.cycleDuration, "a still run")
    }
}
