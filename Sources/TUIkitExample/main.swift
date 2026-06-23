//  🖥️ TUIKit — Terminal UI Kit for Swift
//  main.swift
//
//  Created by LAYERED.work
//  License: MIT
//  This app demonstrates TUIkit capabilities through various demo pages.
//  Use the menu to navigate between demos.
//

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
    }
}

// Run the app
await ExampleApp.main()
