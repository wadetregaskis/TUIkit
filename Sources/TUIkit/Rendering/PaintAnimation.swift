//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaintAnimation.swift
//
//  Fading a whole paint — a colour, or a ramp — that changed inside
//  `withAnimation`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

/// Moves a ``Paint`` that changed inside ``withAnimation(_:_:)`` toward its new
/// value instead of jumping to it.
///
/// ## What a ramp animates as
///
/// Not as one value. A gradient is a handful of independent quantities — each
/// stop's colour, each stop's position, and the geometry's four numbers — and
/// each of them animates **on its own store entry**, exactly as a colour does.
///
/// That is the whole design, and everything else falls out of it:
///
/// - **A ramp of a different length still works.** Growing a two-stop ramp into
///   a five-stop one animates the two that were already there and shows the
///   three that were not at their final colours, because the store's rule for a
///   value it has never seen is that an appearance is not a change. There is no
///   "how does a two-stop ramp become a five-stop one" to answer, which was the
///   question that kept this unbuilt.
/// - **Semantic colours work**, because ``ColorAnimation`` already resolves
///   them against the palette at the moment it is asked.
/// - **A stop that slides, slides.** A location is a `Double`, and the store is
///   generic over `VectorArithmetic`.
///
/// ## What snaps, and why
///
/// A change of KIND — a colour becoming a ramp, a linear ramp becoming a radial
/// one — snaps. The two ends have nothing in common to interpolate: the four
/// numbers a linear geometry carries are two points, and the four a radial one
/// carries are a centre and two radii, so moving between them would interpolate
/// a radius toward an ordinate. Each geometry gets its own slot range, so the
/// store sees a change of kind as a value it has never seen, and shows it.
///
/// The extent named by ``ShapeStyle/in(_:)`` snaps too: it is a statement about
/// what the ramp is measured against rather than about the ramp.
enum PaintAnimation {
    /// The paint to draw for `target` this frame.
    ///
    /// - Parameters:
    ///   - target: What the view tree says the paint is now.
    ///   - owner: The type that paints with it — the discriminator the
    ///     animation store uses everywhere, so two painting modifiers at one
    ///     identity do not collide.
    ///   - context: The render context.
    /// - Returns: `target` unchanged when nothing is moving, otherwise the
    ///   paint partway between where it was and where it is going.
    @MainActor
    static func resolving(_ target: Paint, owner: Any.Type, context: RenderContext) -> Paint {
        switch target {
        case .color(let colour):
            return .color(ColorAnimation.resolving(colour, owner: owner, context: context))
        case .gradient(let ramped):
            return .gradient(resolving(ramped, owner: owner, context: context))
        }
    }

    /// A ramp with every stop — and the geometry — moved to where it is this
    /// frame.
    @MainActor
    private static func resolving(
        _ target: GradientPaint, owner: Any.Type, context: RenderContext
    ) -> GradientPaint {
        var moved = target
        // The STOPS are replaced, not the gradient: rebuilding it with
        // `Gradient(stops:)` would drop everything else the ramp carries — the
        // colour space, today — so a perceptual ramp would blend in `.device`
        // for the length of the animation and snap back at the end.
        moved.gradient.stops = target.gradient.stops.enumerated().map { index, stop in
            Gradient.Stop(
                color: ColorAnimation.resolving(
                    stop.color, owner: owner, slot: Slot.stopColour(index), context: context),
                location: scalar(
                    stop.location, owner: owner, slot: Slot.stopLocation(index),
                    context: context))
        }
        moved.geometry = resolving(target.geometry, owner: owner, context: context)
        return moved
    }

    /// The geometry's four numbers, moved.
    ///
    /// Every case carries exactly four, which is a coincidence worth NOT
    /// relying on: each gets its own slot range so a case that replaces another
    /// starts afresh rather than interpolating a radius toward an ordinate.
    @MainActor
    private static func resolving(
        _ target: GradientGeometry, owner: Any.Type, context: RenderContext
    ) -> GradientGeometry {
        @MainActor
        func moved(_ value: Double, _ kind: Int, _ component: Int) -> Double {
            scalar(value, owner: owner, slot: Slot.geometry(kind, component), context: context)
        }
        switch target {
        case .linear(let from, let to):
            return .linear(
                from: UnitPoint(x: moved(from.x, 0, 0), y: moved(from.y, 0, 1)),
                to: UnitPoint(x: moved(to.x, 0, 2), y: moved(to.y, 0, 3)))
        case .radial(let centre, let startRadius, let endRadius):
            return .radial(
                center: UnitPoint(x: moved(centre.x, 1, 0), y: moved(centre.y, 1, 1)),
                // Rounded back, because a radius here is a count of cells.
                startRadius: Int(moved(Double(startRadius), 1, 2).rounded()),
                endRadius: Int(moved(Double(endRadius), 1, 3).rounded()))
        case .elliptical(let centre, let startFraction, let endFraction):
            return .elliptical(
                center: UnitPoint(x: moved(centre.x, 2, 0), y: moved(centre.y, 2, 1)),
                startRadiusFraction: moved(startFraction, 2, 2),
                endRadiusFraction: moved(endFraction, 2, 3))
        case .angular(let centre, let startAngle, let endAngle):
            return .angular(
                center: UnitPoint(x: moved(centre.x, 3, 0), y: moved(centre.y, 3, 1)),
                startAngle: .radians(moved(startAngle.radians, 3, 2)),
                endAngle: .radians(moved(endAngle.radians, 3, 3)))
        }
    }

    /// One number, moved — the store lookup ``ColorAnimation`` makes for a
    /// colour, made for a scalar.
    @MainActor
    private static func scalar(
        _ target: Double, owner: Any.Type, slot: Int, context: RenderContext
    ) -> Double {
        guard let storage = context.stateStorage else { return target }
        let drawn = storage.animations.value(
            for: AnimationStore.Key(
                identity: context.identity, owner: ObjectIdentifier(owner), slot: slot),
            target: target,
            animation: context.environment.canAnimate
                ? context.environment.transaction.effectiveAnimation : nil,
            nowNanos: context.environment.frameNowNanos,
            isMeasuring: context.isMeasuring)
        guard drawn != target else { return target }
        // The picture is now a function of time, so a value memo must not cache
        // this subtree — it would freeze the movement on its first frame.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        return drawn
    }

    /// Where each of a ramp's quantities lives in the store's slot space.
    ///
    /// Slot 0 is left to ``ColorAnimation``'s flat colour, so a paint that
    /// changes from a colour to a ramp snaps whole rather than half-fading its
    /// first stop out of the colour that was there.
    private enum Slot {
        static func stopColour(_ index: Int) -> Int { 1 + 2 * index }
        static func stopLocation(_ index: Int) -> Int { 2 + 2 * index }
        /// Negative, so no number of stops can reach it.
        static func geometry(_ kind: Int, _ component: Int) -> Int { -1 - (kind * 4 + component) }
    }
}
