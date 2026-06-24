//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Scrollbar.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Scrollbar configuration

/// How end arrows are drawn on a scrollbar.
public enum ScrollbarArrows: Sendable, Hashable, CaseIterable {
    /// No arrows; the track spans the whole scrollbar.
    case none
    /// One arrow at each end pointing away from the centre (`▲` … `▼`,
    /// `◀` … `▶`) — the classic scrollbar.
    case single
    /// Both arrows at each end (`▲▼` … `▲▼`), as on a classic Mac scrollbar.
    case double
}

/// When a scrollbar is shown.
public enum ScrollbarVisibility: Sendable, Hashable, CaseIterable {
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

// MARK: - Environment & modifiers

private struct ScrollbarVisibilityKey: EnvironmentKey {
    // Hidden by default: scrollbars are opt-in, so existing scrolling views are
    // unchanged and their *absence* (the common case) carries no cost — which is
    // exactly what lets a Table skip sizing its content when no scrollbar exposes
    // the scroll position.
    static let defaultValue: ScrollbarVisibility = .hidden
}

private struct ScrollbarArrowsKey: EnvironmentKey {
    static let defaultValue: ScrollbarArrows = .single
}

private struct ScrollbarProportionalKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether scrolling views in this subtree draw a scrollbar. Defaults to
    /// ``ScrollbarVisibility/hidden`` (opt-in).
    public var scrollbarVisibility: ScrollbarVisibility {
        get { self[ScrollbarVisibilityKey.self] }
        set { self[ScrollbarVisibilityKey.self] = newValue }
    }

    /// The end-arrow style for scrollbars in this subtree. Defaults to
    /// ``ScrollbarArrows/single``.
    public var scrollbarArrows: ScrollbarArrows {
        get { self[ScrollbarArrowsKey.self] }
        set { self[ScrollbarArrowsKey.self] = newValue }
    }

    /// Whether a scrollbar's thumb is sized to the visible/total ratio (`true`,
    /// the default) or a fixed one cell (`false`).
    public var scrollbarProportionalThumb: Bool {
        get { self[ScrollbarProportionalKey.self] }
        set { self[ScrollbarProportionalKey.self] = newValue }
    }
}

extension View {
    /// Sets whether scrolling views (``ScrollView``, ``Table``, ``List``) within
    /// this view draw a scrollbar.
    ///
    /// A visible scrollbar reserves one cell on its edge (the right edge for
    /// vertical scrolling) and shows a thumb proportional to the visible region,
    /// at sub-cell precision. Off by default — pass ``ScrollbarVisibility/visible``
    /// to always show one or ``ScrollbarVisibility/automatic`` to show it only
    /// while the content overflows.
    public func scrollbarVisibility(_ visibility: ScrollbarVisibility) -> some View {
        environment(\.scrollbarVisibility, visibility)
    }

    /// Sets the end-arrow style of scrollbars within this view.
    public func scrollbarArrows(_ arrows: ScrollbarArrows) -> some View {
        environment(\.scrollbarArrows, arrows)
    }

    /// Sets whether scrollbar thumbs within this view are sized proportionally to
    /// the visible region (`true`) or a fixed single cell (`false`).
    public func scrollbarProportionalThumb(_ proportional: Bool) -> some View {
        environment(\.scrollbarProportionalThumb, proportional)
    }
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

/// The three colours a scrollbar draws with: the thumb (handle), the track
/// (groove behind it), and the end arrows.
struct ScrollbarColors {
    let thumb: Color
    let track: Color
    let arrow: Color
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

        let span = thumbSpan(
            count: count, extent: extent, viewport: viewport, offset: offset, proportional: proportional)
        let start = span.start
        let end = span.end

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

    /// The thumb's covered sub-cell range `start..<end` (eighths of a cell) within
    /// a `count`-cell track, shared by ``trackCells`` (rendering) and the hit-test
    /// (interaction) so the two never disagree about where the thumb is. The range
    /// spans `0...(count*8)`; the thumb is at least one whole cell (8 sub-units).
    static func thumbSpan(
        count: Int, extent: Int, viewport: Int, offset: Int, proportional: Bool
    ) -> (start: Int, end: Int) {
        let totalSub = count * 8
        guard count > 0, extent > viewport, viewport > 0 else { return (0, totalSub) }
        let proportionalSub = Int((Double(viewport) / Double(extent) * Double(totalSub)).rounded())
        let thumbSub = min(totalSub, max(8, proportional ? proportionalSub : 8))
        let travel = totalSub - thumbSub
        let maxOffset = extent - viewport
        let rawStart = maxOffset > 0
            ? Int((Double(offset) / Double(maxOffset) * Double(travel)).rounded())
            : 0
        let start = max(0, min(travel, rawStart))
        return (start, start + thumbSub)
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

    /// Styles one track cell.
    ///
    /// Fully-covered and empty cells are drawn as a *space* coloured by background
    /// — the thumb colour and the track colour respectively — never as a `█` glyph.
    /// Two reasons: adjacent block glyphs leave a hairline gap in some terminals
    /// (notably Terminal.app, the same gap seen between box-drawing characters),
    /// whereas contiguous background colour is seamless; and a background fill
    /// covers the *whole* cell, so a one-cell thumb is as solid as a multi-cell one
    /// instead of looking thinner. Only the fractional end cells need a partial
    /// glyph: a bottom-/left-anchored end draws the partial block in the thumb
    /// colour over the track, an inverted (top-/right-anchored) end swaps them so
    /// the thumb colour is the cell background — which is also how the two anchors
    /// Unicode lacks a partial-block series for are produced.
    static func styledCell(_ cell: ScrollbarCell, thumb: Color, track: Color) -> String {
        if cell.glyph == " " {
            return ANSIRenderer.colorize(" ", background: track)
        }
        if cell.glyph == "█" {
            return ANSIRenderer.colorize(" ", background: thumb)
        }
        if cell.inverted {
            return ANSIRenderer.colorize(String(cell.glyph), foreground: track, background: thumb)
        }
        return ANSIRenderer.colorize(String(cell.glyph), foreground: thumb, background: track)
    }

    /// The number of cells an arrow configuration reserves at each *end* combined
    /// (so a vertical bar loses this many track cells overall).
    static func arrowReserve(_ arrows: ScrollbarArrows) -> Int {
        switch arrows {
        case .none: return 0
        case .single: return 2
        case .double: return 4
        }
    }

    /// A vertical scrollbar `height` cells tall: a `▲`/`▼` arrow assembly at each
    /// end (per `arrows`) wrapped around a sub-cell-precise track. Returns one
    /// styled single-cell string per line. Arrows are dropped if the bar is too
    /// short to also show a track.
    static func verticalScrollbar(
        height: Int, extent: Int, viewport: Int, offset: Int,
        arrows: ScrollbarArrows, proportional: Bool, colors: ScrollbarColors
    ) -> [String] {
        guard height > 0 else { return [] }
        let reserve = height > arrowReserve(arrows) ? arrowReserve(arrows) : 0
        let trackLen = height - reserve
        let lines = trackCells(
            count: trackLen, extent: extent, viewport: viewport, offset: offset,
            proportional: proportional, vertical: true
        ).map { styledCell($0, thumb: colors.thumb, track: colors.track) }

        guard reserve > 0 else { return lines }
        let up = ANSIRenderer.colorize("▲", foreground: colors.arrow, background: colors.track)
        let down = ANSIRenderer.colorize("▼", foreground: colors.arrow, background: colors.track)
        // `single` → ▲ … ▼; `double` → ▲▼ … ▲▼ (both arrows at each end).
        let head = reserve == 4 ? [up, down] : [up]
        let tail = reserve == 4 ? [up, down] : [down]
        return head + lines + tail
    }

    /// A horizontal scrollbar `width` cells wide: a `◀`/`▶` arrow assembly at each
    /// end wrapped around a sub-cell-precise track, joined into one styled string.
    static func horizontalScrollbar(
        width: Int, extent: Int, viewport: Int, offset: Int,
        arrows: ScrollbarArrows, proportional: Bool, colors: ScrollbarColors
    ) -> String {
        guard width > 0 else { return "" }
        let reserve = width > arrowReserve(arrows) ? arrowReserve(arrows) : 0
        let trackLen = width - reserve
        let trackStr = trackCells(
            count: trackLen, extent: extent, viewport: viewport, offset: offset,
            proportional: proportional, vertical: false
        ).map { styledCell($0, thumb: colors.thumb, track: colors.track) }.joined()

        guard reserve > 0 else { return trackStr }
        let left = ANSIRenderer.colorize("◀", foreground: colors.arrow, background: colors.track)
        let right = ANSIRenderer.colorize("▶", foreground: colors.arrow, background: colors.track)
        let head = reserve == 4 ? left + right : left
        let tail = reserve == 4 ? left + right : right
        return head + trackStr + tail
    }
}
