//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LazyGrids.swift
//
//  The grids that FLOW: you describe the tracks, hand over a pile of views, and
//  they wrap.
//
//  Distinct from ``Grid``, which is the one where you write the rows out
//  yourself with ``GridRow``. That one is a table with an explicit shape; this
//  one is a collection that reflows when the terminal is resized, and it is the
//  shape almost every real grid wants — swatches, thumbnails, a keypad.
//
//  Built on ``Layout`` rather than hand-rolled buffer arithmetic: track
//  placement is precisely what a layout does, so this needs no compositing code
//  of its own and inherits alignment guides, `LayoutValueKey`, and the measure
//  cache for free.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - The Layout

/// Flows subviews across a fixed set of tracks, wrapping onto a new line
/// whenever they run out.
///
/// Backs both grids: ``LazyVGrid`` repeats *columns* and wraps downward,
/// ``LazyHGrid`` repeats *rows* and wraps rightward. The two are mirror images,
/// so `axis` names which way the tracks repeat and the arithmetic below is
/// written once in terms of "across" (along the tracks) and "along" (the
/// direction it wraps).
private struct _LazyGridLayout: Layout, Sendable, Equatable {
    /// The direction subviews accumulate in: `.vertical` wraps downward
    /// (``LazyVGrid``), `.horizontal` rightward (``LazyHGrid``).
    let axis: Axis

    /// The track descriptions — columns when vertical, rows when horizontal.
    let items: [GridItem]

    /// Where a subview sits in its cell, unless its track says otherwise.
    let alignment: Alignment

    /// Cells between lines: rows when vertical, columns when horizontal.
    let spacing: Int

    // MARK: Geometry

    /// The size to offer a subview in a track of this extent.
    private func proposal(forTrack extent: Int) -> ProposedSize {
        axis == .vertical
            ? ProposedSize(width: extent, height: nil)
            : ProposedSize(width: nil, height: extent)
    }

    /// How thick each line is: row heights when vertical, column widths when
    /// horizontal — the largest subview on that line.
    private func lineBreadths(_ subviews: Subviews, tracks: [GridTrack]) -> [Int] {
        guard !tracks.isEmpty else { return [] }
        var breadths: [Int] = []
        var start = 0
        while start < subviews.count {
            var breadth = 0
            for column in 0..<tracks.count where start + column < subviews.count {
                let size = subviews[start + column].sizeThatFits(
                    proposal(forTrack: tracks[column].extent))
                breadth = max(breadth, axis == .vertical ? size.height : size.width)
            }
            breadths.append(breadth)
            start += tracks.count
        }
        return breadths
    }

    /// The tracks' total extent, gaps included.
    private func acrossExtent(_ tracks: [GridTrack]) -> Int {
        tracks.reduce(0) { $0 + $1.extent } + tracks.dropLast().reduce(0) { $0 + $1.spacing }
    }

    /// The extent available for the tracks to divide.
    ///
    /// A `nil` proposal (an unconstrained context — a `ScrollView`'s scrolling
    /// axis, `sizeThatFits` probing) resolves against the tracks' own natural
    /// demand instead, which is what makes a grid inside a horizontal scroller
    /// size to its content rather than collapse.
    private func across(of proposal: ProposedSize) -> Int {
        let proposed = axis == .vertical ? proposal.width : proposal.height
        guard let proposed, proposed > 0 else { return naturalAcross }
        return proposed
    }

    /// What the tracks ask for when nothing constrains them: every track at its
    /// minimum, adaptive ones counted once.
    private var naturalAcross: Int {
        let minima = items.reduce(0) { total, item in
            let minimum: Int =
                switch item.size {
                case .fixed(let extent): max(0, extent)
                case .flexible(let minimum, _): max(1, minimum)
                case .adaptive(let minimum, _): max(1, minimum)
                }
            return total + minimum
        }
        // Gaps go BETWEEN tracks, so there is one fewer than there are tracks —
        // counting the last item's trailing spacing would ask for a cell that
        // is never drawn.
        let gaps = items.dropLast().reduce(0) { $0 + ($1.spacing ?? GridItem.defaultSpacing) }
        return minima + gaps
    }

    // MARK: Layout

    func sizeThatFits(
        proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) -> ViewSize {
        let tracks = GridItem.resolve(items, available: across(of: proposal))
        guard !tracks.isEmpty, !subviews.isEmpty else { return ViewSize(width: 0, height: 0) }

        let breadths = lineBreadths(subviews, tracks: tracks)
        let along =
            breadths.reduce(0, +) + max(0, breadths.count - 1) * spacing
        // A partly-filled last line still claims the full track extent: a grid
        // that narrowed itself to its final row's content would jitter as items
        // are added, and would not line up with the rows above it.
        let across = acrossExtent(tracks)

        return axis == .vertical
            ? ViewSize(width: across, height: along)
            : ViewSize(width: along, height: across)
    }

    func placeSubviews(
        in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()
    ) {
        let tracks = GridItem.resolve(
            items, available: axis == .vertical ? bounds.width : bounds.height)
        guard !tracks.isEmpty else { return }

        let breadths = lineBreadths(subviews, tracks: tracks)
        var along = axis == .vertical ? bounds.y : bounds.x

        for (line, breadth) in breadths.enumerated() {
            var across = axis == .vertical ? bounds.x : bounds.y
            for (column, track) in tracks.enumerated() {
                let index = line * tracks.count + column
                guard index < subviews.count else { break }

                let cell =
                    axis == .vertical
                    ? CellRect(x: across, y: along, width: track.extent, height: breadth)
                    : CellRect(x: along, y: across, width: breadth, height: track.extent)
                subviews[index].place(
                    in: cell,
                    anchor: (track.alignment ?? alignment).unitPoint,
                    proposal: ProposedSize(width: cell.width, height: cell.height))
                across += track.extent + track.spacing
            }
            along += breadth + spacing
        }
    }
}

// MARK: - LazyVGrid

/// A grid that grows downward, flowing its content across a fixed set of
/// columns.
///
/// Mirrors SwiftUI's `LazyVGrid`. Describe the columns with ``GridItem``; the
/// content wraps onto a new row each time it fills them.
///
/// ```swift
/// LazyVGrid(columns: [GridItem(.adaptive(minimum: 10))], spacing: 1) {
///     ForEach(swatches) { swatch in
///         Text(swatch.name).border(swatch.colour)
///     }
/// }
/// ```
///
/// `.adaptive` is the one to reach for in a terminal: the column count becomes
/// an output of the width rather than something to guess, so the grid reflows
/// when the window is resized.
///
/// - Note: Unlike SwiftUI's, this grid measures every subview — "lazy" here
///   describes the API shape, not deferred construction. A grid whose rows must
///   be built lazily belongs inside a ``ScrollView``, which windows what it
///   renders.
public struct LazyVGrid<Content: View>: View {
    /// The column tracks.
    public let columns: [GridItem]

    /// Where content sits in a cell, unless its column says otherwise.
    public let alignment: HorizontalAlignment

    /// Blank rows between the grid's rows.
    public let spacing: Int

    /// The views to flow.
    public let content: Content

    /// Creates a vertically-growing grid.
    ///
    /// - Parameters:
    ///   - columns: The column tracks to flow content across.
    ///   - alignment: Horizontal placement within a cell (default: `.center`).
    ///   - spacing: Blank rows between rows (default: none).
    ///   - content: The views to flow.
    public init(
        columns: [GridItem],
        alignment: HorizontalAlignment = .center,
        spacing: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        _LazyGridLayout(
            axis: .vertical, items: columns,
            alignment: Alignment(horizontal: alignment, vertical: .center),
            spacing: spacing
        ) {
            content
        }
    }
}

// MARK: - LazyHGrid

/// A grid that grows rightward, flowing its content down a fixed set of rows.
///
/// Mirrors SwiftUI's `LazyHGrid`, and the horizontal mirror of ``LazyVGrid`` in
/// every respect: the rows are the fixed tracks, and content wraps into a new
/// column each time it fills them.
///
/// ```swift
/// ScrollView(.horizontal) {
///     LazyHGrid(rows: [GridItem(.fixed(1)), GridItem(.fixed(1))]) {
///         ForEach(items) { Text($0.name) }
///     }
/// }
/// ```
///
/// Rows are measured in **lines**, so `.fixed(1)` is a single-line row — the
/// usual case in a terminal, and why an explicit `.fixed` is more useful here
/// than the `.adaptive` that suits columns.
public struct LazyHGrid<Content: View>: View {
    /// The row tracks.
    public let rows: [GridItem]

    /// Where content sits in a cell, unless its row says otherwise.
    public let alignment: VerticalAlignment

    /// Blank columns between the grid's columns.
    public let spacing: Int

    /// The views to flow.
    public let content: Content

    /// Creates a horizontally-growing grid.
    ///
    /// - Parameters:
    ///   - rows: The row tracks to flow content down.
    ///   - alignment: Vertical placement within a cell (default: `.center`).
    ///   - spacing: Blank columns between columns (default: none).
    ///   - content: The views to flow.
    public init(
        rows: [GridItem],
        alignment: VerticalAlignment = .center,
        spacing: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.rows = rows
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        _LazyGridLayout(
            axis: .horizontal, items: rows,
            alignment: Alignment(horizontal: .center, vertical: alignment),
            spacing: spacing
        ) {
            content
        }
    }
}
