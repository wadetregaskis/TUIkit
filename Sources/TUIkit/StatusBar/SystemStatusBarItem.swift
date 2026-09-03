//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SystemStatusBarItem.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - System Status Bar Items

/// System status bar items that are always present.
///
/// These items are automatically added to the status bar by the framework.
/// They appear in a fixed order and provide essential app-wide functionality.
///
/// System items include:
/// - **quit** (`q`): Exits the application
/// - **appearance** (`a`): Cycles through appearances
/// - **theme** (`t`): Cycles through themes
public enum SystemStatusBarItem {
    /// The quit item (`q quit`).
    ///
    /// This item is always present and exits the application. The label is
    /// localized via the shared ``LocalizationService`` (key `statusbar.quit`),
    /// so it reads in the app's current language.
    public static var quit: StatusBarItem {
        StatusBarItem(
            shortcut: "q",
            label: LocalizationService.shared.string(for: LocalizationKey.StatusBar.quit),
            order: .quit
        )
    }

    /// The appearance item (`a appearance`).
    ///
    /// Cycles through available appearances (border styles).
    /// Action must be set by the framework. The label is localized via the
    /// shared ``LocalizationService`` (key `statusbar.appearance`).
    public static var appearance: StatusBarItem {
        StatusBarItem(
            shortcut: "a",
            label: LocalizationService.shared.string(for: LocalizationKey.StatusBar.appearance),
            order: .appearance
        )
    }

    /// The theme item (`t theme`).
    ///
    /// Cycles through available themes. Action must be set by the framework.
    /// The label is localized via the shared ``LocalizationService`` (key
    /// `statusbar.theme`).
    public static var theme: StatusBarItem {
        StatusBarItem(
            shortcut: "t",
            label: LocalizationService.shared.string(for: LocalizationKey.StatusBar.theme),
            order: .theme
        )
    }

    /// The Escape entry, labelled by whatever claimed the key this frame.
    ///
    /// Informational: it carries no action, so it displays and does not
    /// intercept — the key goes on to whatever claimed it, through the ordinary
    /// chain. That is the whole point of the split. A page that wants Escape to
    /// DO something publishes its own item (`⎋ back`), which wins the shortcut
    /// dedup and keeps its own action.
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. These were the only two public status-bar APIs
    /// without a key overload, so a literal here could never be one while the
    /// same literal on `StatusBarItem(shortcut:label:)` always was.
    public static func escape(label labelKey: LocalizedStringKey) -> StatusBarItem {
        escape(label: labelKey.localized)
    }

    /// The Escape entry, labelled as written.
    ///
    /// Generic over `StringProtocol`, which is what keeps a literal binding to
    /// the key overload above — see ``LocalizedStringKey``.
    @_disfavoredOverload
    public static func escape<S: StringProtocol>(label: S) -> StatusBarItem {
        StatusBarItem(shortcut: Shortcut.escape, label: label, order: .escapeKey)
    }

    /// The Return entry, labelled by whatever claimed the key this frame. See
    /// ``escape(label:)-(LocalizedStringKey)`` — informational for the same
    /// reason, and a literal is a key here too.
    public static func returnKey(label labelKey: LocalizedStringKey) -> StatusBarItem {
        returnKey(label: labelKey.localized)
    }

    /// The Return entry, labelled as written.
    @_disfavoredOverload
    public static func returnKey<S: StringProtocol>(label: S) -> StatusBarItem {
        StatusBarItem(shortcut: Shortcut.enter, label: label, order: .returnKey)
    }

    /// All system items in their default order.
    ///
    /// The two common keys are absent: they exist only while something has said
    /// what they do, so there is no static form of them.
    public static var all: [StatusBarItem] {
        [quit, appearance, theme]
    }
}

// MARK: - Public API

extension SystemStatusBarItem {
    /// Creates system items with custom actions.
    ///
    /// - Parameters:
    ///   - onQuit: Action for quit (default: exits app).
    ///   - onAppearance: Action for appearance cycling (optional).
    ///   - onTheme: Action for theme cycling (optional).
    /// - Returns: Array of configured system items.
    public static func items(
        onQuit: (@Sendable () -> Void)? = nil,
        onAppearance: (@Sendable () -> Void)? = nil,
        onTheme: (@Sendable () -> Void)? = nil
    ) -> [StatusBarItem] {
        var result: [StatusBarItem] = []

        // Quit is always present. Labels are localized via the shared
        // LocalizationService so they read in the app's current language.
        result.append(
            StatusBarItem(
                shortcut: "q",
                label: LocalizationService.shared.string(for: LocalizationKey.StatusBar.quit),
                order: .quit,
                action: onQuit
            )
        )

        // Appearance is present if action is provided
        if let onAppearance {
            result.append(
                StatusBarItem(
                    shortcut: "a",
                    label: LocalizationService.shared.string(for: LocalizationKey.StatusBar.appearance),
                    order: .appearance,
                    action: onAppearance
                )
            )
        }

        // Theme is present if action is provided
        if let onTheme {
            result.append(
                StatusBarItem(
                    shortcut: "t",
                    label: LocalizationService.shared.string(for: LocalizationKey.StatusBar.theme),
                    order: .theme,
                    action: onTheme
                )
            )
        }

        return result
    }
}
