//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ThemeProbePalette.swift
//
//  A palette whose every role is a distinct, recognisable RGB, so a test can read
//  back from the bytes which role a built-in view painted with.
//
//  Created by Wade Tregaskis
//  License: MIT

@testable import TUIkitStyling

/// A palette that states all 17 roles, each a different truecolor value, so a
/// rendered line says which role it was painted from.
///
/// The roles are `var` and the type is `Hashable`: a test that edits a role on a
/// copy gets a palette that compares unequal, which is what lets the edited copy
/// miss the render memo (see `Palette`'s notes on changing a palette's colours).
struct ThemeProbePalette: Palette, Hashable {
    let id = "theme-probe"
    let name = "Theme probe"

    var background = Color.rgb(10, 10, 10)
    var statusBarBackground = Color.rgb(20, 20, 20)
    var appHeaderBackground = Color.rgb(20, 20, 20)
    var overlayBackground = Color.rgb(12, 12, 12)

    var foreground = Color.rgb(220, 220, 220)
    var foregroundSecondary = Color.rgb(170, 170, 170)
    var foregroundTertiary = Color.rgb(90, 90, 90)
    var foregroundQuaternary = Color.rgb(60, 60, 60)

    var accent = Color.rgb(230, 120, 40)
    var success = Color.rgb(40, 200, 90)
    var warning = Color.rgb(240, 200, 40)
    var error = Color.rgb(230, 50, 50)
    var info = Color.rgb(60, 140, 240)

    var border = Color.rgb(100, 100, 120)
    var focusBackground = Color.rgb(40, 40, 40)
    var cursorColor = Color.rgb(230, 120, 40)
    var fieldBackground = Color.rgb(30, 30, 30)
}
