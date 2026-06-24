//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Scrollbar.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Scrollbar configuration

/// How end arrows are drawn on a scrollbar.
public enum ScrollbarArrows: Sendable, Equatable {
    /// No arrows; the track spans the whole scrollbar.
    case none
    /// One arrow at each end pointing away from the centre (`▲` … `▼`,
    /// `◀` … `▶`) — the classic scrollbar.
    case single
    /// Both arrows at each end (`▲▼` … `▲▼`), as on a classic Mac scrollbar.
    case double
}

/// When a scrollbar is shown.
public enum ScrollbarVisibility: Sendable, Equatable {
    /// Show the scrollbar only while the content overflows its viewport.
    case automatic
    /// Always reserve the scrollbar (even when everything fits).
    case visible
    /// Never show a scrollbar.
    case hidden
}

/// Which edges carry a scrollbar.
public struct ScrollbarEdges: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// The right edge (the default for vertical scrolling).
    public static let trailing = Self(rawValue: 1 << 0)
    /// The left edge.
    public static let leading = Self(rawValue: 1 << 1)
    /// The bottom edge (the default for horizontal scrolling).
    public static let bottom = Self(rawValue: 1 << 2)
    /// The top edge.
    public static let top = Self(rawValue: 1 << 3)
}

// MARK: - Track cell

/// One cell of a rendered scrollbar track.
///
/// `inverted` distinguishes the two anchorings that share a glyph set: a
/// bottom-/left-anchored partial is drawn directly (thumb colour as the glyph
/// ink), while a top-/right-anchored partial is drawn by *inverting* the
/// complementary block — the thumb colour becomes the cell background — because
/// Unicode has no top-/right-anchored partial-block series. See
/// ``ScrollbarRenderer``.
struct ScrollbarCell: Equatable {
    /// The block glyph (or a space for an empty track cell, `█` for a full one).
    let glyph: Character
    /// `true` when the thumb colour is the cell *background* (top/right anchor).
    let inverted: Bool

    static let empty = Self(glyph: " ", inverted: false)
    static let full = Self(glyph: "█", inverted: false)
}

// MARK: - Renderer

/// Computes the sub-cell-precise glyphs for a scrollbar track.
///
/// The thumb's size is proportional to `viewport / extent` and its position to
/// `offset / (extent − viewport)`, both measured in *eighths* of a cell so the
/// thumb's ends can land at fractional cell positions. The fractional ends use
/// partial block glyphs; a minimum thumb of one whole cell guarantees the two
/// ends always fall in different cells, so each partial cell is cleanly anchored
/// to one edge.
enum ScrollbarRenderer {
    /// The `count` track cells for the given scroll metrics.
    ///
    /// - Parameters:
    ///   - count: The track length, in cells.
    ///   - extent: The total content size (lines, or columns).
    ///   - viewport: The visible size.
    ///   - offset: The current scroll offset, in `0...(extent − viewport)`.
    ///   - proportional: When `true` the thumb is sized to `viewport / extent`;
    ///     when `false` it is a fixed one cell.
    ///   - vertical: `true` for a vertical scrollbar (lower-block glyphs,
    ///     inverting for the top-anchored end); `false` for a horizontal one
    ///     (left-block glyphs, inverting for the right-anchored end).
    static func trackCells(
        count: Int, extent: Int, viewport: Int, offset: Int,
        proportional: Bool = true, vertical: Bool
    ) -> [ScrollbarCell] {
        guard count > 0 else { return [] }
        // Everything fits: the thumb fills the whole track.
        guard extent > viewport, viewport > 0 else {
            return Array(repeating: .full, count: count)
        }

        let totalSub = count * 8
        let proportionalSub = Int((Double(viewport) / Double(extent) * Double(totalSub)).rounded())
        let thumbSub = min(totalSub, max(8, proportional ? proportionalSub : 8))
        let travel = totalSub - thumbSub
        let maxOffset = extent - viewport
        let rawStart = maxOffset > 0
            ? Int((Double(offset) / Double(maxOffset) * Double(travel)).rounded())
            : 0
        let start = max(0, min(travel, rawStart))
        let end = start + thumbSub

        var cells: [ScrollbarCell] = []
        cells.reserveCapacity(count)
        for cell in 0..<count {
            let cellLo = cell * 8
            let lo = max(start, cellLo) - cellLo  // 0...8 within the cell
            let hi = min(end, cellLo + 8) - cellLo
            if hi <= lo {
                cells.append(.empty)
            } else if lo == 0 && hi == 8 {
                cells.append(.full)
            } else if lo == 0 {
                // Covered from the cell's start edge (top / left).
                cells.append(
                    vertical
                        ? ScrollbarCell(glyph: Self.lowerBlock(8 - hi), inverted: true)
                        : ScrollbarCell(glyph: Self.leftBlock(hi), inverted: false))
            } else {
                // Covered to the cell's far edge (bottom / right).
                cells.append(
                    vertical
                        ? ScrollbarCell(glyph: Self.lowerBlock(8 - lo), inverted: false)
                        : ScrollbarCell(glyph: Self.leftBlock(lo), inverted: true))
            }
        }
        return cells
    }

    /// The lower block filled `eighths`/8 from the bottom: `▁`…`▇`, `█` at 8.
    static func lowerBlock(_ eighths: Int) -> Character {
        guard eighths >= 1 else { return " " }
        return Character(UnicodeScalar(0x2580 + min(8, eighths))!)
    }

    /// The left block filled `eighths`/8 from the left: `▏`…`▉`, `█` at 8.
    static func leftBlock(_ eighths: Int) -> Character {
        guard eighths >= 1 else { return " " }
        return Character(UnicodeScalar(0x2590 - min(8, eighths))!)
    }
}
