//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderLoop+Replay.swift
//
//  Advancing the animated cells of the frame already on screen, without
//  rendering anything — the half of the run loop that exists so a breathing
//  focus ring, a blinking cursor, a spinner or a sweeping progress bar does not
//  cost a walk of the view tree. Split from `RenderLoop.swift`, which had
//  reached the file-length limit, and split HERE because this is the one part
//  of the loop that never renders.
//
//  Created by Wade Tregaskis
//  License: MIT
// MARK: - Which clocks a replay can serve

/// The replay's half of ``RenderActivity``: whether the frame on screen can be
/// patched forward for a clock that ticked, or only a render can serve it. Kept
/// beside the replay it gates rather than beside the struct's properties, which
/// also keeps `RenderLoop.swift` inside its file-length limit.
extension RenderActivity {
    /// The clocks among ``animatedClocks`` that the CHROME — the app header, the
    /// status bar — left runs for.
    ///
    /// Those keep the clock live but can never be replayed: the replay patches the
    /// content's lines at the content's start row, and the chrome is written by its
    /// own passes at its own rows, so only a render advances a run up there. With
    /// nothing to tell the two halves apart, a `Spinner` in the header froze the
    /// moment the page ALSO left a run — any run, on any clock: a second spinner, a
    /// focused control's breath, a caret — because the tick was replayed on the
    /// strength of the page's run alone, reported served, and so never rendered.
    var chromeClocks: Set<AnimationClock> { Set(chromeRuns.lazy.map(\.clock)) }

    /// Whether `clock` can be advanced without walking the view tree.
    func canReplay(_ clock: AnimationClock) -> Bool {
        animatedClocks.contains(clock) && !chromeClocks.contains(clock) && !usesPulse && !usesCursor
    }

    /// Which of the clocks that just ticked can be advanced by replaying the
    /// frame on screen. Empty means the tick has to be served by a render.
    ///
    /// A ticked clock this frame left no runs for is NOT a reason to render:
    /// nothing on screen moves with it, so advancing it owes no frame at all.
    /// That distinction is the whole point of asking per clock, because the
    /// timer posts EVERY clock on every wake (see `CursorTimer.start`) — so
    /// demanding that all of them be replayable meant a page whose only
    /// animation was the caret (`animatedClocks == [.cursor]`) failed the test
    /// on `.content` and walked the entire view tree twenty times a second to
    /// blink one cell.
    ///
    /// A view that read a phase WHILE rendering is the other case, and it is
    /// unchanged: `canReplay` refuses every clock while `usesPulse` or
    /// `usesCursor` is set, so this comes back empty and the caller renders.
    ///
    /// So is a ticked clock the chrome animates on — and that one empties the
    /// whole answer, not just its own entry. The chrome is advanced only by a
    /// render, and a render serves every clock, so replaying the page's clocks
    /// first would patch a frame about to be redrawn; worse, it would report the
    /// tick served, which is exactly how the header's half went undrawn. See
    /// ``chromeClocks``.
    func replayableClocks(among ticked: some Sequence<AnimationClock>) -> Set<AnimationClock> {
        let clocks = Set(ticked)
        guard clocks.isDisjoint(with: chromeClocks) else { return [] }
        return clocks.filter(canReplay)
    }
}

/// The last frame written, kept so an animation tick can be served by patching
/// it instead of by rendering again. See ``AnimatedCellRun``.
@MainActor
struct ReplayableFrame {
    var contentLines: [String]
    var runs: [AnimatedCellRun]
    var terminalWidth: Int
    var startRow: Int
    var backgroundCode: String

    /// The step each clock was last *written* at, so a tick that lands on the
    /// same picture can be skipped.
    ///
    /// The comparison has to be frame-to-frame, not line-to-line: compositing
    /// leaves the replaced run's colour code behind as an empty escape, so a
    /// patched line always differs in bytes from the line it was patched from,
    /// even when it looks identical. Diffing the lines therefore reports a
    /// change on every tick — a blinking caret would emit twenty times a second
    /// to change picture twice.
    var lastSteps: [AnimationClock: Double] = [:]

    /// The last patched line for each row, and the run frame indexes that
    /// produced it.
    ///
    /// A patched line is a pure function of the pristine line and the frame
    /// index of every run sitting on it, so when none of those indexes has
    /// moved the answer is the one already computed. Without this, every wake
    /// re-splices EVERY run — because the patch is always applied to the
    /// pristine render lines (see the note above about accumulating dead
    /// escapes), so a run left unspliced would revert to the frame it rendered
    /// at rather than hold the frame it is showing.
    ///
    /// That is only a rounding error when every run shares one rate. It stops
    /// being one when they do not: ten spinners at ten different intervals wake
    /// the loop at the union of their frame boundaries — around 110 times a
    /// second rather than 20 — and each of those wakes was re-splicing all ten.
    /// Measured on the Example's Spinners page, that alone was 1.8% of a core
    /// against 4.2%.
    var lastPatched: [Int: (indexes: [Int], line: String)] = [:]
}

extension RenderLoop {
    /// How long the clock may sleep before anything on screen would look
    /// different.
    ///
    /// A frame whose animation is entirely in ``AnimatedCellRun``s knows
    /// exactly: each run carries its whole cycle, already rendered, at its own
    /// frame duration, so the next moment a cell changes is a lookup and the
    /// answer is the soonest of them. Nothing is rounded to a shared grid — a
    /// 0.11 s spinner beside a 1/30 s progress bar wakes the loop at 0.11 s and
    /// at 1/30 s, and at neither more often than it asked.
    ///
    /// A frame where some view built its appearance from the phase *while
    /// rendering* cannot say — only that view knows what it would draw next. Its
    /// phase formulas are defined on the cursor clock's ticks, so it can change
    /// only at a whole tick of that clock, and the plan is the NEXT such boundary.
    /// It used to be one interval from the wake, which put every render a wake's
    /// lateness past its boundary and off the lattice every other 50 ms run on the
    /// page steps on. The page's runs do not join the plan while a reader is
    /// present: every wake then renders, and a render serves them.
    ///
    /// A run in the chrome is advanced only by a render, so its next change joins
    /// the plan whether or not there is a reader. It used to keep the clock's
    /// interval instead, because the chrome's runs were not kept to ask.
    ///
    /// The plan is the soonest of those. With none of them — nothing animating —
    /// it is the clock's interval.
    ///
    /// This is also what makes the quantised pulse cheap on a 256-colour
    /// terminal: the ramp repeats each shade it can actually paint for two or
    /// three frames, and there is no reason to wake for the repeats.
    /// - Parameter elapsed: How far each clock has run. Per clock rather than
    ///   one number, because the clocks no longer share a zero: a run's next
    ///   change is a question about ITS clock, and asking it in the cursor
    ///   clock's time would wake a progress bar on the focus's schedule.
    func timeUntilNextChange(elapsed: (AnimationClock) -> Double) -> Double {
        let reads = lastActivity.usesPulse || lastActivity.usesCursor
        func soonestChange(_ runs: [AnimatedCellRun]) -> Double? {
            var soonest: Double?
            for run in runs {
                let change = run.timeUntilChange(afterElapsed: elapsed(run.clock))
                soonest = min(soonest ?? change, change)
            }
            return soonest
        }
        let readerBoundary = reads ? Self.timeToNextTick(ofCursorClockAt: elapsed(.cursor)) : nil
        let plan = [readerBoundary, soonestChange(lastActivity.chromeRuns), reads ? nil : soonestChange(replayable?.runs ?? [])]
        return plan.compactMap { $0 }.min() ?? AnimationClock.seconds(forTicks: AnimationClock.standardFrameTicks)
    }

    /// Seconds from `elapsed` on ``AnimationClock/cursor`` to the end of the tick
    /// showing there, counted in whole nanoseconds like every step boundary, so the
    /// answer is never a tick late or a nanosecond early.
    private static func timeToNextTick(ofCursorClockAt elapsed: Double) -> Double {
        let tick = AnimationClock.seconds(forTicks: AnimationClock.standardFrameTicks)
        let untilEnd =
            AnimationClock.stepEndNanos(atElapsed: elapsed, frameDuration: tick)
            - AnimationClock.nanoseconds(elapsed)
        return Double(untilEnd) / 1_000_000_000
    }

    /// Advances the animated cells of the frame already on screen, without
    /// rendering anything.
    ///
    /// The saving is the whole view walk: no measure, no layout, no render, no
    /// state or lifecycle bookkeeping. Each run's next frame is spliced into the
    /// line it sits on, and the result goes through the ordinary content diff —
    /// which, seeing only those cells differ, emits only those cells.
    ///
    /// - Parameter elapsed: How far each clock being advanced has moved.
    /// - Returns: `true` if the tick was served. `false` means the caller must
    ///   render: there is no frame to patch yet, or nothing on screen animates
    ///   on those clocks.
    @discardableResult
    func replayAnimations(elapsed: [AnimationClock: Double]) -> Bool {
        guard let frame = replayable, !frame.runs.isEmpty else { return false }
        let due = frame.runs.filter { elapsed[$0.clock] != nil }
        guard !due.isEmpty else { return false }

        // Skip a tick that lands on the picture already showing. A blink spends
        // most of its cycle on the same two frames, and a quantised pulse
        // repeats shades, so most ticks change nothing. See `lastSteps`.
        let unchanged = due.allSatisfy { run in
            guard let last = frame.lastSteps[run.clock], let now = elapsed[run.clock] else {
                return false  // nothing written since the render: assume it moved
            }
            return run.frame(atElapsed: last) == run.frame(atElapsed: now)
        }
        guard !unchanged else { return true }

        // Always patched from the frame the last RENDER produced — never from
        // the last patch. Compositing replaces a cell's glyph but keeps the
        // styling around it, so the colour code of the frame being replaced
        // stays behind as an empty run. Feed a patched line back in and those
        // dead escapes accumulate, one per tick: the row still looks correct
        // and never changes width, but it grew without bound and reached the
        // terminal as ~60 kB/s to animate two cells. Patching the pristine line
        // is also strictly less work, since it never gets longer.
        var lines = frame.contentLines
        var touched = false
        // Grouped by row, because a row's patched line depends on every run
        // sitting on it and the memo below is keyed on all of their indexes.
        var byRow: [Int: [AnimatedCellRun]] = [:]
        for run in due where lines.indices.contains(run.offsetY) {
            byRow[run.offsetY, default: []].append(run)
        }
        for (row, runs) in byRow {
            let indexes = runs.map { run in
                elapsed[run.clock].map { run.index(atElapsed: $0) } ?? 0
            }
            // Nothing on this row has moved since it was last patched, so the
            // line it needs is the one already built.
            if let cached = frame.lastPatched[row], cached.indexes == indexes {
                if cached.line != lines[row] {
                    lines[row] = cached.line
                    touched = true
                }
                continue
            }
            for run in runs {
                guard let now = elapsed[run.clock] else { continue }
                // Through the diff writer rather than by hand: it knows how
                // to drop a styled run into a styled line at a visible column
                // and restore the surrounding state afterwards (getting that
                // wrong is how a background stops halfway across a row), and
                // it knows the host's cursor-advance model, which a frame the
                // view rendered has never met. See `patchingAnimatedRun`.
                let patched = diffWriter.patchingAnimatedRun(
                    in: lines[row], with: run.frame(atElapsed: now),
                    atColumn: run.offsetX, width: run.width, bgCode: frame.backgroundCode)
                if patched != lines[row] {
                    lines[row] = patched
                    touched = true
                }
            }
            replayable?.lastPatched[row] = (indexes, lines[row])
        }
        // Every run landed on the frame it was already showing. Emitting would
        // be a no-op the diff would discard anyway, so skip the write and keep
        // the cached frame as it was.
        guard touched else { return true }

        terminal.beginFrame()
        diffWriter.writeContentDiff(
            newLines: lines,
            terminal: terminal,
            startRow: frame.startRow,
            terminalWidth: frame.terminalWidth,
            bgCode: frame.backgroundCode,
            reset: ANSIRenderer.reset
        )
        terminal.endFrame()
        // `replayable.contentLines` deliberately keeps the RENDER's lines, not
        // these. The diff writer already tracks what is on screen; this is the
        // clean base every future tick patches from. See the note above.
        for (clock, now) in elapsed { replayable?.lastSteps[clock] = now }
        return true
    }
}
