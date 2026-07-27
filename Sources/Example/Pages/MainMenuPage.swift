//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MainMenuPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// A small feature highlight box with a bold title and subtitle.
///
/// Used on the main menu to showcase key framework properties.
/// Stateless and palette-driven — wrapped in `.equatable()` for
/// subtree memoization during Spinner/Pulse animation frames.
struct FeatureBox: View, Equatable {
    /// The bold headline text.
    let title: String

    /// The secondary description text.
    let subtitle: String

    init(_ title: String, _ subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack {
            Text(title)
                .bold()
                .foregroundStyle(.palette.accent)
            Text(subtitle)
                .foregroundStyle(.palette.foregroundSecondary)
        }
        .padding(EdgeInsets(horizontal: 2, vertical: 1))
        .border(color: .palette.border)
    }
}

/// The main menu page.
///
/// Displays a centered menu with all available demos and
/// feature highlight boxes at the bottom.
struct MainMenuPage: View {
    @Binding var currentPage: DemoPage
    @Binding var menuSelection: DemoPage

    /// Which entry holds focus. Bound so returning from a demo puts the cursor
    /// back on the entry you left from (`.defaultFocus` below) rather than at
    /// the top of the list.
    @FocusState private var focusedEntry: DemoPage?

    /// One row of the menu: the page it opens, its localization key, and the
    /// key that jumps straight to it.
    private struct Entry {
        let page: DemoPage
        let key: String
        let shortcut: KeyEquivalent
    }

    private static let entries: [Entry] = [
        Entry(page: .textStyles, key: "menu.item.textStyles", shortcut: "1"),
        Entry(page: .colors, key: "menu.item.colors", shortcut: "2"),
        Entry(page: .containers, key: "menu.item.containers", shortcut: "3"),
        Entry(page: .overlays, key: "menu.item.overlays", shortcut: "4"),
        Entry(page: .layout, key: "menu.item.layout", shortcut: "5"),
        Entry(page: .buttons, key: "menu.item.buttons", shortcut: "6"),
        Entry(page: .toggles, key: "menu.item.toggles", shortcut: "7"),
        Entry(page: .textInput, key: "menu.item.textInput", shortcut: "8"),
        Entry(page: .radioButtons, key: "menu.item.radioButtons", shortcut: "9"),
        Entry(page: .spinners, key: "menu.item.spinners", shortcut: "0"),
        Entry(page: .lists, key: "menu.item.lists", shortcut: "-"),
        Entry(page: .tables, key: "menu.item.tables", shortcut: "="),
        Entry(page: .scrollView, key: "menu.item.scrollView", shortcut: "s"),
        Entry(page: .sliders, key: "menu.item.sliders", shortcut: "["),
        Entry(page: .steppers, key: "menu.item.steppers", shortcut: "]"),
        Entry(page: .splitView, key: "menu.item.splitView", shortcut: ";"),
        Entry(page: .imageFile, key: "menu.item.imageFile", shortcut: "'"),
        Entry(page: .imageURL, key: "menu.item.imageURL", shortcut: ","),
        Entry(page: .emoji, key: "menu.item.emoji", shortcut: "."),
        Entry(page: .pickers, key: "menu.item.picker", shortcut: "/"),
        Entry(page: .progress, key: "menu.item.progress", shortcut: "`"),
        Entry(page: .mouse, key: "menu.item.mouse", shortcut: "m"),
        Entry(page: .theme, key: "menu.item.theme", shortcut: "t"),
        Entry(page: .emptyState, key: "menu.item.emptyState", shortcut: "e"),
        Entry(page: .tabViews, key: "menu.item.tabViews", shortcut: "v"),
        Entry(page: .forms, key: "menu.item.forms", shortcut: "f"),
        Entry(page: .statePersistence, key: "menu.item.statePersistence", shortcut: "p"),
        Entry(page: .lifecycle, key: "menu.item.lifecycle", shortcut: "l"),
        Entry(page: .preferences, key: "menu.item.preferences", shortcut: "r"),
        Entry(page: .focus, key: "menu.item.focus", shortcut: "k"),
        Entry(page: .menus, key: "menu.item.menus", shortcut: "n"),
    ]

    /// Subtitle for the SF Symbols feature box: a few thematic glyphs — the
    /// Swift logo, a terminal, and the ⌘ key, resolved through the very API the
    /// box advertises (``SFSymbol/glyph(named:)``) — followed by the "(macOS
    /// only)" caveat. Off Apple platforms the symbols resolve to nothing, so
    /// only the caveat remains.
    private var sfSymbolsSubtitle: String {
        let examples = ["swift", "apple.terminal", "command"]
            .compactMap { SFSymbol.glyph(named: $0) }
            .joined()
        let caveat = L("feature.sfSymbols.macOSOnly")
        // The caveat now names the font requirement too, so it's wide — give it
        // its own line beneath the glyphs.
        return examples.isEmpty ? caveat : "\(examples) \(caveat)"
    }

    var body: some View {
        VStack(spacing: 1) {
            Spacer(minLength: 1)

            HStack {
                Spacer()
                // Each entry is an ordinary Button carrying its own action and
                // key equivalent — SwiftUI's `Menu` API — rendered expanded in
                // place by `.menuStyle(.inline)`. Arrows and Tab walk the rows;
                // the shortcut characters jump straight to a page; the menu
                // scrolls itself if the terminal is too short for all 31.
                Menu(L("menu.title")) {
                    ForEach(Self.entries, id: \.page) { entry in
                        Button(L(entry.key)) {
                            menuSelection = entry.page
                            currentPage = entry.page
                        }
                        .keyboardShortcut(entry.shortcut, modifiers: [])
                        .focused($focusedEntry, equals: entry.page)
                    }
                }
                .menuStyle(.inline)
                .defaultFocus($focusedEntry, menuSelection)
                Spacer()
            }

            Spacer(minLength: 1)

            // Feature highlights (centered)
            HStack {
                Spacer()
                VStack(spacing: 1) {
                    HStack(spacing: 3) {
                        FeatureBox(L("feature.pureSwift.title"), L("feature.pureSwift.subtitle")).equatable()
                        FeatureBox(L("feature.declarative.title"), L("feature.declarative.subtitle")).equatable()
                        FeatureBox(L("feature.composable.title"), L("feature.composable.subtitle")).equatable()
                        FeatureBox(L("feature.unicode.title"), "所有语言 🥳🤙🏽").equatable()
                    }
                    HStack(spacing: 3) {
                        // The SF Symbols subtitle wraps to two lines (glyphs +
                        // "(macOS only)" above, the font caveat below). Centre
                        // them relative to each other to show off
                        // `.multilineTextAlignment(_:)` — the modifier flows
                        // through the custom `FeatureBox` into its inner `Text`.
                        FeatureBox(L("feature.sfSymbols.title"), sfSymbolsSubtitle)
                            .equatable()
                            .multilineTextAlignment(.center)
                    }
                }
                Spacer()
            }

            Spacer()
        }
        .appHeader {
            DemoAppHeader(
                L("app.title"),
                subtitle: L("app.subtitle")
            )
        }
    }
}
