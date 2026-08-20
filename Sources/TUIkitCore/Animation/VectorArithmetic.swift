//  🖥️ TUIkit — Terminal UI Kit for Swift
//  VectorArithmetic.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// A type that can serve as the animatable data of an animatable type.
///
/// The requirement an animation actually has: to know a start and an end value
/// and be able to produce every value in between. `AdditiveArithmetic` supplies
/// the difference and the sum; ``scale(by:)`` supplies the fraction. Together
/// they are exactly `start + (end - start) × t`, which is what
/// ``interpolated(towards:amount:)`` computes and what every curve in
/// ``Animation`` feeds.
///
/// ``magnitudeSquared`` exists for the same reason it does in SwiftUI: a spring
/// needs to know when it has effectively arrived, and comparing squared
/// magnitudes avoids a square root per sample.
///
/// `Double` and `Float` conform. `Int` does not, and neither do the integer
/// geometry types (`CellSize`, `CellRect`, `EdgeInsets`) — those are
/// ``Animatable`` with *`Double`* animatable data instead, so the interpolation
/// is computed at full precision from the original endpoints and only the final
/// position is rounded onto the cell grid. An eased move keeps its easing that
/// way; it simply dwells longer on the cells it passes through slowly.
public protocol VectorArithmetic: AdditiveArithmetic {
    /// Multiplies each component of this value by `rhs`.
    mutating func scale(by rhs: Double)

    /// The dot-product of this value with itself.
    var magnitudeSquared: Double { get }
}

extension VectorArithmetic {
    /// Returns this value scaled by `rhs`.
    public func scaled(by rhs: Double) -> Self {
        var copy = self
        copy.scale(by: rhs)
        return copy
    }

    /// Interpolates this value towards `other` by `amount`, in place.
    ///
    /// `amount` is not clamped: a spring that overshoots passes values above 1,
    /// and a curve is allowed to.
    public mutating func interpolate(towards other: Self, amount: Double) {
        var delta = other
        delta -= self
        delta.scale(by: amount)
        self += delta
    }

    /// This value interpolated towards `other` by `amount`.
    public func interpolated(towards other: Self, amount: Double) -> Self {
        var copy = self
        copy.interpolate(towards: other, amount: amount)
        return copy
    }
}

// MARK: - Standard conformances

extension Double: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= rhs }
    public var magnitudeSquared: Double { self * self }
}

extension Float: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= Float(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}

// MARK: - EmptyAnimatableData

/// The animatable data of something that has none.
///
/// The `Animatable` conformance a type adopts for its *conditional* animation —
/// it wants a transaction's animation to reach it, but nothing about it
/// interpolates. Every operation is a no-op and its magnitude is always zero,
/// so an animator driving one finishes immediately.
public struct EmptyAnimatableData: VectorArithmetic, Sendable, Equatable {
    /// Creates the one value this type has.
    public init() {}

    public static var zero: Self { Self() }

    public static func += (lhs: inout Self, rhs: Self) {}
    public static func -= (lhs: inout Self, rhs: Self) {}
    public static func + (lhs: Self, rhs: Self) -> Self { Self() }
    public static func - (lhs: Self, rhs: Self) -> Self { Self() }

    public mutating func scale(by rhs: Double) {}

    public var magnitudeSquared: Double { 0 }
}

// MARK: - AnimatablePair

/// Two animatable values animated as one.
///
/// The building block for animatable data with more than one component: a
/// position is `AnimatablePair<Double, Double>`, a position and a size is a
/// pair of pairs. Nesting is how SwiftUI spells it too, and it keeps
/// ``VectorArithmetic`` a two-method protocol rather than a vector library.
public struct AnimatablePair<First, Second>: VectorArithmetic
where First: VectorArithmetic, Second: VectorArithmetic {
    /// The first value.
    public var first: First

    /// The second value.
    public var second: Second

    /// Creates a pair from two animatable values.
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public static var zero: Self { Self(First.zero, Second.zero) }

    public static func += (lhs: inout Self, rhs: Self) {
        lhs.first += rhs.first
        lhs.second += rhs.second
    }

    public static func -= (lhs: inout Self, rhs: Self) {
        lhs.first -= rhs.first
        lhs.second -= rhs.second
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(lhs.first + rhs.first, lhs.second + rhs.second)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        Self(lhs.first - rhs.first, lhs.second - rhs.second)
    }

    public mutating func scale(by rhs: Double) {
        first.scale(by: rhs)
        second.scale(by: rhs)
    }

    public var magnitudeSquared: Double {
        first.magnitudeSquared + second.magnitudeSquared
    }
}

extension AnimatablePair: Equatable where First: Equatable, Second: Equatable {}
extension AnimatablePair: Sendable where First: Sendable, Second: Sendable {}
