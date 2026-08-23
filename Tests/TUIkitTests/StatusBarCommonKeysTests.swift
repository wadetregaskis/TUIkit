//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StatusBarCommonKeysTests.swift
//
//  Return and Escape in the status bar: WHETHER they are there is the app's
//  decision, WHAT they say is the focused view's, and neither of them is a
//  view's decision to make.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("The status bar's two common keys")
struct StatusBarCommonKeysTests {
    private func state(
        escapeClaim: String? = nil, returnClaim: String? = nil,
        showEscape: Bool = true, showReturn: Bool = true
    ) -> StatusBarState {
        let bar = StatusBarState()
        bar.escapeLabelOverride = escapeClaim
        bar.activationLabelOverride = returnClaim
        bar.showEscapeItem = showEscape
        bar.showReturnItem = showReturn
        return bar
    }

    private func shortcuts(_ bar: StatusBarState) -> [String] {
        bar.currentSystemItems.map(\.shortcut)
    }

    @Test("With nothing claiming them, neither key is on the bar")
    func nothingClaimedNothingShown() {
        let bar = state()
        #expect(!shortcuts(bar).contains(Shortcut.escape))
        #expect(!shortcuts(bar).contains(Shortcut.enter))
        // Quit is unaffected: it is not conditional on anything being focused.
        #expect(shortcuts(bar).contains("q"))
    }

    @Test("A claim puts the key on the bar, in the claim's own words")
    func claimShows() {
        let bar = state(escapeClaim: "close popover", returnClaim: "toggle")
        let items = bar.currentSystemItems
        #expect(items.first { $0.shortcut == Shortcut.escape }?.label == "close popover")
        #expect(items.first { $0.shortcut == Shortcut.enter }?.label == "toggle")
    }

    @Test("An app that turns a key off is not overruled by a claim")
    func appDecidesPresence() {
        let bar = state(
            escapeClaim: "close popover", returnClaim: "toggle",
            showEscape: false, showReturn: false)
        #expect(!shortcuts(bar).contains(Shortcut.escape))
        #expect(!shortcuts(bar).contains(Shortcut.enter))
        // …and the claim itself is untouched, because it is also what routes
        // the key. Presence is a display decision and nothing more.
        #expect(bar.escapeLabelOverride == "close popover")
    }

    @Test("Each key can be turned off on its own")
    func independentToggles() {
        let bar = state(escapeClaim: "back out", returnClaim: "choose", showReturn: false)
        #expect(shortcuts(bar).contains(Shortcut.escape))
        #expect(!shortcuts(bar).contains(Shortcut.enter))
    }

    @Test("The two common keys sit ahead of the app-wide ones")
    func ordering() throws {
        let bar = state(escapeClaim: "back out", returnClaim: "choose")
        bar.showThemeItem = true
        let ordered = bar.currentSystemItems.sorted { $0.order < $1.order }.map(\.shortcut)
        let escape = try #require(ordered.firstIndex(of: Shortcut.escape))
        let enter = try #require(ordered.firstIndex(of: Shortcut.enter))
        let quit = try #require(ordered.firstIndex(of: "q"))
        #expect(escape < quit)
        #expect(enter < quit)
        #expect(escape < enter, "Escape before Return, as the bar has always read")
    }

    @Test("The entry is informational: pressing the key still reaches the view")
    func doesNotSwallowTheKey() {
        // The whole split depends on this. An entry that consumed the key would
        // make the bar's presence a behaviour change, and turning it off would
        // silently alter what the app does.
        let bar = state(escapeClaim: "close popover", returnClaim: "activate")
        #expect(bar.handleKeyEvent(KeyEvent(key: .enter)) == false)
        #expect(bar.handleKeyEvent(KeyEvent(key: .escape)) == false)
    }

    @Test("A page's own item wins, and takes the claim's words")
    func pageItemWins() {
        let bar = state(escapeClaim: "close popover")
        var acted = false
        bar.setItemsSilently([
            StatusBarItem(shortcut: Shortcut.escape, label: "back") { acted = true }
        ])
        // One escape entry between them, not two: the renderer drops the system
        // item whose shortcut a user item already carries.
        let userShortcuts = Set(bar.currentUserItems.map(\.shortcut))
        let survivingSystem = bar.currentSystemItems.filter { !userShortcuts.contains($0.shortcut) }
        #expect(!survivingSystem.contains { $0.shortcut == Shortcut.escape })
        // And the page's item keeps its action — the claim renames it, which is
        // what `_StatusBarCore` does at draw time.
        (bar.currentUserItems.first as? StatusBarItem)?.execute()
        #expect(acted)
    }
}
