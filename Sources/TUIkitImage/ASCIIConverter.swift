//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ASCIIConverter.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitStyling

/// Standard ANSI escape sequences for ASCII art colorization.
enum ANSIEscape {
    /// The escape character.
    static let escape = "\u{1B}"
    /// The Control Sequence Introducer.
    static let csi = "\(escape)["
    /// Reset all formatting.
    static let reset = "\(csi)0m"
}

// MARK: - Character Set

/// The set of characters used for ASCII art rendering.
///
/// Each set trades off between compatibility and visual quality.
public enum ASCIICharacterSet: Sendable, Equatable {
    /// Standard ASCII characters (10 levels). Works in every terminal.
    case ascii

    /// Unicode block elements (5 levels), one shading per cell. Requires Unicode support.
    case blocks

    /// Half-block cells (`▄`) with independent foreground / background colors,
    /// doubling the effective vertical resolution.
    ///
    /// Each terminal cell encodes two image pixels — the top one is painted
    /// as the cell's background, the bottom one as the foreground of the
    /// lower-half block glyph. Because terminal characters are roughly twice
    /// as tall as they are wide, the resulting sub-cell pixels are very
    /// nearly square — vertical and horizontal resolutions match.
    ///
    /// Falls back gracefully on monochrome terminals: the two pixels are
    /// thresholded against mid-luminance and drawn with space / `▀` / `▄` / `█`.
    case halfBlocks

    /// Unicode Braille patterns (2x4 pixel cells, 256 patterns). Highest resolution.
    case braille
}

// MARK: - Color Mode

/// Controls how colors are rendered in ASCII art output.
public enum ASCIIColorMode: Sendable, Equatable {
    /// 24-bit RGB using `\e[38;2;R;G;B` sequences. Best quality.
    case trueColor

    /// 256-color ANSI palette. Good terminal compatibility.
    case ansi256

    /// 24 shades of gray.
    case grayscale

    /// Black and white only. Universal compatibility.
    case mono
}

// MARK: - Dithering Mode

/// The dithering algorithm applied during color quantization.
public enum DitheringMode: Sendable, Equatable {
    /// Floyd-Steinberg error diffusion. Good for smooth gradients.
    case floydSteinberg

    /// No dithering. Fastest.
    case none
}

// MARK: - ASCII Converter

/// Converts an `RGBAImage` to colored ASCII art strings.
///
/// The conversion pipeline:
/// 1. Scale image to target character dimensions
/// 2. Apply aspect ratio correction (terminal chars are ~2:1)
/// 3. Optionally apply dithering
/// 4. Map each pixel to a character based on luminance
/// 5. Colorize each character using the selected color mode
public struct ASCIIConverter: Sendable {

    /// The character set to use for brightness mapping.
    let characterSet: ASCIICharacterSet

    /// The color mode for output.
    let colorMode: ASCIIColorMode

    /// The dithering algorithm (nil or .none means no dithering).
    let dithering: DitheringMode

    /// Creates a converter with the specified options.
    public init(
        characterSet: ASCIICharacterSet = .blocks,
        colorMode: ASCIIColorMode = .trueColor,
        dithering: DitheringMode = .none
    ) {
        self.characterSet = characterSet
        self.colorMode = colorMode
        self.dithering = dithering
    }
}

// MARK: - Color Mode Capability

extension ASCIIColorMode {

    /// Returns the closest color mode the given terminal depth can render correctly.
    ///
    /// Emitting a mode the terminal does not support produces corrupt
    /// output — for example, a `\e[38;2;R;G;B m` sequence on a 256-color
    /// terminal is partially interpreted and garbles the image. This
    /// helper downgrades the requested mode to one the terminal can
    /// handle, mirroring the downsampling that ``ANSIRenderer`` performs
    /// for non-image colors.
    public func effective(for depth: ColorDepth) -> ASCIIColorMode {
        switch (self, depth) {
        case (_, .noColor):
            return .mono
        case (.trueColor, .truecolor):
            return .trueColor
        case (.trueColor, .palette256):
            return .ansi256
        case (.trueColor, .basic16),
            (.ansi256, .basic16),
            (.grayscale, .basic16):
            return .mono
        default:
            return self
        }
    }
}

// MARK: - Conversion

extension ASCIIConverter {

    /// Converts an image to an array of ANSI-colored strings (one per row).
    ///
    /// - Parameters:
    ///   - image: The source image.
    ///   - width: Target width in characters.
    ///   - height: Target height in characters.
    /// - Returns: An array of ANSI-formatted strings representing the ASCII art.
    public func convert(_ image: RGBAImage, width: Int, height: Int) -> [String] {
        guard image.width > 0, image.height > 0, width > 0, height > 0 else {
            return []
        }

        // Downsample the requested color mode to one the terminal can
        // actually render. Otherwise a `.trueColor` request on a 256-color
        // terminal produces garbled output.
        let effectiveMode = colorMode.effective(for: ColorDepth.current)

        // Each character set has its own sub-cell pixel grid.
        //   .ascii / .blocks  : 1×1 (one pixel per cell)
        //   .halfBlocks       : 1×2 (two vertical pixels per cell)
        //   .braille          : 2×4 (eight dots per cell)
        let pixelWidth: Int
        let pixelHeight: Int
        switch characterSet {
        case .ascii, .blocks:
            pixelWidth = width
            pixelHeight = height
        case .halfBlocks:
            pixelWidth = width
            pixelHeight = height * 2
        case .braille:
            pixelWidth = width * 2
            pixelHeight = height * 4
        }

        // Scale image to target pixel dimensions
        var scaled = image.scaledBilinear(to: pixelWidth, pixelHeight)

        // Apply dithering if requested (only meaningful for non-trueColor modes)
        if dithering == .floydSteinberg, effectiveMode != .trueColor {
            scaled = applyFloydSteinbergDithering(scaled, mode: effectiveMode)
        }

        // Convert to ASCII lines
        switch characterSet {
        case .braille:
            return convertBraille(scaled, width: width, height: height, mode: effectiveMode)
        case .halfBlocks:
            return convertHalfBlocks(scaled, width: width, height: height, mode: effectiveMode)
        case .ascii, .blocks:
            return convertCharacterBased(scaled, width: width, height: height, mode: effectiveMode)
        }
    }
}

// MARK: - Character-Based Conversion

extension ASCIIConverter {

    /// Converts using character brightness mapping (ascii, blocks).
    private func convertCharacterBased(
        _ image: RGBAImage,
        width: Int,
        height: Int,
        mode: ASCIIColorMode
    ) -> [String] {
        let ramp = characterRamp

        var lines = [String]()
        lines.reserveCapacity(height)

        for y in 0..<height {
            var line = ""
            line.reserveCapacity(width * 20)  // Reserve for ANSI codes
            var lastColor = ""

            for x in 0..<width {
                let pixel = image.pixel(at: x, y)

                // Map luminance to character
                let charIndex = Int((pixel.luminance / 255.0) * Double(ramp.count - 1))
                let clampedIndex = min(max(charIndex, 0), ramp.count - 1)
                let char = ramp[clampedIndex]

                // Colorize
                let colorCode = foregroundColorCode(for: pixel, mode: mode)
                if colorCode != lastColor {
                    if !lastColor.isEmpty {
                        line += ANSIEscape.reset
                    }
                    line += colorCode
                    lastColor = colorCode
                }
                line.append(char)
            }

            if !lastColor.isEmpty {
                line += ANSIEscape.reset
            }
            lines.append(line)
        }

        return lines
    }

    /// The character ramp for the current character set, from darkest to brightest.
    private var characterRamp: [Character] {
        switch characterSet {
        case .ascii:
            return Array(" .:;+=xX$@")
        case .blocks:
            return Array(" ░▒▓█")
        case .halfBlocks, .braille:
            // Unused — halfBlocks and braille have their own rendering paths.
            return []
        }
    }
}

// MARK: - Aspect Ratio

extension ASCIIConverter {

    /// Calculates the target character dimensions preserving aspect ratio.
    ///
    /// Terminal characters are approximately 2:1 (height:width), so the
    /// vertical dimension is halved to compensate.
    ///
    /// - Parameters:
    ///   - imageWidth: Source image width in pixels.
    ///   - imageHeight: Source image height in pixels.
    ///   - maxWidth: Maximum width in characters.
    ///   - maxHeight: Maximum height in characters (optional).
    ///   - contentMode: Whether to fit within or fill the available bounds.
    ///   - overrideAspectRatio: An explicit width/height ratio. When `nil`,
    ///     the source image's natural ratio is used.
    /// - Returns: The target width and height in characters.
    public static func targetSize(
        imageWidth: Int,
        imageHeight: Int,
        maxWidth: Int,
        maxHeight: Int? = nil,
        contentMode: ContentMode = .fit,
        overrideAspectRatio: Double? = nil
    ) -> (width: Int, height: Int) {
        let terminalAspect = 2.0  // Terminal chars are ~2x taller than wide

        // Use override ratio or compute from source dimensions.
        let sourceRatio =
            overrideAspectRatio
            ?? (Double(imageWidth) / Double(imageHeight))

        // correctedRatio accounts for terminal character aspect (tall cells).
        let correctedRatio = sourceRatio * terminalAspect

        let maxH = maxHeight ?? Int((Double(maxWidth) / correctedRatio).rounded())

        let targetWidth: Int
        let targetHeight: Int

        switch contentMode {
        case .fit:
            // Scale to fit within both bounds. Result <= bounds.
            let widthFromHeight = Int((Double(maxH) * correctedRatio).rounded())
            if widthFromHeight <= maxWidth {
                targetWidth = widthFromHeight
                targetHeight = maxH
            } else {
                targetWidth = maxWidth
                targetHeight = Int((Double(maxWidth) / correctedRatio).rounded())
            }

        case .fill:
            // Scale so the shorter dimension fills its bound.
            // Result may exceed one bound.
            let widthFromHeight = Int((Double(maxH) * correctedRatio).rounded())
            if widthFromHeight >= maxWidth {
                targetWidth = widthFromHeight
                targetHeight = maxH
            } else {
                targetWidth = maxWidth
                targetHeight = Int((Double(maxWidth) / correctedRatio).rounded())
            }
        }

        return (width: max(1, targetWidth), height: max(1, targetHeight))
    }
}
