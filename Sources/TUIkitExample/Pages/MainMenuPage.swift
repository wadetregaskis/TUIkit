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
    @Binding var menuSelection: Int

    /// Subtitle for the SF Symbols feature box: a few thematic glyphs — the
    /// Swift logo, a terminal, and the ⌘ key, resolved through the very API the
    /// box advertises (``SFSymbol/glyph(named:)``) — followed by the "(macOS
    /// only)" caveat. Off Apple platforms the symbols resolve to nothing, so
    /// only the caveat remains.
    private var sfSymbolsSubtitle: String {
        let examples = ["swift", "apple.terminal", "command"]
            .compactMap { SFSymbol.glyph(named: $0) }
            .joined(separator: " ")
        let caveat = L("feature.sfSymbols.macOSOnly")
        return examples.isEmpty ? caveat : "\(examples)  \(caveat)"
    }

    var body: some View {
        VStack(spacing: 1) {
            Spacer(minLength: 1)

            HStack {
                Spacer()
                Menu(
                    title: L("menu.title"),
                    items: [
                        MenuItem(label: L("menu.item.textStyles"), shortcut: "1"),
                        MenuItem(label: L("menu.item.colors"), shortcut: "2"),
                        MenuItem(label: L("menu.item.containers"), shortcut: "3"),
                        MenuItem(label: L("menu.item.overlays"), shortcut: "4"),
                        MenuItem(label: L("menu.item.layout"), shortcut: "5"),
                        MenuItem(label: L("menu.item.buttons"), shortcut: "6"),
                        MenuItem(label: L("menu.item.toggles"), shortcut: "7"),
                        MenuItem(label: L("menu.item.textFields"), shortcut: "8"),
                        MenuItem(label: L("menu.item.secureFields"), shortcut: "\\"),
                        MenuItem(label: L("menu.item.radioButtons"), shortcut: "9"),
                        MenuItem(label: L("menu.item.spinners"), shortcut: "0"),
                        MenuItem(label: L("menu.item.lists"), shortcut: "-"),
                        MenuItem(label: L("menu.item.tables"), shortcut: "="),
                        MenuItem(label: L("menu.item.scrollView"), shortcut: "s"),
                        MenuItem(label: L("menu.item.sliders"), shortcut: "["),
                        MenuItem(label: L("menu.item.steppers"), shortcut: "]"),
                        MenuItem(label: L("menu.item.splitView"), shortcut: ";"),
                        MenuItem(label: L("menu.item.imageFile"), shortcut: "'"),
                        MenuItem(label: L("menu.item.imageURL"), shortcut: ","),
                        MenuItem(label: L("menu.item.emoji"), shortcut: "."),
                        MenuItem(label: L("menu.item.picker"), shortcut: "/"),
                        MenuItem(label: L("menu.item.progress"), shortcut: "`"),
                        MenuItem(label: L("menu.item.mouse"), shortcut: "m"),
                        MenuItem(label: L("menu.item.theme"), shortcut: "t"),
                        MenuItem(label: L("menu.item.emptyState"), shortcut: "e"),
                        MenuItem(label: L("menu.item.tabViews"), shortcut: "v"),
                        MenuItem(label: L("menu.item.forms"), shortcut: "f"),
                        MenuItem(label: L("menu.item.statePersistence"), shortcut: "p"),
                        MenuItem(label: L("menu.item.lifecycle"), shortcut: "l"),
                        MenuItem(label: L("menu.item.preferences"), shortcut: "r"),
                        MenuItem(label: L("menu.item.focus"), shortcut: "k"),
                    ],
                    selection: $menuSelection,
                    onSelect: { index in
                        // Navigate to the selected page
                        if let page = DemoPage(rawValue: index + 1) {
                            currentPage = page
                        }
                    },
                    selectedColor: .palette.accent,
                    // borderStyle uses appearance default
                    borderColor: .palette.border
                )
                Spacer()
            }

            Spacer(minLength: 1)

            // Feature highlights (centered)
            HStack {
                Spacer()
                HStack(spacing: 3) {
                    FeatureBox(L("feature.pureSwift.title"), L("feature.pureSwift.subtitle")).equatable()
                    FeatureBox(L("feature.declarative.title"), L("feature.declarative.subtitle")).equatable()
                    FeatureBox(L("feature.composable.title"), L("feature.composable.subtitle")).equatable()
                    FeatureBox(L("feature.unicode.title"), "所有语言 🥳🤙🏽").equatable()
                    FeatureBox(L("feature.sfSymbols.title"), sfSymbolsSubtitle).equatable()
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
