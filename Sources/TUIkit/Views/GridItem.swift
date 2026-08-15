//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GridItem.swift
//
//  The description of one grid track, and the arithmetic that turns a list of
//  them into concrete cell widths.
//
//  Split from the grids themselves because the resolution is the part worth
//  testing directly: everything interesting about a grid — whether `.adaptive`
//  fits four columns or five, what happens to the remainder when flexible
//  tracks cannot divide it evenly — is decided here, before a single view is
//  measured.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - GridItem

/// A description of one row or column in a ``LazyVGrid`` or ``LazyHGrid``.
///
/// Mirrors SwiftUI's `GridItem`, in cells rather than points.
///
/// ```swift
/// // Three equal columns.
/// LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) { … }
///
/// // As many 12-cell columns as fit.
/// LazyVGrid(columns: [GridItem(.adaptive(minimum: 12))]) { … }
/// ```
public struct GridItem: Sendable, Equatable {
    /// How a track claims space along the grid's repeating axis.
    public enum Size: Sendable, Equatable {
        /// Exactly this many cells, whatever is available.
        case fixed(Int)

        /// Between `minimum` and `maximum` cells, sharing what is left over
        /// with the other flexible tracks.
        ///
        /// - Note: `minimum` defaults to one cell rather than SwiftUI's ten
        ///   points — a cell is already the smallest unit that can hold
        ///   anything.
        case flexible(minimum: Int = 1, maximum: Int = .max)

        /// One track *definition* that repeats as many times as fits, each at
        /// least `minimum` cells wide.
        ///
        /// This is the one that makes a grid reflow with the terminal: the
        /// track count is an output, not an input.
        case adaptive(minimum: Int, maximum: Int = .max)
    }

    /// How this track claims space.
    public var size: Size

    /// Cells between this track and the next, or `nil` for the grid's default
    /// of one — the same gap ``HStackLayout`` leaves, because two items with no
    /// cell between them read as one item.
    ///
    /// Trailing spacing, so the last track's value is never used.
    public var spacing: Int?

    /// Where a subview sits inside this track's cell, or `nil` to use the
    /// grid's own alignment.
    public var alignment: Alignment?

    /// Creates a grid track.
    ///
    /// - Parameters:
    ///   - size: How the track claims space (default: `.flexible()`).
    ///   - spacing: Cells before the next track (default: the grid's).
    ///   - alignment: Where content sits in the cell (default: the grid's).
    public init(
        _ size: Size = .flexible(),
        spacing: Int? = nil,
        alignment: Alignment? = nil
    ) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}

// MARK: - Track Resolution

/// One concrete track: a width in cells, and how its contents sit in it.
struct GridTrack: Equatable {
    var extent: Int
    var alignment: Alignment?
    /// Cells between this track and the next. Unused on the last one.
    var spacing: Int
}

extension GridItem {
    /// The default gap between tracks, matching ``HStackLayout``.
    static let defaultSpacing = 1

    /// Turns track *descriptions* into concrete tracks that fit `available`.
    ///
    /// Two passes, because `.adaptive` makes the track count depend on the
    /// space and the spacing total depend on the track count:
    ///
    /// 1. **Expand.** Every non-adaptive item becomes one track at its
    ///    minimum; each adaptive item repeats to fill its share of what those
    ///    leave behind.
    /// 2. **Grow.** Whatever is still unclaimed is handed round the tracks that
    ///    can still take it, one pass per round, until it runs out or every
    ///    track is at its maximum.
    ///
    /// - Parameters:
    ///   - items: The track descriptions.
    ///   - available: Cells along the repeating axis.
    /// - Returns: The concrete tracks, in order. Empty if nothing fits.
    static func resolve(_ items: [GridItem], available: Int) -> [GridTrack] {
        guard !items.isEmpty, available > 0 else { return [] }

        // Pass 1a: what the non-adaptive tracks demand, so the adaptive ones
        // know what is left to divide.
        var claimed = 0
        var adaptiveItems = 0
        for item in items {
            let gap = item.spacing ?? defaultSpacing
            switch item.size {
            case .fixed(let width): claimed += max(0, width) + gap
            case .flexible(let minimum, _): claimed += max(1, minimum) + gap
            case .adaptive: adaptiveItems += 1
            }
        }
        let share = adaptiveItems > 0 ? max(0, available - claimed) / adaptiveItems : 0

        // Pass 1b: expand into concrete tracks at their minimum width.
        var tracks: [GridTrack] = []
        var ceilings: [Int] = []
        for item in items {
            let gap = item.spacing ?? defaultSpacing
            switch item.size {
            case .fixed(let width):
                let width = max(0, width)
                tracks.append(GridTrack(extent: width, alignment: item.alignment, spacing: gap))
                ceilings.append(width)
            case .flexible(let minimum, let maximum):
                let minimum = max(1, minimum)
                tracks.append(GridTrack(extent: minimum, alignment: item.alignment, spacing: gap))
                ceilings.append(max(minimum, maximum))
            case .adaptive(let minimum, let maximum):
                let unit = max(1, minimum)
                // At least one track even when nothing fits: a grid that
                // renders one clipped column is far easier to understand than
                // one that silently renders nothing.
                let count = max(1, (share + gap) / (unit + gap))
                for _ in 0..<count {
                    tracks.append(GridTrack(extent: unit, alignment: item.alignment, spacing: gap))
                    ceilings.append(max(unit, maximum))
                }
            }
        }

        // Pass 2: hand out the remainder.
        let gaps = tracks.dropLast().reduce(0) { $0 + $1.spacing }
        var leftover = available - gaps - tracks.reduce(0) { $0 + $1.extent }
        while leftover > 0 {
            let growable = tracks.indices.filter { tracks[$0].extent < ceilings[$0] }
            guard !growable.isEmpty else { break }
            // At least one cell each per round, so this always terminates:
            // every iteration either places a cell or finds nothing growable.
            let each = max(1, leftover / growable.count)
            for index in growable where leftover > 0 {
                let step = min(each, ceilings[index] - tracks[index].extent, leftover)
                tracks[index].extent += step
                leftover -= step
            }
        }
        return tracks
    }
}
