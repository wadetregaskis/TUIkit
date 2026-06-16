//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SwatchPalettes.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitStyling

/// Curated colour sets shown as swatch grids in ``ColorPickerPanel`` (and usable
/// anywhere a fixed palette is handy). Each is a plain `[Color]` of concrete
/// colours, fed to ``_SwatchGridCore``.
enum SwatchPalettes {
    /// A 32-step black→white greyscale ramp, evenly spaced across 0…255.
    static let greyscale: [Color] = (0..<32).map { step in
        let value = UInt8((Double(step) * 255 / 31).rounded())
        return .rgb(value, value, value)
    }
}
