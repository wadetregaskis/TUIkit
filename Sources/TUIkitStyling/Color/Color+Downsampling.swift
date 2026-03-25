//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Color+Downsampling.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Public API

public extension Color {
    /// Converts this color to the nearest 256-color palette entry.
    ///
    /// - `.standard` and `.bright` already map to palette indices 0–15;
    ///   returned unchanged.
    /// - `.palette256` already in range; returned unchanged.
    /// - `.rgb` is quantized to the nearest 6×6×6 cube color (16–231)
    ///   or grayscale ramp entry (232–255), whichever is closer.
    /// - `.semantic` must be resolved before calling this method.
    func downsampledToPalette256() -> Color {
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
    func downsampledToANSI16() -> Color {
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

private extension Color {
    /// The 6 channel levels used by the 256-color RGB cube (indices 16–231).
    static let cubeChannelLevels: [UInt8] = [0, 95, 135, 175, 215, 255]

    /// Finds the nearest 256-color palette index for an RGB color.
    ///
    /// Compares the RGB value against both the 6×6×6 cube (16–231)
    /// and the grayscale ramp (232–255), returning whichever is closer.
    static func nearestPalette256Index(red: UInt8, green: UInt8, blue: UInt8) -> UInt8 {
        let cubeIndex = nearestCubeIndex(red: red, green: green, blue: blue)
        let cubeRGB = palette256ToRGB(cubeIndex)
        let cubeDistance = rgbDistanceSquared(
            (red, green, blue),
            (cubeRGB.red, cubeRGB.green, cubeRGB.blue)
        )

        let grayIndex = nearestGrayscaleIndex(red: red, green: green, blue: blue)
        let grayRGB = palette256ToRGB(grayIndex)
        let grayDistance = rgbDistanceSquared(
            (red, green, blue),
            (grayRGB.red, grayRGB.green, grayRGB.blue)
        )

        return grayDistance < cubeDistance ? grayIndex : cubeIndex
    }

    /// Finds the nearest 6×6×6 cube index (16–231) for an RGB color.
    static func nearestCubeIndex(red: UInt8, green: UInt8, blue: UInt8) -> UInt8 {
        UInt8(16
              + 36 * nearestCubeChannelLevel(red)
              + 6 * nearestCubeChannelLevel(green)
              + nearestCubeChannelLevel(blue))
    }

    /// Finds the nearest channel level index (0–5) for a single component.
    static func nearestCubeChannelLevel(_ value: UInt8) -> Int {
        var bestIndex = 0
        var bestDistance = Int.max

        for (index, level) in cubeChannelLevels.enumerated() {
            let distance = abs(Int(value) - Int(level))
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    /// Finds the nearest grayscale ramp index (232–255) for an RGB color.
    ///
    /// The grayscale ramp covers values 8, 18, 28, …, 238.
    static func nearestGrayscaleIndex(red: UInt8, green: UInt8, blue: UInt8) -> UInt8 {
        let gray = (Int(red) + Int(green) + Int(blue)) / 3
        // Grayscale ramp: index N → gray level 8 + (N - 232) * 10
        // Inverse: N = 232 + (gray - 8) / 10, clamped to 232–255
        let index = min(255, max(232, 232 + (gray - 8 + 5) / 10))
        return UInt8(index)
    }

    /// Squared Euclidean distance between two RGB colors.

    static func rgbDistanceSquared(_ colourA: (UInt8, UInt8, UInt8),
                                   _ colourB: (UInt8, UInt8, UInt8)) -> Int {
        let deltaRed = Int(colourA.0) - Int(colourB.0)
        let deltaGreen = Int(colourA.1) - Int(colourB.1)
        let deltaBlue = Int(colourA.2) - Int(colourB.2)

        return (deltaRed * deltaRed) + (deltaGreen * deltaGreen) + (deltaBlue * deltaBlue)
    }

    /// Converts a 256-color palette index to the nearest ANSI 16-color.
    static func palette256ToANSI16(_ index: UInt8) -> Color {
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
    static let ansi16Table: [(color: Color, red: UInt8, green: UInt8, blue: UInt8)] = {
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
    static func rgbToNearestANSI16(red: UInt8, green: UInt8, blue: UInt8) -> Color {
        var bestColor = Color.white
        var bestDistance = Int.max

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
