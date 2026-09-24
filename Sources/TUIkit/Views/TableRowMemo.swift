//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowMemo.swift
//
//  Keeping a `Table`'s composed row lines across frames, without inventing a
//  way for drawn content to be stale.
//
//  A `Table` composes every drawn row from scratch on every frame where a
//  `List` serves its rows from a memo. Closing that is worth a quarter of a
//  frame — measured, by making rows free in a deliberately wrong build — and
//  the obvious way to close it is not available. The render cache's own
//  invalidation drops every entry BENEATH an identity whose state was written,
//  which is exactly the frame a live table's data arrives on: the write that
//  changes two per cent of the rows clears a hundred per cent of the cache. A
//  memo that survived that sweep would be fast and occasionally wrong, and a
//  cell showing last frame's value is a worse defect than a slow one.
//
//  So this does not survive the sweep by being trusted. It sits outside the
//  sweep — on the table's own `ItemListHandler`, which is `@State` and which
//  already keeps the scroll extent's profile this way — and earns that by
//  keying on the INPUTS themselves rather than on a proxy for them:
//
//  * a row's CELLS are compared, not the row. A closure column may capture a
//    search term, a formatter, a units toggle — none of which the row carries —
//    so an equal row proves nothing about its text. But once the closure has
//    RUN, what it produced is not a proxy for the text: it IS the text, and a
//    line built from equal cells under an equal frame key is the same line.
//    That costs the app's own closures, which is the part nobody can skip, and
//    saves everything downstream of them.
//  * unless every column NAMES its value (``TableColumn/namesAProperty``), in
//    which case the cells are a pure function of the row and an equal row is
//    enough — so a key-path table skips even the property reads. That is an
//    optimisation on top of the rule above, not the rule itself.
//  * everything the FRAME settles that reaches a row's bytes is compared once
//    per frame in ``TableRowFrameKey`` — the widths, the geometry, the resolved
//    ink, each column's alignment and truncation and limit, the colour depth,
//    and the two generations that make a colour or a width mean something
//    different than it did.
//  * everything the ROW settles is compared per row: the row value itself, and
//    whether it is selected, which decides its mark and background.
//  * except for the one row whose look is not settled by the row at all: the
//    CURSOR row of a focused table breathes or holds still as the indicator
//    style and the window say, neither of which a key here carries, so it is
//    never kept. It is one row a frame, and it was never kept while it
//    breathed anyway.
//
//  What is left uncovered is global mutable state read through a computed
//  property — a `static` formatter, a `Date()`. That hole is older than this
//  file and is not widened by it: `fitWidth`, the scroll extent profile and
//  every value memo in the framework already have it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling
import TUIkitView

// MARK: - The frame's half of the key

/// Everything a frame settles that reaches a row's bytes and is not the row.
///
/// Compared ONCE per frame rather than per row: it is the same value for every
/// row, and carrying an array of column widths into each row's key cost more
/// than the memo saved on the tables it could not serve. A frame whose key
/// differs from the last one drops the whole store, which is correct and is
/// also the common case whenever anything about the table's shape moves.
struct TableRowFrameKey: Equatable {
    let columnWidths: [Int]
    let columnSpacing: Int
    let gutter: Int
    let rowWidth: Int
    /// The colour a cell's text resolves to, which the environment and the
    /// palette both reach. Resolved rather than named, so a palette that
    /// changed what `foreground` means changes this.
    let ink: Color
    let alignments: [HorizontalAlignment]
    let truncations: [TruncationMode]
    let lineLimits: [Int]
    /// How many colour channels a cell's SGR will be spelled in. Not covered by
    /// `ink`: the same `Color` renders to different bytes at a different depth,
    /// and unlike the two generations below there is no counter for it.
    let colorDepth: ColorDepth
    let colorGeneration: Int
    let widthGeneration: Int
}

// MARK: - The row's half, and what was kept

/// One row's composed line, and the row state it was composed for.
struct TableRowMemoLine {
    /// The row this line was last PROVED to answer for, when its type could be
    /// compared at all. `nil` for a row type that is not `Equatable`, which
    /// `Table` does not require — those rows are answered by their CELLS alone.
    ///
    /// `var`, and re-pointed by ``TableRowMemoStore/refresh(row:for:)``: a row
    /// that changed in a way its columns do not show passes the cell test and
    /// fails the row test, and leaving it pointing at the row the line was
    /// COMPOSED for would fail that test again every frame thereafter. See the
    /// note on `refresh`.
    var row: AnyEquatableBox?
    /// What every column produced for this row, in column order.
    ///
    /// The soundness of a closure column rests entirely on this. A closure may
    /// capture a search term, a formatter, a units toggle — none of which the
    /// row carries — so an equal row proves nothing about its text. But once
    /// the closure has RUN, what it produced is not a proxy for the text: it IS
    /// the text, and a line built from equal cells under an equal frame key is
    /// the same line.
    let cells: [String]
    /// Whether the row was selected. Not whether it was the cursor: the cursor
    /// row of a focused table is never kept (see `Table.renderRow`), so every
    /// entry is a row the cursor was not on.
    let isSelected: Bool
    let line: String
    let claims: [OpacityRegion]

    /// Whether this entry answers for a row whose cells are `cells`.
    func answers(cells other: [String], isSelected: Bool) -> Bool {
        self.isSelected == isSelected && cells == other
    }

    /// Whether this entry answers for `row` WITHOUT computing its cells — only
    /// for a table whose every column names its value, where the cells are a
    /// pure function of the row.
    func answers(row other: AnyEquatableBox, isSelected: Bool) -> Bool {
        self.isSelected == isSelected && self.row == other
    }
}

/// A table's kept row lines, and the frame key they were composed under.
///
/// Held by ``ItemListHandler`` so that it outlives a render-cache sweep, and
/// bounded so that a long scroll cannot grow it without limit: the store is
/// dropped whole once it holds far more rows than a screenful, which costs one
/// frame of re-composition and is simpler than an eviction order nobody would
/// ever read.
struct TableRowMemoStore<ID: Hashable> {
    /// Whether this frame may keep rows at all, settled ONCE by `begin` rather
    /// than per row.
    ///
    /// Asking `columns.allSatisfy(\.namesAProperty)` per row read a
    /// `TableColumn` per column per row, and a `TableColumn` holds closures and
    /// strings — so the question cost 210 retain/release pairs a frame on a
    /// six-column table and showed up as 20% of the frame in `renderRow` even
    /// when 98% of its rows were being served. The answer cannot change within
    /// a frame; asking it once is the whole fix.
    private(set) var isOpen = false
    /// Whether every column names its value, settled once by `begin` for the
    /// same reason `isOpen` is: asking it reads a `TableColumn` per column, and
    /// a `TableColumn` holds closures and strings.
    private(set) var namesItsValues = false
    private(set) var frameKey: TableRowFrameKey?
    private var lines: [ID: TableRowMemoLine] = [:]

    /// How many rows may be kept, as a multiple of what is on screen.
    private static var slack: Int { 8 }

    /// Prepares the store for a frame, dropping everything if the frame's own
    /// inputs moved.
    mutating func begin(frame key: TableRowFrameKey, viewportHeight: Int, namesItsValues: Bool) {
        isOpen = true
        self.namesItsValues = namesItsValues
        if frameKey != key {
            frameKey = key
            lines.removeAll(keepingCapacity: true)
            return
        }
        if lines.count > max(32, viewportHeight * Self.slack) {
            lines.removeAll(keepingCapacity: true)
        }
    }

    /// The kept entry for `id`, whatever it holds — the caller decides how to
    /// challenge it.
    func entry(for id: ID) -> TableRowMemoLine? { lines[id] }

    mutating func keep(_ entry: TableRowMemoLine, for id: ID) {
        lines[id] = entry
    }

    /// Re-points a kept line at the row it was JUST proved to answer for.
    ///
    /// A model row carries more than it shows — a timestamp, a revision, a
    /// sequence number — so a live snapshot hands over rows that are not equal
    /// to last frame's while drawing identical bytes. Such a row fails the row
    /// test and passes the cell test, which is correct and costs a build per
    /// column. Without this it costs that on EVERY later frame too: the kept
    /// entry still names the row it was composed for, which nothing will ever
    /// equal again, so the table falls permanently to its expensive tier while
    /// drawing the same picture. On cells that come from a formatter, that is
    /// the difference between a frame and ten.
    ///
    /// Sound because it asserts no more than the frame just proved: the line
    /// was built from cells equal to this row's under this frame key, and under
    /// `namesItsValues` the cells are a pure function of the row — so any later
    /// row equal to this one produces those cells and therefore that line.
    mutating func refresh(row: AnyEquatableBox, for id: ID) {
        lines[id]?.row = row
    }

    mutating func removeAll() {
        isOpen = false
        namesItsValues = false
        lines.removeAll(keepingCapacity: true)
        frameKey = nil
    }
}
