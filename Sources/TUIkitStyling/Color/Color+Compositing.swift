//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color+Compositing.swift
//
//  The sRGB transfer function, shared by everything that needs to leave
//  encoded space: WCAG luminance (`Color+Contrast`), the OKLab conversion
//  behind palette downsampling (`Color+Downsampling`), and linear-light
//  alpha compositing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Color {

    /// One encoded sRGB channel decoded to linear light (`0...1`).
    ///
    /// The piecewise IEC 61966-2-1 transfer function. There is exactly one
    /// copy of these constants; `relativeLuminance` and ``oklab(red:green:blue:)``
    /// both decode through here, so the quantiser's metric and the contrast
    /// arithmetic cannot drift apart on what "linear" means.
    package static func linearChannel(_ value: UInt8) -> Double {
        let c = Double(value) / 255.0
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// One linear-light value (`0...1`) encoded back to an sRGB channel.
    ///
    /// The inverse of ``linearChannel(_:)``, with rounding to the nearest
    /// representable byte rather than truncation.
    package static func encodedChannel(_ value: Double) -> UInt8 {
        let clamped = min(1, max(0, value))
        let encoded = clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        return UInt8((encoded * 255).rounded())
    }
}
