//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CustomizablePalette.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

/// A ``Palette`` whose every semantic colour is an editable stored property.
///
/// The example keeps one of these in app-level `@State` and applies it to the
/// whole scene with `.palette(...)`, so editing a colour re-themes every page,
/// the app header, and the status bar live. Presets are loaded by snapshotting a
/// built-in ``SystemPalette`` into this editable form; the theme page's
/// `ColorPicker`s then mutate individual colours.
struct CustomizablePalette: Palette, Hashable {
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

    /// A fade applied to every colour this snapshots, read from the environment:
    /// `TUIKIT_EXAMPLE_PALETTE_ALPHA=0.5` makes the whole app translucent.
    ///
    /// A debugging seam, off unless the variable is set, and it lives here because
    /// this is the one place the app's every colour passes through. What it is for
    /// is stated at length in §68 of `Documentation/Opacity as composition.md`: a
    /// paint site that hands a translucent colour straight to the ANSI emitter is
    /// invisible to a unit test that never renders that page, and every audit of
    /// those sites had been a re-reading of the same list. Fading the whole app and
    /// walking it found six the list never had.
    ///
    /// An invalid or absent value fades nothing, so a typo cannot quietly half-run
    /// the check.
    private static var debugFade: Double? {
        debugAlpha("TUIKIT_EXAMPLE_PALETTE_ALPHA")
    }

    /// The same seam for the four GROUNDS, which `debugFade` deliberately leaves alone:
    /// `TUIKIT_EXAMPLE_GROUND_ALPHA=0.5` fades the page, header, status bar and overlay
    /// backgrounds and nothing else.
    ///
    /// Separate because a translucent ground asks a different question — whether the
    /// framework survives a ground with nothing behind it — and because the Theme page's
    /// pickers can set exactly this, which crashed the app until §70.4 of
    /// `Documentation/Opacity as composition.md`. Run the faded-palette sweep with it set
    /// (the sweep passes its environment through) to prove that across every page.
    private static var debugGroundFade: Double? {
        debugAlpha("TUIKIT_EXAMPLE_GROUND_ALPHA")
    }

    /// An alpha in 0…1 read from `variable`; anything else fades nothing, so a typo cannot
    /// quietly half-run the check.
    private static func debugAlpha(_ variable: String) -> Double? {
        ProcessInfo.processInfo.environment[variable]
            .flatMap(Double.init)
            .flatMap { (0...1).contains($0) ? $0 : nil }
    }

    /// Snapshots every *resolved* colour of `source` into editable storage,
    /// flattening any protocol-default derivations (e.g. `statusBarBackground`
    /// defaulting to `background`) so each becomes independently editable.
    init(from source: any Palette, id: String? = nil, name: String? = nil) {
        let alpha = Self.debugFade
        let groundAlpha = Self.debugGroundFade
        /// Faded under the debug seam above, untouched otherwise.
        func faded(_ colour: Color) -> Color { alpha.map { colour.opacity($0) } ?? colour }
        /// Faded under the GROUND seam, untouched otherwise.
        func groundFaded(_ colour: Color) -> Color {
            groundAlpha.map { colour.opacity($0) } ?? colour
        }
        self.id = id ?? source.id
        self.name = name ?? source.name
        // The four GROUNDS are not faded by `debugFade`. A translucent background is a
        // claim about how present the layer is rather than about the paint on it (§1),
        // so fading them tests the compositor rather than the paint sites that seam is
        // aimed at — and it makes every page's every cell owe something, which buries
        // the one cell that does not. They have a seam of their own instead.
        self.background = groundFaded(source.background)
        self.statusBarBackground = groundFaded(source.statusBarBackground)
        self.appHeaderBackground = groundFaded(source.appHeaderBackground)
        self.overlayBackground = groundFaded(source.overlayBackground)
        self.foreground = faded(source.foreground)
        self.foregroundSecondary = faded(source.foregroundSecondary)
        self.foregroundTertiary = faded(source.foregroundTertiary)
        self.foregroundQuaternary = faded(source.foregroundQuaternary)
        self.accent = faded(source.accent)
        self.success = faded(source.success)
        self.warning = faded(source.warning)
        self.error = faded(source.error)
        self.info = faded(source.info)
        self.border = faded(source.border)
        self.focusBackground = faded(source.focusBackground)
        self.cursorColor = faded(source.cursorColor)
    }
}
