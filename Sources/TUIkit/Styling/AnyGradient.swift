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
///   so a top-to-bottom ramp across it resolves at `t = 0` — the ramp's start,
///   which for ``Color/gradient`` is the lighter end. Give it height (a
///   multi-line block, or a ``View/gradientExtent(_:)`` spanning several rows)
///   and the ramp appears.
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

    /// Creates a directionless gradient from a stop list.
    public init(_ gradient: Gradient) {
        source = .stops(gradient)
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
        case .derived(let color): return Self.derive(from: color, in: environment)
        }
    }

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        .gradient(GradientPaint(gradient(in: environment), .linear(from: .top, to: .bottom)))
    }

    /// The two stops ``Color/gradient`` is: the colour lightened, then the
    /// colour. See that property for what was measured against SwiftUI.
    private static func derive(from color: Color, in environment: EnvironmentValues) -> Gradient {
        let resolved = color.resolve(with: environment.palette)
        guard let base = resolved.rgbComponents else { return Gradient(colors: [resolved]) }
        let (hue, saturation, lightness) = Color.rgbToHSL(
            red: base.red, green: base.green, blue: base.blue)
        return Gradient(colors: [
            Color.hsl(hue, saturation, min(100, lightness + 15)),
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
    /// ``Color/ensuringContrast(against:minimum:)`` also does when it has to
    /// move a colour, so the framework moves colours one way rather than two.
    /// SwiftUI additionally moves saturation, by an amount that is not one
    /// number (it rose for the blue and fell for the green); black is the row
    /// that misses, and a terminal has nothing to show the difference with.
    public var gradient: AnyGradient {
        AnyGradient(derivedFrom: self)
    }
}
