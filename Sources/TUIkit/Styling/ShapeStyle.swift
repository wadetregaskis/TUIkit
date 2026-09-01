//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShapeStyle.swift
//
//  What a thing is painted with: SwiftUI's protocol, narrowed to the half a
//  terminal can honour. The concrete answer it resolves to is `Paint`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - ShapeStyle

/// How a view's content is painted — SwiftUI's protocol, restricted to the
/// part a terminal can answer.
///
/// Only the modern conformance point is here: ``resolve(in:)`` and its
/// `Resolved` associated type, which have been the public way to write a
/// custom style since macOS 14. SwiftUI's three underscored requirements
/// (`_apply`, `_makeView`) are omitted entirely, because they are over types
/// that exist only inside SwiftUI and nothing outside it can call them.
///
/// ```swift
/// struct Attention: ShapeStyle {
///     func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
///         environment.isEnabled ? Color.palette.accent : Color.palette.foregroundTertiary
///     }
/// }
/// ```
///
/// ## What deliberately does not exist
///
/// `Material`, `Shader` and the rest of SwiftUI's styles are absent as
/// **types**, which is what makes `.foregroundStyle(.thickMaterial)` fail to
/// compile rather than compile and do nothing. The protocol is not what
/// decides that; the types are.
public protocol ShapeStyle: Sendable {

    /// What this style resolves to. Defaults to `Never` for a style that is
    /// already primitive — a colour, a gradient — exactly as in SwiftUI.
    associatedtype Resolved: ShapeStyle = Never

    /// This style, resolved against the environment it is being drawn in.
    func resolve(in environment: EnvironmentValues) -> Resolved

    /// The concrete paint this style is.
    ///
    /// SwiftUI has no equivalent — it reaches the same answer through the
    /// underscored `_apply` requirements, which are over types that exist only
    /// inside it. A style written the SwiftUI way implements ``resolve(in:)``
    /// and inherits this; a primitive answers it directly.
    func paint(in environment: EnvironmentValues) -> Paint
}

extension ShapeStyle {
    /// Resolve one step, then ask again. Terminates at a primitive style,
    /// which answers directly.
    public func paint(in environment: EnvironmentValues) -> Paint {
        resolve(in: environment).paint(in: environment)
    }
}

extension ShapeStyle where Resolved == Never {
    /// A primitive style resolves to nothing further — the same shape SwiftUI
    /// gives it, and it is never reached, because every primitive answers
    /// ``paint(in:)`` directly.
    public func resolve(in environment: EnvironmentValues) -> Never {
        fatalError("\(Self.self) is a primitive style: it must answer paint(in:) itself")
    }

    /// The floor for a conformance that supplies neither: the environment's own
    /// ink.
    ///
    /// SwiftUI traps here. A terminal app should not die because somebody wrote
    /// an empty conformance, and painting in the colour the text would have had
    /// anyway is the degradation that says least.
    public func paint(in environment: EnvironmentValues) -> Paint {
        .color(environment.palette.foreground)
    }
}

extension Never: ShapeStyle {
    public typealias Resolved = Never
    public func paint(in environment: EnvironmentValues) -> Paint { switch self {} }
}

// MARK: - The primitives

extension Color: ShapeStyle {
    public typealias Resolved = Never
    public func paint(in environment: EnvironmentValues) -> Paint {
        .color(resolve(with: environment.palette))
    }
}

/// A bare ``Gradient`` used as a style is a **vertical** linear gradient, top
/// to bottom — measured against SwiftUI, where
/// `Rectangle().fill(Gradient(colors: [.red, .blue]))` is red at the top
/// corners and blue at the bottom ones.
extension Gradient: ShapeStyle {
    public typealias Resolved = Never
    public func paint(in environment: EnvironmentValues) -> Paint {
        .gradient(
            GradientPaint(
                resolvingStops(with: environment.palette), .linear(from: .top, to: .bottom)))
    }
}

// MARK: - Modifying a style

extension ShapeStyle {
    /// This style at `opacity`, blended toward the surface it will draw on.
    ///
    /// A terminal cell has no alpha channel, so this is a mix rather than a
    /// composite: every colour the style resolves to — each stop of a gradient,
    /// not merely its ends — is blended toward
    /// ``Palette/background``, which is the surface a styled view draws on
    /// unless something has painted over it. Same shape as
    /// ``Color/opacity(_:over:)``, and the same reason: mixing toward black
    /// instead (what ``Color/opacity(_:)`` does) turns every "dim" into a smudge
    /// on a light palette.
    ///
    /// Where the surface is genuinely not the page — a label inside a coloured
    /// panel — the answer is approximate, and the exact one is
    /// ``View/opacity(_:)``, which composites the rendered cells against what
    /// they actually land on. SwiftUI's `ShapeStyle.opacity(_:)` does not
    /// composite either; it multiplies alpha and lets the drawing sort it out.
    ///
    /// ``Color`` has an `opacity(_:)` of its own returning a `Color`, and a
    /// member on the concrete type beats a protocol extension, so
    /// `.red.opacity(0.5)` is that one — as it is in SwiftUI, where `Color`
    /// shadows `ShapeStyle` identically. It mixes toward black, which on the
    /// dark palettes this framework ships is the same answer as mixing toward
    /// their background; the two part company only on a light one.
    ///
    /// - Parameter opacity: How much of the style survives, `0…1`.
    public func opacity(_ opacity: Double) -> some ShapeStyle {
        _OpacityShapeStyle(base: self, opacity: opacity)
    }

    /// This style resolved over a rectangle of `rect`'s size, whatever the
    /// thing being painted actually measures.
    ///
    /// It fixes the ramp's **scale**, not its **origin**: every leaf still
    /// anchors the ramp at itself, so three stacked rows under a vertical
    /// gradient `.in(_:)` a tall rect all render alike. That is measured
    /// SwiftUI behaviour, not a simplification — see
    /// `Documentation/Gradients where a colour is accepted.md` §4, where it is
    /// why `.in(_:)` cannot express "one ramp spanning a set of views".
    /// ``View/gradientExtent(_:)`` is the modifier that can, and it wins over
    /// this one because it names an origin as well as a size.
    ///
    /// The rectangle's own origin is therefore unused. It is a `CellRect` for
    /// SwiftUI's spelling, and because a caller usually has one to hand from a
    /// ``GeometryProxy``.
    ///
    /// - Parameter rect: The rectangle to resolve in. Only its size is read.
    public func `in`(_ rect: CellRect) -> some ShapeStyle {
        _FixedExtentShapeStyle(base: self, extent: CellSize(width: rect.width, height: rect.height))
    }
}

/// ``ShapeStyle/opacity(_:)``'s style. Resolves its base and mixes what comes
/// back, so it composes with everything — including a gradient, whose every
/// stop is mixed rather than only the two the eye lands on.
struct _OpacityShapeStyle<Base: ShapeStyle>: ShapeStyle {
    let base: Base
    let opacity: Double

    typealias Resolved = Never

    func paint(in environment: EnvironmentValues) -> Paint {
        let palette = environment.palette
        let surface = palette.background
        func mixed(_ colour: Color) -> Color {
            colour.resolve(with: palette).opacity(opacity, over: surface)
        }
        switch base.paint(in: environment) {
        case .color(let colour):
            return .color(mixed(colour))
        case .gradient(var ramp):
            // The stops, not the gradient — see the twin in `PaintAnimation`:
            // replacing the whole value drops whatever else it carries, which
            // is how a faded perceptual ramp would come back `.device`.
            ramp.gradient.stops = ramp.gradient.stops.map {
                Gradient.Stop(color: mixed($0.color), location: $0.location)
            }
            return .gradient(ramp)
        }
    }
}

/// ``ShapeStyle/in(_:)``'s style. A colour has no extent to fix, so this is a
/// gradient's modifier that happens to be spelled on every style — as it is in
/// SwiftUI.
struct _FixedExtentShapeStyle<Base: ShapeStyle>: ShapeStyle {
    let base: Base
    let extent: CellSize

    typealias Resolved = Never

    func paint(in environment: EnvironmentValues) -> Paint {
        let paint = base.paint(in: environment)
        guard case .gradient(var ramp) = paint else { return paint }
        ramp.extent = extent
        return .gradient(ramp)
    }
}

// MARK: - Erasure

/// A type-erased ``ShapeStyle`` — the idiom for choosing a style at runtime:
///
/// ```swift
/// .foregroundStyle(urgent ? AnyShapeStyle(.red) : AnyShapeStyle(warmGradient))
/// ```
///
/// Erased to the *resolution*, not to a box of the style: what a caller can do
/// with a `ShapeStyle` is ask what it paints, so that is all this keeps.
public struct AnyShapeStyle: ShapeStyle {
    public typealias Resolved = Never

    private let resolved: @Sendable (EnvironmentValues) -> Paint

    public init<S: ShapeStyle>(_ style: S) {
        resolved = { style.paint(in: $0) }
    }

    public func paint(in environment: EnvironmentValues) -> Paint { resolved(environment) }
}
