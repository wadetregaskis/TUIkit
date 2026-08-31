//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PaletteEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitStyling

// MARK: - Palette Environment Key

/// Environment key for the current palette.
private struct PaletteKey: EnvironmentKey {
    static let defaultValue: any Palette = SystemPalette(.green)
}

extension EnvironmentValues {
    /// The current palette.
    ///
    /// Set a palette at the app level and it propagates to all child views:
    ///
    /// ```swift
    /// WindowGroup {
    ///     ContentView()
    /// }
    /// .environment(\.palette, SystemPalette(.green))
    /// ```
    ///
    /// Access the palette in `renderToBuffer(context:)`:
    ///
    /// ```swift
    /// let palette = context.environment.palette
    /// let fg = palette.foreground
    /// ```
    public var palette: any Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - PaletteManager Environment Key

/// Environment key for the palette manager.
private struct PaletteManagerKey: EnvironmentKey {
    static let defaultValue: ThemeManager? = nil
}

extension EnvironmentValues {
    /// The palette manager for cycling and setting palettes.
    ///
    /// ```swift
    /// context.environment.paletteManager?.cycleNext()
    /// context.environment.paletteManager?.setCurrent(SystemPalette(.amber))
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
    public var paletteManager: ThemeManager? {
        get { self[PaletteManagerKey.self] }
        set { self[PaletteManagerKey.self] = newValue }
    }
}

// MARK: - Enclosing Surface

/// Environment key for the surface a subtree is drawn on.
private struct SurfaceBackgroundKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// The colour of the surface the current subtree is painted on, when a
    /// container painted one — `nil` when that is just the page.
    ///
    /// A control that draws its own surface (a `TextField`'s well) has to know
    /// what is behind it, because "a step off the page" and "a step off *this*"
    /// are the same colour when the container is itself a step off the page:
    /// a field inside a `TabView`'s body drew the tab's own tone and vanished
    /// into it. Read it through ``Palette/fieldBackground(on:)`` rather than
    /// directly, so the derivation stays in one place.
    ///
    /// `package` rather than `internal` since this moved down a module: the
    /// controls that read it are the umbrella module's.
    package var surfaceBackground: Color? {
        get { self[SurfaceBackgroundKey.self] }
        set { self[SurfaceBackgroundKey.self] = newValue }
    }
}
