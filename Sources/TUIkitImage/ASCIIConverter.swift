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

    /// A longer, perceptually-ordered ASCII ramp (~70 ink levels) rendered with
    /// 2× per-cell supersampling (each cell averages a 2×2 block of source
    /// pixels), for markedly finer tonal gradation than ``ascii`` at the same
    /// cell resolution. Still pure ASCII, so it renders anywhere — but opt in,
    /// since a very long ramp can band or reverse on fonts whose glyph ink
    /// coverage isn't monotonic; ``ascii`` stays the safe universal default.
    case asciiDetailed

    /// Unicode block elements (5 shading levels), one glyph per cell.
    /// Requires Unicode support.
    ///
    /// This is the lowest-resolution block mode — each terminal cell encodes
    /// a single image pixel by luminance, drawn with one of `" ░▒▓█"`. For
    /// colour, prefer ``blocks`` (one solid-colour pixel per cell) or
    /// ``fineBlocks`` (two per cell).
    case coarseBlocks

    /// Solid full-cell colour: each terminal cell is one image pixel, painted
    /// as the cell **background** (a space, no glyph). One pixel per cell — half
    /// the vertical resolution of ``fineBlocks`` — but **gap-free**: because it
    /// draws no block glyph, it never shows the thin inter-row seams that some
    /// fonts leave when their block glyphs (`▄`, `█`, …) are rasterised a hair
    /// short of the cell (notably SF Mono in macOS Terminal.app). Use this when
    /// ``fineBlocks`` bands on the target terminal and you'd rather have a clean
    /// image than the extra vertical detail.
    ///
    /// On a colourless terminal (``ASCIIColorMode/mono``) there is no background
    /// to fill, so it falls back to a `█` / space luminance threshold.
    case blocks

    /// Half-block cells (`▄`) with independent foreground / background colours,
    /// doubling the effective vertical resolution compared with
    /// ``coarseBlocks``. This is the default character set.
    ///
    /// Each terminal cell encodes two image pixels — the top one is painted
    /// as the cell's background, the bottom one as the foreground of the
    /// lower-half block glyph. Because terminal characters are roughly twice
    /// as tall as they are wide, the resulting sub-cell pixels are very
    /// nearly square — vertical and horizontal resolutions match.
    ///
    /// Falls back gracefully on monochrome terminals: the two pixels are
    /// thresholded against mid-luminance and drawn with space / `▀` / `▄` / `█`.
    ///
    /// > Note: `.fineBlocks` paints pixel data into BOTH the cell foreground
    /// > and background, so a faithful image depends on the terminal drawing
    /// > the block glyph (`▄`) cleanly across the whole cell. The emitted cell
    /// > grid is itself gap-free — every cell carries a real foreground and
    /// > background (pinned by `FineBlocksRenderTests`) — so thin seams between
    /// > cells come from the terminal's glyph rendering, not the output. (One
    /// > observed case: macOS Terminal.app + SF Mono rasterises the block
    /// > glyphs a hair short of the cell, banding every row boundary — a
    /// > terminal/font limitation no glyph choice fixes.) When a terminal bands,
    /// > switch to ``blocks``, which fills the whole cell via the background
    /// > colour and so has no glyph seams (at half the vertical resolution).
    case fineBlocks

    /// Shape-based character lookup, after Alex Harri's "ASCII characters
    /// are not pixels" (https://alexharri.com/blog/ascii-rendering).
    ///
    /// Each ASCII character carries a 6-dimensional shape vector that
    /// quantifies how much of its cell's six staggered sampling circles
    /// the glyph occupies. For each output cell the converter samples the
    /// image at the same six points and picks the character whose shape
    /// vector is closest by Euclidean distance — the result follows
    /// curved edges far better than the per-cell-luminance approach
    /// because the picked character itself carries directional shape
    /// information.
    ///
    /// A cell carrying a strong directional edge (detected from a Sobel-style
    /// gradient over its six sampling regions) is drawn with the orientation-
    /// matched line glyph (`-`, `|`, `/`, `\`) rather than the nearest coverage
    /// match, so edges read as clean lines; flat / textured cells still use the
    /// coverage match.
    case shapeBased

    /// Like ``shapeBased`` but edges are drawn with Unicode box-drawing line
    /// glyphs (`─ │ ╱ ╲`) instead of ASCII slashes, for noticeably cleaner
    /// diagonals — at the cost of requiring a terminal/font with box-drawing
    /// support. Non-edge cells use the same coverage glyphs as ``shapeBased``.
    case shapeUnicode

    /// Shape matching over a much WIDER Unicode glyph set: the ASCII shape
    /// glyphs plus shades (`░▒▓█`), half blocks, quadrants (`▘▝▖▗▚▞…`), and
    /// the eighth-block ladders (`▁▂▃…`, `▏▎▍…`) — every glyph's spatial ink
    /// signature measured from the reference font by the calibration tool.
    /// A cell whose darkness sits in one corner gets that corner's quadrant,
    /// a bottom-heavy cell a partial block, an even mid-tone a shade — the
    /// highest structural fidelity short of ``braille``, while keeping real
    /// per-glyph tone. Edges use box-drawing lines like ``shapeUnicode``.
    /// Requires a terminal/font with block-element support.
    case unicodeDetailed

    /// A caller-supplied luminance ramp for the brightness-mapping renderer,
    /// ordered darkest pixel → brightest pixel: the FIRST character renders
    /// black pixels (usually a space, so dark regions stay blank on a dark
    /// terminal) and the LAST renders white ones (usually the densest glyph
    /// — its ink carries the bright colour). Use this to tune the output to
    /// a specific font or aesthetic (e.g. `" ·∘●"`, or a ramp measured for
    /// your terminal's font) without waiting for a built-in preset. Long
    /// ramps (over 20 levels) are rendered with the same 2× per-cell
    /// supersampling as ``asciiDetailed``, unless ``ASCIIConverter`` is given
    /// an explicit supersampling factor. An empty ramp falls back to
    /// ``ascii``.
    case customRamp(String)

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

    /// Source-pixels-per-cell on each axis for the brightness-mapping
    /// character sets (`.ascii` / `.asciiDetailed` / `.coarseBlocks` /
    /// `.customRamp`): each output cell averages an N×N block of source
    /// pixels, anti-aliasing the tone so a longer ramp resolves smoother
    /// gradients. `nil` keeps each set's own default (1, except 2 for
    /// `.asciiDetailed` and long custom ramps). Clamped to 1...4; higher
    /// factors cost quadratically more sampling for no visible gain. Ignored
    /// by the sub-cell sets (blocks / shape / braille), whose sampling grids
    /// are fixed by their glyphs.
    let supersampling: Int?

    /// The minimum Sobel gradient magnitude (in 0…1 region-darkness units,
    /// practical range roughly 0.3…2) for a shape-mode cell (`.shapeBased` /
    /// `.shapeUnicode` / `.unicodeDetailed`) to be drawn as a directional
    /// line glyph instead of its nearest coverage match. Lower values trace
    /// more edges; `nil` disables line glyphs entirely (pure coverage
    /// matching). The default 0.9 triggers on a clean light/dark boundary
    /// across a cell while flat or lightly-textured cells fall through.
    let edgeThreshold: Double?

    /// Creates a converter with the specified options.
    public init(
        characterSet: ASCIICharacterSet = .fineBlocks,
        colorMode: ASCIIColorMode = .trueColor,
        dithering: DitheringMode = .none,
        supersampling: Int? = nil,
        edgeThreshold: Double? = 0.9
    ) {
        self.characterSet = characterSet
        self.colorMode = colorMode
        self.dithering = dithering
        self.supersampling = supersampling.map { min(4, max(1, $0)) }
        self.edgeThreshold = edgeThreshold
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
        //   .ascii / .coarseBlocks / .blocks : 1×1  (one pixel per cell)
        //   .fineBlocks            : 1×2  (two vertical pixels per cell)
        //   .shapeBased       : 5×10 (sampled at six staggered circles per cell)
        //   .braille          : 2×4  (eight dots per cell)
        // The brightness-mapping sets scale by the (configurable)
        // supersampling factor instead.
        let pixelWidth: Int
        let pixelHeight: Int
        switch characterSet {
        case .blocks:
            pixelWidth = width
            pixelHeight = height
        case .ascii, .coarseBlocks, .asciiDetailed, .customRamp:
            let factor = rampSupersampling
            pixelWidth = width * factor
            pixelHeight = height * factor
        case .fineBlocks:
            pixelWidth = width
            pixelHeight = height * 2
        case .shapeBased, .shapeUnicode, .unicodeDetailed:
            pixelWidth = width * 5
            pixelHeight = height * 10
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
        case .fineBlocks:
            return convertFineBlocks(scaled, width: width, height: height, mode: effectiveMode)
        case .blocks:
            return convertBlocks(scaled, width: width, height: height, mode: effectiveMode)
        case .shapeBased:
            return convertShapeBased(
                scaled, width: width, height: height, mode: effectiveMode, unicodeEdges: false)
        case .shapeUnicode:
            return convertShapeBased(
                scaled, width: width, height: height, mode: effectiveMode, unicodeEdges: true)
        case .unicodeDetailed:
            return convertShapeBased(
                scaled, width: width, height: height, mode: effectiveMode,
                unicodeEdges: true, wideUnicode: true)
        case .ascii, .coarseBlocks, .asciiDetailed, .customRamp:
            return convertCharacterBased(
                scaled, width: width, height: height, mode: effectiveMode,
                supersample: rampSupersampling)
        }
    }

    /// The effective source-pixels-per-cell factor for the brightness-mapping
    /// sets: the explicit ``supersampling`` when given, else the set's own
    /// default — 2 for `.asciiDetailed` and long custom ramps (whose extra
    /// tonal levels only resolve with averaged sampling), 1 otherwise.
    private var rampSupersampling: Int {
        if let supersampling { return supersampling }
        switch characterSet {
        case .asciiDetailed:
            return 2
        case .customRamp(let ramp):
            return ramp.count > 20 ? 2 : 1
        default:
            return 1
        }
    }
}

// MARK: - Character-Based Conversion

extension ASCIIConverter {

    /// Converts using character brightness mapping (ascii, blocks).
    ///
    /// `supersample` is the source-pixels-per-cell factor on each axis: `1` reads
    /// one pixel per cell (the classic ascii path); `2` averages a 2×2 block,
    /// anti-aliasing the tone so a longer ramp resolves smoother gradients.
    private func convertCharacterBased(
        _ image: RGBAImage,
        width: Int,
        height: Int,
        mode: ASCIIColorMode,
        supersample: Int
    ) -> [String] {
        let ramp = characterRamp

        var lines = [String]()
        lines.reserveCapacity(height)

        for y in 0..<height {
            var line = ""
            line.reserveCapacity(width * 20)  // Reserve for ANSI codes
            var lastColor = ""

            for x in 0..<width {
                let pixel = averagedPixel(image, cellX: x, cellY: y, supersample: supersample)

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

    /// Converts each pixel to a full-cell background fill: a space whose cell
    /// **background** is the pixel colour. One pixel per cell — half the vertical
    /// resolution of ``convertFineBlocks(_:width:height:mode:)`` — but gap-free:
    /// it draws no glyph, so it never shows the inter-row seams a font leaves
    /// when its block glyphs are rasterised short of the cell.
    ///
    /// Consecutive cells that share a colour coalesce into one ANSI run. On a
    /// colourless terminal (``ASCIIColorMode/mono``), where there is no
    /// background colour to use, it falls back to a `█` / space luminance
    /// threshold.
    private func convertBlocks(
        _ image: RGBAImage,
        width: Int,
        height: Int,
        mode: ASCIIColorMode
    ) -> [String] {
        var lines = [String]()
        lines.reserveCapacity(height)

        for y in 0..<height {
            var line = ""
            line.reserveCapacity(width * 12)  // background ANSI per colour run + a space per cell
            var lastCode = ""

            for x in 0..<width {
                let pixel = image.pixel(at: x, y)

                // No background colour to fill with — approximate with a solid
                // block for dark pixels and a space for light ones.
                if mode == .mono {
                    line.append(pixel.luminance < 128 ? "█" : " ")
                    continue
                }

                let code = backgroundColorCode(for: pixel, mode: mode)
                if code != lastCode {
                    if !lastCode.isEmpty { line += ANSIEscape.reset }
                    line += code
                    lastCode = code
                }
                line.append(" ")
            }

            if !lastCode.isEmpty { line += ANSIEscape.reset }
            lines.append(line)
        }
        return lines
    }

    /// Averages a `supersample × supersample` block of source pixels into one
    /// representative pixel for the cell at `(cellX, cellY)`. `supersample == 1`
    /// is the fast path — a single pixel read.
    private func averagedPixel(
        _ image: RGBAImage, cellX: Int, cellY: Int, supersample: Int
    ) -> RGBA {
        if supersample <= 1 { return image.pixel(at: cellX, cellY) }
        var rSum = 0, gSum = 0, bSum = 0, aSum = 0, count = 0
        let baseX = cellX * supersample
        let baseY = cellY * supersample
        for dy in 0..<supersample {
            for dx in 0..<supersample {
                let sampleX = min(baseX + dx, image.width - 1)
                let sampleY = min(baseY + dy, image.height - 1)
                let pixel = image.pixel(at: sampleX, sampleY)
                rSum += Int(pixel.r)
                gSum += Int(pixel.g)
                bSum += Int(pixel.b)
                aSum += Int(pixel.a)
                count += 1
            }
        }
        guard count > 0 else { return image.pixel(at: cellX, cellY) }
        return RGBA(
            r: UInt8(rSum / count), g: UInt8(gSum / count),
            b: UInt8(bSum / count), a: UInt8(aSum / count))
    }

    /// The character ramp for the current character set, from darkest to brightest.
    private var characterRamp: [Character] {
        switch characterSet {
        case .ascii:
            return Array(" .:;+=xX$@")
        case .asciiDetailed:
            // A coverage-ordered, gap-free pure-ASCII ramp (light → dense),
            // calibrated to the reference font's measured ink coverage by
            // `Tools/GenerateImageGlyphs` (see ImageGlyphCalibration.generated.swift).
            // Fewer but correctly ordered levels beat a longer ramp whose
            // hand-picked ordering doesn't match this font's actual tones.
            return generatedAsciiDetailedRamp
        case .coarseBlocks:
            return Array(" ░▒▓█")
        case .customRamp(let ramp):
            // Caller-supplied, ordered light → dense by contract; an empty
            // ramp falls back to the classic ascii levels.
            return ramp.isEmpty ? Array(" .:;+=xX$@") : Array(ramp)
        case .blocks, .fineBlocks, .shapeBased, .shapeUnicode, .unicodeDetailed, .braille:
            // Unused — these character sets have their own rendering paths.
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
