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
}

// MARK: - Content View (Page Router)

/// The main content view that switches between pages.
///
/// This view acts as a router, displaying the appropriate demo page
/// based on the current state. It uses `@State` for all reactive
/// properties — exactly like SwiftUI.
struct ContentView: View {
    @State var currentPage: DemoPage = .menu
    @State var menuSelection: Int = 0

    // The shared, app-wide theme managers. Cycling these re-themes every page,
    // the app header, and the status bar (the render loop reads them when
    // building each frame's environment). See ThemePage for explicit selection.
    @Environment(\.paletteManager) private var paletteManager
    @Environment(\.appearanceManager) private var appearanceManager

    var body: some View {
        // Capture bindings for use in closures
        let pageSetter = $currentPage
        // Capture the live theme managers HERE, during body evaluation, where
        // `@Environment` resolves to the real render environment. The key handler
        // runs later (during input dispatch), when `@Environment` would resolve to
        // an empty default — so reading the managers inside the closure would hit
        // no-op instances. Capturing the references now binds to the real ones.
        let paletteMgr = paletteManager
        let appearanceMgr = appearanceManager

        // Show current page based on state
        // Note: Background color is set by AppRunner using theme.background
        pageContent(for: currentPage, pageSetter: pageSetter)
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
                    // Cycle the colour palette globally. Function keys are used
                    // (rather than a letter) so the shortcut works on EVERY page
                    // without colliding with TextField / SecureField text entry.
                    paletteMgr.cycleNext()
                    return true
                case .f3:
                    // Cycle the border appearance globally (same rationale).
                    appearanceMgr.cycleNext()
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
            ThemePage()
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
            "m": .mouse, "t": .theme,
        ]

        if case .character(let ch) = key, let page = mapping[ch] {
            currentPage = page
            return true
        }
        return false
    }
}
