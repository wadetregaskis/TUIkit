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
    public func paint(in environment: EnvironmentValues) -> Paint { .color(self) }
}

/// A bare ``Gradient`` used as a style is a **vertical** linear gradient, top
/// to bottom — measured against SwiftUI, where
/// `Rectangle().fill(Gradient(colors: [.red, .blue]))` is red at the top
/// corners and blue at the bottom ones.
extension Gradient: ShapeStyle {
    public typealias Resolved = Never
    public func paint(in environment: EnvironmentValues) -> Paint {
        .gradient(GradientPaint(self, .linear(from: .top, to: .bottom)))
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
