//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SelectionIndicator.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

import TUIkitStyling

// MARK: - Style

private struct SelectionIndicatorStyleKey: EnvironmentKey {
    static let defaultValue: TextCursorStyle.Animation = .pulse
}

extension EnvironmentValues {
    /// How focused selection indicators animate within this view: `.none`,
    /// `.blink` or `.pulse` (the default).
    ///
    /// Set it with ``View/selectionIndicatorStyle(_:)``.
    public var selectionIndicatorStyle: TextCursorStyle.Animation {
        get { self[SelectionIndicatorStyleKey.self] }
        set { self[SelectionIndicatorStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets how a focused selection indicator animates to show it holds the
    /// keyboard focus. That covers the swatch-grid cursor, a focused button's
    /// caps, and any view that draws through
    /// ``EnvironmentValues/selectionEmphasis``.
    ///
    /// The cases are the text cursor's own, so the two read the same, but this
    /// is set apart from the cursor's and defaults to
    /// ``TextCursorStyle/Animation/pulse``: a focused selection breathes. Under
    /// ``TextCursorStyle/Animation/none`` nothing animates, and focus is shown by
    /// colour and bold alone.
    ///
    /// How fast it animates is set separately, with
    /// ``View/indicatorAnimationSpeed(_:for:)`` for
    /// ``IndicatorAnimations/focusEmphasis``: a 700 ms blink and an 800 ms breath
    /// at the standard rate, each divided by the rate.
    ///
    /// TUI-specific: SwiftUI has no equivalent.
    ///
    /// - Parameter animation: `.none`, `.blink` or `.pulse`.
    public func selectionIndicatorStyle(_ animation: TextCursorStyle.Animation) -> some View {
        environment(\.selectionIndicatorStyle, animation)
    }
}

// MARK: - Resolver

/// Resolves the per-frame colour of a focused selection indicator, honouring the
/// animation set by ``View/selectionIndicatorStyle(_:)`` (none / blink / pulse)
/// at the speed set for ``IndicatorAnimations/focusEmphasis``.
///
/// Resolve once per render (the animation phase is shared across cells); then call
/// ``Resolution/color(dim:bright:)`` per element with that element's own dim/bright
/// endpoints (e.g. a swatch's own colour → a contrasting mark).
enum SelectionIndicator {
    typealias Resolution = SelectionEmphasis

    /// Resolves the animation state for this frame. Reads the cursor clock only
    /// when actually animating (focused + not `.none`) — that volatile read is what
    /// keeps the clock ticking, so an idle indicator costs nothing.
    @MainActor
    static func resolve(isFocused: Bool, context: RenderContext) -> SelectionEmphasis {
        resolve(isFocused: isFocused, environment: context.environment)
    }

    /// The environment-only resolution. `RenderContext` adds nothing here — only
    /// its environment is ever read — and a plain `View` body (a `ButtonStyle`,
    /// say) has no context to offer, which is why this is the primitive and the
    /// context overload forwards to it.
    @MainActor
    static func resolve(isFocused: Bool, environment: EnvironmentValues) -> SelectionEmphasis {
        let animation = environment.selectionIndicatorStyle
        guard isFocused, animation != .none else {
            return SelectionEmphasis(
                isFocused: isFocused, animation: animation, phase: 1, blinkOn: true)
        }
        // Held still, and still focused, while the view does not appear active:
        // what is left on screen that asks (an open menu's highlight, a hovered
        // divider) keeps its bright end, and no clock is read, so nothing keeps
        // the loop waking. Asked after the focus test, so an unfocused element
        // pays for no extra environment read.
        guard environment.appearsActive else { return .steady(isFocused: true) }
        let timer = environment.cursorTimer
        // The same speed `SelectionEmphasisClock.cycle(_:)` lays its runs out at, so
        // a render that reads the clock and a replay agree at every speed.
        let speed = environment.indicatorAnimationSpeeds.speed(for: .focusEmphasis)
        let phase = timer?.pulsePhase(for: speed) ?? environment.pulsePhase
        let blinkOn = timer?.blinkVisible(for: speed) ?? true
        return SelectionEmphasis(
            isFocused: isFocused, animation: animation, phase: phase, blinkOn: blinkOn)
    }
}

// MARK: - Per-frame emphasis

/// One frame of the shared focus emphasis — what a focused element should look
/// like *right now*, given the animation in force
/// (``View/selectionIndicatorStyle(_:)``).
///
/// Ask ``EnvironmentValues/selectionEmphasis`` for one and then call
/// ``color(dim:bright:)`` with the element's own two endpoints. That single call
/// covers every setting: a pulse lerps between them, a blink swaps between them,
/// `.none` sits at `bright`, and an unfocused element sits at `bright` too — so a
/// caller never has to branch on the style itself.
public struct SelectionEmphasis: Equatable, Sendable {
    /// Whether the element this describes holds the focus.
    public let isFocused: Bool

    /// The animation in force (`.none` / `.blink` / `.pulse`).
    public let animation: TextCursorStyle.Animation

    /// The pulse position this frame, 0...1 (1 when not pulsing).
    public let phase: Double

    /// The blink state this frame (always `true` when not blinking).
    public let blinkOn: Bool

    /// A non-animated emphasis (the element sits steady at `bright`), for the
    /// given focus state. Handy when there is no clock to read.
    public static func steady(isFocused: Bool) -> Self {
        Self(isFocused: isFocused, animation: .none, phase: 1, blinkOn: true)
    }

    /// The colour this frame.
    ///
    /// - `dim`: the "off"/recessive endpoint (e.g. the element's own colour, so
    ///   the mark fades into it).
    /// - `bright`: the "on"/visible endpoint (e.g. a contrasting mark colour).
    ///
    /// An unfocused-but-selected indicator stays at `bright` (steady, visible);
    /// a focused one animates between the two per the style.
    public func color(dim: Color, bright: Color) -> Color {
        // Asked before the ramp is BUILT, not after. Only a focused pulse reads
        // one (see the overload below), and building one walks a couple of
        // hundred candidate shades — so a steady or blinking emphasis used to
        // pay for a ramp it then ignored. Same test as
        // `SelectionEmphasisCycle.pulseRamp(dim:bright:)`, for the same reason.
        guard isFocused, animation == .pulse else {
            return color(dim: dim, bright: bright, ramp: nil)
        }
        return color(dim: dim, bright: bright, ramp: Self.pulseRamp(dim: dim, bright: bright))
    }

    /// The colour this frame, against a ramp the caller already has.
    ///
    /// Building the ramp walks a couple of hundred candidate shades, and it
    /// depends only on the two endpoints and the terminal's depth — not on the
    /// frame. A cycle asked for all of its colours was rebuilding the identical
    /// ramp once per frame.
    func color(dim: Color, bright: Color, ramp: [Color]?) -> Color {
        guard isFocused else { return bright }
        switch animation {
        case .none: return bright
        case .blink: return blinkOn ? bright : dim
        case .pulse: return Self.pulsed(dim: dim, bright: bright, phase: phase, ramp: ramp)
        }
    }

    /// The shades this terminal can actually show between the two endpoints, or
    /// `nil` where the colour space is continuous and no ramp is needed.
    ///
    /// ``Color/pulseRamp(from:to:depth:samples:)`` memoises the result, so this
    /// costs a full quantiser walk once per `(dim, bright, depth)` and a
    /// dictionary hit every time after — which is why a caller that fails to
    /// hoist wastes a lookup, not the walk. ``SelectionEmphasisCycle`` hoists
    /// it to once per cycle regardless.
    static func pulseRamp(dim: Color, bright: Color) -> [Color]? {
        let depth = ColorDepth.current
        guard depth < .truecolor else { return nil }
        return Color.pulseRamp(from: dim, to: bright, depth: depth)
    }

    /// The pulse position, snapped to the shades this terminal can actually
    /// show.
    ///
    /// A plain `lerp` sampled on an even time grid is right only where the
    /// colour space is continuous. On a 256-colour terminal it is not: the ramp
    /// rounds onto a handful of cube entries, so the fade sits still and then
    /// jumps, and — because the cube has no dark tinted colours — its bottom end
    /// turns GREY, which reads as a glitch rather than a dim. Walking the
    /// distinct, in-hue shades at even intervals instead gives every one of them
    /// the same screen time. See ``Color/pulseRamp(from:to:depth:samples:)``.
    private static func pulsed(
        dim: Color, bright: Color, phase: Double, ramp: [Color]?
    ) -> Color {
        guard let ramp else { return Color.lerp(dim, bright, phase: phase) }
        guard ramp.count > 1 else { return ramp[0] }
        let step = Int((phase * Double(ramp.count)).rounded(.down))
        return ramp[min(max(0, step), ramp.count - 1)]
    }
}

/// The frame's focus-emphasis clock, read from the environment.
///
/// ```swift
/// @Environment(\.selectionEmphasis) private var emphasis
/// …
/// let colour = emphasis(isFocused).color(dim: quiet, bright: loud)
/// ```
///
/// Resolving is what keeps the clock ticking — the phase read is volatile, so a
/// frame that asks for an animating emphasis schedules the next frame, and one
/// that doesn't lets the loop idle. Nothing is read at all unless the element is
/// focused AND the style actually animates AND the view appears active
/// (``EnvironmentValues/appearsActive``). Where it does not, a focused element's
/// emphasis holds still at its bright end.
public struct SelectionEmphasisClock {
    let environment: EnvironmentValues

    /// The emphasis for an element that is (or isn't) focused right now.
    @MainActor
    public func callAsFunction(_ isFocused: Bool) -> SelectionEmphasis {
        SelectionIndicator.resolve(isFocused: isFocused, environment: environment)
    }
}

// MARK: - The whole cycle

/// Every frame of the focus emphasis, plus where it is right now.
///
/// The counterpart to ``SelectionEmphasis``, which is one frame. A view that
/// draws a focus indicator has two ways to animate it:
///
/// - Ask for the emphasis and colour with it. Simple, and it costs a full
///   re-render of the screen on every tick of the clock.
/// - Ask for the cycle, draw `frames[step]` now, and leave an
///   ``AnimatedCellRun`` behind. The run loop then advances those cells alone,
///   with no view involved at all.
///
/// Building the cycle does **not** consult the live clock (it computes each
/// frame from `CursorTimer`'s static formula), which is exactly what makes the
/// second route legal: nothing about this frame's appearance depends on *when*
/// it was rendered, so it can be reproduced without rendering.
public struct SelectionEmphasisCycle: Sendable, Equatable {
    /// One emphasis per frame of a full cycle.
    public let frames: [SelectionEmphasis]

    /// Where the clock is now — the index to draw immediately.
    public let step: Int

    /// How long each of ``frames`` is shown, in seconds.
    ///
    /// The `run` overloads build their run at this rate. A view that builds its
    /// own ``AnimatedCellRun`` from ``colors(dim:bright:)`` passes it on, with
    /// ``clock``, or its run steps at the clock's default interval whatever this
    /// cycle is laid out on.
    public var frameDuration: Double { timing.frameDuration }

    /// The clock ``step`` is counted on, and the one a run built from this cycle
    /// replays on.
    public var clock: AnimationClock { timing.clock }

    /// `frameDuration` and `clock`, as the cycle carries them.
    let timing: IndicatorCycleTiming

    /// A cycle of `frames`, showing `step` now, laid out on `timing`.
    init(frames: [SelectionEmphasis], step: Int, timing: IndicatorCycleTiming = .cursorTick) {
        self.frames = frames
        self.step = step
        self.timing = timing
    }

    /// Whether this actually animates. A `.none` style, or an unfocused
    /// element, is a single frame: a still picture, not an animation.
    public var isAnimating: Bool { frames.count > 1 }

    /// Whether this cycle describes a focused element.
    ///
    /// Worth asking separately from ``isAnimating`` because a still cycle sits
    /// at `bright` — right for a selection mark, which stays visible when the
    /// focus moves elsewhere, and wrong for a *fill* (a button's caps, a tab's
    /// chip), which should recede to its own surface. Those callers draw
    /// `isFocused ? colorNow(dim:bright:) : <their own resting colour>`.
    public var isFocused: Bool { frames[0].isFocused }

    /// The ramp every frame of this cycle is coloured from, or `nil` when none
    /// is needed.
    ///
    /// Built once per CYCLE, which is the whole reason it is a method here and
    /// not an argument each frame fetches for itself: it depends on the two
    /// endpoints and the terminal's depth, never on which frame is being
    /// coloured, and building one walks a couple of hundred candidate shades
    /// through the quantiser.
    ///
    /// Nil for anything but a focused pulse — that is the only case
    /// ``SelectionEmphasis/color(dim:bright:ramp:)`` reads it in, since a blink
    /// and a still cycle both sit on an endpoint. Both are properties of the
    /// CYCLE rather than of a frame (``SelectionEmphasisClock/cycle(_:)`` gives
    /// every frame the same focus state and animation), so the first frame
    /// answers for all of them — the same reasoning ``isFocused`` uses.
    @MainActor
    private func pulseRamp(dim: Color, bright: Color) -> [Color]? {
        guard let first = frames.first, first.isFocused, first.animation == .pulse else {
            return nil
        }
        return SelectionEmphasis.pulseRamp(dim: dim, bright: bright)
    }

    /// The colour at each frame, for an element with these two endpoints.
    @MainActor
    public func colors(dim: Color, bright: Color) -> [Color] {
        let ramp = pulseRamp(dim: dim, bright: bright)
        return frames.map { $0.color(dim: dim, bright: bright, ramp: ramp) }
    }

    /// The colour to draw *right now* — `colors(dim:bright:)` at ``step``.
    ///
    /// The modulo matters: the clock's tick count is unbounded and keeps
    /// running while nothing is focused, so `step` routinely exceeds the
    /// cycle's length.
    @MainActor
    public func colorNow(dim: Color, bright: Color) -> Color {
        frames[step % frames.count].color(
            dim: dim, bright: bright, ramp: pulseRamp(dim: dim, bright: bright))
    }

    /// A run that breathes a single glyph at `(offsetX, offsetY)`, or `nil`
    /// when this cycle is still.
    ///
    /// The nil case is not an omission to paper over: a still glyph was already
    /// drawn by the ordinary render, and a run would have the loop rewrite it
    /// on every tick to no visible effect. Only movement earns a run.
    ///
    /// The run's width is the glyph's own width in *cells*, which is what
    /// ``AnimatedCellRun`` promises and not always what the glyph's character
    /// count suggests — `●` is East Asian Ambiguous, and the radio bullet and a
    /// box-drawing cap do not measure alike everywhere.
    @MainActor
    public func run(
        _ glyph: String, dim: Color, bright: Color, offsetX: Int, offsetY: Int
    ) -> AnimatedCellRun? {
        run(dim: dim, bright: bright, offsetX: offsetX, offsetY: offsetY) {
            ANSIRenderer.colorize(glyph, foreground: $0)
        }
    }

    /// A run for an element the caller draws itself, once per colour of the
    /// cycle — a tab's whole chip, a scrollbar's thumb, anything whose
    /// appearance is more than a foreground colour on a glyph.
    ///
    /// `draw` must produce the same cells the ordinary render drew, at the
    /// colour it is handed; the run's width is taken from the first frame, so
    /// what is replayed is measured from what is actually drawn rather than
    /// from the caller's belief about its width.
    @MainActor
    public func run(
        dim: Color, bright: Color, offsetX: Int, offsetY: Int, draw: (Color) -> String
    ) -> AnimatedCellRun? {
        // Asked BEFORE the colours are built: a still cycle earns no run, and
        // the ramp built for one would be thrown away with it.
        guard isAnimating else { return nil }
        // `colors(dim:bright:)`, not `color(dim:bright:)` per frame. The latter
        // BUILDS the pulse ramp, so calling it from inside the per-frame
        // closure rebuilt the identical ramp once per frame of the cycle —
        // sixteen times for a regular pulse, on every terminal below truecolor.
        // Same colours either way; ~8,200 quantiser samples fewer.
        return run(colors: colors(dim: dim, bright: bright), offsetX: offsetX, offsetY: offsetY, draw: draw)
    }

    /// A run whose frames are drawn from colours the caller already has.
    ///
    /// The route for a caller that spends ONE cycle's colours on more than one
    /// run — a button's two end caps, drawn from the same breath at opposite
    /// ends of the same row. Going through `run(dim:bright:…)` twice would
    /// build the same ramp twice; `colors(dim:bright:)` builds it once and this
    /// spends it as often as the caller likes.
    @MainActor
    func run(
        colors: [Color], offsetX: Int, offsetY: Int, draw: (Color) -> String
    ) -> AnimatedCellRun? {
        guard isAnimating else { return nil }
        return run(drawn: colors.map(draw), offsetX: offsetX, offsetY: offsetY)
    }

    /// A run for an element whose appearance is not one colour between two
    /// endpoints — a cell that pulses its background AND its glyph, say, or one
    /// that blinks rather than fades. `draw` is handed the whole emphasis for
    /// each frame and returns the finished cells.
    ///
    /// The other `run` overloads are this one with a colour picked for the
    /// caller, so every route produces the same frames on the same clock.
    @MainActor
    public func run(
        offsetX: Int, offsetY: Int, draw: (SelectionEmphasis) -> String
    ) -> AnimatedCellRun? {
        // A still cycle earns no run: the render already drew that picture, and
        // replaying it would emit bytes per tick to change nothing.
        guard isAnimating else { return nil }
        // One finished, styled string per step, so the loop's per-tick work is
        // an array index.
        return run(drawn: frames.map(draw), offsetX: offsetX, offsetY: offsetY)
    }

    /// The tail every `run` overload shares: the finished cells become a run,
    /// measured from what was actually drawn.
    @MainActor
    private func run(drawn: [String], offsetX: Int, offsetY: Int) -> AnimatedCellRun? {
        guard let first = drawn.first else { return nil }
        return AnimatedCellRun(
            offsetX: offsetX,
            offsetY: offsetY,
            width: first.strippedLength,
            frames: drawn,
            // The cycle's own frame duration and clock, because those are what its
            // frames were laid out on: a run handed any other would advance at a
            // different rate than it was built for.
            frameDuration: timing.frameDuration, clock: timing.clock)
    }
}

extension SelectionEmphasisClock {
    /// Every frame of the cycle for an element that is (or isn't) focused.
    ///
    /// Where the view does not appear active (``EnvironmentValues/appearsActive``
    /// is `false`), a focused element's cycle is one still frame at its bright
    /// end, as with the animation off. It is still focused, so a fill still
    /// draws as focused.
    ///
    /// See ``SelectionEmphasisCycle``.
    @MainActor
    public func cycle(_ isFocused: Bool) -> SelectionEmphasisCycle {
        let animation = environment.selectionIndicatorStyle
        guard isFocused, animation != .none else {
            return SelectionEmphasisCycle(
                frames: [
                    SelectionEmphasis(
                        isFocused: isFocused, animation: animation, phase: 1, blinkOn: true)
                ],
                step: 0)
        }
        // Held still while the view does not appear active — see
        // `SelectionIndicator.resolve(isFocused:environment:)`.
        guard environment.appearsActive else {
            return SelectionEmphasisCycle(frames: [.steady(isFocused: true)], step: 0)
        }
        let layout = CursorTimer.cycleLayout(
            of: animation, speed: environment.indicatorAnimationSpeeds.speed(for: .focusEmphasis))
        let frames = (0..<layout.frameCount).map { frame in
            // Each frame states only its own animation: a blink's phase is 1 and a
            // pulse's blink is on, as `SelectionEmphasis` documents for the animation
            // not in force. Both used to be sampled from both formulas on the tick
            // grid, and nothing read the one that did not apply.
            SelectionEmphasis(
                isFocused: true,
                animation: animation,
                phase: animation == .pulse
                    ? CursorTimer.pulsePhase(atFrame: frame, of: layout.frameCount) : 1,
                blinkOn: animation == .blink ? CursorTimer.blinkVisible(atFrame: frame) : true)
        }
        // Read only where the cycle animates: a still cycle is one frame, and no
        // timing moves it. A test may force one; nothing else sets it.
        let timing = environment.indicatorCycleTiming ?? layout.timing
        // `step(on:)` is a plain read: unlike `pulsePhase(for:)` it does not mark
        // the frame as having consulted the clock, so a producer that uses it stays
        // replayable.
        return SelectionEmphasisCycle(
            frames: frames, step: timing.step(on: environment.cursorTimer), timing: timing)
    }
}

extension EnvironmentValues {
    /// The shared focus-emphasis clock — the one place that decides how a
    /// focused element breathes, blinks, or simply sits bright.
    ///
    /// Every built-in control resolves through this, so anything an app builds
    /// keeps step with them and honours
    /// ``View/selectionIndicatorStyle(_:)`` and the
    /// speed set for ``IndicatorAnimations/focusEmphasis`` for free. TUI-specific:
    /// SwiftUI has no equivalent, because it has no shared terminal-wide pulse.
    public var selectionEmphasis: SelectionEmphasisClock {
        SelectionEmphasisClock(environment: self)
    }
}
