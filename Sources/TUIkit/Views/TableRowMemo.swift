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
//  * every column must NAME a property rather than compute one
//    (``TableColumn/namesAProperty``). A key path has no closure context, so it
//    cannot capture the search term, the formatter or the units toggle that a
//    closure column captures and that no row value would ever show. This is the
//    whole soundness argument, and it is why a table with one closure column
//    memoises nothing.
//  * everything the FRAME settles that reaches a row's bytes is compared once
//    per frame in ``TableRowFrameKey`` — the widths, the geometry, the resolved
//    ink, each column's alignment and truncation and limit, the colour depth,
//    and the two generations that make a colour or a width mean something
//    different than it did.
//  * everything the ROW settles is compared per row: the row value itself, and
//    the two flags that decide its mark and background.
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
    let row: AnyEquatableBox
    let isFocused: Bool
    let isSelected: Bool
    let line: String
    let claims: [OpacityRegion]

    /// Whether this entry answers for `row` in the state given.
    func answers(row other: AnyEquatableBox, isFocused: Bool, isSelected: Bool) -> Bool {
        self.isFocused == isFocused && self.isSelected == isSelected && row == other
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
    private(set) var frameKey: TableRowFrameKey?
    private var lines: [ID: TableRowMemoLine] = [:]

    /// How many rows may be kept, as a multiple of what is on screen.
    private static var slack: Int { 8 }

    /// Prepares the store for a frame, dropping everything if the frame's own
    /// inputs moved.
    mutating func begin(frame key: TableRowFrameKey, viewportHeight: Int) {
        isOpen = true
        if frameKey != key {
            frameKey = key
            lines.removeAll(keepingCapacity: true)
            return
        }
        if lines.count > max(32, viewportHeight * Self.slack) {
            lines.removeAll(keepingCapacity: true)
        }
    }

    func line(
        for id: ID, row: AnyEquatableBox, isFocused: Bool, isSelected: Bool
    ) -> TableRowMemoLine? {
        guard let kept = lines[id],
            kept.answers(row: row, isFocused: isFocused, isSelected: isSelected)
        else { return nil }
        return kept
    }

    mutating func keep(_ entry: TableRowMemoLine, for id: ID) {
        lines[id] = entry
    }

    mutating func removeAll() {
        isOpen = false
        lines.removeAll(keepingCapacity: true)
        frameKey = nil
    }
}
