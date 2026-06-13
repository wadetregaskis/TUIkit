//  🖥️ TUIKit — Terminal UI Kit for Swift
//  CustomizablePalette.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// A ``Palette`` whose every semantic colour is an editable stored property.
///
/// The example keeps one of these in app-level `@State` and applies it to the
/// whole scene with `.palette(...)`, so editing a colour re-themes every page,
/// the app header, and the status bar live. Presets are loaded by snapshotting a
/// built-in ``SystemPalette`` into this editable form; the theme page's
/// `ColorPicker`s then mutate individual colours.
struct CustomizablePalette: Palette {
    var id: String
    var name: String

    var background: Color
    var statusBarBackground: Color
    var appHeaderBackground: Color
    var overlayBackground: Color
    var foreground: Color
    var foregroundSecondary: Color
    var foregroundTertiary: Color
    var foregroundQuaternary: Color
    var accent: Color
    var success: Color
    var warning: Color
    var error: Color
    var info: Color
    var border: Color
    var focusBackground: Color
    var cursorColor: Color

    /// Snapshots every *resolved* colour of `source` into editable storage,
    /// flattening any protocol-default derivations (e.g. `statusBarBackground`
    /// defaulting to `background`) so each becomes independently editable.
    init(from source: any Palette, id: String? = nil, name: String? = nil) {
        self.id = id ?? source.id
        self.name = name ?? source.name
        self.background = source.background
        self.statusBarBackground = source.statusBarBackground
        self.appHeaderBackground = source.appHeaderBackground
        self.overlayBackground = source.overlayBackground
        self.foreground = source.foreground
        self.foregroundSecondary = source.foregroundSecondary
        self.foregroundTertiary = source.foregroundTertiary
        self.foregroundQuaternary = source.foregroundQuaternary
        self.accent = source.accent
        self.success = source.success
        self.warning = source.warning
        self.error = source.error
        self.info = source.info
        self.border = source.border
        self.focusBackground = source.focusBackground
        self.cursorColor = source.cursorColor
    }
}
