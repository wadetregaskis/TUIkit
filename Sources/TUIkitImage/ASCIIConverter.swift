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

/// The fundamental glyph charset used for image rendering.
///
/// Image rendering is the product of three orthogonal choices:
///
/// - **Charset** — which glyph repertoire: ``ascii(glyphs:)``,
///   ``unicode(glyphs:)`` (which excludes the Block Elements — those belong
///   to the dedicated block modes — and anything that won't respect the
///   foreground colour), ``blocks(_:)``, or a ``customRamp(_:)``.
/// - **Size** — how many glyphs. For `ascii` / `unicode` the `glyphs` count
///   picks the IDEAL subset of the calibrated repertoire (density levels
///   spread as evenly as possible, flattest glyph per level for luminance
///   rendering; widest shape-space spread for shape-aware rendering);
///   `nil` uses the full repertoire. For `blocks`, size is the discrete
///   ``BlockResolution``.
/// - **Shape-awareness** — on ``ASCIIConverter`` (and
///   `View.imageShapeAware(_:)`): whether glyphs are matched by their
///   measured in-cell ink DISTRIBUTION (a corner of darkness picks a
///   corner-heavy glyph) rather than mapped from the cell's overall
///   luminance alone. Applies to every charset except a custom ramp —
///   including `blocks`, which shape-matches over the quadrant / half /
///   shade / corner-triangle (`◢◣◤◥`) repertoire.
public enum ASCIICharacterSet: Sendable, Equatable {

    /// The pixel-subdivision resolutions of the (non-shape-aware) block
    /// modes — the block charset's discrete "size" axis.
    public enum BlockResolution: Sendable, Equatable {
        /// Shade glyphs (`" ░▒▓█"`) mapped from luminance, one image pixel
        /// per cell. The lowest-resolution block mode, and the only one
        /// whose tone survives a colourless terminal.
        case coarse

        /// Solid full-cell colour: each cell is one image pixel painted as
        /// the cell **background** (a space, no glyph). Half the vertical
        /// resolution of ``half`` but **gap-free**: with no block glyph it
        /// never shows the inter-row seams some fonts leave when their
        /// blocks rasterise a hair short of the cell (notably SF Mono in
        /// macOS Terminal.app). On a colourless terminal there is no
        /// background to fill, so it falls back to a `█` / space threshold.
        case solid

        /// Half-block cells (`▄`) with independent foreground / background
        /// colours — two image pixels per cell, whose sub-cells are very
        /// nearly square. The default block resolution.
        ///
        /// > Note: this paints pixels into BOTH the cell foreground and
        /// > background, so a faithful image depends on the terminal drawing
        /// > `▄` cleanly across the whole cell. The emitted grid is itself
        /// > gap-free (pinned by `HalfBlocksRenderTests`); seams come from
        /// > the terminal's glyph rendering (e.g. Terminal.app + SF Mono).
        /// > When a terminal bands, use ``solid``.
        case half

        /// Unicode Braille patterns: 2×4 dots per cell, 256 patterns.
        /// The highest spatial resolution.
        case braille
    }

    /// Printable ASCII. Works in every terminal.
    ///
    /// - Parameter glyphs: How many glyphs to use — the ideal subset is
    ///   chosen from the calibrated repertoire (95 glyphs; ~19 distinct
    ///   density levels for luminance rendering). `nil` uses them all.
    ///   `10` approximates the classic ASCII-art ramp.
    case ascii(glyphs: Int?)

    /// ASCII plus non-block Unicode: box-drawing lines and corners,
    /// geometric shapes, and every other calibrated glyph that is a single
    /// cell wide and respects the foreground colour. Block Elements are
    /// excluded — they belong to ``blocks(_:)``.
    ///
    /// - Parameter glyphs: How many glyphs, as for ``ascii(glyphs:)``;
    ///   `nil` uses the full repertoire.
    case unicode(glyphs: Int?)

    /// Unicode Block Elements, rendered by pixel subdivision at the given
    /// ``BlockResolution`` — or, when the converter is shape-aware, by
    /// shape-matching over the block repertoire (quadrants, halves,
    /// shades, eighth ladders, and the corner triangles `◢◣◤◥`), in which
    /// case the resolution is not used.
    case blocks(BlockResolution)

    /// A caller-supplied luminance ramp, ordered darkest pixel → brightest
    /// pixel: the FIRST character renders black pixels (usually a space,
    /// so dark regions stay blank on a dark terminal) and the LAST renders
    /// white ones. Use this to tune the output to a specific font or
    /// aesthetic (e.g. `" ·∘●"`). Long ramps (over 12 levels) default to
    /// 2× per-cell supersampling unless ``ASCIIConverter`` is given an
    /// explicit factor. An empty ramp falls back to a 10-glyph ASCII ramp.
    /// Always luminance-mapped — custom ramps carry no shape calibration,
    /// so the converter's shape-awareness does not apply.
    case customRamp(String)

    /// The full ASCII repertoire (`.ascii(glyphs: nil)`).
    public static var ascii: Self { .ascii(glyphs: nil) }

    /// The full non-block Unicode repertoire (`.unicode(glyphs: nil)`).
    public static var unicode: Self { .unicode(glyphs: nil) }
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

    /// The fundamental glyph charset (and its size).
    let characterSet: ASCIICharacterSet

    /// Whether glyphs are matched by their measured in-cell ink
    /// DISTRIBUTION (after Alex Harri's "ASCII characters are not pixels",
    /// https://alexharri.com/blog/ascii-rendering) rather than mapped from
    /// each cell's overall luminance. Each glyph carries a 6-region shape
    /// vector measured from the reference font; each cell samples the image
    /// at the same six staggered circles and picks the nearest glyph — so
    /// the picked character itself carries directional information, and
    /// curved edges read far better than a straight luminance map.
    ///
    /// Applies to the `.ascii`, `.unicode`, and `.blocks` charsets (the
    /// block repertoire shape-matches over quadrants / halves / shades /
    /// corner triangles); a `.customRamp` is always luminance-mapped.
    let shapeAware: Bool

    /// The color mode for output.
    let colorMode: ASCIIColorMode

    /// The dithering algorithm (nil or .none means no dithering).
    let dithering: DitheringMode

    /// Source-pixels-per-cell on each axis for the luminance-mapping
    /// renderers (`.ascii` / `.unicode` / `.blocks(.coarse)` /
    /// `.customRamp`, without shape-awareness): each output cell averages
    /// an N×N block of source pixels, anti-aliasing the tone so a longer
    /// ramp resolves smoother gradients. `nil` keeps the default (2 for
    /// ramps longer than 12 levels, else 1). Clamped to 1...4; higher
    /// factors cost quadratically more sampling for no visible gain.
    /// Ignored by the sub-cell renderers (block subdivision, shape
    /// matching), whose sampling grids are fixed by their glyphs.
    let supersampling: Int?

    /// The minimum Sobel gradient magnitude (in 0…1 region-darkness units,
    /// practical range roughly 0.3…2) for a shape-aware cell to be drawn
    /// as a directional line glyph instead of its nearest coverage match.
    /// Lower values trace more edges; `nil` disables line glyphs entirely
    /// (pure coverage matching). The default 0.9 triggers on a clean
    /// light/dark boundary across a cell while flat or lightly-textured
    /// cells fall through. The line glyphs follow the charset — ASCII uses
    /// `- | / \`, Unicode the box-drawing `─ │ ╱ ╲`; the shape-aware block
    /// repertoire carries its own directional glyphs (halves, corner
    /// triangles), so it does not trace edges.
    let edgeThreshold: Double?

    /// Creates a converter with the specified options.
    public init(
        characterSet: ASCIICharacterSet = .blocks(.half),
        shapeAware: Bool = false,
        colorMode: ASCIIColorMode = .trueColor,
        dithering: DitheringMode = .none,
        supersampling: Int? = nil,
        edgeThreshold: Double? = 0.9
    ) {
        self.characterSet = characterSet
        self.shapeAware = shapeAware
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

        // Each rendering path has its own sub-cell pixel grid:
        //   luminance ramps        : 1×1, scaled by the supersampling factor
        //   .blocks(.solid)        : 1×1  (one pixel per cell)
        //   .blocks(.half)         : 1×2  (two vertical pixels per cell)
        //   .blocks(.braille)      : 2×4  (eight dots per cell)
        //   shape-aware (any)      : 5×10 (sampled at six staggered circles)
        let pixelWidth: Int
        let pixelHeight: Int
        if isShapeMatched {
            pixelWidth = width * 5
            pixelHeight = height * 10
        } else {
            switch characterSet {
            case .blocks(.solid):
                pixelWidth = width
                pixelHeight = height
            case .blocks(.half):
                pixelWidth = width
                pixelHeight = height * 2
            case .blocks(.braille):
                pixelWidth = width * 2
                pixelHeight = height * 4
            case .ascii, .unicode, .blocks(.coarse), .customRamp:
                let factor = rampSupersampling
                pixelWidth = width * factor
                pixelHeight = height * factor
            }
        }

        // Scale image to target pixel dimensions
        var scaled = image.scaledBilinear(to: pixelWidth, pixelHeight)

        // Apply dithering if requested (only meaningful for non-trueColor modes)
        if dithering == .floydSteinberg, effectiveMode != .trueColor {
            scaled = applyFloydSteinbergDithering(scaled, mode: effectiveMode)
        }

        // Convert to lines.
        if isShapeMatched {
            let (columns, edge) = shapeConfiguration
            return convertShapeBased(
                scaled, width: width, height: height, mode: effectiveMode,
                columns: columns, edge: edge)
        }
        switch characterSet {
        case .blocks(.braille):
            return convertBraille(scaled, width: width, height: height, mode: effectiveMode)
        case .blocks(.half):
            return convertHalfBlocks(scaled, width: width, height: height, mode: effectiveMode)
        case .blocks(.solid):
            return convertBlocks(scaled, width: width, height: height, mode: effectiveMode)
        case .ascii, .unicode, .blocks(.coarse), .customRamp:
            return convertCharacterBased(
                scaled, width: width, height: height, mode: effectiveMode,
                supersample: rampSupersampling)
        }
    }

    /// Whether this conversion shape-matches: ``shapeAware`` requested AND
    /// the charset carries shape calibration (a custom ramp does not).
    var isShapeMatched: Bool {
        guard shapeAware else { return false }
        switch characterSet {
        case .ascii, .unicode, .blocks:
            return true
        case .customRamp:
            return false
        }
    }

    /// The shape vocabulary and edge-line glyphs for the current charset:
    /// the ideal `glyphs`-sized subset of its calibrated repertoire, and
    /// charset-appropriate line glyphs (ASCII slashes, Unicode box drawing;
    /// the block repertoire carries its own directional glyphs, so it does
    /// not trace edges).
    private var shapeConfiguration:
        (ShapeTableColumns, (horizontal: Character, vertical: Character, backslash: Character, slash: Character)?)
    {
        switch characterSet {
        case .ascii(let glyphs):
            return (
                ShapeTableColumns(GlyphRepertoire.shapeVocabulary(from: GlyphRepertoire.ascii, count: glyphs)),
                ("-", "|", "\\", "/"))
        case .unicode(let glyphs):
            return (
                ShapeTableColumns(GlyphRepertoire.shapeVocabulary(from: GlyphRepertoire.unicode, count: glyphs)),
                ("─", "│", "╲", "╱"))
        case .blocks:
            return (
                ShapeTableColumns(GlyphRepertoire.shapeVocabulary(from: GlyphRepertoire.blockShapes)),
                nil)
        case .customRamp:
            // Unreachable: `isShapeMatched` is false for custom ramps.
            return (ShapeTableColumns([]), nil)
        }
    }

    /// The effective source-pixels-per-cell factor for the luminance
    /// renderers: the explicit ``supersampling`` when given, else 2 for
    /// ramps longer than 12 levels (whose extra tonal levels only resolve
    /// with averaged sampling) and 1 otherwise.
    private var rampSupersampling: Int {
        if let supersampling { return supersampling }
        return characterRamp.count > 12 ? 2 : 1
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
    /// resolution of ``convertHalfBlocks(_:width:height:mode:)`` — but gap-free:
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

    /// The luminance ramp for the current charset, ordered dark pixel →
    /// bright pixel — the ideal `glyphs`-level subset of the calibrated
    /// repertoire (density levels spread as evenly as possible, flattest
    /// glyph per level; see ``GlyphRepertoire/densityRamp(from:count:)``).
    private var characterRamp: [Character] {
        switch characterSet {
        case .ascii(let glyphs):
            return GlyphRepertoire.densityRamp(from: GlyphRepertoire.ascii, count: glyphs)
        case .unicode(let glyphs):
            return GlyphRepertoire.densityRamp(from: GlyphRepertoire.unicode, count: glyphs)
        case .blocks(.coarse):
            return Array(" ░▒▓█")
        case .customRamp(let ramp):
            // Caller-supplied, ordered light → dense by contract; an empty
            // ramp falls back to a 10-level calibrated ASCII ramp.
            return ramp.isEmpty
                ? GlyphRepertoire.densityRamp(from: GlyphRepertoire.ascii, count: 10)
                : Array(ramp)
        case .blocks:
            // Unused — the other block resolutions have their own paths.
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
