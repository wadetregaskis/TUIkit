//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Animatable.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// A view whose value changes smoothly rather than in one step.
///
/// Conforming says two things: *what* about this view is continuous
/// (``animatableData``), and — implicitly — that the framework may render the
/// view at values it was never given. When a change to a conforming view
/// happens inside ``withAnimation(_:_:)``, the framework does not render the
/// new value; it renders the *old* one, and then a value between old and new on
/// every frame until the animation ends.
///
/// ```swift
/// struct Bar: View, Animatable {
///     var fraction: Double
///
///     // The one continuous thing about this view. Everything else — the
///     // width, the glyphs, the colour — is a function of it.
///     var animatableData: Double {
///         get { fraction }
///         set { fraction = newValue }
///     }
///
///     var body: some View {
///         let filled = Int((Double(width) * fraction).rounded())
///         Text(String(repeating: "█", count: filled))
///     }
/// }
/// ```
///
/// ```swift
/// withAnimation(.easeOut(duration: 0.4)) { progress = 1 }
/// ```
///
/// Note what the terminal does *not* change about this. `body` is re-evaluated
/// per frame, exactly as SwiftUI does for an `Animatable` **view** (it is
/// `Animatable` *modifiers* that SwiftUI can drive without re-evaluating a
/// body, by handing the interpolation to the render server — a terminal has no
/// render server). So the subtree under an animating view is walked once per
/// animation frame, for the animation's duration and no longer. That is
/// affordable for a transient change and is *not* affordable forever, which is
/// why ``Animation/repeatForever(autoreverses:)`` is served differently — see
/// <doc:AnimatingYourOwnView>.
///
/// - Note: The animated value is what the view is *rendered* with; it is not
///   written back to your state. `progress` is 1 the instant the closure
///   returns, and every event handler sees 1. Only the picture lags.
public protocol Animatable {
    /// The type defining the data to animate.
    associatedtype AnimatableData: VectorArithmetic

    /// The data to animate.
    var animatableData: AnimatableData { get set }
}

extension Animatable where AnimatableData == EmptyAnimatableData {
    /// The animatable data of a type that has none.
    ///
    /// Lets a type adopt `Animatable` for the *conditional* half of the
    /// protocol — it wants to know an animation is in flight — without
    /// nominating anything to interpolate.
    public var animatableData: EmptyAnimatableData {
        // `EmptyAnimatableData` has exactly one value, so the setter has
        // nothing to store and the getter cannot be wrong.
        get { EmptyAnimatableData() }
        // swiftlint:disable:next unused_setter_value
        set {}
    }
}

extension Animatable where Self: VectorArithmetic, AnimatableData == Self {
    /// A vector's animatable data is the vector.
    public var animatableData: Self {
        get { self }
        set { self = newValue }
    }
}
