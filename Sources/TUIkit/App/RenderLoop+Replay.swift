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
    /// rendering* cannot say — only that view knows what it would draw next —
    /// so those keep the clock's own interval, which is the one thing that
    /// interval is still for.
    ///
    /// This is also what makes the quantised pulse cheap on a 256-colour
    /// terminal: the ramp repeats each shade it can actually paint for two or
    /// three frames, and there is no reason to wake for the repeats.
    func timeUntilNextChange(from elapsed: Double) -> Double {
        let interval = AnimationClock.cursor.tickInterval
        guard !lastActivity.usesPulse, !lastActivity.usesCursor else { return interval }
        let runs = replayable?.runs ?? []
        guard !runs.isEmpty else { return interval }
        return runs.map { $0.timeUntilChange(afterElapsed: elapsed) }.min() ?? interval
    }

    /// Advances the animated cells of the frame already on screen, without
    /// rendering anything.
    ///
    /// The saving is the whole view walk: no measure, no layout, no render, no
    /// state or lifecycle bookkeeping. Each run's next frame is spliced into the
    /// line it sits on, and the result goes through the ordinary content diff —
    /// which, seeing only those cells differ, emits only those cells.
    ///
    /// - Parameter steps: The current step of each clock being advanced.
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
                    atColumn: run.offsetX, width: run.width,
                    terminalWidth: frame.terminalWidth, bgCode: frame.backgroundCode)
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
