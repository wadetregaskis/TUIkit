//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Paint.swift
//
//  A style, resolved: the concrete thing a cell is painted with, and the four
//  answers to "given a cell, what is t?".
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - Paint

/// A style, resolved: the concrete thing a cell is painted with.
///
/// Every ``ShapeStyle`` reduces to one of these before anything is drawn, and
/// this — not the style — is what travels in the environment. That is
/// deliberate and load-bearing in two ways:
///
/// - **The render memo.** `RenderCache.noteAppliedEnvironment` asks whether a
///   value `is any Equatable`; an existential answers no, which sets
///   `hasUncomparableEnvironmentValue` and refuses every memo store in that
///   subtree. A concrete `Equatable` enum keeps memoization alive under a
///   styled subtree — an existential would silently turn it off.
/// - **One slot, not two.** A colour and a gradient share
///   ``EnvironmentValues/foregroundStyle``, so a leaf reads one dictionary key
///   however it was styled, and an outer gradient with an inner colour has an
///   unambiguous answer instead of two keys and no rule for ordering them.
public enum Paint: Equatable, Sendable {
    /// One colour, everywhere.
    case color(Color)

    /// A ramp, and the geometry that decides where each cell sits along it.
    case gradient(GradientPaint)
}

extension Paint {
    /// The one colour this paint is, where a gradient cannot go.
    ///
    /// A gradient is accepted where a colour is PAINTED and collapses where a
    /// colour is DERIVED FROM — contrast floors, the button styles' face /
    /// border / label chain, the scrollbar's separation rules. See
    /// ``Gradient/representative``.
    public var representative: Color {
        switch self {
        case .color(let colour): colour
        case .gradient(let paint): paint.gradient.representative
        }
    }

    /// Whether this paint is a single colour — the fast path everything that
    /// does not yet handle a ramp takes.
    public var solid: Color? {
        if case .color(let colour) = self { return colour }
        return nil
    }

    /// Whether nothing in this paint carries alpha.
    ///
    /// Asked of the STOPS rather than of a sampled ramp, because it gates whether
    /// a path that cannot express alpha at all may be taken — a terminal picture,
    /// which has no alpha channel here — and that decision comes before any
    /// sampling. A stop's alpha survives interpolation (`Color.lerp` treats it as
    /// a fourth channel), so opaque stops cannot produce a translucent ramp.
    public var isOpaqueThroughout: Bool {
        switch self {
        case .color(let colour): colour.isOpaque
        case .gradient(let paint): paint.gradient.isOpaqueThroughout
        }
    }
}

// MARK: - A ramp with a shape

/// A ``Gradient`` and the geometry it is drawn with — everything the renderer
/// needs to answer "what colour is this cell?".
///
/// The two halves are separate because they vary independently: the same stops
/// are drawn as a bar, a ring or a wheel, and the same geometry is reused with
/// different stops. A struct rather than more enum payload so that a knob
/// affecting all four geometries — ``ShapeStyle/in(_:)``'s fixed extent, say —
/// is one field rather than four more associated values.
public struct GradientPaint: Equatable, Sendable {
    /// The stops.
    public var gradient: Gradient

    /// Where each cell sits along them.
    public var geometry: GradientGeometry

    /// The size to resolve over, from ``ShapeStyle/in(_:)`` — overriding both
    /// what is being painted and any ``View/gradientExtent(_:)`` around it.
    ///
    /// `nil`, the default, is "whatever this is being painted on", which is
    /// SwiftUI's per-leaf rule.
    public var extent: CellSize?

    /// Creates a paint from stops and a geometry.
    public init(_ gradient: Gradient, _ geometry: GradientGeometry, extent: CellSize? = nil) {
        self.gradient = gradient
        self.geometry = geometry
        self.extent = extent
    }
}

// MARK: - The geometry

/// Where a cell sits along a ramp — the one question the four gradient types
/// answer differently.
///
/// Each case is exactly the parameters of its ``ShapeStyle``, so
/// ``LinearGradient``, ``RadialGradient``, ``EllipticalGradient`` and
/// ``AngularGradient`` are thin: they carry SwiftUI's spelling, and this
/// carries the meaning.
///
/// ## Measured against SwiftUI, not guessed
///
/// Every rule here — and the two deviations — came off pixels rendered by
/// `ImageRenderer`; see `Documentation/Gradients where a colour is accepted.md`
/// §3. The ones nobody guesses right:
///
/// - **`t` clamps at both ends.** Inside ``radial(center:startRadius:endRadius:)``'s
///   start radius every cell is the first stop, and past its end radius every
///   cell is the last. The ramp does not repeat.
/// - **An angle of 0 points at the trailing edge**, and increases *clockwise*
///   on screen, because y grows downward.
/// - **Outside an angular sweep, a cell takes the nearer of the two ends** —
///   not a wrap back through the ramp. A `0°…180°` sweep is blue from 180°
///   round to 270° and then abruptly red again, which is the seam SwiftUI
///   draws.
public enum GradientGeometry: Equatable, Sendable {
    /// A ramp along the line from `from` to `to`, in the unit space of
    /// whatever is being painted.
    case linear(from: UnitPoint, to: UnitPoint)

    /// A ramp outward from `center`, between two radii **in cells**.
    ///
    /// SwiftUI's radii are lengths, which on a square pixel grid makes a
    /// circle. Terminal cells are about twice as tall as they are wide, so a
    /// radius of *n* cells vertically and *n* cells horizontally would draw an
    /// ellipse twice as tall as it is wide. The radius is therefore measured
    /// **along the horizontal axis**, and the vertical extent derived through
    /// ``EnvironmentValues/imageCellAspect`` — so a circle looks like one.
    /// Use ``elliptical(center:startRadiusFraction:endRadiusFraction:)`` when
    /// what is wanted is the shape of the box rather than a circle.
    case radial(center: UnitPoint, startRadius: Int, endRadius: Int)

    /// A ramp outward from `center`, between two radii given as fractions of
    /// the painted rectangle — an ellipse that follows the box's own shape.
    ///
    /// The fractions are of the width horizontally and of the height
    /// vertically, so the default `0 … 0.5` reaches the last stop exactly at
    /// the middle of each edge, whatever shape the box is. No cell-aspect
    /// correction: the box's proportions are the point.
    case elliptical(center: UnitPoint, startRadiusFraction: Double, endRadiusFraction: Double)

    /// A ramp swept around `center` from `startAngle` to `endAngle`.
    ///
    /// Angles are aspect-corrected like ``radial(center:startRadius:endRadius:)``,
    /// so 45° is the diagonal it looks like rather than the one the cell grid
    /// would make of it.
    case angular(center: UnitPoint, startAngle: Angle, endAngle: Angle)
}
