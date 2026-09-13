//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnyGradient.swift
//
//  A gradient with no direction of its own, and the one every colour carries.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - AnyGradient

/// A ``Gradient`` used as a style without naming a direction — it runs top to
/// bottom, the way SwiftUI resolves one.
///
/// SwiftUI's type, with SwiftUI's initialiser. What it exists for is
/// ``Color/gradient``: `.foregroundStyle(.red.gradient)` is a colour with a
/// little depth in it, and nothing else in the API can say that without
/// spelling out a `LinearGradient` and two `UnitPoint`s.
///
/// ```swift
/// Text("Header")
///     .foregroundStyle(Color.blue.gradient)
/// ```
///
/// > Note: A gradient needs room to run. A one-line ``Text`` is one cell tall,
///   so a top-to-bottom ramp across it is sampled once, at the cell's centre —
///   `t = 0.5`, which for ``Color/gradient``'s two-entry ramp rounds to the
///   LAST entry: the base colour itself, so the text looks exactly as it would
///   without the gradient. (Not the lighter end, which an earlier version of
///   this note claimed.) Give it height (a multi-line block, or a
///   ``View/gradientExtent(_:)`` spanning several rows) and the ramp appears.
public struct AnyGradient: ShapeStyle, Hashable, Sendable {
    /// Stops given outright, or a colour to derive them from when the palette
    /// is known.
    ///
    /// Derivation cannot happen at `.gradient` — `Color.palette.accent` is a
    /// reference, not a colour, and there is no palette to resolve it against
    /// until something paints. So a derived gradient carries its base colour
    /// and works its stops out at ``paint(in:)``, which is the first moment it
    /// can. A theme change then moves it, as it moves everything else.
    private enum Source: Hashable, Sendable {
        case stops(Gradient)
        case derived(Color)
    }

    private let source: Source

    /// The space a DERIVED gradient's two stops are blended in — the derived
    /// case cannot carry it on a ``Gradient``, because it has no stops until
    /// something paints.
    ///
    /// Not optional, and it matters that it is not: `AnyGradient` is `Hashable`
    /// and public, so a "no space asked for" that is distinct from the space it
    /// resolves to would make `.red.gradient.colorSpace(.device)` unequal to
    /// `.red.gradient` while the two paint identically.
    private var derivedSpace = Gradient.ColorSpace.device

    /// Creates a directionless gradient from a stop list.
    public init(_ gradient: Gradient) {
        source = .stops(gradient)
    }

    /// This gradient, interpolated in `space`.
    ///
    /// SwiftUI's spelling, and in SwiftUI it is the ONLY place a colour space
    /// can live — which is why `Gradient` carries one here as well; see
    /// `Gradient.colorSpace`.
    ///
    /// - Parameter space: The space to interpolate the stops in.
    /// - Returns: The same ramp, blended differently.
    public func colorSpace(_ space: Gradient.ColorSpace) -> Self {
        switch source {
        case .stops(var gradient):
            gradient.colorSpace = space
            return Self(gradient)
        case .derived(let colour):
            var moved = Self(derivedFrom: colour)
            moved.derivedSpace = space
            return moved
        }
    }

    /// The gradient behind ``Color/gradient``.
    init(derivedFrom color: Color) {
        source = .derived(color)
    }

    /// The stops this resolves to.
    ///
    /// SwiftUI exposes nothing here — its `AnyGradient` is opaque. TUIkit
    /// answers, for the same reason ``LinearGradient`` exposes its own storage:
    /// an app writing a `Renderable` has to be able to ask what it was handed.
    /// It takes an environment because a derived gradient's base colour may be
    /// a palette role.
    ///
    /// - Parameter environment: The environment being painted in.
    /// - Returns: The stops, with any palette reference resolved.
    public func gradient(in environment: EnvironmentValues) -> Gradient {
        switch source {
        case .stops(let gradient): return gradient
        case .derived(let color):
            var derived = Self.derive(from: color, in: environment)
            derived.colorSpace = derivedSpace
            return derived
        }
    }

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        .gradient(
            GradientPaint(
                gradient(in: environment).resolvingStops(with: environment.palette),
                .linear(from: .top, to: .bottom)))
    }

    /// The two stops ``Color/gradient`` is: the colour lightened, then the
    /// colour. See that property for what was measured against SwiftUI.
    private static func derive(from color: Color, in environment: EnvironmentValues) -> Gradient {
        let resolved = color.resolve(with: environment.palette)
        guard let base = resolved.rgbComponents else { return Gradient(colors: [resolved]) }
        let (hue, saturation, lightness) = Color.rgbToHSL(
            red: base.red, green: base.green, blue: base.blue)
        // The lighter stop carries `resolved`'s alpha rather than the 255 `Color.hsl`
        // builds at. Built opaque, `Color.blue.opacity(0.5).gradient` was a ramp from
        // a solid top to a half-faded bottom — alpha interpolates as a fourth channel
        // and a vertical ramp's per-row alpha is claimed (§15, §34.1) — so text tall
        // enough to show the ramp faded in down its rows instead of being half all
        // the way. Carried, not composed: `resolved` has already composed the
        // reference's alpha with any faded palette slot, and the lighter end is that
        // same ink re-spelled.
        return Gradient(colors: [
            Color.hsl(hue, saturation, min(100, lightness + 15)).carryingAlpha(of: resolved),
            resolved,
        ])
    }
}

// MARK: - The gradient a colour carries

extension Color {
    /// A subtle top-to-bottom gradient derived from this colour: a lighter
    /// version of it at the top, the colour itself at the bottom.
    ///
    /// ```swift
    /// Text("Total")
    ///     .foregroundStyle(Color.blue.gradient)
    /// ```
    ///
    /// ## How this differs from SwiftUI's
    ///
    /// SwiftUI derives its lighter end in a perceptual space TUIkit does not
    /// have, so the two agree on the *shape* — hue held, lightness raised, the
    /// base colour at the bottom — and part company in the last few percent.
    /// Measured against SwiftUI's own renderer (`ImageRenderer` over
    /// one-cell-wide strips), its lighter end sits at these HSL lightnesses:
    ///
    /// | base | base L | SwiftUI's top | here |
    /// |---|---|---|---|
    /// | grey 128 | 0.502 | 0.647 | 0.652 |
    /// | `rgb(51, 102, 204)` | 0.500 | 0.639 | 0.650 |
    /// | `rgb(0, 153, 51)` | 0.300 | 0.451 | 0.450 |
    /// | white | 1.000 | 1.000 | 1.000 |
    /// | black | 0.000 | 0.198 | 0.150 |
    ///
    /// `+0.15` in lightness is the single-parameter fit to that set, and hue
    /// and saturation are held — which is what
    /// ``Color/ensuringContrast(atLeast:against:)`` also does when it has to
    /// move a colour, so the framework moves colours one way rather than two.
    /// SwiftUI additionally moves saturation, by an amount that is not one
    /// number (it rose for the blue and fell for the green); black is the row
    /// that misses, and a terminal has nothing to show the difference with.
    public var gradient: AnyGradient {
        AnyGradient(derivedFrom: self)
    }
}

// MARK: - The SwiftUI spelling on `Gradient`

extension Gradient {
    /// This gradient as a directionless ``AnyGradient``, interpolated in
    /// `space`.
    ///
    /// SwiftUI's signature exactly, including the return type: there,
    /// `AnyGradient` is the only thing that can carry a colour space. TUIkit
    /// additionally lets a ``Gradient`` carry one — see
    /// `Gradient.colorSpace` — so that a `LinearGradient`, which a
    /// terminal reaches for far more often than a directionless ramp, can be
    /// perceptual too.
    ///
    /// - Parameter space: The space to interpolate the stops in.
    /// - Returns: The ramp, erased and blended in that space.
    public func colorSpace(_ space: ColorSpace) -> AnyGradient {
        var moved = self
        moved.colorSpace = space
        return AnyGradient(moved)
    }
}
