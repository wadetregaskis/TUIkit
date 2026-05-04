//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Shortcut.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Shortcut Symbols

/// A collection of Unicode symbols commonly used for keyboard shortcuts.
///
/// Use these constants instead of typing Unicode characters directly.
/// They provide a consistent look and are easier to read in code.
///
/// # Example
///
/// ```swift
/// StatusBarItem(shortcut: .escape, label: "close") { dismiss() }
/// StatusBarItem(shortcut: .arrowsUpDown, label: "nav")
/// StatusBarItem(shortcut: .enter, label: "select", key: .enter)
/// ```
public enum Shortcut {
    // MARK: - Special Keys

    /// Escape key symbol: ⎋
    public static let escape = "⎋"

    /// Return/Enter key symbol: ↵
    public static let enter = "↵"

    /// Alternative return symbol: ⏎
    public static let returnKey = "⏎"

    /// Tab key symbol: ⇥
    public static let tab = "⇥"

    /// Shift+Tab (backtab) symbol: ⇤
    public static let shiftTab = "⇤"

    /// Backspace/Delete symbol: ⌫
    public static let backspace = "⌫"

    /// Forward delete symbol: ⌦
    public static let delete = "⌦"

    /// Space bar symbol: ␣
    public static let space = "␣"

    // MARK: - Arrow Keys (Single)

    /// Up arrow: ↑
    public static let arrowUp = "↑"

    /// Down arrow: ↓
    public static let arrowDown = "↓"

    /// Left arrow: ←
    public static let arrowLeft = "←"

    /// Right arrow: →
    public static let arrowRight = "→"

    // MARK: - Arrow Key Combinations

    /// Up and down arrows: ↑↓
    public static let arrowsUpDown = "↑↓"

    /// Left and right arrows: ←→
    public static let arrowsLeftRight = "←→"

    /// All four arrows: ↑↓←→
    public static let arrowsAll = "↑↓←→"

    /// Vertical arrows (alternative): ⇅
    public static let arrowsVertical = "⇅"

    /// Horizontal arrows (alternative): ⇆
    public static let arrowsHorizontal = "⇆"

    // MARK: - Modifier Keys

    /// Command key (Mac): ⌘
    public static let command = "⌘"

    /// Option/Alt key (Mac): ⌥
    public static let option = "⌥"

    /// Control key: ⌃
    public static let control = "⌃"

    /// Shift key: ⇧
    public static let shift = "⇧"

    /// Caps Lock: ⇪
    public static let capsLock = "⇪"

    // MARK: - Function Keys

    /// Function key prefix: Fn
    public static let fn = "Fn"

    /// Function key F1
    public static let f1 = "F1"

    /// Function key F2
    public static let f2 = "F2"

    /// Function key F3
    public static let f3 = "F3"

    /// Function key F4
    public static let f4 = "F4"

    /// Function key F5
    public static let f5 = "F5"

    /// Function key F6
    public static let f6 = "F6"

    /// Function key F7
    public static let f7 = "F7"

    /// Function key F8
    public static let f8 = "F8"

    /// Function key F9
    public static let f9 = "F9"

    /// Function key F10
    public static let f10 = "F10"

    /// Function key F11
    public static let f11 = "F11"

    /// Function key F12
    public static let f12 = "F12"

    // MARK: - Navigation

    /// Home key symbol: ⤒
    public static let home = "⤒"

    /// End key symbol: ⤓
    public static let end = "⤓"

    /// Page Up symbol: ⇞
    public static let pageUp = "⇞"

    /// Page Down symbol: ⇟
    public static let pageDown = "⇟"

    // MARK: - Actions

    /// Plus/Add symbol: +
    public static let plus = "+"

    /// Minus/Remove symbol: −
    public static let minus = "−"

    /// Checkmark/Confirm: ✓
    public static let checkmark = "✓"

    /// Cross/Cancel: ✗
    public static let cross = "✗"

    /// Search/Find: 🔍 (or use "?" for simpler display)
    public static let search = "?"

    /// Help symbol: ?
    public static let help = "?"

    /// Save symbol: 💾 (or use "S" for simpler display)
    public static let save = "S"

    // MARK: - Common Shortcuts

    /// Quit shortcut: q
    public static let quit = "q"

    /// Yes shortcut: y
    public static let yes = "y"

    /// No shortcut: n
    public static let no = "n"

    /// Cancel shortcut: c
    public static let cancel = "c"

    /// OK shortcut: o
    public static let ok = "o"

    // MARK: - Brackets and Selection

    /// Selection indicator: ▸
    public static let selectionRight = "▸"

    /// Selection indicator left: ◂
    public static let selectionLeft = "◂"

    /// Bullet point: •
    public static let bullet = "•"

    /// Square selection: ▪
    public static let squareBullet = "▪"

    // MARK: - Combining Helpers

}

// MARK: - Public API

extension Shortcut {
    /// Combines multiple shortcuts with a separator.
    ///
    /// - Parameters:
    ///   - shortcuts: The shortcuts to combine.
    ///   - separator: The separator (default: empty string).
    /// - Returns: The combined shortcut string.
    ///
    /// # Example
    ///
    /// ```swift
    /// Shortcut.combine(.control, "c") // "⌃c"
    /// Shortcut.combine(.shift, .tab)   // "⇧⇥"
    /// ```
    public static func combine(_ shortcuts: String..., separator: String = "") -> String {
        shortcuts.joined(separator: separator)
    }

    /// Creates a Ctrl+key shortcut display.
    ///
    /// - Parameter key: The key character.
    /// - Returns: The formatted shortcut (e.g., "^c").
    public static func ctrl(_ key: Character) -> String {
        "^\(key)"
    }

    /// Creates a range shortcut display (e.g., "1-9").
    ///
    /// - Parameters:
    ///   - start: The start of the range.
    ///   - end: The end of the range.
    /// - Returns: The formatted range (e.g., "1-9").
    public static func range(_ start: String, _ end: String) -> String {
        "\(start)-\(end)"
    }
}
