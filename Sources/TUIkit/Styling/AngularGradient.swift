//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AngularGradient.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - AngularGradient

/// A ``Gradient`` swept around a centre — the "conic" or colour-wheel one: a
/// cell's colour comes from its *angle* from ``center``, not its distance.
///
/// ```swift
/// Text("◍").foregroundStyle(AngularGradient(colors: [.red, .green, .blue],
///                                           center: .center))
/// ```
///
/// ## Where the angles point
///
/// Zero points at the **trailing** edge and angles increase **clockwise** on
/// screen, because rows grow downward. The default sweep — `startAngle` and
/// `endAngle` both `.zero` — is therefore not a full turn but a degenerate
/// one; ``init(gradient:center:angle:)`` is the full turn.
///
/// Angles are corrected by ``EnvironmentValues/imageCellAspect``, since a cell
/// is about twice as tall as it is wide and 45° should look like the diagonal
/// it names rather than the one the grid would make of it.
///
/// ## Outside the sweep
///
/// A cell whose angle falls outside `startAngle…endAngle` takes **whichever
/// end is angularly nearer** — it does not wrap back through the ramp.
/// Measured against SwiftUI: a `0°…180°` sweep of red→blue stays blue from
/// 180° round to 270°, then is abruptly red again the rest of the way. The
/// seam is real, and it is SwiftUI's.
public struct AngularGradient: ShapeStyle, Equatable, Sendable {
    /// The stops.
    public var gradient: Gradient

    /// Where the sweep is centred, in unit space.
    public var center: UnitPoint

    /// The angle at which the ramp begins.
    public var startAngle: Angle

    /// The angle at which the ramp ends.
    public var endAngle: Angle

    /// Creates an angular gradient from a stop list and a sweep.
    public init(
        gradient: Gradient, center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .zero
    ) {
        self.gradient = gradient
        self.center = center
        self.startAngle = startAngle
        self.endAngle = endAngle
    }

    /// Creates an angular gradient from evenly-spaced colours and a sweep.
    public init(
        colors: [Color], center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .zero
    ) {
        self.init(
            gradient: Gradient(colors: colors), center: center,
            startAngle: startAngle, endAngle: endAngle)
    }

    /// Creates an angular gradient from positioned stops and a sweep.
    public init(
        stops: [Gradient.Stop], center: UnitPoint,
        startAngle: Angle = .zero, endAngle: Angle = .zero
    ) {
        self.init(
            gradient: Gradient(stops: stops), center: center,
            startAngle: startAngle, endAngle: endAngle)
    }

    /// Creates a **full turn**, starting at `angle`.
    ///
    /// The whole ramp fits in one revolution, so the last stop meets the first
    /// at `angle` with a seam — which is what a conic gradient of
    /// non-matching ends looks like in SwiftUI too.
    public init(gradient: Gradient, center: UnitPoint, angle: Angle = .zero) {
        self.init(
            gradient: gradient, center: center, startAngle: angle,
            endAngle: Angle(radians: angle.radians + 2 * .pi))
    }

    /// Creates a full turn from evenly-spaced colours.
    public init(colors: [Color], center: UnitPoint, angle: Angle = .zero) {
        self.init(gradient: Gradient(colors: colors), center: center, angle: angle)
    }

    /// Creates a full turn from positioned stops.
    public init(stops: [Gradient.Stop], center: UnitPoint, angle: Angle = .zero) {
        self.init(gradient: Gradient(stops: stops), center: center, angle: angle)
    }

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        .gradient(
            GradientPaint(
                gradient.resolvingStops(with: environment.palette),
                .angular(center: center, startAngle: startAngle, endAngle: endAngle)))
    }
}

// MARK: - The static-member spelling

extension ShapeStyle where Self == AngularGradient {
    /// `.foregroundStyle(.angularGradient(…))`.
    public static func angularGradient(
        _ gradient: Gradient, center: UnitPoint = .center,
        startAngle: Angle = .zero, endAngle: Angle = .zero
    ) -> Self {
        .init(gradient: gradient, center: center, startAngle: startAngle, endAngle: endAngle)
    }

    /// `.angularGradient(colors:center:startAngle:endAngle:)`.
    public static func angularGradient(
        colors: [Color], center: UnitPoint = .center,
        startAngle: Angle = .zero, endAngle: Angle = .zero
    ) -> Self {
        .init(colors: colors, center: center, startAngle: startAngle, endAngle: endAngle)
    }

    /// `.angularGradient(stops:center:startAngle:endAngle:)`.
    public static func angularGradient(
        stops: [Gradient.Stop], center: UnitPoint = .center,
        startAngle: Angle = .zero, endAngle: Angle = .zero
    ) -> Self {
        .init(stops: stops, center: center, startAngle: startAngle, endAngle: endAngle)
    }

    /// `.conicGradient(…)` — the full-turn spelling.
    public static func conicGradient(
        _ gradient: Gradient, center: UnitPoint = .center, angle: Angle = .zero
    ) -> Self {
        .init(gradient: gradient, center: center, angle: angle)
    }

    /// `.conicGradient(colors:center:angle:)`.
    public static func conicGradient(
        colors: [Color], center: UnitPoint = .center, angle: Angle = .zero
    ) -> Self {
        .init(colors: colors, center: center, angle: angle)
    }

    /// `.conicGradient(stops:center:angle:)`.
    public static func conicGradient(
        stops: [Gradient.Stop], center: UnitPoint = .center, angle: Angle = .zero
    ) -> Self {
        .init(stops: stops, center: center, angle: angle)
    }
}
