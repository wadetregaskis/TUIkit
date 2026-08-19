//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatedColor.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// A colour that varies over one of the terminal's animation clocks, given as
/// every frame of its cycle rather than as the one showing now.
///
/// Hand one to a modifier that paints — ``View/border(_:style:width:)-(AnimatedColor,_,_)`` — and
/// that modifier animates the cells it drew, by leaving ``AnimatedCellRun``s
/// for the run loop to advance. Nothing re-renders per tick, and you never
/// compute an offset: the thing that knows where the cells are is the thing
/// that placed them.
///
/// The usual source is the shared focus clock:
///
/// ```swift
/// struct Target: View {
///     @Environment(\.isFocused) private var isFocused
///     @Environment(\.selectionEmphasis) private var emphasis
///     @Environment(\.palette) private var palette
///
///     var body: some View {
///         Text("Right-click me")
///             .border(emphasis.animatedColor(
///                 isFocused, dim: palette.border, bright: palette.accent))
///     }
/// }
/// ```
///
/// A colour that does not vary is still an `AnimatedColor` — `AnimatedColor(.red)`
/// is one frame — so a call site does not have to branch on whether anything is
/// animating. ``isAnimating`` is what the framework branches on, and it is false
/// for a single frame *and* for several identical ones.
///
/// See <doc:AnimatingYourOwnView>.
public struct AnimatedColor: Sendable, Equatable {
    /// A colour that does not vary is stored AS one colour, not as an array of
    /// one. Every bordered container in a frame builds one of these, and an
    /// array — even of a single element — is a heap allocation apiece; a
    /// paired A/B measured that at ~1% of a table frame before this split.
    private enum Storage: Sendable, Equatable {
        case constant(Color)
        case cycle([Color])
    }

    private let storage: Storage

    /// Where the clock is now — the index to draw immediately. Taken modulo
    /// ``frames``' count on use, because a clock's tick count is unbounded and
    /// keeps running while nothing is animating.
    public let step: Int

    /// The clock that advances it.
    public let clock: AnimationClock

    /// One colour per tick of a full cycle. Never empty.
    ///
    /// Materialised on demand: prefer ``current`` and ``isAnimating``, which
    /// answer without building an array.
    public var frames: [Color] {
        switch storage {
        case .constant(let colour): [colour]
        case .cycle(let frames): frames
        }
    }

    /// A colour that does not vary.
    public init(_ color: Color) {
        storage = .constant(color)
        step = 0
        clock = .cursor
    }

    /// A colour given as every frame of its cycle.
    ///
    /// - Parameters:
    ///   - frames: One colour per tick. An empty array is treated as a single
    ///     terminal-default frame rather than trapping — a colour is not the
    ///     place to take an app down.
    ///   - step: Which frame is showing now.
    ///   - clock: The clock that advances it.
    public init(frames: [Color], step: Int, clock: AnimationClock = .cursor) {
        switch frames.count {
        case 0: storage = .constant(.default)
        case 1: storage = .constant(frames[0])
        default: storage = .cycle(frames)
        }
        self.step = step
        self.clock = clock
    }

    /// The colour to draw in the frame being rendered now.
    public var current: Color {
        switch storage {
        case .constant(let colour): colour
        case .cycle(let frames): frames[step.modulo(frames.count)]
        }
    }

    /// Whether this actually varies.
    ///
    /// False for a single frame, and false for several identical ones — a
    /// 256-colour terminal quantises many a ramp down to one entry, and a run
    /// whose frames are all the same emits bytes per tick to change nothing.
    public var isAnimating: Bool {
        guard case .cycle(let frames) = storage else { return false }
        return frames.contains { $0 != frames[0] }
    }

    /// The colour at an arbitrary point in the cycle — for a caller drawing
    /// several things that must stay in phase with each other.
    public func color(atStep step: Int) -> Color {
        switch storage {
        case .constant(let colour): colour
        case .cycle(let frames): frames[step.modulo(frames.count)]
        }
    }

    /// The same colour with every frame resolved against `palette`, so a
    /// semantic endpoint (`.palette.accent`) becomes a concrete one.
    public func resolved(with palette: any Palette) -> Self {
        switch storage {
        case .constant(let colour): Self(colour.resolve(with: palette))
        case .cycle(let frames):
            Self(frames: frames.map { $0.resolve(with: palette) }, step: step, clock: clock)
        }
    }

    /// A run that redraws `width` cells at `(offsetX, offsetY)` once per frame,
    /// or `nil` when this colour does not animate.
    ///
    /// `draw` must produce the same cells the ordinary render drew, at the
    /// colour it is handed. The `nil` case is not an omission to paper over: a
    /// still picture was already drawn, and a run would have the loop rewrite it
    /// every tick to no visible effect.
    public func run(offsetX: Int, offsetY: Int, draw: (Color) -> String) -> AnimatedCellRun? {
        run(offsetX: offsetX, offsetY: offsetY) { _, colour in draw(colour) }
    }

    /// A run whose `draw` is also told WHICH frame it is drawing, for a caller
    /// that has something else to keep in phase with this colour — a second
    /// animated element sharing the same clock, drawn into the same cells.
    public func run(
        offsetX: Int, offsetY: Int, drawAtStep draw: (Int, Color) -> String
    ) -> AnimatedCellRun? {
        guard case .cycle(let frames) = storage, isAnimating else { return nil }
        let drawn = frames.enumerated().map { draw($0.offset, $0.element) }
        guard let first = drawn.first else { return nil }
        return AnimatedCellRun(
            offsetX: offsetX, offsetY: offsetY, width: first.strippedLength,
            frames: drawn, clock: clock)
    }
}

extension Int {
    /// A non-negative remainder, because a clock's step is unbounded and the
    /// `%` operator keeps the sign of the dividend.
    fileprivate func modulo(_ divisor: Int) -> Int {
        guard divisor > 0 else { return 0 }
        let remainder = self % divisor
        return remainder < 0 ? remainder + divisor : remainder
    }
}

// MARK: - From the shared focus clock

extension SelectionEmphasisClock {
    /// The focus emphasis as an animated colour, for a modifier to paint with.
    ///
    /// The cheap counterpart to `emphasis(isFocused).color(dim:bright:)`: that
    /// one resolves THIS TICK's colour and reads the clock to do it, which
    /// makes the frame unreplayable and costs a full render pass per tick. This
    /// one carries the whole cycle, computed from a static formula, so the
    /// modifier that paints with it can hand the loop the finished frames.
    ///
    /// - Parameters:
    ///   - isFocused: Whether the element this describes holds the focus. An
    ///     unfocused element does not animate, and asking is free.
    ///   - dim: The recessive endpoint.
    ///   - bright: The visible endpoint.
    @MainActor
    public func animatedColor(_ isFocused: Bool, dim: Color, bright: Color) -> AnimatedColor {
        let cycle = self.cycle(isFocused)
        return AnimatedColor(
            frames: cycle.colors(dim: dim, bright: bright), step: cycle.step, clock: .cursor)
    }
}

extension SelectionEmphasisCycle {
    /// This cycle as an animated colour between two endpoints.
    ///
    /// The same thing ``SelectionEmphasisClock/animatedColor(_:dim:bright:)``
    /// produces, for a caller that already has the cycle in hand.
    @MainActor
    public func animatedColor(dim: Color, bright: Color) -> AnimatedColor {
        AnimatedColor(frames: colors(dim: dim, bright: bright), step: step, clock: .cursor)
    }
}
