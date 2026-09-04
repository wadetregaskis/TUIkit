//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SystemStatusBarItemFactoryTests.swift
//
//  `SystemStatusBarItem.items(onQuit:onAppearance:onTheme:)`, `.all` and
//  `.quit` are public and have no caller anywhere in the repository — the
//  framework builds its own bar in `StatusBarState.currentSystemItems`, which
//  reaches for `.appearance`, `.theme`, `.escape` and `.returnKey` only. They
//  are not dead, though: Tools/APIParity/parity-map.json names `items(...)` as
//  the parity answer for re-binding the system items' actions, so they are
//  surface a downstream package is invited to call, with nothing asserting
//  which shortcut, order or closure each entry gets.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("System status bar item factories")
struct SystemStatusBarItemFactoryTests {

    @Test("The static items carry the documented shortcut and order, and no action")
    func staticItems() {
        #expect(SystemStatusBarItem.quit.shortcut == "q")
        #expect(SystemStatusBarItem.quit.order == .quit)
        #expect(SystemStatusBarItem.appearance.shortcut == "a")
        #expect(SystemStatusBarItem.appearance.order == .appearance)
        #expect(SystemStatusBarItem.theme.shortcut == "t")
        #expect(SystemStatusBarItem.theme.order == .theme)
        // "Action must be set by the framework": these three are descriptions
        // of an entry, not bindings.
        #expect(!SystemStatusBarItem.quit.hasAction)
        #expect(!SystemStatusBarItem.appearance.hasAction)
        #expect(!SystemStatusBarItem.theme.hasAction)
    }

    @Test("`all` is the three of them in display order")
    func allIsTheThree() {
        // `StatusBarItem` is not Equatable, so this compares the two fields
        // that define an entry's place in the bar.
        #expect(SystemStatusBarItem.all.map(\.shortcut) == ["q", "a", "t"])
        #expect(SystemStatusBarItem.all.map(\.order) == [.quit, .appearance, .theme])
    }

    @Test("Quit alone is the whole result when nothing else is bound")
    func quitIsAlwaysPresent() {
        let items = SystemStatusBarItem.items()
        #expect(items.map(\.shortcut) == ["q"])
        #expect(items.map(\.order) == [.quit])
        // And it has no action: `nil` really means "no action", not "the
        // default one". Quitting is dispatched against
        // `StatusBarState.quitShortcut`, never through this.
        #expect(!items[0].hasAction)
    }

    @Test("Appearance and theme appear only when given an action")
    func optionalItemsAreConditional() {
        #expect(SystemStatusBarItem.items(onAppearance: {}).map(\.shortcut) == ["q", "a"])
        #expect(SystemStatusBarItem.items(onTheme: {}).map(\.shortcut) == ["q", "t"])
        let all = SystemStatusBarItem.items(onQuit: {}, onAppearance: {}, onTheme: {})
        #expect(all.map(\.shortcut) == ["q", "a", "t"])
        #expect(all.map(\.order) == [.quit, .appearance, .theme])
        #expect(all.filter(\.hasAction).count == 3)
    }

    @Test("Each item runs the closure passed for it, not one of the others")
    func actionsAreNotTransposed() {
        // Three counters rather than one: the bug this catches is a
        // transposition, which any single-closure test passes.
        let fired = Lock(initialState: [String]())
        let items = SystemStatusBarItem.items(
            onQuit: { fired.withLock { $0.append("quit") } },
            onAppearance: { fired.withLock { $0.append("appearance") } },
            onTheme: { fired.withLock { $0.append("theme") } })

        for item in items { item.execute() }
        let order = fired.withLock { $0 }
        #expect(order == ["quit", "appearance", "theme"])
    }

    @Test("The labels are resolved on every access, so a language switch reaches them")
    func labelsAreLocalizedLive() {
        // Computed, not stored: this is what lets `currentSystemItems`
        // re-localize a running app's bar.
        let english = LocalizationService.shared.string(for: LocalizationKey.StatusBar.quit)
        #expect(SystemStatusBarItem.quit.label == english)
        #expect(SystemStatusBarItem.items()[0].label == english)
        #expect(
            SystemStatusBarItem.items(onAppearance: {})[1].label
                == LocalizationService.shared.string(for: LocalizationKey.StatusBar.appearance))
    }
}
