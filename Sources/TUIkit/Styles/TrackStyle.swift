//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TrackStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Track Style

/// The visual style of a track-based control like ProgressView or Slider.
///
/// TUIKit provides five built-in styles using different Unicode characters:
///
/// ```
/// bar:       ▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌────────────────
/// block:     ████████████████░░░░░░░░░░░░░░░░
/// blockFine: ████████████████▍░░░░░░░░░░░░░░░   (sub-character precision)
/// dot:       ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬●────────────────
/// shade:     ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░
/// ```
public enum TrackStyle: Sendable, Equatable {
    /// Vertical bar characters with a horizontal line track.
    ///
    /// Uses `▌` for filled and `─` for empty.
    case bar

    /// Full block characters (default).
    ///
    /// Uses `█` for filled cells and `░` for empty cells.
    case block

    /// Full block characters with sub-character fractional precision.
    ///
    /// Uses `█` for filled cells, fractional blocks (`▉▊▋▌▍▎▏`) for the
    /// partial cell at the boundary, and `░` for empty cells. This gives
    /// 8x finer visual resolution than ``block``.
    case blockFine

    /// Rectangle track with a dot indicator at the progress position.
    ///
    /// Uses `▬` for filled, `●` as the progress head, and `─` for empty.
    /// The dot head renders in the accent color.
    case dot

    /// Shade characters for a softer, textured look.
    ///
    /// Uses `▓` (dark shade) for filled and `░` (light shade) for empty.
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
    case shadeRamp(gradient: [Color]? = nil)

    /// Three-segment custom fill, e.g. `("Sw", "i", "ft")` →
    /// `Swiiiiiiift` at a wide track or `Swift` at the narrow end.
    ///
    /// `leading` is drawn once at the left of the filled region;
    /// `trailing` once at the right of the filled region; `middle` is
    /// repeated across the gap between them. Empty cells are filled with
    /// a space, padded out to the track's width. Each segment is
    /// rendered separately so callers can style them independently —
    /// pass coloured/bold/dim strings via the segments directly.
    case threeSegment(leading: String, middle: String, trailing: String, emptyFill: String = " ")
}

// MARK: - Backwards Compatibility

/// Backwards-compatible type alias for `TrackStyle`.
///
/// Use `TrackStyle` in new code. This alias exists to maintain
/// compatibility with existing code using `ProgressBarStyle`.
@available(*, deprecated, renamed: "TrackStyle")
public typealias ProgressBarStyle = TrackStyle
