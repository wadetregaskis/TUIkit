//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Gradient.swift
//
//  A gradient's stops, and what colour they give at a point. Deliberately no
//  geometry: a stop list says what the colours ARE and in what order, and
//  where `t` comes from is the paint's business — the length of a progress
//  track, the width of a `Text`, the extent of a subtree.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Gradient

/// A colour ramp: colours at positions, interpolated piecewise between them.
///
/// The same type SwiftUI names, with the same two initialisers and the same
/// ``Stop``, so ported source compiles unchanged:
///
/// ```swift
/// Gradient(colors: [.red, .orange, .yellow])                    // even spacing
/// Gradient(stops: [.init(color: .red, location: 0),
///                  .init(color: .yellow, location: 0.8)])       // positioned
/// ```
///
/// Positioned stops are the reason this exists rather than the `[Color]` lists
/// TUIkit's gradients used to be. "Mostly red, then a fast run to yellow at the
/// end" is the shape most hand-made ramps actually want, and an evenly-spaced
/// list cannot say it.
///
/// ## What a stop list means
///
/// Three behaviours, each **measured against SwiftUI** rather than assumed
/// (`Documentation/Gradients where a colour is accepted.md` §1) and each pinned
/// by a test here:
///
/// - **Order does not matter.** An unsorted list renders as if sorted, so
///   `red@0.8, blue@0.2` is a blue-to-red ramp.
/// - **Two stops at one location make a hard edge**, with the later stop
///   winning from that point on. This is how a stop list draws a stripe.
/// - **Locations outside 0…1 are not clamped.** The ramp is evaluated *through*
///   them, so stops at −0.5 and 1.5 show the middle half of the ramp across
///   `0…1`. Clamping instead would silently turn a deliberate crop into a
///   different gradient.
///
/// A gradient carries no geometry — see the file note. `t` is supplied by
/// whatever is painting.
public struct Gradient: Sendable, Hashable {
    /// Whether nothing in this ramp carries alpha.
    ///
    /// Asked of the STOPS rather than of a sampled ramp, because it gates whether a
    /// path that cannot express alpha at all may be taken — a terminal picture, which
    /// has no alpha channel — and that decision comes before any sampling. A stop's
    /// alpha survives interpolation (``Color/lerp(_:_:phase:)`` treats it as a fourth
    /// channel), so opaque stops cannot produce a translucent ramp.
    ///
    /// Here rather than in `Paint`, which used to spell it out, because a track's
    /// fill and empty gradients are bare `Gradient`s and were about to spell it a
    /// third and fourth time.
    public var isOpaqueThroughout: Bool {
        stops.allSatisfy(\.color.isOpaque)
    }

    /// One colour, at one position along the ramp.
    public struct Stop: Sendable, Hashable {
        /// The colour at this point.
        public var color: Color

        /// Where it sits. Conventionally `0…1`, and deliberately not clamped —
        /// see ``Gradient``.
        ///
        /// `Double` rather than SwiftUI's `CGFloat`: TUIkit measures in cells
        /// and `CGFloat` is a Darwin type, but every literal that compiles as
        /// one compiles as this, so the spelling is unchanged.
        public var location: Double

        public init(color: Color, location: Double) {
            self.color = color
            self.location = location
        }
    }

    /// Which space the stops are interpolated in.
    ///
    /// SwiftUI's type, with SwiftUI's two members. What it decides is what
    /// happens BETWEEN two stops, which is where naive interpolation goes
    /// wrong: red to blue in encoded sRGB passes through a middle darker than
    /// either end (OKLab lightness 0.628 → 0.395 → 0.452), and blue to yellow
    /// passes through `rgb(127, 127, 127)` — a grey, no chroma left at all.
    /// Both are measured, and both are what ``perceptual`` is for.
    public struct ColorSpace: Sendable, Hashable {
        /// The encoded sRGB components, blended directly. Cheap, and what a
        /// gradient does unless told otherwise — SwiftUI's default too.
        public static let device = Self(isPerceptual: false)

        /// OKLab, where a straight line looks like one.
        public static let perceptual = Self(isPerceptual: true)

        /// The whole state: there are two spaces and no third.
        let isPerceptual: Bool
    }

    /// The stops, exactly as the caller wrote them — unsorted if they wrote
    /// them unsorted, because the order is not what the gradient means and
    /// rewriting it would make a round trip lossy.
    public var stops: [Stop]

    /// The space ``color(at:)`` interpolates in.
    ///
    /// **A TUI-specific addition, and the reason is a hole in SwiftUI's own
    /// API.** There, a space can only ride on `AnyGradient` — `Gradient` has
    /// `colorSpace(_:)` as a method returning one, and no property — so a
    /// `LinearGradient` cannot be perceptual at all. Measured, not recalled:
    /// `LinearGradient(gradient:startPoint:endPoint:)` takes a `Gradient` and
    /// refuses an `AnyGradient`. A terminal's gradients are overwhelmingly
    /// directional, so the knob has to reach them, and the storage is here.
    ///
    /// `colorSpace(_:)` — the SwiftUI spelling, which the umbrella module adds
    /// because `AnyGradient` is its — still returns one, and sets this on the
    /// way. (Inline code rather than a doc link: both live a module up.)
    public var colorSpace: ColorSpace = .device

    /// A gradient with these stops.
    public init(stops: [Stop]) {
        self.stops = stops
    }

    /// A gradient with these stops, interpolated in the given space.
    ///
    /// The `colorSpace:` parameter is the TUI-specific half — see
    /// ``colorSpace``. SwiftUI's `init(stops:)` is above it and
    /// unchanged.
    public init(stops: [Stop], colorSpace: ColorSpace) {
        self.stops = stops
        self.colorSpace = colorSpace
    }

    /// A gradient with these colours, evenly spaced from `0` to `1`.
    ///
    /// One colour sits at `0` and is therefore flat; none is an empty ramp,
    /// which ``color(at:)`` answers as black rather than trapping.
    public init(colors: [Color]) {
        guard colors.count > 1 else {
            self.stops = colors.map { Stop(color: $0, location: 0) }
            return
        }
        let last = Double(colors.count - 1)
        self.stops = colors.enumerated().map {
            Stop(color: $0.element, location: Double($0.offset) / last)
        }
    }

    /// A gradient with these colours, interpolated in the given space. See
    /// ``init(stops:colorSpace:)``.
    public init(colors: [Color], colorSpace: ColorSpace) {
        self.init(colors: colors)
        self.colorSpace = colorSpace
    }
}

// MARK: - Editing

extension Gradient {
    /// This gradient with different stops, and everything else about it kept.
    ///
    /// The alternative — `Gradient(stops: newStops)` — silently drops whatever
    /// else the ramp carries, which is how a perceptual gradient came back
    /// `.device` from the animator, from `.opacity(_:)`, and from every edit
    /// the gradient panel makes.
    ///
    /// The rule those three now follow: **never spell a rebuild
    /// `Gradient(stops:)`** — either assign `stops` on a copy you already hold,
    /// or come through here. Both keep whatever the next field turns out to be;
    /// the initialiser does not.
    ///
    /// - Parameter stops: The new stops.
    /// - Returns: The same gradient, with those stops.
    public func withStops(_ stops: [Stop]) -> Self {
        var moved = self
        moved.stops = stops
        return moved
    }

    /// This gradient with every stop resolved against `palette`.
    ///
    /// A stop may name a palette role — `.accentColor`, `.primary`, an
    /// app's own ``Palette`` slot — and a role is a *reference*, not a colour:
    /// it has no channels until there is a palette to look it up in. Everything
    /// that blends stops asks for those channels and gets `nil`, so an
    /// unresolved ramp interpolates to nothing and the ANSI layer traps on the
    /// first stop it is handed.
    ///
    /// So a ramp is resolved at the same moment a lone ``Color`` is: when a
    /// style becomes a ``Paint``, which is the first point the palette is
    /// known. See `ShapeStyle.paint(in:)`.
    ///
    /// - Parameter palette: The palette to look roles up in.
    /// - Returns: The same ramp, with concrete colours.
    public func resolvingStops(with palette: any Palette) -> Self {
        guard stops.contains(where: { $0.color.rgbComponents == nil }) else { return self }
        return withStops(
            stops.map { Stop(color: $0.color.resolve(with: palette), location: $0.location) })
    }
}

// MARK: - Evaluation

extension Gradient {

    /// The stops in position order — the order the ramp is read in, and the
    /// only order in which "the stop after this one" means anything.
    ///
    /// A stable sort, so two stops at the same location keep the order they
    /// were written in, which is what decides which side of a hard edge each
    /// one takes.
    ///
    /// Returns `stops` itself when they are already in order, which is almost
    /// always — `init(colors:)` produces them sorted and people write them that
    /// way. That makes the common path a comparison per stop and **no
    /// allocation**, which matters because this is consulted per painted cell.
    var ordered: [Stop] {
        var previous = -Double.infinity
        for stop in stops {
            if stop.location < previous { return sortedStops() }
            previous = stop.location
        }
        return stops
    }

    private func sortedStops() -> [Stop] {
        stops.enumerated()
            .sorted {
                $0.element.location == $1.element.location
                    ? $0.offset < $1.offset
                    : $0.element.location < $1.element.location
            }
            .map(\.element)
    }

    /// The colour at `phase` along the ramp.
    ///
    /// Held at the end colours outside the stops' own range — the same rule
    /// ``ASCIIToneCurve`` follows for knots, and the reason locations outside
    /// `0…1` crop the ramp rather than extending it.
    ///
    /// A stop is returned as it is spelled, so at a `.ansi(.red)` stop's location
    /// this is that slot, and between it and its neighbours it is RGB. A
    /// segment with a stop that has no RGB (``Color/default``, or a colour of the
    /// terminal's own it has not reported) has nothing to blend, so it is a hard
    /// edge at its middle: the earlier stop through the midpoint, the later one
    /// past it. See ``Color/lerp(_:_:phase:)``.
    public func color(at phase: Double) -> Color {
        Self.color(at: phase, in: ordered, space: colorSpace)
    }

    /// The evaluation itself, against a list already known to be in order — so
    /// a caller sampling many cells orders once rather than per cell.
    private static func color(at phase: Double, in list: [Stop], space: ColorSpace) -> Color {
        guard let first = list.first else { return .rgb(0, 0, 0) }
        guard list.count > 1 else { return first.color }
        guard phase > first.location else { return first.color }
        guard let last = list.last, phase < last.location else { return list[list.count - 1].color }

        // The last segment whose start is at or before `phase`. Searching from
        // the END is what makes a hard edge work: stops sharing a location
        // leave zero-length segments, and the later one has to win from that
        // point on.
        var index = list.count - 2
        while index > 0 && list[index].location > phase { index -= 1 }
        while index < list.count - 2 && list[index + 1].location <= phase { index += 1 }

        let lower = list[index]
        let upper = list[index + 1]
        let span = upper.location - lower.location
        guard span > 0 else { return upper.color }
        return Color.interpolate(
            lower.color, upper.color, phase: (phase - lower.location) / span, in: space)
    }

    /// `count` colours evenly sampled across `0…1`.
    ///
    /// The sampling every painter does, in one place — and the input
    /// ``Color/quantisedRamp(_:count:depth:)`` repairs.
    public func sampled(count: Int) -> [Color] {
        let list = ordered
        return (0..<max(0, count)).map { index in
            Self.color(
                at: count > 1 ? Double(index) / Double(count - 1) : 0, in: list,
                space: colorSpace)
        }
    }
}

// MARK: - Collapsing to one colour

extension Gradient {

    /// The one colour that stands in for this gradient where a gradient cannot
    /// go — the midpoint of the ramp.
    ///
    /// TUIkit derives colours from colours constantly: contrast floors, the
    /// button styles' face / border / label chain, the scrollbar's separation
    /// and groove rules, the pulse ramps. Each needs a single colour to do
    /// arithmetic with, and the rule is that a gradient is accepted where a
    /// colour is PAINTED and collapses where a colour is DERIVED FROM. This is
    /// the collapse for identity, cache keys and derivation.
    ///
    /// The midpoint rather than the first stop: a two-stop ramp's first colour
    /// is an end of the range, not a summary of it.
    public var representative: Color { color(at: 0.5) }

    /// The stop this gradient is least readable in, against `background`.
    ///
    /// What a contrast floor has to be applied to. Flooring
    /// ``representative`` instead would leave the ends below the floor — see
    /// ``Color/ensuringRenderedContrast(atLeast:against:)`` for what a floor
    /// means, and the design note for why flooring the STOPS is still not
    /// sufficient on its own when a ramp's ends straddle the background's
    /// luminance.
    public func leastContrasting(against background: Color) -> Color {
        var worst: (color: Color, ratio: Double)?
        for stop in stops {
            let ratio = stop.color.contrastRatio(against: background)
            if worst == nil || ratio < worst!.ratio { worst = (stop.color, ratio) }
        }
        return worst?.color ?? representative
    }
}
