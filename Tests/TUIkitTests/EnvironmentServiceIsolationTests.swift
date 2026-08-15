//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EnvironmentServiceIsolationTests.swift
//
//  A runtime service is the running application's object. The environment
//  hands out `nil` when there is no application, and never a SHARED instance.
//
//  It used to hand out shared ones — `StatusBarKey.defaultValue` and four
//  siblings were `static let defaultValue = SomeClass()` — so every render
//  that had not been given a real service mutated the same object. That is
//  invisible until two of them run at once: two tests rendering sheets in
//  parallel both registered their ESC item into it and read each other's back,
//  and one of them passed for entirely the wrong reason.
//
//  These are the two halves of the fix: absent when there is no app, and
//  genuinely separate per context when there is.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore
import TUIkitStyling

@testable import TUIkit
@testable import TUIkitView

@MainActor
@Suite("Runtime services are per-application, never shared")
struct EnvironmentServiceIsolationTests {

    /// All five that used to carry a shared default. `nil` is the truth: these
    /// objects belong to `AppRunner` and reach views through
    /// `RenderLoop.buildEnvironment()`, so a bare environment has none.
    @Test("a bare environment carries no runtime service")
    func absentWithoutAnApplication() {
        let environment = EnvironmentValues()
        #expect(environment.statusBar == nil)
        #expect(environment.appHeader == nil)
        #expect(environment.notificationService == nil)
        #expect(environment.paletteManager == nil)
        #expect(environment.appearanceManager == nil)
    }

    /// The property that actually failed. Two contexts, each registering into
    /// its own status bar; neither may see the other's item. On the shared
    /// default both reads returned the same object and this could not fail —
    /// which is precisely why nothing caught it.
    @Test("one context's status-bar items are invisible to another's")
    func itemsDoNotLeakBetweenContexts() {
        func register(_ label: String) -> StatusBarState {
            let context = makeRenderContext(width: 40, height: 10)
            let bar = context.environment.statusBar!
            bar.setItems([StatusBarItem(shortcut: Shortcut.escape, label: label)])
            return bar
        }
        let first = register("first")
        let second = register("second")

        #expect(first !== second, "each context gets its own")
        #expect(first.currentUserItems.map(\.label) == ["first"])
        #expect(second.currentUserItems.map(\.label) == ["second"])
    }

    /// The other half: a service that IS provided is the one views see, so
    /// making the default absent did not disconnect the app from its own bar.
    @Test("a provided service is the one the environment carries")
    func providedServiceWins() {
        let bar = StatusBarState()
        var environment = EnvironmentValues()
        environment.statusBar = bar
        #expect(environment.statusBar === bar)

        let manager = ThemeManager(items: [Appearance.line, Appearance.heavy] as [Appearance])
        environment.appearanceManager = manager
        #expect(environment.appearanceManager === manager)
    }

    /// Rendering something that publishes status-bar items without a bar to
    /// publish into must not trap or throw the content away — a headless
    /// render is a supported thing to do.
    @Test("rendering without a status bar still draws the content")
    func headlessRenderSurvives() {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        #expect(environment.statusBar == nil, "the fixture really has none")
        let context = RenderContext(
            availableWidth: 40, availableHeight: 10,
            environment: environment, tuiContext: TUIContext())

        let view = Text(verbatim: "content")
            .statusBarItems { StatusBarItem(shortcut: "q", label: "quit") }
        let lines = renderToBuffer(view, context: context).lines.map(\.stripped)
        #expect(lines.contains { $0.contains("content") })
    }
}
