//  🖥️ TUIkit — Terminal UI Kit for Swift
//  QuitShortcut.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Quit Shortcut

/// Defines the keyboard shortcut used to quit the application.
///
/// By default, TUIkit uses `q` to quit. You can change this by setting
/// a different `QuitShortcut` on the status bar state:
///
/// ```swift
/// statusBar.quitShortcut = .escape
/// statusBar.quitShortcut = .ctrlQ
/// statusBar.quitShortcut = QuitShortcut(
///     key: .f12,
///     shortcutSymbol: Shortcut.f12,
///     label: "exit"
/// )
/// ```
///
/// The status bar automatically updates to display the configured shortcut.
public struct QuitShortcut: Sendable {
    /// The key that triggers the quit action.
    public let key: Key

    /// Whether the Ctrl modifier is required.
    public let ctrl: Bool

    /// The symbol displayed in the status bar (e.g., `"q"`, `"⎋"`, `"⌃q"`).
    public let shortcutSymbol: String

    /// The label displayed next to the shortcut symbol (e.g., `"quit"`).
    public let label: String

    /// Creates a custom quit shortcut with a localized label.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. Only `label` is: `shortcutSymbol` is the key
    /// glyph, which is the same in every language. The label is not defaulted
    /// in this overload, or the two would be ambiguous where it is omitted.
    ///
    /// - Parameters:
    ///   - key: The key that triggers quit.
    ///   - ctrl: Whether Ctrl must be held (default: `false`).
    ///   - shortcutSymbol: The symbol shown in the status bar.
    ///   - labelKey: The key for the label shown next to the symbol.
    public init(
        key: Key,
        ctrl: Bool = false,
        shortcutSymbol: String,
        label labelKey: LocalizedStringKey
    ) {
        self.init(
            key: key, ctrl: ctrl, shortcutSymbol: shortcutSymbol,
            label: labelKey.localized)
    }

    /// Creates a custom quit shortcut, labelled as written.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``. A generic parameter cannot carry a default, so
    /// the defaulted label lives in ``init(key:ctrl:shortcutSymbol:)`` instead
    /// of here.
    ///
    /// - Parameters:
    ///   - key: The key that triggers quit.
    ///   - ctrl: Whether Ctrl must be held (default: `false`).
    ///   - shortcutSymbol: The symbol shown in the status bar.
    ///   - label: The label shown next to the symbol.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        key: Key,
        ctrl: Bool = false,
        shortcutSymbol: String,
        label: S
    ) {
        self.key = key
        self.ctrl = ctrl
        self.shortcutSymbol = shortcutSymbol
        self.label = String(label)
    }

    /// Creates a custom quit shortcut labelled `"quit"`.
    ///
    /// The label's default lives here rather than on either labelled overload:
    /// neither of those can carry it — a generic parameter cannot have a
    /// default, and defaulting the ``LocalizedStringKey`` one would make the
    /// two ambiguous wherever the label is omitted.
    ///
    /// - Parameters:
    ///   - key: The key that triggers quit.
    ///   - ctrl: Whether Ctrl must be held (default: `false`).
    ///   - shortcutSymbol: The symbol shown in the status bar.
    public init(key: Key, ctrl: Bool = false, shortcutSymbol: String) {
        self.init(key: key, ctrl: ctrl, shortcutSymbol: shortcutSymbol, label: "quit" as String)
    }
}

// MARK: - Presets

extension QuitShortcut {
    // Each of these spelled `label: "quit"`, which is the default written out —
    // and, now that a literal binds to the key overload, would ask for the key
    // `"quit"` rather than the `statusbar.quit` these actually display. They
    // take the default instead, which is what they always meant.

    /// The default quit shortcut: `q` (matches both `q` and `Q`).
    public static let q = QuitShortcut(
        key: .character("q"),
        shortcutSymbol: "q"
    )

    /// Quit with the Escape key (`⎋`).
    public static let escape = QuitShortcut(
        key: .escape,
        shortcutSymbol: Shortcut.escape
    )

    /// Quit with Ctrl+Q (`⌃q`).
    public static let ctrlQ = QuitShortcut(
        key: .character("q"),
        ctrl: true,
        shortcutSymbol: Shortcut.ctrl("q")
    )

    /// Quit with Ctrl+C (`⌃c`).
    public static let ctrlC = QuitShortcut(
        key: .character("c"),
        ctrl: true,
        shortcutSymbol: Shortcut.ctrl("c")
    )
}

// MARK: - Key Matching

extension QuitShortcut {
    /// Returns whether the given key event matches this quit shortcut.
    ///
    /// For character keys without Ctrl, matching is case-insensitive
    /// (e.g., `.q` matches both `q` and `Q`).
    ///
    /// - Parameter event: The key event to check.
    /// - Returns: `true` if the event matches this shortcut.
    public func matches(_ event: KeyEvent) -> Bool {
        // The alt guard on every arm: a quit shortcut spells at most Ctrl —
        // Alt+Q (a meta-sending terminal's Option+Q) is some other binding's
        // chord, and quitting the app on it would be a destructive surprise.
        if ctrl {
            return event.ctrl && !event.alt && event.key == key
        }

        // Case-insensitive matching for character keys
        if case .character(let expected) = key,
            case .character(let actual) = event.key
        {
            return !event.ctrl && !event.alt && actual.lowercased() == expected.lowercased()
        }

        return event.key == key && !event.ctrl && !event.alt
    }
}
