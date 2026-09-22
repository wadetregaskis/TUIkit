//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ExistentialEquality.swift
//
//  Comparing a value against one held as `any Equatable`.
//
//  Split out of `RenderCache.swift`, which is where it was written and where it
//  is no longer about anything: three callers in two modules ask this question
//  and only one of them is a cache.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Equatable {
    /// Compares against a type-erased value, `false` if it is a different type.
    ///
    /// The standard opening move for comparing two `any Equatable`s: open one
    /// existential so `Self` is concrete, then downcast the other to it.
    ///
    /// Package-wide rather than file-private because two more callers ask the
    /// same question of a value they hold as an existential:
    /// `Palette.isSamePalette(as:)` here, and `ThemeModifier.ComparableStyle` in
    /// `TUIkit`, of a control style.
    package func isEqual(to other: Any) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}
