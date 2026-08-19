//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AnimatedCellRun.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Animation clocks

/// Which of the run loop's animation clocks advances a run.
///
/// One, now. There were two — a breathing clock for focus indicators and a
/// blink clock for text cursors — and having two was a bug rather than a
/// feature: they ran at different rates from different formulas, so the same
/// focus pulse breathed at 2 s on a section's border and 0.8 s on the controls
/// inside it, depending only on which route the view happened to take. Both
/// cadences now come from one clock and one formula (`CursorTimer`), selected
/// per element by ``SelectionIndicatorStyle`` rather than by the plumbing.
public enum AnimationClock: String, Sendable, Equatable, Hashable, CaseIterable {
    /// The animation clock: blinks and breaths alike (`CursorTimer`).
    case cursor
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

    /// The cycle, one finished styled string per step.
    ///
    /// Indexed modulo `count`, so a run may use any number of steps regardless
    /// of the clock's own period: two frames on the cursor clock is a blink,
    /// twenty on the pulse clock is a breath.
    public let frames: [String]

    /// The clock that advances this run.
    public let clock: AnimationClock

    /// Creates a run.
    ///
    /// - Parameters:
    ///   - offsetX: Column of the first cell, relative to the carrying buffer.
    ///   - offsetY: Row, relative to the carrying buffer.
    ///   - width: Visible width in cells; every frame must match it.
    ///   - frames: The cycle, already styled. Fewer than two frames is not an
    ///     animation and is rejected by ``isAnimating``.
    ///   - clock: Which clock advances it.
    public init(
        offsetX: Int, offsetY: Int, width: Int, frames: [String], clock: AnimationClock
    ) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.width = width
        self.frames = frames
        self.clock = clock
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
    public var isAnimating: Bool {
        guard frames.count > 1 else { return false }
        let first = frames[0]
        return frames.contains { $0 != first }
    }

    /// The frame to show at `step` of the driving clock.
    public func frame(at step: Int) -> String {
        guard !frames.isEmpty else { return "" }
        let index = step % frames.count
        return frames[index < 0 ? index + frames.count : index]
    }

    /// How many ticks until this run shows something different from what it
    /// shows at `step` — at least 1, and never more than the cycle's length.
    ///
    /// The point is the ticks in between: a pulse quantised to what a
    /// 256-colour terminal can actually paint repeats each shade for two or
    /// three ticks, and a blink spends half its cycle on each of two frames.
    /// Waking the run loop for those is pure cost — it cannot change a single
    /// cell. Measured on the built-in palettes at the regular speed, a focus
    /// breath changes 16 times out of 16 ticks in truecolor and **9 out of 16**
    /// through the cube.
    public func ticksUntilChange(after step: Int) -> Int {
        guard frames.count > 1 else { return frames.count }
        let current = frame(at: step)
        for delta in 1..<frames.count where frame(at: step + delta) != current {
            return delta
        }
        // Every frame identical: nothing will ever change, so the caller may
        // wait a whole cycle (it will find the same answer again).
        return frames.count
    }

    /// A copy moved by `(x, y)` — the compositing shift, matching
    /// ``HitTestRegion``'s.
    public func shifted(byX x: Int, y: Int) -> Self {
        var copy = self
        copy.offsetX += x
        copy.offsetY += y
        return copy
    }
}
