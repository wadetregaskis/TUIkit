//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContrastingLabel.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The colour a built-in view draws a label or a mark in on a surface it did not
/// choose: the active tab chip's resting label, and the check mark and index
/// numbers on a colour swatch.
///
/// The palette's readable ink for that surface, so the theme decides it, as it
/// already decides the label on a colour swatch button. It was black or white, in
/// three identical copies, one in each of `_TabViewCore`, `_SwatchGridCore` and
/// `_Color256GridCore`.
enum ContrastingLabel {
    /// `readableText(on:)` for `surface`, resolved against `palette`, spent over the
    /// surface, then floored at `ViewConstants.labelContrastFloor` as drawn.
    ///
    /// Spent, because a palette's foreground or background can be translucent, and
    /// the active tab chip breathes from this colour to a loud end that is spent:
    /// two ends that disagree about alpha cannot share one claim. Floored after the
    /// spend, because the floor reads RGB, not alpha; and as drawn, because a
    /// 256-colour terminal moves the surface as well as the label.
    static func on(_ surface: Color, palette: any Palette) -> Color {
        let resolved = surface.resolve(with: palette)
        return palette.readableText(on: resolved).resolve(with: palette)
            .spendingAlpha(over: resolved)
            .ensuringRenderedContrast(atLeast: ViewConstants.labelContrastFloor, against: resolved)
    }
}
