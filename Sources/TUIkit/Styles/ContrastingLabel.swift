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
/// One picker for all of them. It was three identical copies, one in each of
/// `_TabViewCore`, `_SwatchGridCore` and `_Color256GridCore`.
enum ContrastingLabel {
    /// Black or white, whichever reads better on `surface`, resolved against
    /// `palette`: Rec. 601 luma above 140 takes black. A surface with no RGB reads
    /// as black, so it takes white.
    static func on(_ surface: Color, palette: any Palette) -> Color {
        let c = surface.resolve(with: palette).rgbComponents ?? (0, 0, 0)
        let luminance = 0.299 * Double(c.red) + 0.587 * Double(c.green) + 0.114 * Double(c.blue)
        return luminance > 140 ? .rgb(0, 0, 0) : .rgb(255, 255, 255)
    }
}
