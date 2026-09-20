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

/// A modified row is still a row, and the modifier belongs to its CELLS.
///
/// SwiftUI: "If you apply a view modifier to a row, the row applies the
/// modifier to all of the cells, similar to how a `Group` behaves. For example,
/// if you apply the `border(_:width:)` modifier to a row, SwiftUI draws a
/// border on each cell in the row rather than around the row." Without this the
/// cast in ``_GridCore/rows(context:)`` missed a wrapped row and fell into the
/// "not a `GridRow`, therefore spans every column" branch that exists for a
/// `Divider` between rows — so the row was laid out by ``GridRow``'s fallback
/// `HStack` body and its cells left the grid's columns.
///
/// The companion to `ModifiedView`'s ``ChildViewProvider`` conformance, and the
/// same shape: resolve through the wrapper, then put the wrapper back around
/// each thing that came out.
extension ModifiedView: GridRowProviding where Content: GridRowProviding {
    var rowAlignment: VerticalAlignment? { content.rowAlignment }

    func gridCells(context: RenderContext) -> [ChildView] {
        content.gridCells(context: context).map { $0.modified(by: modifier) }
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

        // The widest child that spans the whole grid, which belongs to no
        // column — see Pass C.
        var fullWidthNeed = 0

        // Pass A: single-column cells set their column's width.
        for row in rows {
            var height = 0
            var index = 0
            for (cell, span) in zip(row.cells, row.spans) {
                let size = cell.measure(proposal: .unspecified, context: context)
                height = max(height, size.height)
                widen(to: index + span)
                // `span == 1` is not enough on its own. A child that is not a
                // `GridRow` arrives here as a one-cell row with span 1, and the
                // render draws it at `x: 0` across the FULL width — it is not in
                // column 0, so its width must not become column 0's. It did,
                // which pushed every other column right by the difference: two
                // short cells beside a sentence put the second column a
                // sentence-width away. Pass B already excludes these rows; Pass
                // A is where it was missed.
                if span == 1 && !row.spansFullWidth {
                    columns[index] = max(columns[index], size.width)
                    if let guide = cell.gridColumnAlignment, columnAlignment[index] == nil {
                        columnAlignment[index] = guide
                    }
                }
                if row.spansFullWidth {
                    fullWidthNeed = max(fullWidthNeed, size.width)
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

        // Pass C: a full-width child is a cell spanning every column, so it
        // grows the last one when it still does not fit — exactly what Pass B
        // does for an explicit `gridCellColumns` span. Excluding it from the
        // per-column vote must not shrink the grid: the render lays it out at
        // the grid's own width, and a grid narrower than its widest child would
        // clip the child instead of moving a column.
        if fullWidthNeed > 0 {
            widen(to: 1)
            let shortfall = fullWidthNeed - totalWidth(columns)
            if shortfall > 0 {
                columns[columns.count - 1] += shortfall
            }
        }
        return (columns, heights, columnAlignment)
    }

    /// The grid's total width for a lattice.
    private func totalWidth(_ columns: [Int]) -> Int {
        columns.reduce(0, +) + max(0, columns.count - 1) * horizontalSpacing
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        // Ground the proposal into the context before the lattice reads it —
        // the same two lines `_ContainerViewCore.sizeThatFits` and
        // `_ViewThatFitsCore.sizeThatFits` open with. `lattice` measures every
        // cell at `.unspecified`, which a wrapping cell resolves against
        // `context.availableWidth`, so without this the proposal reached only
        // the final clamp and the row heights belonged to a width the grid was
        // never going to be drawn at. `_HStackCore.resolvedLayout` re-measures
        // a column it squeezed at `ProposedSize(width: allocated, height: nil)`
        // and leaves `availableWidth` at the whole row's, while `renderChild`
        // DOES narrow it: "alpha beta gamma delta epsilon" beside "TAIL" in a
        // 20-cell row measured as 2 lines wrapped at 20, the row became 2 lines
        // tall, and the render built its lattice at the 15 cells it was given
        // — 3 lines — and clamped "epsilon" away with nothing on screen to say
        // so. Grounded, both passes build the lattice from the same width.
        var context = context.publishingContainerAxis(.vertical)
        context.availableWidth = proposal.width ?? context.availableWidth
        context.availableHeight = proposal.height ?? context.availableHeight
        let rows = rows(context: context)
        guard !rows.isEmpty else { return ViewSize.fixed(0, 0) }
        let lattice = lattice(rows, context: context)
        // `max(1, …)` per row, because that is what `renderToBuffer` draws: it
        // gives every row a canvas of `max(1, rowHeight)`, so a row is at least
        // a line whatever it holds. Summing the raw heights made the reported
        // height one line short for each row that measured zero tall, and the
        // parent clips what overflows — with one empty row, the grid's LAST row
        // did not appear. Aligned to the render rather than the other way
        // round: the render is what anyone has ever seen, so this changes no
        // pixels, only the number the grid tells its parent about them.
        let height =
            lattice.heights.reduce(0) { $0 + max(1, $1) }
            + max(0, lattice.heights.count - 1) * verticalSpacing
        return ViewSize(
            width: min(totalWidth(lattice.columns), max(0, proposal.width ?? context.availableWidth)),
            height: min(height, max(0, proposal.height ?? context.availableHeight)))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A grid stacks its rows into a column, so it publishes `.vertical` for
        // everything inside it — exactly as `_VStackCore` does, and for the
        // same reader. It is a child that is NOT a `GridRow` that needs it: it
        // spans every column, so the `Divider` between two rows must be the
        // horizontal rule it is when the grid stands alone. Publishing nothing
        // is not the same as publishing this: with nothing published, a grid
        // placed inside an `HStack` handed that full-width child the ROW's
        // axis, and the rule collapsed to a single `│` in column 0.
        let context = context.publishingContainerAxis(.vertical)
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

        // A `.gradientExtent(.subtree)` ramp spanning this grid. A grid is the
        // one container that places children two-dimensionally without being a
        // `Layout` — its cells are a lattice, which `LayoutSubviews` cannot
        // describe — so it cannot inherit `_LayoutCore`'s answer and has to
        // give its own. `nil` when nothing above asked for one, and then every
        // line below is the identity.
        let rowTops = Self.rowTops(heights, spacing: verticalSpacing)
        let gradientFrame = context.gradientContentFrame(
            width: width,
            height: (rowTops.last ?? 0) + max(1, heights.last ?? 1))

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
                let box = CellRect(
                    x: row.spansFullWidth ? 0 : origins[index], y: 0,
                    width: max(0, boxWidth), height: max(1, rowHeight))
                let rowAlignment = row.alignment
                let columnGuide = row.spansFullWidth ? nil : columnAlignment[index]
                var childContext = context
                if let gradientFrame {
                    // Where the cell will land, from its MEASURED size — the
                    // rendered one is a pass later, and the modifier's contract
                    // is that measure and render agree. The measure is the one
                    // `lattice` already took, so it is a memo hit.
                    let measured = cell.measure(
                        proposal: ProposedSize(width: max(0, boxWidth), height: max(1, rowHeight)),
                        context: context)
                    let seat = placement(
                        width: measured.width, height: measured.height, in: box, cell: cell,
                        rowAlignment: rowAlignment, columnAlignment: columnGuide)
                    childContext = context.placingGradientChild(
                        gradientFrame, x: seat.x, y: rowTops[rowIndex] + seat.y)
                }
                let rendered = cell.render(
                    width: max(0, boxWidth), height: max(1, rowHeight), context: childContext)
                canvas = canvas.composited(
                    with: rendered,
                    at: placement(
                        width: rendered.width, height: rendered.height, in: box, cell: cell,
                        rowAlignment: rowAlignment, columnAlignment: columnGuide))
                index += span
            }
            result.appendVertically(canvas, spacing: rowIndex > 0 ? verticalSpacing : 0)
        }
        return result.clamped(toWidth: context.availableWidth, height: context.availableHeight)
    }

    /// The y each row starts at within the grid's own content, in cells.
    ///
    /// Accumulated rather than multiplied, and clamped the same way the row
    /// canvases are — a zero-height row still occupies the one line
    /// `FrameBuffer(emptyWithWidth:height:)` gives it.
    private static func rowTops(_ heights: [Int], spacing: Int) -> [Int] {
        var tops: [Int] = []
        tops.reserveCapacity(heights.count)
        var y = 0
        for (index, height) in heights.enumerated() {
            if index > 0 { y += spacing }
            tops.append(y)
            y += max(1, height)
        }
        return tops
    }

    /// Where a rendered cell sits inside its box.
    ///
    /// Precedence matches SwiftUI: the cell's own `gridCellAnchor` beats the
    /// column's `gridColumnAlignment`, which beats the row's alignment, which
    /// beats the grid's. Each axis floors exactly once — see ``AlignmentID``.
    /// Takes a size rather than the buffer, because a
    /// `.gradientExtent(.subtree)` ramp has to know where a cell will land
    /// BEFORE the cell renders — and the only size available then is the
    /// measured one.
    private func placement(
        width renderedWidth: Int,
        height renderedHeight: Int,
        in box: CellRect,
        cell: ChildView,
        rowAlignment: VerticalAlignment?,
        columnAlignment: HorizontalAlignment?
    ) -> (x: Int, y: Int) {
        if let anchor = cell.gridCellAnchor {
            let dx = Int((anchor.x * Double(box.width - renderedWidth)).rounded(.down))
            let dy = Int((anchor.y * Double(box.height - renderedHeight)).rounded(.down))
            return (
                x: box.x + min(max(0, dx), max(0, box.width - renderedWidth)),
                y: box.y + min(max(0, dy), max(0, box.height - renderedHeight))
            )
        }
        let horizontal = columnAlignment ?? alignment.horizontal
        let vertical = rowAlignment ?? alignment.vertical
        return (
            x: box.x + horizontal.childOffset(childWidth: renderedWidth, in: box.width),
            y: box.y + vertical.childOffset(childHeight: renderedHeight, in: box.height)
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
