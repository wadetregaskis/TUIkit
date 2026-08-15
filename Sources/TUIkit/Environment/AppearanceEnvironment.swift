//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AppearanceEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitStyling

// MARK: - Appearance Environment Key

/// Environment key for the current appearance.
private struct AppearanceKey: EnvironmentKey {
    static let defaultValue: Appearance = .default
}

extension EnvironmentValues {
    /// The current appearance.
    ///
    /// Set an appearance at the app level and it propagates to all child views:
    ///
    /// ```swift
    /// WindowGroup {
    ///     ContentView()
    /// }
    /// .appearance(.rounded)
    /// ```
    ///
    /// Access the appearance in `renderToBuffer(context:)`:
    ///
    /// ```swift
    /// let appearance = context.environment.appearance
    /// let borderStyle = appearance.borderStyle
    /// ```
    public var appearance: Appearance {
        get { self[AppearanceKey.self] }
        set { self[AppearanceKey.self] = newValue }
    }
}

// MARK: - AppearanceManager Environment Key

/// Environment key for the appearance manager.
private struct AppearanceManagerKey: EnvironmentKey {
    static let defaultValue: ThemeManager? = nil
}

extension EnvironmentValues {
    /// The appearance manager for cycling and setting appearances.
    ///
    /// ```swift
    /// context.environment.appearanceManager?.cycleNext()
    /// context.environment.appearanceManager?.setCurrent(Appearance.rounded)
    /// ```
    ///
    /// `nil` outside a running application. These are the app's own objects,
    /// created by `AppRunner` and published by `RenderLoop.buildEnvironment()`
    /// — so a bare `EnvironmentValues()` (a headless render, a test) has none,
    /// which is the truth. It used to hand out a SHARED instance instead, and
    /// every such render mutated the same object: two tests rendering sheets in
    /// parallel both registered their ESC item into it and read each other's
    /// back. The convention here is the one `focusManager` and
    /// `keyEventDispatcher` already follow — a runtime service is Optional, and
    /// absent means absent.
    public var appearanceManager: ThemeManager? {
        get { self[AppearanceManagerKey.self] }
        set { self[AppearanceManagerKey.self] = newValue }
    }
}
