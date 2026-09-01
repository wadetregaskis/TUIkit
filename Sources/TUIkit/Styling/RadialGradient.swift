//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RadialGradient.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - RadialGradient

/// A ``Gradient`` drawn outward from a centre: the ramp runs from
/// ``startRadius`` to ``endRadius``, and every cell takes its colour from how
/// far it is from ``center``.
///
/// ```swift
/// Text("warning")
///     .foregroundStyle(RadialGradient(colors: [.yellow, .red],
///                                     center: .center, startRadius: 0, endRadius: 8))
/// ```
///
/// Inside the start radius every cell is the first stop; past the end radius
/// every cell is the last. The ramp does not repeat — measured against
/// SwiftUI, which clamps at both ends.
///
/// ## The one deviation: radii are cells
///
/// SwiftUI's radii are `CGFloat` lengths. Here they are `Int` **cells**,
/// because every other dimension in this framework is
/// (``View/frame(width:height:alignment:)``) and a fractional radius has nothing to
/// round to on a character grid.
///
/// A cell is about twice as tall as it is wide, so a radius counted equally in
/// both directions would draw an ellipse rather than the circle it names. The
/// radius is therefore measured **along the horizontal axis**, and the
/// vertical extent derived through ``EnvironmentValues/imageCellAspect`` — the
/// same correction images use. For a ramp that follows the box's own shape
/// instead, use ``EllipticalGradient``.
public struct RadialGradient: ShapeStyle, Equatable, Sendable {
    /// The stops.
    public var gradient: Gradient

    /// Where the rings are centred, in unit space.
    public var center: UnitPoint

    /// The radius, in cells, at which the ramp begins.
    public var startRadius: Int

    /// The radius, in cells, at which the ramp ends.
    public var endRadius: Int

    /// Creates a radial gradient from a stop list.
    public init(gradient: Gradient, center: UnitPoint, startRadius: Int, endRadius: Int) {
        self.gradient = gradient
        self.center = center
        self.startRadius = startRadius
        self.endRadius = endRadius
    }

    /// Creates a radial gradient from evenly-spaced colours.
    public init(colors: [Color], center: UnitPoint, startRadius: Int, endRadius: Int) {
        self.init(
            gradient: Gradient(colors: colors), center: center,
            startRadius: startRadius, endRadius: endRadius)
    }

    /// Creates a radial gradient from positioned stops.
    public init(stops: [Gradient.Stop], center: UnitPoint, startRadius: Int, endRadius: Int) {
        self.init(
            gradient: Gradient(stops: stops), center: center,
            startRadius: startRadius, endRadius: endRadius)
    }

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        .gradient(
            GradientPaint(
                gradient.resolvingStops(with: environment.palette),
                .radial(center: center, startRadius: startRadius, endRadius: endRadius)))
    }
}

// MARK: - The static-member spelling

extension ShapeStyle where Self == RadialGradient {
    /// `.foregroundStyle(.radialGradient(…))`.
    public static func radialGradient(
        _ gradient: Gradient, center: UnitPoint = .center, startRadius: Int, endRadius: Int
    ) -> Self {
        .init(gradient: gradient, center: center, startRadius: startRadius, endRadius: endRadius)
    }

    /// `.radialGradient(colors:center:startRadius:endRadius:)`.
    public static func radialGradient(
        colors: [Color], center: UnitPoint = .center, startRadius: Int, endRadius: Int
    ) -> Self {
        .init(colors: colors, center: center, startRadius: startRadius, endRadius: endRadius)
    }

    /// `.radialGradient(stops:center:startRadius:endRadius:)`.
    public static func radialGradient(
        stops: [Gradient.Stop], center: UnitPoint = .center, startRadius: Int, endRadius: Int
    ) -> Self {
        .init(stops: stops, center: center, startRadius: startRadius, endRadius: endRadius)
    }
}
