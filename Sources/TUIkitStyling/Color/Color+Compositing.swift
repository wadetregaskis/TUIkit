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

    /// This colour composited at `opacity` over `surface`, in **linear
    /// light** — physical alpha blending.
    ///
    /// The distinction from ``opacity(_:over:)`` is the space the mix happens
    /// in, and each has its job. That method interpolates the encoded sRGB
    /// components, which is the right tool for deriving *styles* — a "30%
    /// strength" secondary label, a dim border — because every palette the
    /// framework derives was tuned by eye in encoded space, and re-deriving
    /// them through different arithmetic would re-tint the whole system.
    /// Simulating a translucent layer is a different question with a physical
    /// answer: light adds linearly, and mixing encoded bytes understates it —
    /// halfway between white and black lands at 22% of white's light rather
    /// than half — so an encoded-space fade spends most of its range darker
    /// than the light it stands for and pops at the end.
    ///
    /// - Parameters:
    ///   - opacity: The weight of this colour (0–1; clamped).
    ///   - surface: What is underneath.
    /// - Returns: The composite, or `self` if either side is semantic.
    public func compositing(_ opacity: Double, over surface: Color) -> Color {
        guard let source = rgbComponents, let behind = surface.rgbComponents else { return self }
        let alpha = min(1, max(0, opacity))
        func channel(_ over: UInt8, _ under: UInt8) -> UInt8 {
            Self.encodedChannel(
                alpha * Self.linearChannel(over) + (1 - alpha) * Self.linearChannel(under))
        }
        return .rgb(
            channel(source.red, behind.red),
            channel(source.green, behind.green),
            channel(source.blue, behind.blue))
    }
}
