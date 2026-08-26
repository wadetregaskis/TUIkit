//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Grid.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Grid Cell Layout Values

/// How many columns a cell spans, set with ``View/gridCellColumns(_:)``.
private struct GridCellColumnsKey: LayoutValueKey {
    static let defaultValue = 1
}

/// A cell's own placement within its box, set with ``View/gridCellAnchor(_:)``.
private struct GridCellAnchorKey: LayoutValueKey {
    static let defaultValue: UnitPoint? = nil
}

/// A column-wide horizontal alignment, set with ``View/gridColumnAlignment(_:)``
/// on any cell in that column.
private struct GridColumnAlignmentKey: LayoutValueKey {
    static let defaultValue: HorizontalAlignment? = nil
}

extension View {
    /// Makes this cell span `count` columns of its ``Grid``.
    ///
    /// - Parameter count: The number of columns to span. Values below 1 are
    ///   treated as 1.
    /// - Returns: A view carrying the span.
    public func gridCellColumns(_ count: Int) -> some View {
        layoutValue(key: GridCellColumnsKey.self, value: max(1, count))
    }

    /// Overrides where this cell sits inside the box the grid gives it.
    ///
    /// - Parameter anchor: The point of the cell that meets the same point of
    ///   its box.
    /// - Returns: A view carrying the anchor.
    public func gridCellAnchor(_ anchor: UnitPoint) -> some View {
        layoutValue(key: GridCellAnchorKey.self, value: anchor)
    }

    /// Sets the horizontal alignment for this cell's whole **column**.
    ///
    /// As in SwiftUI, one cell decides for the column it is in; if several cells
    /// in a column disagree, the first one the grid walks wins.
    ///
    /// - Parameter guide: The alignment for the column.
    /// - Returns: A view carrying the column alignment.
    public func gridColumnAlignment(_ guide: HorizontalAlignment) -> some View {
        layoutValue(key: GridColumnAlignmentKey.self, value: guide)
    }
}

// MARK: - Grid Row

/// One row of a ``Grid``.
///
/// Each view inside a row is one cell, unless it carries
/// ``View/gridCellColumns(_:)``.
public struct GridRow<Content: View>: View {
    /// Overrides the grid's vertical alignment for this row.
    public let alignment: VerticalAlignment?

    /// The row's cells.
    public let content: Content

    /// Creates a grid row.
    ///
    /// - Parameters:
    ///   - alignment: The vertical alignment for this row's cells, or `nil` to
    ///     use the grid's.
    ///   - content: The cells.
    public init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    public var body: some View {
        // A `GridRow` outside a `Grid` is a row of views, which is the least
        // surprising reading of it — and matches SwiftUI, where the row's
        // layout is supplied by the enclosing grid and it degrades to a
        // horizontal arrangement without one.
        HStack(alignment: alignment ?? .center, spacing: 1) { content }
    }
}

/// A view the enclosing ``Grid`` should treat as a row rather than a cell.
@MainActor
protocol GridRowProviding {
    /// This row's vertical alignment override, if it set one.
    var rowAlignment: VerticalAlignment? { get }

    /// The row's cells.
    func gridCells(context: RenderContext) -> [ChildView]
}

extension GridRow: GridRowProviding {
    var rowAlignment: VerticalAlignment? { alignment }

    func gridCells(context: RenderContext) -> [ChildView] {
        resolveChildViews(from: content, context: context)
    }
}

// MARK: - Grid

/// A container that arranges its ``GridRow``s into aligned columns.
///
/// Columns are as wide as their widest cell, so cells line up across rows
/// without any of them being told a width:
///
/// ```swift
/// Grid(alignment: .leading) {
///     GridRow {
///         Text("Name");  Text("Size"); Text("Kind")
///     }
///     GridRow {
///         Text("README"); Text("2 KB"); Text("Markdown")
///     }
/// }
/// ```
///
/// A child that is **not** a `GridRow` spans the whole width — which is how a
/// `Divider` between rows works.
///
/// ## Terminal specifics
///
/// Spacings are `Int` cells, defaulting to 1 column and 0 rows: a column gap of
/// zero would run adjacent text together, whereas rows are already separated by
/// being different lines.
///
/// SwiftUI's `gridCellUnsizedAxes(_:)` has no counterpart. It exists in SwiftUI so
/// a `Divider` does not force its own ideal length onto a column; here a
/// non-`GridRow` child already spans the full width, which is the case that
/// needed it.
public struct Grid<Content: View>: View {
    /// How cells sit inside the boxes the grid gives them.
    public let alignment: Alignment

    /// Cells between columns, in cells.
    public let horizontalSpacing: Int

    /// Blank lines between rows.
    public let verticalSpacing: Int

    /// The grid's rows.
    public let content: Content

    /// Creates a grid.
    ///
    /// - Parameters:
    ///   - alignment: How each cell sits in its box (default `.center`).
    ///   - horizontalSpacing: Columns between cells (default 1).
    ///   - verticalSpacing: Blank lines between rows (default 0).
    ///   - content: The ``GridRow``s.
    public init(
        alignment: Alignment = .center,
        horizontalSpacing: Int = 1,
        verticalSpacing: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    public var body: some View {
        _GridCore(
            alignment: alignment, horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing, content: content)
    }
}

// MARK: - Core

/// Measures every cell, derives the column widths and row heights, then places
/// the cells into that lattice.
struct _GridCore<Content: View>: View, Renderable, Layoutable {
    let alignment: Alignment
    let horizontalSpacing: Int
    let verticalSpacing: Int
    let content: Content

    var body: Never {
        fatalError("_GridCore renders via Renderable")
    }

    /// One row's worth of resolved cells. A `nil` `row` marks a child that was
    /// not a `GridRow` and therefore spans every column.
    private struct Row {
        let cells: [ChildView]
        let spans: [Int]
        let alignment: VerticalAlignment?
        let spansFullWidth: Bool
    }

    private func rows(context: RenderContext) -> [Row] {
        resolveChildViews(from: content, context: context).map { child in
            guard let provider = child.wrappedView as? GridRowProviding else {
                return Row(cells: [child], spans: [1], alignment: nil, spansFullWidth: true)
            }
            let cells = provider.gridCells(context: context)
            return Row(
                cells: cells,
                spans: cells.map { $0.gridSpan },
                alignment: provider.rowAlignment,
                spansFullWidth: false)
        }
    }

    /// The lattice both passes agree on: column widths, row heights, and the
    /// per-column alignment overrides.
    ///
    /// Column widths come from the single-column cells alone. A spanning cell
    /// that needs more than the columns it covers grows the LAST of them —
    /// the columns it shares with single-column cells keep the width those
    /// cells asked for, which is the property that makes a grid look like a
    /// grid.
    private func lattice(
        _ rows: [Row], context: RenderContext
    ) -> (columns: [Int], heights: [Int], columnAlignment: [Int: HorizontalAlignment]) {
        var columns: [Int] = []
        var heights: [Int] = []
        var columnAlignment: [Int: HorizontalAlignment] = [:]

        func widen(to count: Int) {
            while columns.count < count { columns.append(0) }
        }

        // Pass A: single-column cells set their column's width.
        for row in rows {
            var height = 0
            var index = 0
            for (cell, span) in zip(row.cells, row.spans) {
                let size = cell.measure(proposal: .unspecified, context: context)
                height = max(height, size.height)
                widen(to: index + span)
                if span == 1 {
                    columns[index] = max(columns[index], size.width)
                    if let guide = cell.gridColumnAlignment, columnAlignment[index] == nil {
                        columnAlignment[index] = guide
                    }
                }
                index += span
            }
            heights.append(height)
        }

        // Pass B: spanning cells grow their last column if they still overflow.
        for row in rows where !row.spansFullWidth {
            var index = 0
            // Every cell, not just the spanning ones: a `where` on the loop
            // skips the whole body, `index += span` included, so a spanning
            // cell preceded by any ordinary one measured its width against the
            // wrong columns and grew the wrong column. The render loop advances
            // for every cell; this has to agree with it.
            for (cell, span) in zip(row.cells, row.spans) {
                defer { index += span }
                guard span > 1 else { continue }
                let size = cell.measure(proposal: .unspecified, context: context)
                let covered =
                    columns[index..<(index + span)].reduce(0, +)
                    + (span - 1) * horizontalSpacing
                if size.width > covered {
                    columns[index + span - 1] += size.width - covered
                }
            }
        }
        return (columns, heights, columnAlignment)
    }

    /// The grid's total width for a lattice.
    private func totalWidth(_ columns: [Int]) -> Int {
        columns.reduce(0, +) + max(0, columns.count - 1) * horizontalSpacing
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let rows = rows(context: context)
        guard !rows.isEmpty else { return ViewSize.fixed(0, 0) }
        let lattice = lattice(rows, context: context)
        let height =
            lattice.heights.reduce(0, +) + max(0, lattice.heights.count - 1) * verticalSpacing
        return ViewSize(
            width: min(totalWidth(lattice.columns), max(0, proposal.width ?? context.availableWidth)),
            height: min(height, max(0, proposal.height ?? context.availableHeight)))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let rows = rows(context: context)
        guard !rows.isEmpty else { return FrameBuffer() }
        let (columns, heights, columnAlignment) = lattice(rows, context: context)
        let width = totalWidth(columns)
        guard width > 0 else { return FrameBuffer() }

        // Column x-origins, accumulated rather than divided — the integer rule
        // recorded on `Layout`.
        var origins: [Int] = []
        var x = 0
        for column in columns {
            origins.append(x)
            x += column + horizontalSpacing
        }

        var result = FrameBuffer()
        for (rowIndex, row) in rows.enumerated() {
            let rowHeight = heights[rowIndex]
            var canvas = FrameBuffer(emptyWithWidth: width, height: max(1, rowHeight))
            var index = 0
            for (cell, span) in zip(row.cells, row.spans) {
                let boxWidth =
                    row.spansFullWidth
                    ? width
                    : columns[index..<min(columns.count, index + span)].reduce(0, +)
                        + (span - 1) * horizontalSpacing
                let rendered = cell.render(
                    width: max(0, boxWidth), height: max(1, rowHeight), context: context)
                let box = CellRect(
                    x: row.spansFullWidth ? 0 : origins[index], y: 0,
                    width: max(0, boxWidth), height: max(1, rowHeight))
                canvas = canvas.composited(
                    with: rendered,
                    at: placement(
                        of: rendered, in: box, cell: cell,
                        rowAlignment: row.alignment,
                        columnAlignment: row.spansFullWidth ? nil : columnAlignment[index]))
                index += span
            }
            result.appendVertically(canvas, spacing: rowIndex > 0 ? verticalSpacing : 0)
        }
        return result.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// Where a rendered cell sits inside its box.
    ///
    /// Precedence matches SwiftUI: the cell's own `gridCellAnchor` beats the
    /// column's `gridColumnAlignment`, which beats the row's alignment, which
    /// beats the grid's. Each axis floors exactly once — see ``AlignmentID``.
    private func placement(
        of rendered: FrameBuffer,
        in box: CellRect,
        cell: ChildView,
        rowAlignment: VerticalAlignment?,
        columnAlignment: HorizontalAlignment?
    ) -> (x: Int, y: Int) {
        if let anchor = cell.gridCellAnchor {
            let dx = Int((anchor.x * Double(box.width - rendered.width)).rounded(.down))
            let dy = Int((anchor.y * Double(box.height - rendered.height)).rounded(.down))
            return (
                x: box.x + min(max(0, dx), max(0, box.width - rendered.width)),
                y: box.y + min(max(0, dy), max(0, box.height - rendered.height))
            )
        }
        let horizontal = columnAlignment ?? alignment.horizontal
        let vertical = rowAlignment ?? alignment.vertical
        return (
            x: box.x + horizontal.childOffset(childWidth: rendered.width, in: box.width),
            y: box.y + vertical.childOffset(childHeight: rendered.height, in: box.height)
        )
    }
}

// MARK: - Reading a Cell's Grid Values

extension ChildView {
    /// The span this cell asked for, or 1.
    fileprivate var gridSpan: Int {
        gridValue(GridCellColumnsKey.self) ?? 1
    }

    /// The anchor this cell asked for, if any.
    fileprivate var gridCellAnchor: UnitPoint? {
        gridValue(GridCellAnchorKey.self).flatMap { $0 }
    }

    /// The column alignment this cell set for its column, if any.
    fileprivate var gridColumnAlignment: HorizontalAlignment? {
        gridValue(GridColumnAlignmentKey.self).flatMap { $0 }
    }

    /// Reads a layout value straight off the wrapped view.
    ///
    /// `LayoutSubview`'s subscript is the public spelling of this, but a grid
    /// is not a `Layout` — its cells are two-dimensional, which
    /// `LayoutSubviews` (a flat collection) cannot describe — so it reads the
    /// same values through the same wrapper directly.
    private func gridValue<K: LayoutValueKey>(_ key: K.Type) -> K.Value? {
        guard let provider = wrappedView as? LayoutValueProviding,
            let value = provider.layoutValue(for: ObjectIdentifier(K.self)) as? K.Value
        else { return nil }
        return value
    }
}
