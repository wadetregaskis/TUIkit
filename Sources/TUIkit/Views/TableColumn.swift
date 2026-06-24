//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TableColumn.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Column Width

/// Defines the width behavior for a table column.
public enum ColumnWidth: Sendable, Equatable {
    /// Fixed width in characters.
    case fixed(Int)

    /// Flexible width that expands to fill available space.
    /// Multiple flexible columns share space equally.
    case flexible

    /// Proportional width as a ratio of total available space.
    /// For example, `.ratio(0.5)` takes 50% of available width.
    case ratio(Double)

    /// Sizes the column to fit its content — the width of the widest of the
    /// column header and every cell value in the column (so nothing in the
    /// column is truncated, space permitting). This mirrors the content-based
    /// sizing of a SwiftUI table's automatic columns.
    ///
    /// It scans all of the column's values to find that width, so it is O(rows);
    /// for very large tables where a per-frame content scan is undesirable,
    /// prefer `.fixed` or `.flexible`. The fitted width is stable as the table
    /// scrolls (it considers every row, not just the visible ones), so the
    /// columns do not jump while scrolling.
    case fit
}

// MARK: - Table Column

/// Defines a column in a Table view.
///
/// `TableColumn` specifies how to display a property of the data items,
/// including the column header, alignment, width, and value extraction.
///
/// ## Usage
///
/// ```swift
/// Table(files, selection: $selectedID) {
///     TableColumn("Name", value: \.name)
///     TableColumn("Size", value: \.formattedSize)
///         .width(.fixed(10))
///         .alignment(.trailing)
///     TableColumn("Modified", value: \.modifiedDate)
///         .width(.ratio(0.3))
/// }
/// ```
///
/// ## Width Modes
///
/// | Mode | Behavior |
/// |------|----------|
/// | `.fixed(n)` | Exactly n characters wide |
/// | `.flexible` | Expands to fill remaining space (shared equally) |
/// | `.ratio(r)` | Takes r proportion of available width (0.0-1.0) |
/// | `.fit` | Sizes to the widest of the header and all cell values (O(rows)) |
public struct TableColumn<Value>: Sendable {
    /// The column header title.
    public let title: String

    /// The horizontal alignment for column content.
    public var alignment: HorizontalAlignment

    /// The width mode for this column.
    public var width: ColumnWidth

    /// How a cell value is shortened when it is wider than the column.
    ///
    /// A cell is always clipped to its column's width so the columns stay
    /// aligned; this controls *which* part of an over-long value is kept.
    /// Defaults to `.tail` (keep the start, drop the end).
    public var truncationMode: TruncationMode = .tail

    /// The maximum number of lines a cell in this column may occupy.
    ///
    /// A value that is wider than the column — or that contains explicit line
    /// breaks — wraps onto further lines up to this limit (the row grows to its
    /// tallest cell); content beyond the limit is folded into the last line and
    /// truncated with an ellipsis. Mirrors SwiftUI's `lineLimit`. Defaults to `1`
    /// (single-line cells, the classic table look).
    public var lineLimit: Int = 1

    /// Extracts the display value from a data item.
    let valueExtractor: @Sendable (Value) -> String

    /// Creates a table column with a key path to a String property.
    ///
    /// - Parameters:
    ///   - title: The column header title.
    ///   - value: A key path to the String property to display.
    public init(_ title: String, value: KeyPath<Value, String> & Sendable) where Value: Sendable {
        self.title = title
        self.alignment = .leading
        self.width = .flexible
        self.valueExtractor = { item in item[keyPath: value] }
    }

    /// Creates a table column with a custom value extractor.
    ///
    /// - Parameters:
    ///   - title: The column header title.
    ///   - value: A closure that extracts the display string from a data item.
    public init(_ title: String, value: @escaping @Sendable (Value) -> String) {
        self.title = title
        self.alignment = .leading
        self.width = .flexible
        self.valueExtractor = value
    }
}

// MARK: - Modifiers

extension TableColumn {
    /// Sets the alignment for this column.
    ///
    /// - Parameter alignment: The horizontal alignment.
    /// - Returns: A modified column with the specified alignment.
    public func alignment(_ alignment: HorizontalAlignment) -> TableColumn {
        var copy = self
        copy.alignment = alignment
        return copy
    }

    /// Sets the width mode for this column.
    ///
    /// - Parameter width: The column width mode.
    /// - Returns: A modified column with the specified width.
    public func width(_ width: ColumnWidth) -> TableColumn {
        var copy = self
        copy.width = width
        return copy
    }

    /// Sets the maximum number of lines a cell in this column may occupy.
    ///
    /// With a limit above 1 a cell wraps its value (and honours embedded
    /// newlines) onto multiple lines, growing the row; the content is clipped to
    /// the limit with an ellipsis. A limit below 1 is treated as 1.
    ///
    /// ```swift
    /// TableColumn("Notes", value: \.notes).lineLimit(3)
    /// ```
    ///
    /// - Parameter limit: The maximum number of lines per cell.
    /// - Returns: A modified column with the specified line limit.
    public func lineLimit(_ limit: Int) -> TableColumn {
        var copy = self
        copy.lineLimit = max(1, limit)
        return copy
    }

    /// Sets how cell values in this column are shortened when they exceed
    /// the column's width.
    ///
    /// Cells are always clipped to the column width so the table stays
    /// aligned; this chooses which part of an over-long value survives —
    /// for example `.head` keeps the end of a long file path.
    ///
    /// - Parameter mode: The truncation mode for this column's cells.
    /// - Returns: A modified column with the specified truncation mode.
    public func truncationMode(_ mode: TruncationMode) -> TableColumn {
        var copy = self
        copy.truncationMode = mode
        return copy
    }
}

// MARK: - Column Content Extraction

extension TableColumn {
    /// Extracts the display value from an item.
    ///
    /// - Parameter item: The data item.
    /// - Returns: The string to display in this column.
    func value(for item: Value) -> String {
        valueExtractor(item)
    }
}

// MARK: - Table Column Builder

/// A result builder for composing table columns.
@resultBuilder
public struct TableColumnBuilder<Value> {
    /// Builds an array of columns from a single column.
    public static func buildBlock(_ columns: TableColumn<Value>...) -> [TableColumn<Value>] {
        columns
    }

    /// Builds an array of columns from an array.
    public static func buildArray(_ components: [[TableColumn<Value>]]) -> [TableColumn<Value>] {
        components.flatMap { $0 }
    }

    /// Builds an optional column.
    public static func buildOptional(_ component: [TableColumn<Value>]?) -> [TableColumn<Value>] {
        component ?? []
    }

    /// Builds the first branch of an if-else.
    public static func buildEither(first component: [TableColumn<Value>]) -> [TableColumn<Value>] {
        component
    }

    /// Builds the second branch of an if-else.
    public static func buildEither(second component: [TableColumn<Value>]) -> [TableColumn<Value>] {
        component
    }
}
