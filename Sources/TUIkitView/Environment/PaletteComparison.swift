//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaletteComparison.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

// MARK: - Telling Two Palettes Apart

extension Palette {
    /// Whether `other` draws what this palette draws: compared by VALUE when the
    /// palette is `Equatable`, and by ``Cyclable/id`` alone when it is not.
    ///
    /// Asked wherever something drawn under one frame's palette is kept for a later
    /// one. The id alone used to be the whole question, and it is the wrong one for a
    /// palette edited in place: the Example's Theme page keeps its preset's id while
    /// the colours change under it, so "has the palette changed?" answered no after
    /// every edit, and memoized views went on drawing the colours from before it.
    ///
    /// The id is still asked first. It is the cheap rejection, and for a palette that
    /// is not `Equatable` it is all there is — which is why `Palette`'s documentation
    /// asks such a palette to take a new id whenever its colours change.
    ///
    /// The framework's own wrappers are compared through their derivation (see
    /// ``DerivedPalette``) rather than as values. Neither can be `Equatable` honestly:
    /// each holds its base as an existential that may not be, so its `==` would have
    /// to fall back to the base's id — and `Equatable` is what the render cache's
    /// environment notes trust to mean "draws the same".
    package func isSamePalette(as other: any Palette) -> Bool {
        guard id == other.id else { return false }
        if let derived = self as? any DerivedPalette {
            return derived.isSameDerivation(as: other)
        }
        guard let equatable = self as? any Equatable else { return true }
        return equatable.isEqual(to: other)
    }
}

/// A palette the framework builds over another one, changing only what its own
/// stored fields say: `TintedPalette` (the accent) and ``GroundedPalette`` (the
/// terminal's colours it grounded the base on, which spend the root grounds and
/// re-spell the `Color.default` roles).
///
/// Compared as "the same derivation of the same base". That is exact wherever the
/// base can be compared by value, and falls back to the base's id exactly where the
/// base on its own would.
package protocol DerivedPalette: Palette {
    /// The palette every role this one does not change is read from.
    var base: any Palette { get }

    /// Whether `other` derives the same way — this type's own fields, and nothing
    /// about the two bases, which ``Palette/isSamePalette(as:)`` compares.
    func hasSameDerivation(as other: Self) -> Bool
}

extension DerivedPalette {
    /// The same derivation of the same base; a different wrapper type is not.
    fileprivate func isSameDerivation(as other: any Palette) -> Bool {
        guard let other = other as? Self else { return false }
        return hasSameDerivation(as: other) && base.isSamePalette(as: other.base)
    }
}

/// A palette held so it can be compared with a later one, by
/// ``Palette/isSamePalette(as:)`` — for a key or snapshot that must be `Equatable`
/// and would otherwise have to settle for the id.
package struct ComparablePalette: Equatable {
    package let palette: any Palette

    package init(_ palette: any Palette) {
        self.palette = palette
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.palette.isSamePalette(as: rhs.palette)
    }
}
