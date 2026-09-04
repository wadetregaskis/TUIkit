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
    /// A table, because the domain is 256 values and the function is a `pow`.
    ///
    /// Bit-exact by construction — the same expression, over every input it can
    /// be given — and the difference is not marginal on the paths that reach
    /// here per PIXEL rather than per cell. `oklab(red:green:blue:)` decodes
    /// three channels, so quantising a megapixel image to a palette was three
    /// million `pow` calls before it started measuring distances.
    @inlinable
    package static func linearChannel(_ value: UInt8) -> Double {
        linearChannelTable[Int(value)]
    }

    /// `@usableFromInline` so the inlinable accessor above can reach it.
    @usableFromInline
    internal static let linearChannelTable: [Double] = (0...255).map { byte in
        let c = Double(byte) / 255.0
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// One linear-light value (`0...1`) encoded back to an sRGB channel.
    ///
    /// The inverse of ``linearChannel(_:)``, with rounding to the nearest
    /// representable byte rather than truncation.
    @inlinable
    package static func encodedChannel(_ value: Double) -> UInt8 {
        let clamped = min(1, max(0, value))
        let encoded = clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        return UInt8((encoded * 255).rounded())
    }

    /// This colour composited at `opacity` over `surface`, in **linear
    /// light** — physical alpha blending.
    ///
    /// Correct, and **not what the framework fades with**. The distinction from
    /// ``opacity(_:over:)`` is the space the mix happens in, and the two answer
    /// different questions. This one answers *what light would actually leave a
    /// translucent layer*: light adds linearly, and mixing encoded bytes
    /// understates it — halfway between white and black carries 22% of white's
    /// light rather than half.
    ///
    /// What a fade needs is the other question — *what does a person see change*
    /// — and the two diverge sharply, because perceived lightness goes roughly
    /// as the cube root of luminance. In linear light `dL/d(opacity)` is 7.52 at
    /// 0 and 0.25 at 1: a **22×** sensitivity ratio, almost all of the visible
    /// movement crammed into the first few percent of alpha. Encoded sRGB is
    /// near enough perceptually uniform (ratio 1.66×), which is why it is the
    /// space every 8-bit compositor mixes in, and what SwiftUI is measured to
    /// use. `View.opacity(_:)`, the transition dissolve and every style
    /// derivation therefore go through ``opacity(_:over:)``; see
    /// `Documentation/Opacity as composition.md`, rule 5, for the numbers and
    /// the reversal.
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
