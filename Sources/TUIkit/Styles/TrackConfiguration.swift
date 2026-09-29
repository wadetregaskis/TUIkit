//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TrackConfiguration.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Track Configuration

/// A fully-configurable recipe for a "fill" track — the family of ``TrackStyle``
/// that draws a run of full cells, an optional leading-edge cell, and a
/// background.
///
/// Most built-in fill styles are just presets of `TrackConfiguration` (see the
/// static members below), so the named styles and a hand-rolled
/// ``TrackStyle/custom(_:)`` share one renderer. This lets you mix any fill
/// glyph with any background treatment — e.g. a shade-ramp fill with `·` dots
/// *or* `░` blocks for the background — without the framework predefining
/// every combination.
///
/// ```swift
/// // A shade-ramp fill, but with a solid background:
/// ProgressView(value: 0.6)
///     .progressViewStyle(.custom(
///         TrackConfiguration(fullGlyph: "█", leadingEdge: ["░", "▒", "▓"],
///                            background: .solid)))
/// ```
public struct TrackConfiguration: Sendable, Equatable {
    /// How a track's background — the cells the fill has not reached — is
    /// drawn.
    public enum Background: Sendable, Equatable {
        /// Draw `pattern` cyclically across the background cells in the
        /// background colour — a single character gives the classic look (`░`,
        /// `·`, `⠀`, `─`); several repeat in sequence, anchored to the track
        /// (cell *j* always shows the same pattern character, so the texture
        /// stays put while the fill sweeps over it).
        case pattern(String)

        /// Paint the ENTIRE track on the background colour, with the
        /// background cells reduced to spaces. Two benefits: the background is
        /// one flat colour rather than a textured glyph, and because the
        /// filled cells carry the same background, any inter-cell gaps the
        /// terminal leaves in the fill show the bar's own colour instead of the
        /// terminal background — so the bar always reads as one solid unit.
        case solid

        /// A single-character background pattern — sugar for
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
    /// the width must not change with the fill:background ratio. In that
    /// coarse mode the ``leadingEdge`` subdivides the quantum *block* instead
    /// of a cell: the partially-filled block renders as its leading-edge glyph
    /// repeated across the block.
    public var fill: String

    /// The leading edge: the lightest → fullest sub-cell ramp for the single
    /// partly-filled cell at the fill's front (e.g. `▏▎▍▌▋▊▉` or `░▒▓`). `nil`
    /// quantizes the fill to whole cells (no leading-edge cell). A ramp of *n*
    /// glyphs gives `n + 1` steps of sub-cell precision at the edge (sub-block,
    /// for a coarse multi-cell ``fill`` — see there).
    public var leadingEdge: [Character]?

    /// How the background is drawn.
    public var background: Background

    /// An optional per-cell colour gradient the lit cells fade across (the
    /// filled portion interpolates between the stops regardless of how many
    /// cells are lit). `nil` uses the flat filled colour.
    public var fillGradient: Gradient?

    /// An optional colour for the BACKGROUND, overriding the one the control
    /// would otherwise use.
    ///
    /// The background of a bar is half of what a bar looks like, and it was
    /// the half a style could say nothing about: the control passed its own
    /// recessive colour and that was that. A style that has chosen a fill also
    /// wants a say in what the fill is drawn *against*. `nil` keeps the
    /// control's choice, which is what every built-in preset does.
    public var backgroundColor: Color?

    /// An optional per-cell colour gradient the background cells fade across.
    ///
    /// Measured the same way the fill's is (see ``TrackGradientScaling``): with
    /// `.track` the background cells take the part of the ramp their POSITION
    /// on the bar names, so fill and background gradients drawn from the same
    /// stops are one continuous ramp interrupted by the leading edge. With
    /// `.region` the ramp is compressed into the background, which is the
    /// decorative reading.
    ///
    /// The leading-edge cell counts as the background's FIRST cell either way:
    /// a ``leadingEdge`` glyph covers only the filled part of that cell and the
    /// background colour shows through the rest, so it is a cell the background
    /// ramp reaches rather than one it steps over.
    public var backgroundGradient: Gradient?

    /// Creates a track configuration.
    ///
    /// - Parameters:
    ///   - fill: The fill pattern, repeated cyclically along the lit region
    ///     (see ``fill``).
    ///   - leadingEdge: The lightest→fullest ramp for the leading-edge cell,
    ///     or `nil` to quantize to whole cells.
    ///   - background: How the background is drawn.
    ///   - fillGradient: An optional colour gradient across the lit cells.
    ///   - backgroundColor: An optional colour for the background.
    ///   - backgroundGradient: An optional colour gradient across the
    ///     background cells.
    public init(
        fill: String,
        leadingEdge: [Character]? = nil,
        background: Background,
        fillGradient: Gradient? = nil,
        backgroundColor: Color? = nil,
        backgroundGradient: Gradient? = nil
    ) {
        self.fill = fill
        self.leadingEdge = leadingEdge
        self.background = background
        self.fillGradient = fillGradient
        self.backgroundColor = backgroundColor
        self.backgroundGradient = backgroundGradient
    }

    /// Creates a track configuration with a single-character fill — sugar
    /// for ``init(fill:leadingEdge:background:fillGradient:backgroundColor:backgroundGradient:)``.
    public init(
        fullGlyph: Character,
        leadingEdge: [Character]? = nil,
        background: Background,
        fillGradient: Gradient? = nil,
        backgroundColor: Color? = nil,
        backgroundGradient: Gradient? = nil
    ) {
        self.init(
            fill: String(fullGlyph), leadingEdge: leadingEdge,
            background: background, fillGradient: fillGradient,
            backgroundColor: backgroundColor, backgroundGradient: backgroundGradient)
    }
}

// MARK: - Built-in Presets

extension TrackConfiguration {
    /// `█` full cells on a solid background — whole-cell quantized. Backs
    /// ``TrackStyle/block``. The background is a solid fill, not a `░` shade
    /// glyph: mixing a full-cell solid block with a dithered shade makes the
    /// filled run read TALLER than the background on terminals whose font
    /// draws `░▒▓` as a sparse crosshatch (iTerm2) — see Terminal-compatibility.md.
    /// A uniform two-tone bar reads at a consistent height everywhere (same
    /// reasoning as ``blockFine``).
    public static let block = TrackConfiguration(fullGlyph: "█", background: .solid)

    /// `▓` (dark shade) full cells on a `░` background — whole-cell quantized.
    /// Backs ``TrackStyle/shade``. (Differs from ``block`` only in the fill
    /// glyph, so on most fonts it reads similarly — ``shadeRamp(gradient:)`` is
    /// the visibly "shaded" look.)
    public static let shade = TrackConfiguration(fullGlyph: "▓", background: .glyph("░"))

    /// `▌` full cells on a `─` line. Backs ``TrackStyle/bar``.
    public static let bar = TrackConfiguration(fullGlyph: "▌", background: .glyph("─"))

    /// `█` full cells with a leading edge of eighth blocks (`▏▎▍▌▋▊▉`, 8
    /// steps/cell) on a solid background. Backs ``TrackStyle/blockFine``. The
    /// solid background keeps the rest of the leading-edge cell the same colour
    /// as the background cells (no terminal-background seam) and delineates the
    /// whole bar as one solid unit.
    public static let blockFine = TrackConfiguration(
        fullGlyph: "█", leadingEdge: ["▏", "▎", "▍", "▌", "▋", "▊", "▉"], background: .solid)

    /// `⣿` full cells with a braille-density leading edge (`⣀⣄⣤⣦⣶⣷⣿`, 8
    /// steps/cell) on a `⠀` (braille blank) background. Backs
    /// ``TrackStyle/braille``.
    public static let braille = TrackConfiguration(
        fullGlyph: "⣿", leadingEdge: ["⣀", "⣄", "⣤", "⣦", "⣶", "⣷", "⣿"], background: .glyph("⠀"))

    /// `█` full cells with a shade-ramp leading edge (`░▒▓`, 4 steps/cell) on a
    /// `·` background, and an optional colour gradient. Backs
    /// ``TrackStyle/shadeRamp(gradient:)``.
    public static func shadeRamp(gradient: Gradient? = nil) -> TrackConfiguration {
        TrackConfiguration(
            fullGlyph: "█", leadingEdge: ["░", "▒", "▓"], background: .glyph("·"),
            fillGradient: gradient)
    }
}

// MARK: - Value Hash

/// Read by a `switch`: `solid` is spelled in the pattern string's spare values,
/// so the string's first word is written by nobody when it is stored in place.
/// See `_ValueHashing`.
extension TrackConfiguration.Background: _ValueHashing {
    package static func _mixValueHash(
        at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans
    ) -> Bool {
        switch pointer.assumingMemoryBound(to: Self.self).pointee {
        case .pattern(let pattern): plans.mixCase(0, pattern, into: &hash)
        case .solid: plans.mixCase(1, (), into: &hash)
        }
    }
}
