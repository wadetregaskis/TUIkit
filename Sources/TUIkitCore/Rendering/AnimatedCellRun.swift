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
/// (`CursorTimer`), selected per element by `.selectionIndicatorStyle(_:)` rather
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
    /// RENDERS is re-rendered, in ticks of 1/60 s: 3 ticks, 50 ms.
    ///
    /// This is not the rate anything replayed moves at. A pre-rendered cycle
    /// carries its own ``AnimatedCellRun/frameTicks`` and the loop wakes on
    /// whatever mix of those is on screen — see
    /// ``AnimatedCellRun/timeUntilChange(afterElapsed:)``. This interval binds
    /// only the paths that cannot say in advance what they would draw next: a
    /// text cursor whose view reads `blinkVisible`, a border whose view reads
    /// `pulsePhase`. For those, "how often" is a policy, and 20 Hz is it.
    ///
    /// It is also the default frame duration for a run that does not name one,
    /// which is what every producer written before runs carried their own
    /// timing already assumed.
    ///
    /// One count for both clocks, and a count of ticks rather than seconds: a frame
    /// is a whole number of the display's 1/60 s ticks, and this frame is three of
    /// them, not one. In seconds it is `seconds(forTicks: standardFrameTicks)`, which
    /// is bit for bit `0.05`.
    public static let standardFrameTicks = 3

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
    /// `AnimatedCellRun`'s frame index, its time-to-change and `CursorTimer`'s step
    /// count all ask this, so what the render draws and what a replay splices cannot
    /// disagree about which step an instant is in.
    public static func nanoseconds(_ seconds: Double) -> Int64 {
        Int64((seconds * 1_000_000_000).rounded())
    }

    /// Whole steps of `frameTicks` ticks in `elapsed`: the tick `elapsed` is in, counted
    /// at nanosecond resolution (see ``nanoseconds(_:)`` and
    /// ``tick(atNanoseconds:)``), divided by `frameTicks`. A `frameTicks` below 1 is
    /// taken as 1.
    ///
    /// So step `s` begins exactly when tick `s·frameTicks` begins, and every run's
    /// steps begin on the one lattice of tick instants. A step used to last its frame's
    /// length rounded to whole nanoseconds, because a sixtieth of a second is not one:
    /// 2 ticks were 33,333,333 ns and 7 ticks 116,666,667. Each rounded step moved its
    /// boundaries up to a third of a nanosecond further off their ticks, so runs whose
    /// multiples meet on a tick changed nanoseconds apart there, and the timer woke for
    /// each. Counting ticks by index has nothing to drift.
    ///
    /// Elapsed is a `Double` of seconds, and the round trip from whole nanoseconds
    /// through it is exact below 2^51 ns, about 26 days. Past that, a wake landing
    /// exactly on a tick's instant can read the tick before, and draw its change one
    /// tick late; a render and a replay index the same `Double`, so they still agree.
    ///
    /// `Int64` rather than `Int`, which is 32 bits on wasm32: a step count is bounded by
    /// elapsed time, not by anything this can clamp, and a narrowing conversion that
    /// traps there has shipped in this codebase before. Floor division, so a negative
    /// elapsed steps backwards rather than towards zero.
    public static func step(atElapsed elapsed: Double, frameTicks: Int) -> Int64 {
        let period = Int64(max(1, frameTicks))
        let tick = tick(atNanoseconds: nanoseconds(elapsed))
        let quotient = tick / period
        return tick % period < 0 ? quotient - 1 : quotient
    }

    /// When the step showing at `elapsed` ends, in whole nanoseconds on the same
    /// clock as `elapsed`: the instant the next tick whose index is a multiple of
    /// `frameTicks` begins. A `frameTicks` below 1 is taken as 1.
    ///
    /// Counted from the same tick index ``step(atElapsed:frameTicks:)`` divides, so the
    /// end is the end of the step actually showing, and never the end of the one before;
    /// and it is strictly after `elapsed`, by the inverse pair of
    /// ``nanoseconds(atTick:)`` and ``tick(atNanoseconds:)``. See
    /// `AnimatedCellRun.timeUntilChange(afterElapsed:)` for why a seconds-based answer
    /// spun the run loop.
    package static func stepEndNanos(atElapsed elapsed: Double, frameTicks: Int) -> Int64 {
        nanoseconds(ofNextTickMultiple: frameTicks, after: nanoseconds(elapsed))
    }
}

// MARK: - The 1/60 s tick

/// The tick every animation frame is meant to be a whole number of: 1/60 s.
///
/// A terminal's paint ends up on a display that refreshes 60 (or 120) times a
/// second, so a frame that lasts anything other than a whole number of sixtieths
/// is held for a different number of refreshes from one frame to the next, and
/// two animations on different ticks change on different refreshes.
///
/// A sixtieth of a second is not a whole number of nanoseconds, so a tick is
/// named by its INDEX, counted in integers, and its instant is computed from the
/// index every time, never accumulated. Tick `k` begins at ⌈k·10⁹/60⌉ ns, and the
/// instant `t` is in tick ⌊t·60/10⁹⌋. Instants round up and indexes round down
/// because that is the only choice that makes the two an exact inverse pair:
/// `nanoseconds(atTick: k) <= t` exactly when `k <= tick(atNanoseconds: t)`. So a
/// wake landing exactly on a tick's instant reads as that tick. Rounding the
/// instant down would read the tick before at two ticks in three, and rounding it
/// to the nearest at one in three: a frame drawn a tick late.
extension AnimationClock {
    /// How many ticks make a second.
    public static let ticksPerSecond = 60

    /// Nanoseconds in three ticks, the smallest whole number of ticks that is a
    /// whole number of nanoseconds. Both conversions go through it, so neither
    /// multiplies an instant by 60 and neither can overflow doing so.
    private static let nanosecondsPerThreeTicks: Int64 = 50_000_000

    /// The tick the instant `nanoseconds` falls in: ⌊nanoseconds·60/10⁹⌋.
    ///
    /// Defined for every `Int64`, including `.min` and `.max`. Floored, so an
    /// instant before zero is in a tick before zero.
    public static func tick(atNanoseconds nanoseconds: Int64) -> Int64 {
        // t = q·50,000,000 + r with 0 <= r < 50,000,000, so ⌊t·3/50,000,000⌋ is
        // 3q + ⌊3r/50,000,000⌋, and neither term overflows.
        var quotient = nanoseconds / nanosecondsPerThreeTicks
        var remainder = nanoseconds % nanosecondsPerThreeTicks
        if remainder < 0 {
            quotient -= 1
            remainder += nanosecondsPerThreeTicks
        }
        return 3 * quotient + 3 * remainder / nanosecondsPerThreeTicks
    }

    /// The instant tick `tick` begins: ⌈tick·10⁹/60⌉ nanoseconds.
    ///
    /// Consecutive instants are 16,666,666 or 16,666,667 ns apart. See the
    /// discussion above for why the instant rounds up.
    ///
    /// Saturating: past ±553,402,322,211 ticks, about 292 years, the instant is not
    /// an `Int64`, and the answer is `Int64.max` or `Int64.min`. An instant that far
    /// out is never reached, and a wake planned for it is a wake that never comes,
    /// which a saturated value still says. Trapping would take the process down for
    /// the arithmetic of an animation.
    public static func nanoseconds(atTick tick: Int64) -> Int64 {
        // k = 3a + b with 0 <= b < 3: ⌈k·50,000,000/3⌉ is a·50,000,000 + ⌈b·50,000,000/3⌉.
        var threes = tick / 3
        var extra = tick % 3
        if extra < 0 {
            threes -= 1
            extra += 3
        }
        let whole = threes.multipliedReportingOverflow(by: nanosecondsPerThreeTicks)
        let partial = (extra * nanosecondsPerThreeTicks + 2) / 3
        let sum = whole.partialValue.addingReportingOverflow(partial)
        guard !whole.overflow, !sum.overflow else { return tick < 0 ? .min : .max }
        return sum.partialValue
    }

    /// The whole number of ticks nearest to `seconds`, for a frame that lasts about
    /// that long: at least 1 and at most `Int32.max`.
    ///
    /// Halves round away from zero, so 0.125 s (7.5 ticks) is 8. A duration that is
    /// not finite, or not greater than zero, is 1 tick: the shortest frame there is.
    public static func frameTicks(forSeconds seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 1 }
        let ticks = (seconds * Double(ticksPerSecond)).rounded()
        // Compared as a Double, which holds Int32.max exactly: converting first
        // would trap for a duration longer than an `Int` of ticks.
        guard ticks < Double(Int32.max) else { return Int(Int32.max) }
        return max(1, Int(ticks))
    }

    /// `ticks` ticks in seconds: `ticks / 60`.
    ///
    /// A correctly rounded division, so a count that is a decimal number of seconds
    /// comes back as that decimal's own `Double`: 3 ticks is bit for bit `0.05`, and
    /// 21 ticks is `0.35`.
    public static func seconds(forTicks ticks: Int) -> Double {
        Double(ticks) / Double(ticksPerSecond)
    }

    /// The first instant strictly after `nanoseconds` that begins a tick whose index
    /// is a whole multiple of `multiple`.
    ///
    /// A lattice of every `multiple`-th tick from tick zero, which is where grids of
    /// that period fire. Every such lattice shares tick zero, so two lattices meet
    /// wherever their multiples do. Strictly after, so an instant already on the
    /// lattice asks for the next one. A `multiple` below 1 is taken as 1, and an
    /// instant whose next lattice tick is past `Int64` saturates to `Int64.max`, as
    /// ``nanoseconds(atTick:)`` does.
    public static func nanoseconds(ofNextTickMultiple multiple: Int, after nanoseconds: Int64) -> Int64 {
        let period = Int64(max(1, multiple))
        let current = tick(atNanoseconds: nanoseconds)
        // Floored, so the next multiple of a tick before zero is still after it.
        var multiples = current / period
        if current % period < 0 { multiples -= 1 }
        let start = multiples.multipliedReportingOverflow(by: period)
        let next = start.partialValue.addingReportingOverflow(period)
        guard !start.overflow, !next.overflow else { return .max }
        return Self.nanoseconds(atTick: next.partialValue)
    }

    /// When a held repeat of `period` ticks is next due, after a step it took at
    /// `nanoseconds`: the instant tick p·⌈(k + p)/p⌉ begins, where k is the step's
    /// tick and p the period. That is the first multiple of the period at least a
    /// whole period past the step's tick, and less than two periods past it.
    ///
    /// A held repeat (a drag at a scrollable's edge, a pressed scrollbar arrow) is
    /// drawn by renders the run loop makes on a lattice of the same period, and a
    /// render is a little late. Counted from the step's own tick, the next step
    /// falls on the lattice instant after the one that took this step, however
    /// late in its tick that render was, so the steps come a steady period apart.
    /// And a step taken between the lattice's instants — at a render a mouse move
    /// caused — waits a whole period, where ``nanoseconds(ofNextTickMultiple:after:)``
    /// from the step would be due as soon as one tick later, a step twice in a
    /// period. Adding the interval to the step's instant instead drifts off the
    /// lattice, so a render that lands a hair early for it waits a whole firing.
    ///
    /// A `period` below 1 is taken as 1, and an instant past `Int64` saturates to
    /// `Int64.max`, as ``nanoseconds(atTick:)`` does.
    package static func nanoseconds(ofRepeatTicks period: Int, afterStepAt nanoseconds: Int64) -> Int64 {
        let ticks = Int64(max(1, period))
        let current = tick(atNanoseconds: nanoseconds)
        // ⌈k/p⌉ + 1 periods. Truncating division already rounds a negative
        // quotient up, so only a positive remainder needs the extra period.
        var periods = current / ticks
        if current % ticks > 0 { periods += 1 }
        let next = periods.addingReportingOverflow(1)
        let tickIndex = next.partialValue.multipliedReportingOverflow(by: ticks)
        guard !next.overflow, !tickIndex.overflow else { return .max }
        return Self.nanoseconds(atTick: tickIndex.partialValue)
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
///
/// ## What is under a run's cells
///
/// A frame that states no background for a cell is drawn, on every replayed
/// tick, over the field the views around the run painted beneath that cell. The
/// framework records that field on the run as it paints it: `.background(_:)`,
/// flat or ramped; compositing (a `ZStack`, an `.overlay`, a layer made opaque); a
/// `List` row's fill; a menu row's bar. A pass that repaints the fields of
/// something already drawn repaints the record too, as it repaints the frames:
/// the wash that `.dimmed()` and a modal's backdrop flatten everything to, and
/// a colour effect (`.colorInvert()`, `.grayscale(_:)`, `.hueRotation(_:)`,
/// `.brightness(_:)`, `.contrast(_:)`, `.saturation(_:)`, `.colorMultiply(_:)`),
/// and the fade of a `.transition(.opacity)`. A frame that states the terminal's
/// own field for a cell (SGR 49, which `Color.default` as a background is spelled
/// as) is replayed as each of those containers drew it: a `.background` lets it
/// through, and compositing fills it. Inside an `.opacity(_:)`, whose blend of a
/// run's frames reads the same records, both kinds of cell are blended from the
/// field each was drawn over.
///
/// A `Renderable` of your own has no way to record a field. If it paints one
/// beneath a run's cells and the run's frames leave those cells bare, the
/// render shows your field, but every replayed tick shows whatever the
/// containers around your view painted there instead. Put the field in the
/// run's frames, or leave the painting to a `.background(_:)` and declare the
/// run inside it (with `View.animatedCells(_:)` from a composed view), so the
/// fill is painted after the run exists and records itself on it.
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

    /// How many ticks of 1/60 s each frame is shown for: at least 1.
    ///
    /// The run's own rate, NOT a multiple of some coarser grid the loop imposes.
    /// The loop wakes on whatever mix of rates is on screen, so a 7-tick spinner
    /// and a 2-tick progress bar each keep their own cadence and neither is
    /// resampled onto the other's. A grid coarser than the tick forces a choice
    /// between a visible limp (frames of 2, 2, 3, 2, 2, 3 grid steps) and a changed
    /// speed, and it caps every animation at the grid's rate.
    ///
    /// A count of ticks, not a length in seconds, because the tick is the grid a
    /// frame is shown on anyway: a terminal's paint ends up on a display that
    /// refreshes 60 times a second. A frame that lasts anything else is held for a
    /// different number of refreshes from one frame to the next, the same limp, and
    /// runs whose frames are not whole ticks change on different refreshes and wake
    /// the loop apart. A length in seconds let a run ask for such a frame; a count
    /// of ticks cannot. A duration an app chooses in seconds becomes one through
    /// ``AnimationClock/frameTicks(forSeconds:)``.
    ///
    /// At least 1, so no run asks the loop to wake more often than the display can
    /// show a change: a count below 1 is taken as 1. Defaults to
    /// ``AnimationClock/standardFrameTicks``, 50 ms, which is what every producer
    /// written before runs carried their own rate assumed.
    public let frameTicks: Int

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

    /// What the containers around this run painted beneath its cells: a styled row
    /// exactly as wide as the run, spaces on each cell's field, painted by every
    /// painter the run has passed through exactly as it painted the lines, and
    /// rewritten by every pass that rewrote those lines' fields afterwards exactly
    /// as it rewrote them (the flatten behind a modal and under `.dimmed()`, a
    /// colour effect, a transition's fade) — or
    /// `nil` while none has, which is a run on whatever the row is built on.
    ///
    /// A frame that states no background for a cell is drawn over the field under
    /// that cell, and the replay has to know what that was. The row the render drew
    /// cannot say: where the drawn frame gave a cell a field of its own, the row
    /// shows that field and not the one beneath it. See `AnimatedCellRun+Ground.swift`.
    package var ground: String?

    /// The same record for a cell whose frame STATES the terminal's own field
    /// (`ESC[49m`) rather than stating none: painted by the same painters, from a
    /// row that states `ESC[49m` before its first cell — or `nil` while none has,
    /// which is the terminal's own under every such cell.
    ///
    /// A second record because the painters disagree about a stated 49, and the
    /// render is whatever each did. One that restates its field only after a
    /// reset — a `.background`, flat or ramp, a `List` row, a menu row's bar, the
    /// page — lets it through; compositing reads it as no field and fills it.
    /// Painted by each of them as the row was, this records the answer each gave.
    /// See `AnimatedCellRun+Ground.swift`.
    package var groundUnderStatedDefault: String?

    /// Creates a run.
    ///
    /// - Parameters:
    ///   - offsetX: Column of the first cell, relative to the carrying buffer.
    ///   - offsetY: Row, relative to the carrying buffer.
    ///   - width: Visible width in cells; every frame must match it.
    ///   - frames: The cycle, already styled. Fewer than two frames is not an
    ///     animation and is rejected by ``isAnimating``.
    ///   - frameTicks: How many ticks of 1/60 s each frame is shown for. Defaults to
    ///     ``AnimationClock/standardFrameTicks``, and a count below 1 is taken as 1.
    ///   - clock: Which clock advances it.
    ///   - alpha: What the cells owe per frame, for the rare run whose frames disagree
    ///     about alpha. Defaults to `nil`, which is a run that owes nothing beyond
    ///     whatever regions cover it.
    public init(
        offsetX: Int, offsetY: Int, width: Int, frames: [String],
        frameTicks: Int? = nil, clock: AnimationClock,
        alpha: AnimatedRunAlpha? = nil
    ) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.width = width
        self.frames = frames
        self.frameTicks = max(1, frameTicks ?? AnimationClock.standardFrameTicks)
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
        let step = AnimationClock.step(atElapsed: elapsed, frameTicks: frameTicks)
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
    ///   minimum and sleeps exactly that long. It is always to the instant a
    ///   1/60 s tick begins, the one lattice every run's steps begin on, so runs
    ///   whose steps meet wake the loop once, and a slow run costs nothing extra
    ///   for sharing a screen with a fast one.
    public func timeUntilChange(afterElapsed elapsed: Double) -> Double {
        guard frames.count > 1 else { return AnimationClock.seconds(forTicks: frameTicks) }
        let step = AnimationClock.step(atElapsed: elapsed, frameTicks: frameTicks)
        let index = index(atElapsed: elapsed)
        let current = frames[index]
        // The frame now showing, then whole frames after it for as long as they paint the
        // same picture.
        //
        // The (picture, alpha) PAIR, not the picture alone: a frame that paints the
        // same cells in the same bytes but owes a different alpha shows something
        // different once the resolver has spent it, and sleeping through it would
        // freeze exactly the animation ``AnimatedRunAlpha`` exists for.
        let currentSpans = alpha?.spans(atFrame: index)
        var held: Int64 = 1
        for offset in 1..<frames.count {
            let next = (index + offset) % frames.count
            if frames[next] != current { break }
            if let currentSpans, alpha?.spans(atFrame: next) != currentSpans { break }
            held += 1
        }
        // Every frame identical leaves `held` a whole cycle: nothing will ever change,
        // so the caller may wait that long (it will find the same answer again).
        //
        // To the END of the last frame held rather than a `truncatingRemainder`, which is
        // not exact in binary: `0.1 % 0.05` is 0.049999…, so at every exact frame boundary
        // the remainder came out one ulp short of a whole frame and the answer was ~1e-17.
        // That is not a rounding blemish, it is a spinning run loop — a sleep of nothing,
        // at the very moment the loop is most likely to ask.
        //
        // And in TICK INDEXES, the unit `AnimationClock.step` counts in, so the end asked
        // about is the end of the step actually showing. The seconds floor that replaced
        // `truncatingRemainder` had the same flaw one level up: at a boundary reached by
        // summing sleeps it picked the step before, whose end had already passed, and
        // answered ~1e-17 again. The end is a tick's instant computed from its index, not
        // a frame's length added once per frame held, so nothing accumulates; and it is
        // after `elapsed` by the inverse pair of `AnimationClock.nanoseconds(atTick:)`
        // and `tick(atNanoseconds:)`, so the answer is at least a nanosecond: asked at the
        // exact instant a frame ends, it is the whole of the next frame, never zero, and
        // a caller that sleeps for it cannot wake immediately and ask again.
        let endTick = (step + held).multipliedReportingOverflow(by: Int64(frameTicks))
        let end = endTick.overflow ? Int64.max : AnimationClock.nanoseconds(atTick: endTick.partialValue)
        let untilChange = end.subtractingReportingOverflow(AnimationClock.nanoseconds(elapsed))
        return Double(untilChange.overflow ? Int64.max : untilChange.partialValue) / 1_000_000_000
    }

    /// How many ticks of 1/60 s one full cycle lasts: every frame's ``frameTicks``.
    public var cycleTicks: Int64 { Int64(frames.count) * Int64(frameTicks) }

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

    /// A copy showing `frames` instead of its own, with `alpha` as what they owe,
    /// and everything else — where it sits, how wide it is, its rate, its clock and
    /// its ``ground`` — carried over.
    ///
    /// For a pass that restyles a run's frames the way it restyles the lines under
    /// them: a fade blending them, a backdrop flattening them, a link wrapping them.
    /// A copy rather than a run rebuilt field by field, because a rebuild names every
    /// property it keeps and drops every one it does not name — which is how a
    /// spinner inside a `List` once lost its rate (`_ListCore.RowRun`).
    ///
    /// `alpha` has no default. Some passes spend it into the frames and must drop
    /// it; others leave the frames' cells as they were and must keep it; each says
    /// which.
    ///
    /// - Parameters:
    ///   - frames: The restyled cycle, one frame per frame of this one, each as wide
    ///     as this run.
    ///   - alpha: What the restyled frames' cells owe per frame, or `nil`.
    package func replacingFrames(_ frames: [String], alpha: AnimatedRunAlpha?) -> Self {
        var copy = Self(
            offsetX: offsetX, offsetY: offsetY, width: width, frames: frames,
            frameTicks: frameTicks, clock: clock, alpha: alpha)
        copy.ground = ground
        copy.groundUnderStatedDefault = groundUnderStatedDefault
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
        func cut(_ cells: String) -> String {
            cells.ansiAwareSlice(visibleStart: kept.lowerBound, visibleCount: kept.count)
        }
        var piece = Self(
            offsetX: window.lowerBound, offsetY: offsetY, width: window.count,
            frames: frames.map(cut),
            frameTicks: frameTicks, clock: clock,
            // Sliced in the same breath as the frames, and to the same window, so a cut
            // run's spans describe the cells the cut actually kept.
            alpha: alpha?.sliced(toRunColumns: kept))
        // And the ground, by the same cut: it is a row of the run's width like any
        // frame, and the piece's cells sit on exactly the fields those columns had.
        piece.ground = ground.map(cut)
        piece.groundUnderStatedDefault = groundUnderStatedDefault.map(cut)
        return piece
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
