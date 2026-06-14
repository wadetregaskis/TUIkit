//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ContentView.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Demo Page Enum

/// The available demo pages in the example app.
enum DemoPage: Int, CaseIterable {
    case menu
    case textStyles
    case colors
    case containers
    case overlays
    case layout
    case buttons
    case toggles
    case textFields
    case secureFields
    case radioButtons
    case spinners
    case lists
    case tables
    case scrollView
    case sliders
    case steppers
    case splitView
    case imageFile
    case imageURL
    case emoji
    case pickers
    case progress
    case mouse
    case theme
    case emptyState
}

// MARK: - App-wide styling

/// App-wide styling toggles edited on the Theme page and applied to every page,
/// demonstrating the styling cascade: a tint (accent override), uppercase
/// section headers (a `.chrome` role), and bold button text (a `.control`
/// scope).
struct ExampleStyling: Equatable {
    var tint: Color?
    var uppercaseSectionHeaders = false
    var boldButtons = false
}

// MARK: - Content View (Page Router)

/// The main content view that switches between pages.
///
/// This view acts as a router, displaying the appropriate demo page
/// based on the current state. It uses `@State` for all reactive
/// properties — exactly like SwiftUI.
struct ContentView: View {
    /// The app-wide palette, owned by `ExampleApp` and applied to the scene.
    /// F2 loads the next preset into it; the Theme page edits it. Editing this
    /// re-themes every page (it drives the scene's `.palette`).
    @Binding var palette: CustomizablePalette
    /// App-wide styling toggles (tint, uppercase headers, bold buttons), edited on
    /// the Theme page and applied to every page via the styling cascade.
    @Binding var styling: ExampleStyling
    @State var currentPage: DemoPage = .menu
    @State var menuSelection: Int = 0
    /// Which built-in preset F2 last loaded — so F2 can cycle from there.
    @State private var presetIndex: Int = 0

    // Appearance (border style) is the other app-wide theme axis; cycling it
    // re-renders every page. (Palette lives in `palette` above, not here.)
    @Environment(\.appearanceManager) private var appearanceManager

    init(palette: Binding<CustomizablePalette>, styling: Binding<ExampleStyling>) {
        self._palette = palette
        self._styling = styling
    }

    var body: some View {
        // Capture bindings for use in closures
        let pageSetter = $currentPage

        // Show current page based on state
        // Note: Background color is set by AppRunner using theme.background
        pageContent(for: currentPage, pageSetter: pageSetter)
            // App-wide styling from the Theme page: the scene's `.theme` handles
            // tint; these add chrome + control text styling across every page.
            // `nil` attributes mean "no override", so the toggles are off by default.
            .style(.chrome(.sectionHeader)) {
                $0.textCase = styling.uppercaseSectionHeaders ? .uppercase : nil
            }
            .buttonTextStyle { $0.bold = styling.boldButtons ? true : nil }
            .onKeyPress { event in
                switch event.key {
                case .escape:
                    // ESC goes back to menu (or exits if already on menu)
                    if currentPage != .menu {
                        pageSetter.wrappedValue = .menu
                        return true  // Consumed
                    }
                    return false  // Let default handler exit the app
                case .f2:
                    // Load the next built-in preset into the app palette. Function
                    // keys are used (not a letter) so the shortcut works on EVERY
                    // page without colliding with TextField / SecureField input.
                    presetIndex = (presetIndex + 1) % PaletteRegistry.all.count
                    palette = CustomizablePalette(from: PaletteRegistry.all[presetIndex])
                    return true
                case .f3:
                    // Cycle the border appearance globally. `@Environment`
                    // resolves correctly inside this handler.
                    appearanceManager.cycleNext()
                    return true
                default:
                    // Quick-jump shortcuts only work from the menu page.
                    // On sub-pages they would conflict with text input
                    // (e.g. TextField, SecureField).
                    guard currentPage == .menu else { return false }
                    return handleMenuShortcut(event.key)
                }
            }
    }

    @ViewBuilder
    // The complexity is one case per demo page — exactly what you'd
    // want to see when adding or removing a page; splitting fragments it.
    // swiftlint:disable:next cyclomatic_complexity
    private func pageContent(for page: DemoPage, pageSetter: Binding<DemoPage>) -> some View {
        switch page {
        case .menu:
            // The 1–9 / 0 quick-jump shortcuts are still wired up via
            // `handleMenuShortcut`, but the menu page already lists each
            // page's shortcut next to its title — repeating them in the
            // status bar would be noise.
            MainMenuPage(currentPage: $currentPage, menuSelection: $menuSelection)
                .statusBarItems {
                    StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: "nav")
                    StatusBarItem(shortcut: Shortcut.enter, label: "select", key: .enter)
                }
        case .textStyles:
            TextStylesPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .colors:
            ColorsPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .containers:
            ContainersPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .overlays:
            OverlaysPage(onBack: { pageSetter.wrappedValue = .menu })
        case .layout:
            LayoutPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .buttons:
            ButtonsPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .toggles:
            TogglePage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .textFields:
            TextFieldPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .secureFields:
            SecureFieldPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .radioButtons:
            RadioButtonPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .spinners:
            SpinnersPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .lists:
            ListPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .tables:
            TablePage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .scrollView:
            ScrollViewPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .sliders:
            SliderPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .steppers:
            StepperPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .splitView:
            SplitViewPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .imageFile:
            ImageFilePage()
        case .imageURL:
            ImageURLPage()
        case .emoji:
            EmojiPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .pickers:
            PickerPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .progress:
            ProgressViewPage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .mouse:
            MousePage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .theme:
            ThemePage(palette: $palette, styling: $styling)
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        case .emptyState:
            ContentUnavailablePage()
                .statusBarItems(subPageItems(pageSetter: pageSetter))
        }
    }

    /// Common status bar items for sub-pages.
    private func subPageItems(pageSetter: Binding<DemoPage>) -> [any StatusBarItemProtocol] {
        [
            StatusBarItem(shortcut: Shortcut.escape, label: "back") { [pageSetter] in
                pageSetter.wrappedValue = .menu
            },
            StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: "scroll"),
        ]
    }

    /// Handles quick-jump shortcuts from the menu page.
    ///
    /// - Returns: `true` if the key was consumed, `false` otherwise.
    private func handleMenuShortcut(_ key: Key) -> Bool {
        let mapping: [Character: DemoPage] = [
            "1": .textStyles, "2": .colors, "3": .containers,
            "4": .overlays, "5": .layout, "6": .buttons,
            "7": .toggles, "8": .textFields, "\\": .secureFields,
            "9": .radioButtons, "0": .spinners, "-": .lists,
            "=": .tables, "s": .scrollView,
            "[": .sliders, "]": .steppers,
            ";": .splitView, "'": .imageFile, ",": .imageURL,
            ".": .emoji, "/": .pickers, "`": .progress,
            "m": .mouse, "t": .theme, "e": .emptyState,
        ]

        if case .character(let ch) = key, let page = mapping[ch] {
            currentPage = page
            return true
        }
        return false
    }
}
