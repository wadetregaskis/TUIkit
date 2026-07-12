//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TrackConfiguration.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Track Configuration

/// A fully-configurable recipe for a "fill" track — the family of ``TrackStyle``
/// that draws a run of full cells, an optional fractional boundary cell, and an
/// unfilled remainder.
///
/// Most built-in fill styles are just presets of `TrackConfiguration` (see the
/// static members below), so the named styles and a hand-rolled
/// ``TrackStyle/custom(_:)`` share one renderer. This lets you mix any fill
/// glyph with any unfilled treatment — e.g. a shade-ramp fill with `·` dots
/// *or* `░` blocks for the empty region — without the framework predefining
/// every combination.
///
/// ```swift
/// // A shade-ramp fill, but with a solid background for the unfilled region:
/// ProgressView(value: 0.6)
///     .progressViewStyle(.custom(
///         TrackConfiguration(fullGlyph: "█", partialRamp: ["░", "▒", "▓"],
///                            emptyStyle: .background)))
/// ```
public struct TrackConfiguration: Sendable, Equatable {
    /// How the unfilled region of a track is drawn.
    public enum EmptyStyle: Sendable, Equatable {
        /// Draw `pattern` cyclically across the unfilled cells in the empty
        /// colour — a single character gives the classic look (`░`, `·`, `⠀`,
        /// `─`); several repeat in sequence, anchored to the track (cell *j*
        /// always shows the same pattern character, so the texture stays put
        /// while the fill sweeps over it).
        case pattern(String)

        /// Paint the ENTIRE track on the empty colour as a solid background,
        /// with the unfilled cells reduced to spaces. Two benefits: the
        /// unfilled region is one flat colour rather than a textured glyph, and
        /// because the filled cells carry the same background, any inter-cell
        /// gaps the terminal leaves in the fill show the bar's own colour
        /// instead of the terminal background — so the bar always reads as one
        /// solid unit.
        case background

        /// A single-character unfilled pattern — sugar for
        /// ``pattern(_:)`` with a one-character string.
        public static func glyph(_ glyph: Character) -> Self {
            .pattern(String(glyph))
        }
    }

    /// The fill pattern: repeated cyclically along the lit region and
    /// truncated at the boundary, so `"abc"` over five cells grows
    /// `a----`, `ab---`, `abc--`, `abca-`, `abcab`. A single character is
    /// the classic solid fill.
    ///
    /// Multi-cell characters (emoji, CJK) cannot be truncated mid-glyph:
    /// they coarsen the track's resolution to the widest character's cell
    /// width, and the track PERMANENTLY shrinks to a neat multiple of it —
    /// the width must not change with the fill:unfilled ratio. The sub-cell
    /// ``partialRamp`` is skipped in that coarse mode.
    public var fill: String

    /// The sub-cell ramp for the single fractional boundary cell, ordered
    /// lightest → fullest (e.g. `▏▎▍▌▋▊▉` or `░▒▓`). `nil` quantizes the fill to
    /// whole cells (no fractional boundary cell). A ramp of *n* glyphs gives
    /// `n + 1` steps of sub-cell precision at the boundary.
    public var partialRamp: [Character]?

    /// How the unfilled region is rendered.
    public var emptyStyle: EmptyStyle

    /// An optional per-cell colour gradient the lit cells fade across (the
    /// filled portion interpolates between the stops regardless of how many
    /// cells are lit). `nil` uses the flat filled colour.
    public var fillGradient: [Color]?

    /// Creates a track configuration.
    ///
    /// - Parameters:
    ///   - fill: The fill pattern, repeated cyclically along the lit region
    ///     (see ``fill``).
    ///   - partialRamp: The lightest→fullest ramp for the fractional boundary
    ///     cell, or `nil` to quantize to whole cells.
    ///   - emptyStyle: How the unfilled region is drawn.
    ///   - fillGradient: An optional colour gradient across the lit cells.
    public init(
        fill: String,
        partialRamp: [Character]? = nil,
        emptyStyle: EmptyStyle,
        fillGradient: [Color]? = nil
    ) {
        self.fill = fill
        self.partialRamp = partialRamp
        self.emptyStyle = emptyStyle
        self.fillGradient = fillGradient
    }

    /// Creates a track configuration with a single-character fill — sugar
    /// for ``init(fill:partialRamp:emptyStyle:fillGradient:)``.
    public init(
        fullGlyph: Character,
        partialRamp: [Character]? = nil,
        emptyStyle: EmptyStyle,
        fillGradient: [Color]? = nil
    ) {
        self.init(
            fill: String(fullGlyph), partialRamp: partialRamp,
            emptyStyle: emptyStyle, fillGradient: fillGradient)
    }
}

// MARK: - Built-in Presets

extension TrackConfiguration {
    /// `█` full cells, `░` empty — whole-cell quantized. Backs ``TrackStyle/block``.
    public static let block = TrackConfiguration(fullGlyph: "█", emptyStyle: .glyph("░"))

    /// `▓` (dark shade) full cells, `░` empty — whole-cell quantized. Backs
    /// ``TrackStyle/shade``. (Differs from ``block`` only in the fill glyph, so
    /// on most fonts it reads similarly — ``shadeRamp(gradient:)`` is the
    /// visibly "shaded" look.)
    public static let shade = TrackConfiguration(fullGlyph: "▓", emptyStyle: .glyph("░"))

    /// `▌` full cells, `─` empty line. Backs ``TrackStyle/bar``.
    public static let bar = TrackConfiguration(fullGlyph: "▌", emptyStyle: .glyph("─"))

    /// `█` full cells with an eighth-block fractional boundary (`▏▎▍▌▋▊▉`, 8
    /// steps/cell) and a solid background for the unfilled region. Backs
    /// ``TrackStyle/blockFine``. The background keeps the boundary cell's
    /// unfilled remainder the same colour as the empty run (no terminal-
    /// background seam) and delineates the whole bar as one solid unit.
    public static let blockFine = TrackConfiguration(
        fullGlyph: "█", partialRamp: ["▏", "▎", "▍", "▌", "▋", "▊", "▉"], emptyStyle: .background)

    /// `⣿` full cells with a braille-density fractional boundary (`⣀⣄⣤⣦⣶⣷⣿`, 8
    /// steps/cell), `⠀` (braille blank) empty. Backs ``TrackStyle/braille``.
    public static let braille = TrackConfiguration(
        fullGlyph: "⣿", partialRamp: ["⣀", "⣄", "⣤", "⣦", "⣶", "⣷", "⣿"], emptyStyle: .glyph("⠀"))

    /// `█` full cells with a shade-ramp fractional boundary (`░▒▓`, 4
    /// steps/cell), `·` empty, and an optional colour gradient. Backs
    /// ``TrackStyle/shadeRamp(gradient:)``.
    public static func shadeRamp(gradient: [Color]? = nil) -> TrackConfiguration {
        TrackConfiguration(
            fullGlyph: "█", partialRamp: ["░", "▒", "▓"], emptyStyle: .glyph("·"),
            fillGradient: gradient)
    }
}
