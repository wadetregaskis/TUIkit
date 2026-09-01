//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EllipticalGradient.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - EllipticalGradient

/// A ``Gradient`` drawn outward from a centre in the *shape of the box*: the
/// radii are fractions of what is being painted, so the ramp reaches its last
/// stop at the middle of each edge whatever proportions that box has.
///
/// ```swift
/// Text("glow").background(EllipticalGradient(colors: [.white, .black]))
/// ```
///
/// The twin of ``RadialGradient``, and the difference is worth stating: a
/// radial gradient's radii are *cells* and it draws a circle (with the cell
/// aspect corrected for); an elliptical gradient's radii are *fractions* and it
/// draws the box's own ellipse. Neither needs the cell aspect here — the box's
/// proportions are the whole point.
///
/// Source-identical to SwiftUI, whose fractions are already unit-space.
public struct EllipticalGradient: ShapeStyle, Equatable, Sendable {
    /// The stops.
    public var gradient: Gradient

    /// Where the rings are centred, in unit space.
    public var center: UnitPoint

    /// The fraction of the painted rectangle at which the ramp begins.
    public var startRadiusFraction: Double

    /// The fraction of the painted rectangle at which the ramp ends. The
    /// default `0.5` is the middle of each edge.
    public var endRadiusFraction: Double

    /// Creates an elliptical gradient from a stop list.
    public init(
        gradient: Gradient, center: UnitPoint = .center,
        startRadiusFraction: Double = 0, endRadiusFraction: Double = 0.5
    ) {
        self.gradient = gradient
        self.center = center
        self.startRadiusFraction = startRadiusFraction
        self.endRadiusFraction = endRadiusFraction
    }

    /// Creates an elliptical gradient from evenly-spaced colours.
    public init(
        colors: [Color], center: UnitPoint = .center,
        startRadiusFraction: Double = 0, endRadiusFraction: Double = 0.5
    ) {
        self.init(
            gradient: Gradient(colors: colors), center: center,
            startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
    }

    /// Creates an elliptical gradient from positioned stops.
    public init(
        stops: [Gradient.Stop], center: UnitPoint = .center,
        startRadiusFraction: Double = 0, endRadiusFraction: Double = 0.5
    ) {
        self.init(
            gradient: Gradient(stops: stops), center: center,
            startRadiusFraction: startRadiusFraction, endRadiusFraction: endRadiusFraction)
    }

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        .gradient(
            GradientPaint(
                gradient.resolvingStops(with: environment.palette),
                .elliptical(
                    center: center, startRadiusFraction: startRadiusFraction,
                    endRadiusFraction: endRadiusFraction)))
    }
}

// MARK: - The static-member spelling

extension ShapeStyle where Self == EllipticalGradient {
    /// `.foregroundStyle(.ellipticalGradient(…))`.
    public static func ellipticalGradient(
        _ gradient: Gradient, center: UnitPoint = .center,
        startRadiusFraction: Double = 0, endRadiusFraction: Double = 0.5
    ) -> Self {
        .init(
            gradient: gradient, center: center, startRadiusFraction: startRadiusFraction,
            endRadiusFraction: endRadiusFraction)
    }

    /// `.ellipticalGradient(colors:center:startRadiusFraction:endRadiusFraction:)`.
    public static func ellipticalGradient(
        colors: [Color], center: UnitPoint = .center,
        startRadiusFraction: Double = 0, endRadiusFraction: Double = 0.5
    ) -> Self {
        .init(
            colors: colors, center: center, startRadiusFraction: startRadiusFraction,
            endRadiusFraction: endRadiusFraction)
    }

    /// `.ellipticalGradient(stops:center:startRadiusFraction:endRadiusFraction:)`.
    public static func ellipticalGradient(
        stops: [Gradient.Stop], center: UnitPoint = .center,
        startRadiusFraction: Double = 0, endRadiusFraction: Double = 0.5
    ) -> Self {
        .init(
            stops: stops, center: center, startRadiusFraction: startRadiusFraction,
            endRadiusFraction: endRadiusFraction)
    }
}
