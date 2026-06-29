//  🖥️ TUIKit — Terminal UI Kit for Swift
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

    /// All system items in their default order.
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
