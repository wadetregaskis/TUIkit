//  🖥️ TUIkit — Terminal UI Kit for Swift
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
///   ``BlockStyle``.
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
    public enum BlockStyle: Sendable, Equatable {
        /// Shade glyphs (`" ░▒▓█"`) mapped from luminance, one image pixel
        /// per cell. The lowest-resolution block mode, and the only one
        /// whose tone survives a colourless terminal.
        case coarse

        /// Solid full-cell colour: each cell is one image pixel painted as
        /// the cell **background** (a space, no glyph). Half the vertical
        /// resolution of ``fine`` but **gap-free**: with no block glyph it
        /// never shows the inter-row seams some fonts leave when their
        /// blocks rasterise a hair short of the cell (notably SF Mono in
        /// macOS Terminal.app). On a colourless terminal there is no
        /// background to fill, so it falls back to a `█` / space threshold.
        case solid

        /// Half-block cells (`▄`) with independent foreground / background
        /// colours — two image pixels per cell, whose sub-cells are very
        /// nearly square. The default block style.
        ///
        /// Named for the resolution it achieves, not for the glyph it uses:
        /// it is the FINEST of the non-Braille block styles, twice the
        /// vertical resolution of ``solid`` and ``coarse``. (It was briefly
        /// spelled `half`, after the ▄ half-block — which read as *half* the
        /// resolution, the exact opposite of what it delivers.)
        ///
        /// > Note: this paints pixels into BOTH the cell foreground and
        /// > background, so a faithful image depends on the terminal drawing
        /// > `▄` cleanly across the whole cell. The emitted grid is itself
        /// > gap-free (pinned by `HalfBlocksRenderTests`); seams come from
        /// > the terminal's glyph rendering (e.g. Terminal.app + SF Mono).
        /// > When a terminal bands, use ``solid``.
        case fine

        /// Unicode Braille patterns: 2×4 dots per cell, 256 patterns.
        /// The highest spatial resolution.
        case braille

        /// The fifteen block-element eighths (`▁▂▃▄▅▆▇█▉▊▋▌▍▎▏`) mapped from
        /// luminance, one image pixel per cell — ``coarse`` with three times
        /// the levels, and the same lack of any need for colour.
        ///
        /// In code point order, which is deliberately not ink order: the
        /// bottom eighths fill upward to `█`, then the left eighths empty back
        /// down to `▏`. Coverage therefore peaks in the middle of the ramp and
        /// falls away, and since a luminance ramp indexes by brightness, this
        /// paints mid-tones solid and returns highlights as fine vertical
        /// rules. That is the effect the style is for — it stylises the
        /// picture rather than reproducing its tone.
        ///
        /// Interleaving the two families (`▏▁▎▂▍▃▌▄▋▅▊▆▉▇█`) would make
        /// coverage monotone and reproduce tone faithfully. It is the obvious
        /// correction to make here and it is not one; `blockRampIsStylised`
        /// fails if someone makes it.
        case ramp
    }

    /// Printable ASCII. Works in every terminal.
    ///
    /// - Parameter glyphs: How many glyphs to use — the ideal subset is
    ///   chosen from the calibrated repertoire (95 glyphs, which collapse to
    ///   15 distinct density levels for luminance rendering: near-equal ink
    ///   coverages add banding, not levels). `nil` uses them all.
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
    /// ``BlockStyle`` — or, when the converter is shape-aware, by
    /// shape-matching over the block repertoire (quadrants, halves,
    /// shades, eighth ladders, and the corner triangles `◢◣◤◥`), in which
    /// case the resolution is not used.
    case blocks(BlockStyle)

    /// A caller-supplied luminance ramp, ordered darkest pixel → brightest
    /// pixel: the FIRST character renders black pixels (usually a space,
    /// so dark regions stay blank on a dark terminal) and the LAST renders
    /// white ones. Use this to tune the output to a specific font or
    /// aesthetic (e.g. `" ·∘●"`). Long ramps (over 12 levels) default to
    /// 2× per-cell supersampling unless ``ASCIIConverter`` is given an
    /// explicit factor. An empty ramp falls back to a 10-glyph ASCII ramp.
    /// Always luminance-mapped — custom ramps carry no shape calibration,
    /// so the converter's shape-awareness does not apply.
    ///
    /// > Important: every character must occupy ONE cell. The renderer emits
    /// > one character per column, so a ramp of wide characters makes each row
    /// > that many times too wide: asked for 20 cells, `"丏丑丟"` produces 40.
    /// > A ramp MIXING widths is worse than merely wide — how many cells a row
    /// > takes then depends on which characters that row's pixels chose, so
    /// > rows of the same picture come out different lengths and shear against
    /// > each other (`"丏a丑"` gave 34 for one image and would give something
    /// > else for another). Supporting wide ramps means quantising the grid to
    /// > the widest character, resampling at `width / quantum` and correcting
    /// > the aspect for it — the shape ``TrackConfiguration`` takes for the
    /// > same problem — and is not implemented.
    ///
    /// > Important: a character the terminal is entitled to MOVE cannot be a
    /// > pixel. A ramp of right-to-left letters (Hebrew, Arabic) draws a
    /// > corrupt picture on Apple Terminal — reported, and consistent with the
    /// > host reordering each run of them within the columns it occupies, which
    /// > in a picture swaps the ink with the blanks beside it and mirrors the
    /// > row in patches. In text that reordering is arguably correct and merely
    /// > looks odd; here every character is a pixel and moving one is
    /// > corruption with nothing gained.
    /// >
    /// > Whether a mark or an isolate around each cell suppresses it is
    /// > measured by `Tools/TerminalProbes/rtl_image_card.py` and is an open
    /// > question in `Documentation/Terminal-compatibility.md` — the obvious
    /// > candidate, U+202D … U+202C, is already ruled out: Apple Terminal
    /// > paints those two as the missing-glyph box.
    case customRamp(String)

    /// The full ASCII repertoire (`.ascii(glyphs: nil)`).
    public static var ascii: Self { .ascii(glyphs: nil) }

    /// The full non-block Unicode repertoire (`.unicode(glyphs: nil)`).
    public static var unicode: Self { .unicode(glyphs: nil) }

    /// The largest `glyphs:` count this charset can usefully honour under
    /// the given rendering algorithm — the calibrated pool size for
    /// shape-aware matching, or the number of usefully-distinct density
    /// levels for luminance mapping (near-equal ink coverages add banding,
    /// not levels, so they collapse). Counts above this are equivalent to
    /// `nil` (the full repertoire). `nil` for charsets without a
    /// glyph-count axis (``blocks(_:)``, ``customRamp(_:)``).
    ///
    /// Configuration UIs can use this to keep a glyph-count control's
    /// range — and its displayed value — matching what actually renders.
    public func maximumGlyphs(shapeAware: Bool) -> Int? {
        switch self {
        case .ascii:
            return shapeAware
                ? GlyphRepertoire.ascii.count : GlyphRepertoire.asciiDensityLevels
        case .unicode:
            return shapeAware
                ? GlyphRepertoire.unicode.count : GlyphRepertoire.unicodeDensityLevels
        case .blocks, .customRamp:
            return nil
        }
    }
}

// MARK: - Color Mode

/// Controls how colors are rendered in ASCII art output.
public enum ASCIIColorMode: Sendable, Equatable {
    /// 24-bit RGB using `\e[38;2;R;G;B` sequences. Best quality.
    case trueColor

    /// The terminal's own 256 — the 6×6×6 colour cube and the 24-step grey
    /// ramp, emitted as `38;5;n` with `n` never below 16.
    ///
    /// Where a `.trueColor` image LANDS on a 256-colour terminal, so the
    /// picture and the page beside it draw from the same 240 colours. Mapped by
    /// nearest in OKLab, like every other palette here — the same COLOURS as
    /// the UI, deliberately not the same RULE, and
    /// `ASCIIPalette.nearestIndex(to:)` says why. It used to divide each
    /// channel by 51 onto the cube instead, which rotates hue in the pale range
    /// — a cream came out pink — and short-circuited near-greys on a test that
    /// never compared red against blue. See `ASCIIPalette.ansi256`.
    case ansi256

    /// The terminal's own sixteen: the 8 standard ANSI colours and their 8
    /// bright twins, emitted as SGR 30–37 / 90–97 rather than as an index or a
    /// triple.
    ///
    /// The bottom rung of the fidelity ladder that is still colour, and the one
    /// every terminal that has colour at all can draw. It matters because it is
    /// where the higher rungs LAND: `TERM=xterm-color` used to take a
    /// `.trueColor` image all the way down to ``mono``, so a terminal with
    /// sixteen colours drew none of them.
    ///
    /// Worth asking for above 16 colours too, for the same reason ``ansi256``
    /// is on a truecolor terminal: it is the look of the terminal's own palette,
    /// and it follows the user's theme, since the sixteen are whatever their
    /// terminal profile says they are — when drawn as GLYPHS, which emit the
    /// names (SGR 30–37 / 90–97). Drawn as pixels through terminal graphics
    /// the sixteen are xterm's default RGB, baked in: a transmitted image is
    /// not SGR, and nothing here can ask the terminal what its profile paints
    /// for "red". See `ASCIIConverter.recoloured`.
    case ansi16

    /// 24 shades of gray: the terminal's own grey ramp, emitted as `38;5;n`
    /// with `n` in 232…255, whose RGB is 8, 18, … 238.
    ///
    /// 24 in both renderings of a picture. Drawn as pixels through terminal
    /// graphics there is no palette index to send, so the RGB of the step is
    /// sent instead — the same 24 shades, and so neither pure black nor pure
    /// white in either rendering. See `ASCIIConverter.greyRampStep(for:)`.
    case grayscale

    /// Black and white only. Universal compatibility.
    case mono

    /// A specific set of colours, chosen by intent rather than by what the
    /// terminal can display. See ``ASCIIPalette``.
    case palette(ASCIIPalette)

    /// This mode with any adaptive palette's colours chosen from `image`.
    ///
    /// The converters call it once per conversion, on the picture AFTER the
    /// tone curve and the edge lift have run — the colours have to be taken
    /// from the picture as it will be drawn, not as it arrived, or a negative
    /// or a duotone would be quantised to the palette of a picture nobody sees.
    /// Everything else is unaffected, since a non-adaptive palette answers with
    /// itself. See ``ASCIIPalette/derived(from:depth:)``.
    ///
    /// - Parameter depth: What the output can draw, for an adaptive palette
    ///   asked to choose colours the output HAS — see
    ///   ``ASCIIPalette/AdaptationTarget``. The caller's own answer, not
    ///   ``ColorDepth/current``: a picture drawn as terminal graphics is a field
    ///   of RGB pixels whatever the terminal's SGR depth, so the two renderings
    ///   of one picture pass different depths on the same terminal.
    public func derived(from image: RGBAImage, depth: ColorDepth) -> Self {
        guard case .palette(let colors) = self else { return self }
        return .palette(colors.derived(from: image, depth: depth))
    }

    /// This mode with every colour it names made concrete.
    ///
    /// Only ``palette(_:)`` names any; the rest are returned unchanged. Callers
    /// that render do this once, before consulting a cache keyed on the mode —
    /// see ``ASCIIPalette/resolved(with:)``.
    public func resolved(with palette: any Palette) -> Self {
        guard case .palette(let colors) = self else { return self }
        return .palette(colors.resolved(with: palette))
    }

    /// Whether SGR 1 changes only a glyph's WEIGHT in this mode, or its COLOUR
    /// as well.
    ///
    /// Bold is not only a weight. xterm and most of its descendants implement
    /// "bold means bright": under SGR 1 a foreground named as one of the
    /// standard eight is painted in its BRIGHT twin instead. Hosts differ, and
    /// each spells the choice its own way — iTerm2's "Use Bright Bold" (on by
    /// default), Terminal.app's "Use bright colors for bold text", Ghostty's
    /// weight-only bold — so the same sequence is a weight change on one and a
    /// colour change on the next.
    ///
    /// It is safe exactly where the foreground is stated in a form that has no
    /// bright twin to be swapped for:
    /// - ``trueColor`` is `38;2;r;g;b`, a triple and not a name.
    /// - ``ansi256`` and ``grayscale`` are `38;5;n`, and **n is never below
    ///   16**: ``ASCIIPalette/ansi256`` holds exactly the cube (16…231) and the
    ///   grey ramp (232…255) and none of the sixteen, and `.grayscale` indexes
    ///   the ramp directly. That is what makes them safe, so it is load-bearing
    ///   rather than incidental — and it is why `Color`'s own search starts at
    ///   16 as well.
    /// - ``mono`` states no colour at all.
    /// - ``ansi16`` is `30`–`37` / `90`–`97`: the very names bold reinterprets.
    /// - ``palette(_:)`` is safe only if no entry of it is one of the sixteen,
    ///   which ``ASCIIPalette/foregroundSurvivesBold`` answers — note that
    ///   ``ASCIIPalette/downsampled(to:)`` turns any palette into unsafe
    ///   entries on a 16-colour terminal.
    ///
    /// Used by `convertHalfBlocksColor`, which emboldens `▄` to close a
    /// rasterisation gap and must not do so at the cost of the colour.
    var foregroundSurvivesBold: Bool {
        switch self {
        case .trueColor, .ansi256, .grayscale, .mono: return true
        case .ansi16: return false
        case .palette(let palette): return palette.foregroundSurvivesBold
        }
    }
}

// MARK: - Dithering Mode

/// The dithering algorithm applied during color quantization.
public enum DitheringMode: Sendable, Equatable {
    /// Floyd-Steinberg error diffusion. Good for smooth gradients.
    ///
    /// Each mode diffuses only the error it can express. ``ASCIIColorMode/mono``
    /// and ``ASCIIColorMode/grayscale`` decide on luminance, so they carry the
    /// neutral part of theirs and no chroma; for `.grayscale` that part is under
    /// one level of 255, so there this draws the plain quantisation, which the
    /// glyph renderer's 24-step ramp then rounds to within one step of `none`.
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

    /// The area-sampling factor for every non-shape renderer: each sample —
    /// a ramp cell's tone, a solid/half-block pixel, a braille dot — is
    /// averaged from an N×N block of source pixels instead of the bilinear
    /// scaler's 2×2 point read, which aliases fine textures on heavy
    /// downscales. `nil` keeps the default (2 for luminance ramps longer
    /// than 12 levels, whose extra tonal levels only resolve with averaged
    /// sampling; 1 otherwise). Clamped to 1...4; higher factors cost
    /// quadratically more sampling for no visible gain. Ignored when
    /// shape-aware — the shape matcher already reads 96 staggered samples
    /// per cell.
    let supersampling: Int?

    /// The minimum Sobel gradient magnitude (in 0…1 darkness units, practical
    /// range roughly 0.3…2) for a cell to be drawn as a directional line
    /// glyph instead of the character it would otherwise get.
    /// Lower values trace more edges; `nil` disables line glyphs entirely.
    /// The default 0.9 triggers on a clean light/dark boundary while flat or
    /// lightly-textured cells fall through. The line glyphs follow the
    /// charset — ASCII uses `- | / \`, Unicode the box-drawing `─ │ ╱ ╲`; the
    /// block repertoire carries its own directional glyphs (halves, corner
    /// triangles) and a custom ramp has no vocabulary to borrow, so neither
    /// traces edges.
    ///
    /// **Independent of ``shapeAware``.** They answer different questions —
    /// where the image has an edge, and how a cell's ink should be chosen —
    /// and either can be had without the other. The two renderers take the
    /// gradient from what each of them has: the shape one from the six
    /// staggered regions it already sampled INSIDE the cell, the luminance one
    /// from the eight cells AROUND it. Same six slots, same formula, same
    /// units, so this number means the same thing in both.
    let edgeThreshold: Double?

    /// A recolouring applied to every pixel before anything measures the image.
    /// `nil` leaves the image as it is. See ``ASCIIToneCurve``.
    let toneCurve: ASCIIToneCurve?

    /// How hard to push each pixel away from its neighbours before any glyph is
    /// chosen — an unsharp mask, run at the render's own pixel grid. `0` (the
    /// default) leaves the picture alone; around `0.6` is a visible lift and `2`
    /// is heavy-handed.
    ///
    /// **The third of three independent questions**, and the one about the
    /// PICTURE rather than about the characters:
    ///
    /// - ``edgeThreshold`` asks *where does the picture have an edge*, and draws
    ///   the cells that do as directional line glyphs (`╱ ╲ ─ │`).
    /// - ``shapeAware`` asks *how should a cell's ink be chosen* — by where the
    ///   darkness sits inside the cell rather than by how much of it there is.
    /// - This asks *how much separation is there to see in the first place*. It
    ///   runs before either, on the pixels, so both of them read a picture whose
    ///   boundaries have already been pulled apart — and it is worth having with
    ///   neither of them, because a plain luminance ramp gains contrast at the
    ///   glyph boundaries too.
    ///
    /// Distinct from a ``toneCurve``, which is the GLOBAL version of the same
    /// wish: a curve moves every pixel of a given tone, wherever it sits, so
    /// steepening it clips the highlights and shadows to buy separation in the
    /// midtones. This moves a pixel only by how far it differs from its
    /// neighbours, so a flat region does not move at all.
    let edgeContrast: Double

    /// Creates a converter with the specified options.
    public init(
        characterSet: ASCIICharacterSet = .blocks(.fine),
        shapeAware: Bool = false,
        colorMode: ASCIIColorMode = .trueColor,
        dithering: DitheringMode = .none,
        supersampling: Int? = nil,
        edgeThreshold: Double? = 0.9,
        toneCurve: ASCIIToneCurve? = nil,
        edgeContrast: Double = 0
    ) {
        self.characterSet = characterSet
        self.shapeAware = shapeAware
        self.colorMode = colorMode
        self.dithering = dithering
        self.supersampling = supersampling.map { min(4, max(1, $0)) }
        self.edgeThreshold = edgeThreshold
        self.toneCurve = toneCurve
        self.edgeContrast = max(0, edgeContrast)
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
    /// handle, mirroring the downsampling that `ANSIRenderer` performs
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
            // Sixteen colours, not none. `.mono` was the old answer, and it
            // threw away the colour a 16-colour terminal genuinely has:
            // `TERM=xterm-color` drew every image in one ink whatever mode was
            // asked for. `.grayscale` lands here too and loses nothing by it —
            // its pixels are already grey, so the nearest of the sixteen to
            // each of them is one of the four the terminal has.
            return .ansi16
        // A chosen palette SURVIVES a downgrade, where a fidelity mode cannot.
        case (.palette(let colors), _):
            return .palette(colors.downsampled(to: depth))
        // "16.7 million colours" has no meaning on a 16-colour terminal and has
        // to be abandoned; "these three colours" still does — the honest
        // degradation is to quantise the colours themselves, which
        // ``foregroundColorCode(for:mode:)`` does when it emits them, exactly as
        // every other colour in the app is quantised. The intent is preserved
        // and only the accuracy drops, which is the right way round.
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
        let depth = ColorDepth.current
        var effectiveMode = colorMode.effective(for: depth)

        // Each rendering path has its own sub-cell pixel grid:
        //   luminance ramps        : 1×1  (one tone per cell)
        //   .blocks(.solid)        : 1×1  (one pixel per cell)
        //   .blocks(.fine)         : 1×2  (two vertical pixels per cell)
        //   .blocks(.braille)      : 2×4  (eight dots per cell)
        //   shape-aware (any)      : 5×10 (sampled at six staggered circles)
        // Every non-shape grid is scaled by the supersampling factor and then
        // box-reduced, so each sample — a cell's tone, a half-cell pixel, a
        // braille dot — is a true N×N area average rather than the bilinear
        // scaler's 2×2 point read (which aliases fine textures on heavy
        // downscales). The shape matcher needs no factor: it already reads
        // 96 staggered samples per cell.
        let pixelWidth: Int
        let pixelHeight: Int
        let factor: Int
        /// The sub-cell pixel grid, kept because ``ASCIIConverter/edgeContrast``
        /// measures its neighbourhood in cells rather than in pixels.
        let cellGrid: (x: Int, y: Int)
        if isShapeMatched {
            factor = 1
            cellGrid = (5, 10)
            pixelWidth = width * 5
            pixelHeight = height * 10
        } else {
            let grid: (x: Int, y: Int)
            switch characterSet {
            case .blocks(.fine):
                grid = (1, 2)
            case .blocks(.braille):
                grid = (2, 4)
            case .blocks(.solid), .ascii, .unicode, .blocks(.coarse), .blocks(.ramp),
                .customRamp:
                grid = (1, 1)
            }
            factor = effectiveSupersampling
            cellGrid = grid
            pixelWidth = width * grid.x * factor
            pixelHeight = height * grid.y * factor
        }

        // Scale to the (supersampled) pixel grid, then area-average down to
        // the render grid BEFORE dithering — error diffusion belongs at the
        // resolution the glyphs actually quantise (dither-then-average would
        // just smooth the pattern back out).
        // Over black, explicitly: the glyph renderers below read colour and
        // never alpha, and the resampler no longer darkens a soft edge for
        // them by accident. See `flattenedOverBlack`.
        var scaled = image.scaledBilinear(to: pixelWidth, pixelHeight).flattenedOverBlack()
        if factor > 1 {
            scaled = scaled.boxReduced(by: factor)
        }

        // Recolouring comes FIRST, before anything measures or quantises the
        // image. An inversion moves where the ink/background split falls, so a
        // threshold taken from the original would be taken from tones that no
        // longer exist — and a palette would map colours the render is not
        // going to draw. See ``ASCIIToneCurve``.
        if let toneCurve, !toneCurve.isIdentity {
            scaled.mapPixels(toneCurve.apply(to:))
        }

        // …and the local lift after it, for the same reason in the other
        // direction: a curve says what a TONE becomes and this says how far a
        // pixel stands from its neighbours, so sharpening first would then have
        // the curve flatten some of what it separated. Both run before anything
        // measures or quantises — the ink/background split below is taken from
        // the picture the glyphs will actually be chosen from.
        if edgeContrast > 0 {
            // Radii of a whole cell, not of a pixel: the picture is about to be
            // reduced to one glyph per cell, so a lift measured in pixels of a
            // 5×10 shape grid would average straight back out before a
            // character was chosen. In cells, the same number means the same
            // thing for every charset.
            scaled = scaled.sharpened(
                amount: edgeContrast, radiusX: cellGrid.x, radiusY: cellGrid.y)
        }

        // An adaptive palette takes its colours from the picture HERE, for the
        // same reason the threshold below is measured here: this is the picture
        // that will be drawn. Inert for every other mode.
        //
        // …and then fitted to the terminal AGAIN. The fit above ran on the
        // palette's stand-in greys; the colours chosen here are the picture's
        // own, as RGB triples, and a triple is a spelling a 256-colour terminal
        // does not have. Emitted as `38;2;r;g;b` there, Terminal.app read the
        // five parameters as five SGR codes — a channel value of 5 is *blink*,
        // 30–37 and 40–47 are the sixteen named colours — and drew "Most used"
        // as blinking primaries. Every other palette was fitted once and stayed
        // fitted; an adaptive one changes its colours after the fit, so it is
        // fitted after the change.
        effectiveMode = effectiveMode.derived(from: scaled, depth: depth).effective(for: depth)

        // The split between ink and background, measured from THIS image
        // rather than assumed to be mid-grey — see ``monoInkThreshold(for:)``.
        // Measured before dithering, because dithering quantises against it and
        // measuring after would be measuring its own output.
        let monoThreshold = Self.monoInkThreshold(for: scaled)

        // Apply dithering if requested (only meaningful for non-trueColor modes)
        if dithering == .floydSteinberg, effectiveMode != .trueColor {
            scaled = applyFloydSteinbergDithering(
                scaled, mode: effectiveMode, monoThreshold: monoThreshold)
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
            return convertBraille(
                scaled, width: width, height: height, mode: effectiveMode,
                monoThreshold: monoThreshold)
        case .blocks(.fine):
            return convertHalfBlocks(
                scaled, width: width, height: height, mode: effectiveMode,
                monoThreshold: monoThreshold)
        case .blocks(.solid):
            return convertBlocks(
                scaled, width: width, height: height, mode: effectiveMode,
                monoThreshold: monoThreshold)
        case .ascii, .unicode, .blocks(.coarse), .blocks(.ramp), .customRamp:
            return convertCharacterBased(scaled, width: width, height: height, mode: effectiveMode)
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
                edgeLineGlyphs)
        case .unicode(let glyphs):
            return (
                ShapeTableColumns(GlyphRepertoire.shapeVocabulary(from: GlyphRepertoire.unicode, count: glyphs)),
                edgeLineGlyphs)
        case .blocks:
            return (
                ShapeTableColumns(GlyphRepertoire.shapeVocabulary(from: GlyphRepertoire.blockShapes)),
                edgeLineGlyphs)
        case .customRamp:
            // Unreachable: `isShapeMatched` is false for custom ramps.
            return (ShapeTableColumns([]), edgeLineGlyphs)
        }
    }

    /// The charset's directional line glyphs, or `nil` where it has none.
    ///
    /// Separate from ``shapeConfiguration`` because edge tracing is not a
    /// shape-matching feature: it asks where the image has a strong gradient,
    /// which is a question about the picture rather than about how glyphs are
    /// chosen. Both renderers reach it.
    ///
    /// A custom ramp has no vocabulary to borrow from — the caller chose those
    /// characters and a `/` from nowhere would not belong — and the block
    /// repertoire carries its own directional glyphs (halves, corner
    /// triangles), so neither traces edges.
    var edgeLineGlyphs:
        (horizontal: Character, vertical: Character, backslash: Character, slash: Character)?
    {
        switch characterSet {
        case .ascii: return ("-", "|", "\\", "/")
        case .unicode: return ("─", "│", "╲", "╱")
        case .blocks, .customRamp: return nil
        }
    }

    /// The six darkness slots ``orientationGlyph`` reads, filled from the
    /// cells AROUND `(x, y)` rather than from regions inside it.
    ///
    /// The shape renderer samples six staggered circles per cell and takes the
    /// gradient of those; the luminance renderer has one number per cell and
    /// nothing inside it to differentiate. But it has eight neighbours, and an
    /// edge in the picture crosses them — so the same six slots are filled
    /// from the neighbourhood's corners and mid-sides, in the same layout
    /// (`[0][1]` top, `[2][3]` middle, `[4][5]` bottom). The formula, the
    /// units and the threshold are then literally the same ones.
    ///
    /// Out-of-bounds neighbours clamp to the edge cell, which makes the
    /// border's gradient zero across the frame rather than an artefact of
    /// falling off it.
    static func neighbourhoodSampling(
        darkness: [Double], width: Int, height: Int, x: Int, y: Int
    ) -> [Double] {
        func at(_ column: Int, _ row: Int) -> Double {
            darkness[min(max(row, 0), height - 1) * width + min(max(column, 0), width - 1)]
        }
        return [
            at(x - 1, y - 1), at(x + 1, y - 1),
            at(x - 1, y), at(x + 1, y),
            at(x - 1, y + 1), at(x + 1, y + 1),
        ]
    }

    /// The effective supersampling factor for the non-shape renderers: the
    /// explicit ``supersampling`` when given, else 2 for luminance ramps
    /// longer than 12 levels (whose extra tonal levels only resolve with
    /// averaged sampling) and 1 otherwise (the sub-cell block modes'
    /// ``characterRamp`` is empty, so they default to 1 — supersampling
    /// there is opt-in).
    private var effectiveSupersampling: Int {
        if let supersampling { return supersampling }
        return characterRamp.count > 12 ? 2 : 1
    }
}

// MARK: - Character-Based Conversion

extension ASCIIConverter {

    /// Converts using character brightness mapping: one (already
    /// area-averaged, when supersampling) pixel per cell, mapped by
    /// luminance onto the charset's density ramp.
    private func convertCharacterBased(
        _ image: RGBAImage,
        width: Int,
        height: Int,
        mode: ASCIIColorMode
    ) -> [String] {
        let ramp = characterRamp
        // Edge tracing is independent of shape matching: it asks where the
        // PICTURE has a strong gradient, which the luminance renderer can
        // answer as well as the shape one — from the cells around each cell
        // rather than from regions inside it. Built once, and only when a
        // threshold and a vocabulary are both in hand.
        let edge = edgeLineGlyphs
        let darkness: [Double]? =
            (edgeThreshold != nil && edge != nil)
            ? (0..<(width * height)).map { index in
                1.0 - (image.pixel(at: index % width, index / width).luminance / 255.0)
            } : nil

        var lines = [String]()
        lines.reserveCapacity(height)

        image.pixels.withUnsafeBufferPointer { pixels in
            for y in 0..<height {
                var row = ANSIRowBuilder(capacity: width * 20)
                let base = y * image.width

                for x in 0..<width {
                    let pixel = pixels[base + x]

                    // Map luminance to character: equal bands, one per ramp
                    // level. Scaling by `count - 1` and truncating (as this
                    // did) made the TOP level reachable only at luminance
                    // exactly 255 — invisible on a 15-level ramp, but a 2-level
                    // ramp rendered virtually everything as its dark level
                    // (space), i.e. a blank image.
                    let charIndex = Int((pixel.luminance / 255.0) * Double(ramp.count))
                    let clampedIndex = min(max(charIndex, 0), ramp.count - 1)
                    // A strong directional edge overrides the luminance match with
                    // the orientation-matched line glyph, exactly as it overrides
                    // the coverage match in the shape renderer — same six slots,
                    // same formula, same threshold.
                    let char =
                        darkness.flatMap { grid in
                            Self.orientationGlyph(
                                sampling: Self.neighbourhoodSampling(
                                    darkness: grid, width: width, height: height, x: x, y: y),
                                edge: edge, threshold: edgeThreshold)
                        } ?? ramp[clampedIndex]

                    row.setColors(foreground: cellColor(for: pixel, mode: mode), background: nil)
                    row.append(char)
                }
                lines.append(row.finish())
            }
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
        mode: ASCIIColorMode,
        monoThreshold: Double
    ) -> [String] {
        var lines = [String]()
        lines.reserveCapacity(height)
        image.pixels.withUnsafeBufferPointer { pixels in
            for y in 0..<height {
                var row = ANSIRowBuilder(capacity: width * 12)  // a background per colour run + a space per cell
                let base = y * image.width
                for x in 0..<width {
                    let pixel = pixels[base + x]
                    if mode == .mono {
                        row.append(Self.isMonoInk(pixel, threshold: monoThreshold) ? "█" : " ")
                        continue
                    }
                    row.setColors(foreground: nil, background: cellColor(for: pixel, mode: mode))
                    row.append(ascii: 0x20)
                }
                lines.append(row.finish())
            }
        }
        return lines
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
        case .blocks(.ramp):
            // Code point order, not ink order, and deliberately — see
            // `BlockStyle.ramp`.
            return Array("▁▂▃▄▅▆▇█▉▊▋▌▍▎▏")
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
    ///   - cellAspect: The terminal cell's height-to-width ratio (a cell is
    ///     taller than it is wide). Governs how many columns a row of the image
    ///     needs to look undistorted: a taller/narrower cell (larger value)
    ///     wants more columns. Defaults to `2.0` (Apple Terminal's typical
    ///     cell); iTerm2 and other terminals differ with the font/line spacing,
    ///     which is why the image looked horizontally squished when this was
    ///     hard-coded. Supply the real ratio (measured, or via
    ///     ``View/imageCellAspect(_:)``) to correct it.
    /// - Returns: The target width and height in characters.
    public static func targetSize(
        imageWidth: Int,
        imageHeight: Int,
        maxWidth: Int,
        maxHeight: Int? = nil,
        contentMode: ContentMode = .fit,
        overrideAspectRatio: Double? = nil,
        cellAspect: Double = 2.0
    ) -> (width: Int, height: Int) {
        // The terminal cell's height:width ratio — cells are taller than wide.
        let terminalAspect = Self.sanitizedCellAspect(cellAspect)

        // Use override ratio or compute from source dimensions.
        let sourceRatio =
            overrideAspectRatio
            ?? (Double(imageWidth) / Double(imageHeight))

        // A degenerate ratio — a zero-sized image (0/0 is NaN, w/0 is
        // infinite; both arrive as decode SUCCESSES) or a nonsense override —
        // has no geometry to honour, and feeding it onward traps in `Int(_:)`
        // at the first `.rounded()`. One cell is the answer for nothing.
        guard sourceRatio.isFinite, sourceRatio > 0 else { return (width: 1, height: 1) }

        // correctedRatio accounts for terminal character aspect (tall cells).
        // Guarded AGAIN, not redundantly: two finite operands can still
        // multiply to infinity (an override ratio near `Double.greatestFiniteMagnitude`).
        let correctedRatio = sourceRatio * terminalAspect
        guard correctedRatio.isFinite, correctedRatio > 0 else { return (width: 1, height: 1) }

        // `Int(clamping:)` throughout, not `Int(_:)`: the ratio is bounded but
        // the product with a caller's size need not fit an `Int`, and the
        // conversion is the one place this arithmetic can trap. A saturated
        // dimension is then cut back to the bound it exceeds, or floored at 1.
        let maxH = maxHeight ?? Int(clamping: (Double(maxWidth) / correctedRatio).rounded())

        let targetWidth: Int
        let targetHeight: Int

        switch contentMode {
        case .fit:
            // Scale to fit within both bounds. Result <= bounds.
            let widthFromHeight = Int(clamping: (Double(maxH) * correctedRatio).rounded())
            if widthFromHeight <= maxWidth {
                targetWidth = widthFromHeight
                targetHeight = maxH
            } else {
                targetWidth = maxWidth
                targetHeight = Int(clamping: (Double(maxWidth) / correctedRatio).rounded())
            }

        case .fill:
            // Scale so the shorter dimension fills its bound.
            // Result may exceed one bound.
            let widthFromHeight = Int(clamping: (Double(maxH) * correctedRatio).rounded())
            if widthFromHeight >= maxWidth {
                targetWidth = widthFromHeight
                targetHeight = maxH
            } else {
                targetWidth = maxWidth
                targetHeight = Int(clamping: (Double(maxWidth) / correctedRatio).rounded())
            }
        }

        return (width: max(1, targetWidth), height: max(1, targetHeight))
    }

    /// The cell aspects ``targetSize(imageWidth:imageHeight:maxWidth:maxHeight:contentMode:overrideAspectRatio:cellAspect:)``
    /// will compute with: cells between a tenth as tall as they are wide and
    /// ten times as tall.
    ///
    /// No terminal is near either end — measured cells sit between 1 and 4
    /// (`Terminal` clamps its own measurement to that) — so the range costs a
    /// real caller nothing. What it buys is that the arithmetic downstream
    /// is bounded: an aspect of `1e300` is finite, passes a `> 0` test, and
    /// still produces a width no `Int` can hold.
    public static let cellAspectRange: ClosedRange<Double> = 0.1...10

    /// `ratio`, if it is a cell aspect the arithmetic can use; otherwise the
    /// default of `2.0`, or the nearer end of ``cellAspectRange``.
    ///
    /// ONE implementation of the rule, shared by this function's own argument
    /// and by the `imageCellAspect` environment value that feeds it, so the
    /// two cannot drift. NaN, infinities and non-positive values have no
    /// meaning as a ratio and fall back to the default rather than to a bound.
    public static func sanitizedCellAspect(_ ratio: Double) -> Double {
        guard ratio.isFinite, ratio > 0 else { return 2.0 }
        return min(max(ratio, cellAspectRange.lowerBound), cellAspectRange.upperBound)
    }
}
