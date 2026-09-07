//  🖥️ TUIkit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by LAYERED.work
//  License: MIT
//  This app demonstrates TUIkit capabilities through various demo pages.
//  Use the menu to navigate between demos.
//

import Foundation
import TUIkit

// MARK: - Main App

/// The main example application.
struct ExampleApp: App {
    /// The whole app's colour palette, held as editable `@State` and applied to
    /// the scene with `.palette(...)`. The Theme page edits it — presets load a
    /// `SystemPalette`'s colours, the colour pickers tweak individual ones — so a
    /// change re-themes every page, the app header, and the status bar live.
    /// (App-level `@State` is re-evaluated each frame, so the scene's `.palette`
    /// override stays in sync.)
    @State private var palette = CustomizablePalette(from: SystemPalette(.green))

    /// App-wide styling (tint + text-attribute toggles), edited on the Theme
    /// page. The scene's `.theme` folds the tint into the palette so the app
    /// header and status bar pick it up too; ContentView applies the chrome and
    /// control text styling to the pages.
    @State private var styling = ExampleStyling()

    var body: some Scene {
        WindowGroup {
            ContentView(palette: $palette, styling: $styling)
                // Host notifications once, at the app root, so a toast posted on
                // any page stays visible until it expires — even after the user
                // navigates to a different page. (A per-page host would drop the
                // toast the instant you left that page, though the global
                // `NotificationService` still holds it.)
                .notificationHost()
        }
        .theme(Theme(palette: palette, tint: styling.tint))
        // Apply the user-built custom border (Theme page) at the *scene* level so
        // it reaches the app header and status bar too — not just the page
        // content. `nil` (no custom border) defers to the appearance manager, so
        // F2 / F3 / the appearance picker keep driving the built-in border.
        .appearance(styling.customBorder.map {
            Appearance(id: Appearance.ID(rawValue: "custom"), borderStyle: $0)
        })
        // Likewise scene-level: how the two framing bars separate themselves
        // from the page is a property of the app's chrome, not of any page.
        // The Theme page's picker drives both at once by default; the
        // two-argument spelling is what lets it set them apart.
        .chromeStyle(appHeader: styling.appHeaderStyle, statusBar: styling.statusBarStyle)
    }
}

// Register the example app's own localized strings with the shared
// LocalizationService before the UI renders, so `L(_:)` resolves them.
registerExampleLocalizations()

// How many entries the menu has, printed and nothing else.
//
// For the PTY smoke walk, which has to know when it has seen every page. The
// number lived in `Tools/Smoke/ci-pty-smoke.sh` as a literal, and a literal
// count of a list someone else maintains only ever drifts one way: two
// scenarios were added to the sibling Stress app and its count was not raised,
// so CI walked 19 of 21 and quietly stopped smoking two pages. Stress already
// answers this from its registry rather than a literal (see the note above
// `scenarioIDs` in its `main.swift`); this is the Example saying the same
// thing about `DemoPage`, which is the only place that actually knows.
if CommandLine.arguments.dropFirst().contains("--pages") {
    print(DemoPage.allCases.count)
    exit(0)
}

// Run the app
await ExampleApp.main()
