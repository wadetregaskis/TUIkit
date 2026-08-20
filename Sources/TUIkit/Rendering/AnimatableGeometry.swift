//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatableGeometry.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Why these are Double when the types are Int
//
// Terminal geometry is whole cells, and every type here stores `Int`. Their
// animatable data is `Double` anyway, and that is the point: the interpolation
// is computed once per frame from the ORIGINAL endpoints — `from + (to − from)
// × t` — so the curve is evaluated at full precision and only the final
// position is rounded onto the grid. An eased move keeps its easing; it simply
// dwells longer on the cells it passes through slowly.
//
// (What would break is an interpolation that ACCUMULATED — `value += step` each
// frame — where rounding compounds. Nothing here does that.)

extension EdgeInsets: Animatable {
    /// The four insets, animated together.
    ///
    /// Nested pairs rather than a four-component type, which is how SwiftUI
    /// spells it too: it keeps ``VectorArithmetic`` a two-method protocol
    /// rather than a vector library.
    public var animatableData: AnimatablePair<
        AnimatablePair<Double, Double>, AnimatablePair<Double, Double>
    > {
        get {
            AnimatablePair(
                AnimatablePair(Double(top), Double(leading)),
                AnimatablePair(Double(bottom), Double(trailing)))
        }
        set {
            top = Int(newValue.first.first.rounded())
            leading = Int(newValue.first.second.rounded())
            bottom = Int(newValue.second.first.rounded())
            trailing = Int(newValue.second.second.rounded())
        }
    }
}

extension UnitPoint: Animatable {
    /// A unit point is already two continuous numbers, so this is a rename.
    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(x, y) }
        set {
            x = newValue.first
            y = newValue.second
        }
    }
}

extension CellSize: Animatable {
    /// Width and height, animated together.
    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(Double(width), Double(height)) }
        set {
            width = Int(newValue.first.rounded())
            height = Int(newValue.second.rounded())
        }
    }
}

extension CellRect: Animatable {
    /// Origin and size, animated together — a rectangle moving and resizing at
    /// once is one animation, not two.
    public var animatableData: AnimatablePair<
        AnimatablePair<Double, Double>, AnimatablePair<Double, Double>
    > {
        get {
            AnimatablePair(
                AnimatablePair(Double(x), Double(y)),
                AnimatablePair(Double(width), Double(height)))
        }
        set {
            x = Int(newValue.first.first.rounded())
            y = Int(newValue.first.second.rounded())
            width = Int(newValue.second.first.rounded())
            height = Int(newValue.second.second.rounded())
        }
    }
}
