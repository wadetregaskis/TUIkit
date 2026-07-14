//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Color+Downsampling.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Public API

extension Color {
    /// Converts this color to the nearest 256-color palette entry.
    ///
    /// - `.standard` and `.bright` already map to palette indices 0–15;
    ///   returned unchanged.
    /// - `.palette256` already in range; returned unchanged.
    /// - `.rgb` is quantized to the nearest 6×6×6 cube color (16–231)
    ///   or grayscale ramp entry (232–255), whichever is closer.
    /// - `.semantic` must be resolved before calling this method.
    public func downsampledToPalette256() -> Color {
        switch value {
        case .standard, .bright, .palette256:
            return self
        case .rgb(let red, let green, let blue):
            let index = Self.nearestPalette256Index(red: red, green: green, blue: blue)
            return .palette(index)
        case .semantic:
            return self
        }
    }

    /// Converts this color to the nearest basic ANSI color (16-color).
    ///
    /// - `.standard` and `.bright` already in range; returned unchanged.
    /// - `.palette256` indices 0–15 map directly to standard/bright;
    ///   indices 16–255 are converted via their RGB representation.
    /// - `.rgb` is matched to the closest of the 16 standard/bright
    ///   ANSI colors using Euclidean distance in RGB space.
    /// - `.semantic` must be resolved before calling this method.
    public func downsampledToANSI16() -> Color {
        switch value {
        case .standard, .bright:
            return self
        case .palette256(let index):
            return Self.palette256ToANSI16(index)
        case .rgb(let red, let green, let blue):
            return Self.rgbToNearestANSI16(red: red, green: green, blue: blue)
        case .semantic:
            return self
        }
    }
}

// MARK: - Private Helpers

extension Color {
    /// The 6 channel levels used by the 256-color RGB cube (indices 16–231).
    fileprivate static let cubeChannelLevels: [UInt8] = [0, 95, 135, 175, 215, 255]

    /// Finds the nearest 256-color palette index for an RGB color.
    ///
    /// "Nearest" is perceptual, not per-channel: candidates (the whole 6×6×6
    /// cube plus the grayscale ramp) are compared in OKLab with the HUE
    /// difference weighted double. The 216-colour cube is coarse in the pale
    /// range, where per-channel rounding shifts hue — Solid Colors' warm
    /// cream #F2DEC9 rounded to pink (255,215,215) instead of the warm
    /// (255,215,175), turning a whole background rosy. Weighting hue keeps a
    /// quantised colour in its own colour family; greys (no chroma) and
    /// saturated colours (a cube point close by) are unaffected.
    ///
    /// Results are memoised — a full-screen render quantises two colours per
    /// cell, but an app only ever uses a few dozen distinct colours.
    fileprivate static func nearestPalette256Index(red: UInt8, green: UInt8, blue: UInt8) -> UInt8 {
        let key = UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
        quantiseCacheLock.lock()
        let cached = quantiseCache[key]
        quantiseCacheLock.unlock()
        if let cached { return cached }

        let target = oklab(red: red, green: green, blue: blue)
        var bestIndex = 16
        var bestDistance = Double.infinity
        // Deliberate linear scan: n=240, memoised below, and OKLab distance has no ordering to exploit — don't "optimise".
        for index in 16...255 {
            let candidate = palette256Lab[index - 16]
            let distance = hueWeightedDistanceSquared(target, candidate)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        quantiseCacheLock.lock()
        if quantiseCache.count > 4096 { quantiseCache.removeAll(keepingCapacity: true) }
        quantiseCache[key] = UInt8(bestIndex)
        quantiseCacheLock.unlock()
        return UInt8(bestIndex)
    }

    /// OKLab coordinates for palette indices 16...255, in index order.
    private static let palette256Lab: [(l: Double, a: Double, b: Double)] = (16...255).map {
        let rgb = palette256ToRGB(UInt8($0))
        return oklab(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private static let quantiseCacheLock = NSLock()
    nonisolated(unsafe) private static var quantiseCache: [UInt32: UInt8] = [:]

    /// Converts sRGB bytes to OKLab.
    private static func oklab(red: UInt8, green: UInt8, blue: UInt8) -> (l: Double, a: Double, b: Double) {
        func linear(_ value: UInt8) -> Double {
            let c = Double(value) / 255.0
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let linearRed = linear(red)
        let linearGreen = linear(green)
        let linearBlue = linear(blue)
        let long = cbrt(
            0.4122214708 * linearRed + 0.5363325363 * linearGreen + 0.0514459929 * linearBlue)
        let medium = cbrt(
            0.2119034982 * linearRed + 0.6806995451 * linearGreen + 0.1073969566 * linearBlue)
        let short = cbrt(
            0.0883024619 * linearRed + 0.2817188376 * linearGreen + 0.6299787005 * linearBlue)
        return (
            l: 0.2104542553 * long + 0.7936177850 * medium - 0.0040720468 * short,
            a: 1.9779984951 * long - 2.4285922050 * medium + 0.4505937099 * short,
            b: 0.0259040371 * long + 0.7827717662 * medium - 0.8086757660 * short
        )
    }

    /// OKLab distance with the lightness/chroma/hue components split and hue
    /// weighted ×2 (à la CIEDE2000's spirit: staying in the right colour
    /// family matters more than exact chroma).
    private static func hueWeightedDistanceSquared(
        _ lhs: (l: Double, a: Double, b: Double),
        _ rhs: (l: Double, a: Double, b: Double)
    ) -> Double {
        let deltaL = lhs.l - rhs.l
        let chromaL = (lhs.a * lhs.a + lhs.b * lhs.b).squareRoot()
        let chromaR = (rhs.a * rhs.a + rhs.b * rhs.b).squareRoot()
        let deltaC = chromaL - chromaR
        let deltaA = lhs.a - rhs.a
        let deltaB = lhs.b - rhs.b
        // Standard decomposition: ΔH² = Δa² + Δb² − ΔC² (tangential part).
        let deltaH2 = max(0, deltaA * deltaA + deltaB * deltaB - deltaC * deltaC)
        return deltaL * deltaL + deltaC * deltaC + 4 * deltaH2
    }

    /// Squared Euclidean distance between two RGB colors.

    fileprivate static func rgbDistanceSquared(
        _ colourA: (UInt8, UInt8, UInt8),
        _ colourB: (UInt8, UInt8, UInt8)
    ) -> Int {
        let deltaRed = Int(colourA.0) - Int(colourB.0)
        let deltaGreen = Int(colourA.1) - Int(colourB.1)
        let deltaBlue = Int(colourA.2) - Int(colourB.2)

        return (deltaRed * deltaRed) + (deltaGreen * deltaGreen) + (deltaBlue * deltaBlue)
    }

    /// Converts a 256-color palette index to the nearest ANSI 16-color.
    fileprivate static func palette256ToANSI16(_ index: UInt8) -> Color {
        switch index {
        case 0...7:
            guard let ansi = ANSIColor(rawValue: index) else { return .white }
            return Color(value: .standard(ansi))
        case 8...15:
            guard let ansi = ANSIColor(rawValue: index - 8) else { return .brightWhite }
            return Color(value: .bright(ansi))
        default:
            let rgb = palette256ToRGB(index)
            return rgbToNearestANSI16(red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
    }

    /// All 16 ANSI colors with their RGB values for nearest-neighbor matching.
    fileprivate static let ansi16Table: [(color: Color, red: UInt8, green: UInt8, blue: UInt8)] = {
        var table: [(Color, UInt8, UInt8, UInt8)] = []

        // Standard colors (indices 0–7)
        for raw: UInt8 in 0...7 where raw != 9 {
            guard let ansi = ANSIColor(rawValue: raw) else { continue }
            let rgb = ansi.rgbValues
            table.append((Color(value: .standard(ansi)), rgb.red, rgb.green, rgb.blue))
        }

        // Bright colors (indices 8–15)
        for raw: UInt8 in 0...7 where raw != 9 {
            guard let ansi = ANSIColor(rawValue: raw) else { continue }
            let rgb = ansi.brightRGBValues
            table.append((Color(value: .bright(ansi)), rgb.red, rgb.green, rgb.blue))
        }

        return table
    }()

    /// Finds the nearest ANSI 16-color for an RGB value.
    fileprivate static func rgbToNearestANSI16(red: UInt8, green: UInt8, blue: UInt8) -> Color {
        var bestColor = Color.white
        var bestDistance = Int.max

        // Deliberate linear scan: n=16 is trivially cheap and beats anything cleverer — don't "optimise".
        for entry in ansi16Table {
            let distance = rgbDistanceSquared(
                (red, green, blue),
                (entry.red, entry.green, entry.blue)
            )
            if distance < bestDistance {
                bestDistance = distance
                bestColor = entry.color
            }
        }

        return bestColor
    }
}
