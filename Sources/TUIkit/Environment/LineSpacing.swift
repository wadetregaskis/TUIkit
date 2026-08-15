//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LineSpacing.swift
//
//  Blank rows between the wrapped lines of a `Text`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Environment

private struct LineSpacingKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// Blank rows inserted between the wrapped lines of a ``Text``, in **rows**.
    ///
    /// Set via ``View/lineSpacing(_:)``. Default: none.
    public var lineSpacing: Int {
        get { self[LineSpacingKey.self] }
        set { self[LineSpacingKey.self] = max(0, newValue) }
    }
}

// MARK: - Modifier

extension View {
    /// Sets the space between the wrapped lines of text in this view.
    ///
    /// ```swift
    /// Text(longProse)
    ///     .lineSpacing(1)          // one blank row between lines
    /// ```
    ///
    /// - Note: SwiftUI measures this in points and permits fractions. A terminal
    ///   can only insert whole rows, so the unit here is **rows** and the type is
    ///   `Int` — the argument label is unchanged, so the call site reads the
    ///   same. Negative values clamp to zero; text cannot overlap itself on a
    ///   cell grid.
    ///
    /// Spacing goes BETWEEN lines, so a single-line text is unaffected however
    /// large the value, and *n* lines occupy `n + (n − 1) × spacing` rows.
    ///
    /// It also does not change what ``View/lineLimit(_:)`` counts: a limit is a
    /// number of LINES OF TEXT, as in SwiftUI, not of rows on screen. Three
    /// lines at spacing 1 are three lines and five rows.
    ///
    /// - Parameter lineSpacing: Blank rows between lines.
    /// - Returns: A view whose text is spaced.
    public func lineSpacing(_ lineSpacing: Int) -> some View {
        environment(\.lineSpacing, max(0, lineSpacing))
    }
}

// MARK: - Row arithmetic

/// Converting between lines of text and the rows they occupy once spacing is
/// interleaved.
///
/// One place, because the measure and the render both need it and must agree:
/// the measure reports the total, the render decides how many lines it may draw
/// to stay inside the space it was given. That is the measure/render parity bug
/// class — reserve rows nothing fills, or draw past what the parent allowed.
enum LineSpacingRows {
    /// The display rows `lines` lines occupy at `spacing`.
    ///
    /// Gaps go BETWEEN lines, so *n* lines carry *n − 1* of them.
    static func displayRows(forLines lines: Int, spacing: Int) -> Int {
        guard lines > 0 else { return 0 }
        guard spacing > 0 else { return lines }
        return lines + (lines - 1) * spacing
    }

    /// The most lines of text that fit in `rows` display rows at `spacing`.
    ///
    /// The inverse of ``displayRows(forLines:spacing:)``, and never zero for a
    /// positive budget: one line always fits in one row, since its gap would
    /// come after it and is never drawn.
    static func lines(fittingRows rows: Int, spacing: Int) -> Int {
        guard rows > 0 else { return 0 }
        guard spacing > 0 else { return rows }
        return max(1, (rows + spacing) / (spacing + 1))
    }

    /// `rows` with `spacing` copies of `blank` interleaved between them.
    ///
    /// Generic because a spaced `Text` interleaves two parallel arrays — the
    /// styled lines and their cell widths — and they must gain their gaps in
    /// lockstep or a parent aligning the column reads a width against the wrong
    /// row.
    static func interleaved<Row>(_ rows: [Row], spacing: Int, blank: Row) -> [Row] {
        guard spacing > 0, rows.count > 1 else { return rows }
        var spaced: [Row] = []
        spaced.reserveCapacity(displayRows(forLines: rows.count, spacing: spacing))
        for (index, row) in rows.enumerated() {
            if index > 0 { spaced.append(contentsOf: repeatElement(blank, count: spacing)) }
            spaced.append(row)
        }
        return spaced
    }
}
