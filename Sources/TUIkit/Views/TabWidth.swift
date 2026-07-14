//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabWidth.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - TabWidth

/// How a literal tab character advances the column in text-editing views
/// (``TextEditor``).
///
/// The macOS text system lays tabs out against *tab stops* — positions a tab
/// advances to (`NSParagraphStyle.tabStops`, falling back to
/// `defaultTabInterval`) — so a tab's visual width varies with where it
/// starts. ``periodic(_:)`` is that behaviour on the terminal's character
/// grid, and matches how terminals themselves (8-column stops), `vim`'s
/// `tabstop`, and code editors' "tab width" settings all treat tabs.
/// ``fixed(_:)`` instead always advances the same number of cells, for the
/// rare layout where tabs are just wide spaces.
///
/// Set it for a subtree with ``SwiftUICore/View/tabWidth(_:)``; the default is
/// `.periodic(4)`.
public enum TabWidth: Sendable, Equatable, Hashable {
    /// A tab advances to the next multiple of `interval` columns — proper tab
    /// *stops*. A tab starting exactly on a stop advances a full interval
    /// (there is always at least one cell, so adjacent columns never merge).
    case periodic(_ interval: Int)

    /// A tab always advances exactly `cells` columns, regardless of where it
    /// starts.
    case fixed(_ cells: Int)

    /// The display column immediately after a tab that begins at `column`.
    /// Intervals/cells are clamped to at least 1 so a degenerate value can't
    /// stall the layout walk.
    func advance(from column: Int) -> Int {
        switch self {
        case .periodic(let interval):
            let interval = max(1, interval)
            return ((column / interval) + 1) * interval
        case .fixed(let cells):
            return column + max(1, cells)
        }
    }
}

// MARK: - TabLayout

/// Character-index ↔ display-column arithmetic for a line that may contain
/// tabs or multi-cell characters (emoji, CJK), shared by ``TextEditor``'s
/// renderer (caret and selection placement, click mapping, the row walk) and
/// ``TextEditorHandler`` (vertical motion's visual-column preservation) so
/// the two can never disagree about where a character puts the columns after
/// it.
///
/// The editor's model stays character-indexed — these helpers translate at
/// the display boundary only, in terminal CELLS: a tab advances to its stop,
/// and a wide character advances by its real cell width. Plain lines (no tab,
/// every character one cell) take an O(1) fast path, so ASCII editing pays
/// nothing.
enum TabLayout {
    /// Whether every character in `chars` occupies exactly one display cell
    /// (no tabs, no wide characters) — the fast-path predicate under which
    /// character index and display column coincide.
    private static func isPlain(_ chars: [Character]) -> Bool {
        !chars.contains { $0 == "\t" || $0.terminalWidth != 1 }
    }

    /// The display column after `character` when it begins at `column`: the
    /// next tab stop for a tab, `column` + the character's cell width
    /// otherwise (floored at one cell so a zero-width oddity can't stall a
    /// layout walk).
    static func advance(from column: Int, over character: Character, tabWidth: TabWidth) -> Int {
        character == "\t"
            ? tabWidth.advance(from: column)
            : column + max(1, character.terminalWidth)
    }

    /// The display column at which the character at `charIndex` begins
    /// (`charIndex == chars.count` gives the line's total display width).
    static func displayColumn(
        ofCharIndex charIndex: Int, in chars: [Character], tabWidth: TabWidth
    ) -> Int {
        guard !isPlain(chars) else { return min(charIndex, chars.count) }
        var column = 0
        for index in 0..<min(charIndex, chars.count) {
            column = advance(from: column, over: chars[index], tabWidth: tabWidth)
        }
        return column
    }

    /// The character index containing display column `displayColumn` — any
    /// column within a character's span (a tab's stop run, a wide character's
    /// cells) maps to that character. Columns at or past the end of the line
    /// map to the end-of-line insertion point (`chars.count`), matching a
    /// click beyond the last character.
    static func charIndex(
        forDisplayColumn displayColumn: Int, in chars: [Character], tabWidth: TabWidth
    ) -> Int {
        guard !isPlain(chars) else { return min(max(0, displayColumn), chars.count) }
        var column = 0
        for (index, character) in chars.enumerated() {
            let next = advance(from: column, over: character, tabWidth: tabWidth)
            if displayColumn < next { return index }
            column = next
        }
        return chars.count
    }
}

// MARK: - Environment

private struct TabWidthKey: EnvironmentKey {
    static let defaultValue: TabWidth = .periodic(4)
}

extension EnvironmentValues {
    /// How literal tab characters advance the column in text-editing views.
    public var tabWidth: TabWidth {
        get { self[TabWidthKey.self] }
        set { self[TabWidthKey.self] = newValue }
    }
}

extension View {
    /// Sets how literal tab characters are laid out in text-editing views in
    /// this view's subtree (``TextEditor``): snapped to periodic column stops
    /// (`.periodic(4)`, the default — the text-system/terminal behaviour) or
    /// a constant advance (`.fixed(n)`).
    ///
    /// TUI-specific: SwiftUI's `TextEditor` exposes no tab-stop control (the
    /// underlying text system does, via `NSParagraphStyle`, but not through
    /// SwiftUI), so this is kept separate from the SwiftUI-parity surface.
    public func tabWidth(_ width: TabWidth) -> some View {
        environment(\.tabWidth, width)
    }
}
