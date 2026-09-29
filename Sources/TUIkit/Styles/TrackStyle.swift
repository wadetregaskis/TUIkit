//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TrackStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Track Style

/// The visual style of a track-based control like ProgressView or Slider.
///
/// TUIkit provides five built-in styles using different Unicode characters:
///
/// ```
/// bar:       ▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌────────────────
/// block:     ████████████████                 (empty run is a solid bg)
/// blockFine: ████████████████▍                (sub-cell precision; solid bg)
/// dot:       ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬●────────────────
/// knob:      ━━━━━━━━━━━━━━━●────────────────   (Slider default)
/// shade:     ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░
/// ```
///
/// The "fill" styles (``bar``, ``block``, ``blockFine``, ``shade``,
/// ``braille``, ``shadeRamp(gradient:)``) are presets of ``TrackConfiguration``
/// and share one renderer; ``custom(_:)`` lets you supply your own recipe.
public enum TrackStyle: Sendable, Equatable {
    /// Vertical bar characters with a horizontal line track.
    ///
    /// Uses `▌` for filled and `─` for empty.
    case bar

    /// Full block characters (default).
    ///
    /// Uses `█` for filled cells and a solid background for the empty run —
    /// NOT a `░` shade glyph, which reads taller than `█` on terminals whose
    /// font draws the shades as a sparse crosshatch (iTerm2). The result is a
    /// uniform-height two-tone bar. See ``TrackConfiguration/block``.
    case block

    /// Full block characters with sub-character fractional precision.
    ///
    /// Uses `█` for filled cells and fractional blocks (`▉▊▋▌▍▎▏`) for the
    /// partial cell at the boundary — 8× finer visual resolution than
    /// ``block``. The unfilled region is a solid background (not `░` glyphs),
    /// so the boundary cell's remainder matches the empty run and any
    /// inter-cell gaps in the fill show the bar's colour, keeping it one solid
    /// unit. See ``TrackConfiguration/blockFine``.
    case blockFine

    /// Rectangle track with a dot indicator at the progress position.
    ///
    /// Uses `▬` for filled, `●` as the progress head, and `─` for empty.
    /// The dot head renders in the accent color.
    case dot

    /// A thin rail with a round knob at the value — the ``Slider`` default.
    ///
    /// Uses `━` (heavy line) for the filled rail, `●` as the knob, and `─`
    /// (light line) for the empty rail. The knob renders in the accent color.
    /// The rail-and-knob reads unmistakably as a draggable control, distinct
    /// from ``ProgressView``'s solid block bar and ``Gauge``'s shaded meter.
    case knob

    /// A plain line with a marker at the value and NO fill — `─────●─────`.
    ///
    /// Uses `─` on BOTH sides of the position and `●` as the accent marker.
    /// Unlike ``dot``/``knob`` (which fill up to the marker), this only marks
    /// the position — used by the non-capacity `Gauge` accessory style, which
    /// shows *where* the value sits rather than a filled range.
    case marker

    /// Shade characters for a softer, textured look.
    ///
    /// Uses `▓` (dark shade) for filled and `░` (light shade) for empty. This
    /// differs from ``block`` only in the fill glyph (`▓` vs `█`), so on most
    /// terminal fonts the two read alike; ``shadeRamp(gradient:)`` is the
    /// style that delivers a visibly graded "shaded" look.
    case shade

    /// Braille dot fill, 8 steps per cell using `⣀⣄⣤⣦⣶⣷⣿`.
    ///
    /// Each cell ramps up from "nothing" to "full" through seven
    /// intermediate dot patterns, so the rightmost cell of the filled
    /// region shows the fractional sub-cell progress at the cost of
    /// just one glyph. Empty cells use `⠀` (braille blank).
    case braille

    /// 4-step shade-ramp fill `░▒▓█` with an optional colour gradient.
    ///
    /// Each cell picks from `░ ▒ ▓ █` based on its sub-cell fraction —
    /// so the rightmost filled cell carries the boundary's fractional
    /// information visually rather than via colour. When
    /// `gradient` is non-nil, the filled portion interpolates between
    /// the supplied stops, smoothly fading across the track regardless
    /// of how many cells are lit. Empty cells use `·`.
    case shadeRamp(gradient: Gradient? = nil)

    /// Three-segment custom fill, e.g. `("Sw", "i", "ft")` →
    /// `Swiiiiiiift` at a wide track or `Swift` at the narrow end.
    ///
    /// `leading` is drawn once at the left of the filled region;
    /// `trailing` once at the right of the filled region; `middle` is
    /// repeated across the gap between them. Background cells are filled with
    /// `backgroundPattern` (a space by default), padded out to the track's width.
    ///
    /// `coloring` selects how the lit region is coloured: the control's
    /// own filled colour (``SegmentColoring/automatic``, the default), one
    /// solid colour, a colour per segment, or a per-cell gradient across
    /// the lit span. With `.automatic`/`.solid`/`.perSegment` the segment
    /// strings may carry their own embedded ANSI styling; `.gradient`
    /// re-colours every cell, so it expects plain segment text.
    ///
    /// (Five associated values is the honest shape here — three segment
    /// strings, the background pattern, and the colouring are orthogonal, and
    /// bundling them into a struct would just add a second spelling of the
    /// same call.)
    case threeSegment(  // swiftlint:disable:this enum_case_associated_values_count
        leading: String, middle: String, trailing: String, backgroundPattern: String = " ",
        coloring: SegmentColoring = .automatic)

    /// A fully-configurable "fill" track.
    ///
    /// Most fill styles above are just presets of ``TrackConfiguration``; use
    /// this to supply your own combination of fill glyph, leading-edge ramp,
    /// background (a pattern or solid), and optional colour gradient — without
    /// the framework predefining every mix.
    case custom(TrackConfiguration)
}

// MARK: - Segment Coloring

/// How a ``TrackStyle/threeSegment(leading:middle:trailing:backgroundPattern:coloring:)``
/// track's lit region is coloured.
public enum SegmentColoring: Sendable, Equatable {
    /// The control's own filled colour (the default).
    case automatic

    /// One solid colour for all three segments.
    case solid(Color)

    /// A distinct colour for each segment (the truncated-endpoints case at
    /// very small fractions uses `leading`).
    case perSegment(leading: Color, middle: Color, trailing: Color)

    /// A per-cell colour fade across the lit span, interpolating between the
    /// stops — the same stop model as ``TrackConfiguration/fillGradient`` and
    /// ``TrackStyle/shadeRamp(gradient:)``. Needs at least two stops (fewer
    /// fall back to the control's filled colour).
    case gradient(Gradient)
}

// MARK: - Value Hash

/// Read by a `switch` — its payloads hold strings, gradients and colours, so no
/// fixed choice of its bytes is always written — and each case's payload by
/// its own plan. See `_ValueHashing`.
extension TrackStyle: _ValueHashing {
    package static func _mixValueHash(
        at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans
    ) -> Bool {
        switch pointer.assumingMemoryBound(to: Self.self).pointee {
        case .bar: plans.mixCase(0, (), into: &hash)
        case .block: plans.mixCase(1, (), into: &hash)
        case .blockFine: plans.mixCase(2, (), into: &hash)
        case .dot: plans.mixCase(3, (), into: &hash)
        case .knob: plans.mixCase(4, (), into: &hash)
        case .marker: plans.mixCase(5, (), into: &hash)
        case .shade: plans.mixCase(6, (), into: &hash)
        case .braille: plans.mixCase(7, (), into: &hash)
        case .shadeRamp(let gradient): plans.mixCase(8, gradient, into: &hash)
        case .threeSegment(let leading, let middle, let trailing, let backgroundPattern, let coloring):
            plans.mixCase(9, (leading, middle, trailing, backgroundPattern, coloring), into: &hash)
        case .custom(let configuration): plans.mixCase(10, configuration, into: &hash)
        }
    }
}

/// Read by a `switch`, as ``TrackStyle`` is.
extension SegmentColoring: _ValueHashing {
    package static func _mixValueHash(
        at pointer: UnsafeRawPointer, into hash: inout UInt64, plans: ValueHashPlans
    ) -> Bool {
        switch pointer.assumingMemoryBound(to: Self.self).pointee {
        case .automatic: plans.mixCase(0, (), into: &hash)
        case .solid(let color): plans.mixCase(1, color, into: &hash)
        case .perSegment(let leading, let middle, let trailing):
            plans.mixCase(2, (leading, middle, trailing), into: &hash)
        case .gradient(let gradient): plans.mixCase(3, gradient, into: &hash)
        }
    }
}
