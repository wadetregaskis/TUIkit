//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LinearGradient.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - LinearGradient

/// A ``Gradient`` given a direction: the ramp runs along the line from
/// ``startPoint`` to ``endPoint``, in the unit space of whatever is painted.
///
/// SwiftUI's type and SwiftUI's three initialisers, unchanged — ``UnitPoint``
/// is already TUIkit's with all ten of SwiftUI's constants, so this is
/// source-identical rather than merely similar:
///
/// ```swift
/// .foregroundStyle(LinearGradient(colors: [.red, .blue],
///                                 startPoint: .leading, endPoint: .trailing))
/// ```
///
/// ## In a cell grid
///
/// `t` at a cell is that cell's centre projected onto the start→end line. Cells
/// are about twice as tall as they are wide, so anything not axis-aligned needs
/// the cell aspect to come out looking like the angle it names — the same
/// correction ``EnvironmentValues/imageCellAspect`` exists for. Axis-aligned
/// gradients (`.leading`→`.trailing`, `.top`→`.bottom`) need no correction and
/// are what almost everyone writes.
///
/// ## What SwiftUI hides and this does not
///
/// SwiftUI keeps the three stored properties `package`, so a `LinearGradient`
/// is write-only to its callers. TUIkit exposes them: a terminal app writing
/// its own `Renderable` has to be able to ask what it was handed. Additive, so
/// nothing that compiles against SwiftUI behaves differently here.
public struct LinearGradient: ShapeStyle, Equatable, Sendable {
    /// The stops.
    public var gradient: Gradient

    /// Where `t = 0` sits, in unit space.
    public var startPoint: UnitPoint

    /// Where `t = 1` sits, in unit space.
    public var endPoint: UnitPoint

    /// Creates a linear gradient from a stop list and a direction.
    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    /// Creates a linear gradient from evenly-spaced colours.
    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }

    /// Creates a linear gradient from positioned stops.
    public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
    }

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        .gradient(
            GradientPaint(
                gradient.resolvingStops(with: environment.palette),
                .linear(from: startPoint, to: endPoint)))
    }
}

// MARK: - The static-member spelling

extension ShapeStyle where Self == LinearGradient {
    /// `.foregroundStyle(.linearGradient(…))` — the spelling most SwiftUI
    /// source actually uses, and the reason the protocol exists rather than a
    /// pile of overloads: a static member on `ShapeStyle where Self == …` has
    /// nowhere to live without it.
    public static func linearGradient(
        _ gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint
    ) -> Self {
        .init(gradient: gradient, startPoint: startPoint, endPoint: endPoint)
    }

    /// `.linearGradient(colors:startPoint:endPoint:)`.
    public static func linearGradient(
        colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint
    ) -> Self {
        .init(colors: colors, startPoint: startPoint, endPoint: endPoint)
    }

    /// `.linearGradient(stops:startPoint:endPoint:)`.
    public static func linearGradient(
        stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint
    ) -> Self {
        .init(stops: stops, startPoint: startPoint, endPoint: endPoint)
    }
}
