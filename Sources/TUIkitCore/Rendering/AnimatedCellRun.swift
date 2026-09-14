//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatedCellRun.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Animation clocks

/// Which of the run loop's animation clocks advances a run.
///
/// Two — but not the two there used to be. The old pair was a breathing clock
/// for focus indicators and a blink clock for text cursors, and having those
/// two was a bug rather than a feature: they ran at different rates from
/// different formulas, so the same focus pulse breathed at 2 s on a section's
/// border and 0.8 s on the controls inside it, depending only on which route
/// the view happened to take. Both cadences became one clock and one formula
/// (`CursorTimer`), selected per element by ``SelectionIndicatorStyle`` rather
/// than by the plumbing — and commit 7c5514aa (2026-09-01) then split that one
/// clock along a different seam. These two still tick together off the one
/// timer and share the one formula; they differ only in where their zero sits,
/// because moving the focus should restart a text cursor's blink and must not
/// restart a spinner.
public enum AnimationClock: String, Sendable, Equatable, Hashable, CaseIterable {
    /// The FOCUS-relative clock: the text cursor's blink, and the breath a
    /// focused control draws itself with.
    ///
    /// Its zero is the last time the focus moved, so whatever has just taken
    /// the focus is at its brightest immediately — a breath caught at its dim
    /// end leaves a newly focused control looking unfocused for a third of a
    /// second, which is the moment it least can afford to.
    case cursor

    /// The MONOTONIC clock: everything the app is showing that happens to
    /// move — an indeterminate bar's sweep, a spinner, a breathing label.
    ///
    /// Never restarted. These animations have nothing to do with the focus,
    /// and pressing Tab used to jump every one of them back to phase zero,
    /// because there was one clock and the focus reset it.
    case content

    /// How often a view that builds its appearance from the phase AS IT
    /// RENDERS is re-rendered.
    ///
    /// This is not the rate anything replayed moves at. A pre-rendered cycle
    /// carries its own ``AnimatedCellRun/frameDuration`` and the loop wakes on
    /// whatever mix of those is on screen — see
    /// ``AnimatedCellRun/timeUntilChange(afterElapsed:)``. This interval binds
    /// only the paths that cannot say in advance what they would draw next: a
    /// text cursor whose view reads `blinkVisible`, a border whose view reads
    /// `pulsePhase`. For those, "how often" is a policy, and 20 Hz is it.
    ///
    /// It is also the default frame duration for a run that does not name one,
    /// which is what every producer written before runs carried their own
    /// timing already assumed.
    public var tickInterval: Double {
        switch self {
        case .cursor, .content: 0.05
        }
    }

    /// The tick animation frame durations are meant to be whole multiples of:
    /// 25 ms.
    ///
    /// A run's steps are whole multiples of its frame duration from its clock's
    /// zero, and the ``cursor`` clock's zero is floored to a whole 50 ms of the
    /// ``content`` clock's. So two durations that are both whole multiples of this
    /// tick step together wherever their multiples meet, on either clock, and the
    /// run loop wakes once for both. Two that are not (110 ms and 120 ms, say)
    /// step apart almost everywhere and each costs a wake of its own.
    ///
    /// A recommendation, not a grid anything is rounded to: a run keeps the frame
    /// duration it names, whatever it is. Not every built-in indicator's standard
    /// duration is a whole number of these ticks yet.
    public static let baseTick: Double = 0.025

    /// The shortest gap the loop will wake on, whatever a run asks for.
    ///
    /// A safety floor rather than a policy: a producer naming a two-millisecond
    /// frame would otherwise spin a core to animate cells no terminal can
    /// repaint that fast.
    public static let minimumFrameDuration: Double = 0.01

    /// `seconds` as whole nanoseconds, rounded to the nearest.
    ///
    /// The one conversion every animation step boundary goes through. A clock's
    /// elapsed time is a binary double, and a double is not the decimal it spells. The
    /// clock used to be a SUM of the sleeps it credited: seven 0.05 s sleeps add to one
    /// ulp under 0.35, so a floor taken in seconds selected the step BEFORE the one that
    /// was due — at every step from 6 to 12 of a 50 ms grid, and at the literal
    /// `0.35 / 0.05` too. A flip due on that wake did not happen, the time to the next
    /// change came out ~1e-17 s, and a steady blink turned into a skipped half and a
    /// double flip. The clock is measured now, a nanosecond count divided by 1e9, and
    /// those seconds are no more exact than the sum was, so the rounding stays.
    ///
    /// Nanoseconds are far finer than any frame and exact in an `Int64` for centuries,
    /// so rounding there and dividing in integers puts every boundary on its own step.
    /// `AnimatedCellRun`'s frame index, its time-to-change and `CursorTimer`'s tick
    /// count all ask this, so what the render draws and what a replay splices cannot
    /// disagree about which step an instant is in.
    public static func nanoseconds(_ seconds: Double) -> Int64 {
        Int64((seconds * 1_000_000_000).rounded())
    }

    /// Whole `frameDuration` steps in `elapsed`, counted at nanosecond resolution —
    /// see ``nanoseconds(_:)``.
    ///
    /// `Int64` rather than `Int`, which is 32 bits on wasm32: a step count is bounded by
    /// elapsed time, not by anything this can clamp, and a narrowing conversion that
    /// traps there has shipped in this codebase before. Floor division, so a negative
    /// elapsed steps backwards rather than towards zero.
    public static func step(atElapsed elapsed: Double, frameDuration: Double) -> Int64 {
        let duration = nanoseconds(frameDuration)
        guard duration > 0 else { return 0 }
        let time = nanoseconds(elapsed)
        let quotient = time / duration
        return time % duration < 0 ? quotient - 1 : quotient
    }

    /// When the step showing at `elapsed` ends, in whole nanoseconds on the same
    /// clock as `elapsed`: the next whole multiple of `frameDuration`.
    ///
    /// Both sides are counted in nanoseconds, the unit ``step(atElapsed:frameDuration:)``
    /// counts in, so the end is the end of the step actually showing, and never the
    /// end of the one before. See `AnimatedCellRun.timeUntilChange(afterElapsed:)`
    /// for why a seconds-based answer spun the run loop.
    package static func stepEndNanos(atElapsed elapsed: Double, frameDuration: Double) -> Int64 {
        nanoseconds(frameDuration) * (step(atElapsed: elapsed, frameDuration: frameDuration) + 1)
    }
}

// MARK: - AnimatedCellRun

/// A short run of cells that animates on its own, without the view that drew it.
///
/// ## Why this exists
///
/// A focus ring breathing and a text cursor blinking used to cost a **full
/// render of the whole screen** on every tick — measure, layout, render, diff —
/// 10 to 30 times a second, forever, to change two cells. Measured on the
/// Example: the Forms page burned 42% of a core sitting still, and most of those
/// frames came out byte-identical (see
/// `Documentation/Performance-profile-2026-08.md`).
///
/// So a view that wants a few cells to animate says so *once*, when it renders,
/// by leaving a run behind on its ``FrameBuffer``. The run loop replays it on
/// each tick against the frame already on screen. No view is asked anything; no
/// layout happens; nothing is measured.
///
/// ## Why whole frames, not a recipe
///
/// A run carries the animation's cycle **already rendered** — one finished,
/// styled string per step — rather than colours and a rule for blending them.
/// Three reasons:
///
/// 1. The loop does no work per tick beyond an array index. Colour blending,
///    palette resolution, contrast correction and downsampling all happen once,
///    at render time, on the thread that was going to do them anyway.
/// 2. It costs nothing in layering. ``FrameBuffer`` is in `TUIkitCore`, which
///    cannot see `Color` (that is `TUIkitStyling`); strings it can see.
/// 3. It is not limited to colour. Anything a view can draw as a sequence — a
///    spinner's glyphs, a cursor swapping shape, a marching-ants border — is
///    expressible without the loop learning a new rule for each.
///
/// The cost is one extra styled string per step, computed at render time. Runs
/// are a handful of cells and cycles are a handful of steps, so that is bytes.
///
/// ## Anchoring
///
/// `offsetX` / `offsetY` are relative to the top-left of the carrying buffer,
/// exactly like ``HitTestRegion``, and are shifted and dropped by the same
/// compositing rules. A run that is clipped away — scrolled out of a viewport,
/// covered by a modal — goes with the cells it described, because it *is* those
/// cells.
public struct AnimatedCellRun: Sendable, Equatable {
    /// The column of the run's first cell, relative to the carrying buffer.
    public var offsetX: Int

    /// The row the run sits on, relative to the carrying buffer.
    public var offsetY: Int

    /// The run's visible width in terminal cells.
    ///
    /// Every frame must occupy exactly this many cells. A frame that did not
    /// would shift the rest of the row sideways on some ticks and not others —
    /// the reflow this whole mechanism exists to avoid.
    public let width: Int

    /// The cycle, one finished styled string per frame.
    ///
    /// Indexed modulo `count`, so a run may use any number of frames: two is a
    /// blink, twenty is a breath, forty-seven is a gradient sweeping a bar.
    public let frames: [String]

    /// How long each frame is shown.
    ///
    /// The run's own rate, in seconds — NOT a multiple of some grid the loop
    /// imposes. The loop wakes on whatever mix of durations is on screen, so a
    /// 0.11 s spinner and a 1/30 s progress bar each keep their own cadence and
    /// neither is resampled onto the other's.
    ///
    /// That matters more than it sounds. Sampling onto a fixed grid forces a
    /// choice between a visible limp (frames of 2, 2, 3, 2, 2, 3 ticks) and a
    /// changed speed (rounding 0.11 s to 0.10), and it caps every animation at
    /// the grid's rate however fine the producer's own timing was.
    ///
    /// Defaults to ``AnimationClock/tickInterval``, which is what every
    /// producer written before this assumed.
    public let frameDuration: Double

    /// The clock that advances this run.
    public let clock: AnimationClock

    /// What these cells owe the compositor, per frame — `nil` for the overwhelming
    /// majority of runs, whose frames agree about alpha (or are wholly opaque) and
    /// whose producer states an ordinary ``OpacityRegion`` instead.
    ///
    /// See ``AnimatedRunAlpha`` for why the statement rides here rather than beside the
    /// run: frames and their alphas are the same array in the same order, so they
    /// cannot drift apart.
    public var alpha: AnimatedRunAlpha?

    /// Creates a run.
    ///
    /// - Parameters:
    ///   - offsetX: Column of the first cell, relative to the carrying buffer.
    ///   - offsetY: Row, relative to the carrying buffer.
    ///   - width: Visible width in cells; every frame must match it.
    ///   - frames: The cycle, already styled. Fewer than two frames is not an
    ///     animation and is rejected by ``isAnimating``.
    ///   - frameDuration: How long each frame is shown. Defaults to the clock's
    ///     own interval, and is floored at ``AnimationClock/minimumFrameDuration``.
    ///   - clock: Which clock advances it.
    ///   - alpha: What the cells owe per frame, for the rare run whose frames disagree
    ///     about alpha. Defaults to `nil`, which is a run that owes nothing beyond
    ///     whatever regions cover it.
    public init(
        offsetX: Int, offsetY: Int, width: Int, frames: [String],
        frameDuration: Double? = nil, clock: AnimationClock,
        alpha: AnimatedRunAlpha? = nil
    ) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.width = width
        self.frames = frames
        self.frameDuration = max(
            AnimationClock.minimumFrameDuration, frameDuration ?? clock.tickInterval)
        self.clock = clock
        self.alpha = alpha
    }

    /// Whether this run actually animates.
    ///
    /// A one-frame run is a still picture that the ordinary render already drew,
    /// so replaying it would emit bytes for no change. Producers are allowed to
    /// build one anyway (a disabled control, a cursor style with no blink) and
    /// let this filter it out, rather than each having to decide not to.
    ///
    /// Several frames that are all the SAME picture is the same thing, and it
    /// happens for real: on a 256-colour terminal a pulse walks the shades the
    /// cube can show, and on a dim palette in a narrow hue that can be one
    /// shade. Keeping such a run alive holds the animation clock open forever
    /// to repaint a picture that cannot change.
    ///
    /// A run whose frames are identical PICTURES but disagree about alpha is animating
    /// too, and saying otherwise is not a nicety: the clip, punch and clamp paths all
    /// drop a run this calls still, and they run before the resolver blends the alphas
    /// into the frames — so a blinking caret whose two frames differ only in what the
    /// cell owes would be discarded before anything could tell them apart.
    public var isAnimating: Bool {
        guard frames.count > 1 else { return false }
        let first = frames[0]
        if frames.contains(where: { $0 != first }) { return true }
        return alpha?.varies ?? false
    }

    /// Which frame of the cycle is showing `elapsed` seconds into the
    /// animation.
    public func index(atElapsed elapsed: Double) -> Int {
        guard frames.count > 1 else { return 0 }
        let step = AnimationClock.step(atElapsed: elapsed, frameDuration: frameDuration)
        let index = Int(step % Int64(frames.count))
        return index < 0 ? index + frames.count : index
    }

    /// The frame to show `elapsed` seconds into the animation.
    public func frame(atElapsed elapsed: Double) -> String {
        frame(atIndex: index(atElapsed: elapsed))
    }

    /// The frame at position `index` of the cycle, wrapped.
    ///
    /// Separate from ``frame(atElapsed:)`` because the two ask different
    /// questions, and a single `frame(at:)` taking a bare number invited the
    /// wrong one: a caller holding a cycle position and a caller holding a time
    /// both had something to pass, and only one of them was right.
    public func frame(atIndex index: Int) -> String {
        guard !frames.isEmpty else { return "" }
        let wrapped = index % frames.count
        return frames[wrapped < 0 ? wrapped + frames.count : wrapped]
    }

    /// How long until this run shows something DIFFERENT from what it shows at
    /// `elapsed` — never more than one cycle.
    ///
    /// Two savings, and the second is the interesting one:
    ///
    /// - Frames that repeat cost no wake-ups. A pulse quantised to what a
    ///   256-colour terminal can actually paint holds each shade for two or
    ///   three frames, and a blink spends half its cycle on each of two.
    ///   Measured on the built-in palettes at the regular speed, a focus breath
    ///   changes 16 times out of 16 frames in truecolor and **9 out of 16**
    ///   through the cube.
    /// - The answer is in SECONDS, so a caller holding several runs takes the
    ///   minimum and sleeps exactly that long. Nothing is rounded to a shared
    ///   grid, and a slow run costs nothing extra for sharing a screen with a
    ///   fast one.
    public func timeUntilChange(afterElapsed elapsed: Double) -> Double {
        guard frames.count > 1 else { return frameDuration }
        let index = index(atElapsed: elapsed)
        let current = frames[index]
        // Time to the end of the frame now showing, then whole frames after it
        // for as long as they paint the same picture.
        //
        // From the frame's own END rather than `truncatingRemainder`, which is
        // not exact in binary: `0.1 % 0.05` is 0.049999…, so at every exact
        // frame boundary the remainder came out one ulp short of a whole frame
        // and the answer was ~1e-17. That is not a rounding blemish, it is a
        // spinning run loop — a sleep of nothing, at the very moment the loop
        // is most likely to ask.
        //
        // And in whole NANOSECONDS, the unit `AnimationClock.step` counts in, so the end
        // asked about is the end of the step actually showing. The seconds floor that
        // replaced `truncatingRemainder` had the same flaw one level up: at a boundary
        // reached by summing sleeps it picked the step before, whose end had already
        // passed, and answered ~1e-17 again.
        let untilStepEnds =
            AnimationClock.stepEndNanos(atElapsed: elapsed, frameDuration: frameDuration)
            - AnimationClock.nanoseconds(elapsed)
        var remaining = max(
            Self.shortestUsefulSleep, Double(untilStepEnds) / 1_000_000_000)
        // The (picture, alpha) PAIR, not the picture alone: a frame that paints the
        // same cells in the same bytes but owes a different alpha shows something
        // different once the resolver has spent it, and sleeping through it would
        // freeze exactly the animation ``AnimatedRunAlpha`` exists for.
        let currentSpans = alpha?.spans(atFrame: index)
        for offset in 1..<frames.count {
            let next = (index + offset) % frames.count
            if frames[next] != current { return remaining }
            if let currentSpans, alpha?.spans(atFrame: next) != currentSpans { return remaining }
            remaining += frameDuration
        }
        // Every frame identical: nothing will ever change, so the caller may
        // wait a whole cycle (it will find the same answer again).
        return remaining
    }

    /// How long one full cycle lasts.
    public var cycleDuration: Double { Double(frames.count) * frameDuration }

    /// The floor on ``timeUntilChange(afterElapsed:)``'s answer.
    ///
    /// Guards the one degenerate case: asked at the exact instant a frame ends,
    /// the honest answer is zero, and a caller that sleeps for it wakes
    /// immediately and asks again. A microsecond is far below anything a
    /// terminal can show and far above zero.
    private static let shortestUsefulSleep: Double = 0.000_001

    /// A copy sitting on `row`, whatever row it was built for.
    ///
    /// For a producer that builds its cycle once and reuses it across renders:
    /// the frames do not depend on where the run ends up, but the run does.
    public func movedTo(row: Int) -> Self {
        var copy = self
        copy.offsetY = row
        return copy
    }

    /// A copy moved by `(x, y)` — the compositing shift, matching
    /// ``HitTestRegion``'s.
    public func shifted(byX x: Int, y: Int) -> Self {
        var copy = self
        copy.offsetX += x
        copy.offsetY += y
        return copy
    }

    /// The part of this run inside `columns`, or `nil` if that is none of it.
    ///
    /// Every frame is cut to the same window by ``String/ansiAwareSlice(visibleStart:visibleCount:)``,
    /// which carries the styling that was active at the cut and blanks a wide
    /// glyph straddling either edge — so a slice claims exactly the columns it
    /// was asked for and can be spliced like any other frame.
    ///
    /// What this is for is an overlay landing on part of a run: a dialog
    /// centred over a page cuts across the rows either side of it, and a run
    /// dropped whole there takes the visible remainder of the row with it.
    public func clipped(toColumns columns: Range<Int>) -> Self? {
        let window = columns.clamped(to: offsetX..<(offsetX + width))
        guard !window.isEmpty else { return nil }
        guard window != offsetX..<(offsetX + width) else { return self }
        let kept = (window.lowerBound - offsetX)..<(window.upperBound - offsetX)
        return Self(
            offsetX: window.lowerBound, offsetY: offsetY, width: window.count,
            frames: frames.map {
                $0.ansiAwareSlice(
                    visibleStart: window.lowerBound - offsetX, visibleCount: window.count)
            },
            frameDuration: frameDuration, clock: clock,
            // Sliced in the same breath as the frames, and to the same window, so a cut
            // run's spans describe the cells the cut actually kept.
            alpha: alpha?.sliced(toRunColumns: kept))
    }
}

extension AnimatedCellRun {
    /// Whether every cell of this run lies inside a `columns` × `rows` canvas.
    ///
    /// A run even partly outside must not be replayed onto it: patching a
    /// frame past the canvas edge pads the row out to the run's extent, and a
    /// row wider than the terminal wraps and smears the row below — which the
    /// diff writer, believing that row untouched, never repairs. `clamped`
    /// applies this at every interior clip; the render loop applies it to the
    /// screen itself, whose content (a wide unwrapped row, say) can exceed
    /// the terminal without ever having been clamped.
    package func fits(columns: Int, rows: Int) -> Bool {
        offsetY >= 0 && offsetY < rows && offsetX >= 0 && offsetX + width <= columns
    }

    /// The part of this run inside a `columns` × `rows` canvas, or `nil` when
    /// none of it is — the CUT where ``fits(columns:rows:)`` is the yes/no.
    ///
    /// Rows are all-or-nothing (a run is one row); columns are cut with
    /// ``clipped(toColumns:)``, so the piece kept claims exactly the cells the
    /// canvas has and can be replayed without padding a row past the edge. A
    /// cut piece with nothing left animating is dropped, since a still run
    /// only holds the clock open; a run that needed no cut comes back as it
    /// is, animating or not, which is what the whole-run filter kept too.
    package func clipped(toCanvasColumns columns: Int, rows: Int) -> Self? {
        guard offsetY >= 0, offsetY < rows else { return nil }
        let span = offsetX..<(offsetX + width)
        let window = (0..<max(0, columns)).clamped(to: span)
        guard !window.isEmpty else { return nil }
        if window == span { return self }
        guard let cut = clipped(toColumns: window), cut.isAnimating else { return nil }
        return cut
    }
}
