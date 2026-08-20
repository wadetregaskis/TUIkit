//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ColorAnimation.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

/// Fades a colour that changed inside ``withAnimation(_:_:)``.
///
/// ## Why colours do not go through `Animatable`
///
/// Every other animated thing here declares ``Animatable`` and lets the
/// framework substitute its value before it renders. A colour cannot: the
/// animatable data would have to be the colour's components, and a TUIkit
/// `Color` may be *semantic* — `.palette.accent` is not a red, a green and a
/// blue until it meets a palette, and a palette is not available where
/// `animatableData` is read. SwiftUI has the same problem and solves it the
/// same way, with an internal resolved-colour type its public `Color` never
/// exposes.
///
/// So a modifier that paints asks *here* instead, at render, where the palette
/// is in the environment. The app-facing API is unchanged — `withAnimation`
/// and `.animation(_:value:)` work on colours exactly as on anything else.
///
/// ## What it costs
///
/// A render pass per frame for the animation's duration, like any other
/// non-`.opacity` animation: a colour reaches the screen through whatever drew
/// it, so there is no single buffer to re-style per phase. For a colour that
/// should move *forever* — a focus pulse, a breathing indicator — use
/// ``AnimatedColor``, which hands the run loop the whole cycle and costs no
/// render passes at all. See <doc:AnimatingYourOwnView>.
enum ColorAnimation {
    /// A colour's animatable data: its resolved red, green and blue.
    ///
    /// Nested pairs because ``VectorArithmetic`` is a two-method protocol; the
    /// components are `Double` so the interpolation happens at full precision
    /// and only the drawn colour is rounded back to bytes.
    typealias Data = AnimatablePair<Double, AnimatablePair<Double, Double>>

    /// The colour to draw for `target` this frame.
    ///
    /// - Parameters:
    ///   - target: What the view tree says the colour is now. Resolved against
    ///     the palette here, so a semantic colour animates between whatever it
    ///     resolves to at each end.
    ///   - owner: The type that paints with it — the same discriminator the
    ///     animation store uses everywhere, so two colour modifiers at one
    ///     identity do not collide.
    ///   - slot: Which of that type's colours this is.
    ///   - context: The render context.
    /// - Returns: `target` unchanged when nothing is moving; otherwise the
    ///   colour partway between where it was and where it is going.
    @MainActor
    static func resolving(
        _ target: Color, owner: Any.Type, slot: Int = 0, context: RenderContext
    ) -> Color {
        let palette = context.environment.palette
        let resolved = target.resolve(with: palette)
        guard let storage = context.stateStorage,
            let components = resolved.rgbComponents
        else { return target }

        let key = AnimationStore.Key(
            identity: context.identity, owner: ObjectIdentifier(owner), slot: slot)
        let wanted = data(components)
        let drawn = storage.animations.value(
            for: key,
            target: wanted,
            animation: context.environment.canAnimate
                ? context.environment.transaction.effectiveAnimation : nil,
            nowNanos: context.environment.frameNowNanos,
            isMeasuring: context.isMeasuring)
        guard drawn != wanted else { return target }

        // The picture is now a function of time, so a value memo must not cache
        // this subtree — it would freeze the fade on its first frame.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        return color(drawn)
    }

    private static func data(_ rgb: (red: UInt8, green: UInt8, blue: UInt8)) -> Data {
        AnimatablePair(Double(rgb.red), AnimatablePair(Double(rgb.green), Double(rgb.blue)))
    }

    /// A colour back from its components, clamped — a spring overshoots, and
    /// 300 is not a channel.
    private static func color(_ data: Data) -> Color {
        Color.rgb(channel(data.first), channel(data.second.first), channel(data.second.second))
    }

    private static func channel(_ value: Double) -> UInt8 {
        UInt8(min(255, max(0, value.rounded())))
    }
}
