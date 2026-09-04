//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarSystemItemsModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@Suite("StatusBarSystemItemsModifier")
struct StatusBarSystemItemsModifierTests {
    @Test("Default shows only quit item")
    func defaultShowsOnlyQuit() {
        let statusBar = StatusBarState()
        #expect(statusBar.showSystemItems == true)
        #expect(statusBar.showThemeItem == false)
        #expect(statusBar.showAppearanceItem == false)

        let items = statusBar.currentSystemItems
        #expect(items.count == 1)
        #expect(items.first?.shortcut == "q")
    }

    @Test("Theme item can be enabled")
    func themeItemEnabled() {
        let statusBar = StatusBarState()
        statusBar.showThemeItem = true

        let items = statusBar.currentSystemItems
        #expect(items.count == 2)
        #expect(items.contains { $0.shortcut == "q" })
        #expect(items.contains { $0.shortcut == "t" })
    }

    @Test("Appearance item can be enabled")
    func appearanceItemEnabled() {
        let statusBar = StatusBarState()
        statusBar.showAppearanceItem = true

        let items = statusBar.currentSystemItems
        #expect(items.count == 2)
        #expect(items.contains { $0.shortcut == "q" })
        #expect(items.contains { $0.shortcut == "a" })
    }

    @Test("Both theme and appearance can be enabled")
    func bothItemsEnabled() {
        let statusBar = StatusBarState()
        statusBar.showThemeItem = true
        statusBar.showAppearanceItem = true

        let items = statusBar.currentSystemItems
        #expect(items.count == 3)
        #expect(items.contains { $0.shortcut == "q" })
        #expect(items.contains { $0.shortcut == "t" })
        #expect(items.contains { $0.shortcut == "a" })
    }

    /// The four tests above mutate a bare `StatusBarState`, so they cover the
    /// state's consumption of the flags and say nothing about the modifier.
    /// The test that stood here asserted `view is
    /// StatusBarSystemItemsModifier<Text>`, which the extension guarantees by
    /// construction — so the modifier's whole `Renderable` body was
    /// unexecuted, and swapping the theme and appearance assignments left
    /// every test in this file green.
    @MainActor
    @Test("Rendering the modifier publishes all four flags to the status bar")
    func renderingPublishesTheFlags() {
        let statusBar = StatusBarState()
        let context = makeRenderContext { environment, _ in
            environment.statusBar = statusBar
        }

        _ = renderToBuffer(
            Text("Test").statusBarSystemItems(
                theme: true, appearance: false, returnKey: false, escapeKey: true),
            context: context)

        // Asserted one flag at a time, and with the two pairs disagreeing:
        // a transposition inside either pair is invisible to any test that
        // turns them all on together. `returnKey`/`escapeKey` had never been
        // passed by any test at all.
        #expect(statusBar.showThemeItem)
        #expect(!statusBar.showAppearanceItem)
        #expect(!statusBar.showReturnItem)
        #expect(statusBar.showEscapeItem)
    }

    @MainActor
    @Test("The other assignment of each pair lands too")
    func flagsArePublishedInBothDirections() {
        let statusBar = StatusBarState()
        let context = makeRenderContext { environment, _ in
            environment.statusBar = statusBar
        }

        _ = renderToBuffer(
            Text("Test").statusBarSystemItems(
                theme: false, appearance: true, returnKey: true, escapeKey: false),
            context: context)

        #expect(!statusBar.showThemeItem)
        #expect(statusBar.showAppearanceItem)
        #expect(statusBar.showReturnItem)
        #expect(!statusBar.showEscapeItem)
    }

    @MainActor
    @Test("The content renders through the modifier, with or without a status bar")
    func contentPassesThrough() {
        let context = makeRenderContext { environment, _ in
            environment.statusBar = StatusBarState()
        }
        let plain = renderToBuffer(Text("Test"), context: context)
        #expect(
            renderToBuffer(Text("Test").statusBarSystemItems(theme: true), context: context).lines
                == plain.lines)

        // The `guard let statusBar` fallback: no bar in the environment is not
        // an error, and the content must still draw.
        var barless = EnvironmentValues()
        barless.focusManager = FocusManager()
        let barlessContext = RenderContext(
            availableWidth: 80, availableHeight: 24, environment: barless,
            tuiContext: TUIContext())
        #expect(barlessContext.environment.statusBar == nil)
        #expect(
            renderToBuffer(Text("Test").statusBarSystemItems(theme: true), context: barlessContext)
                .lines == plain.lines)
    }

    @MainActor
    @Test("Measuring the modifier changes no flags")
    func measuringHasNoSideEffects() {
        // What the `sizeThatFits` comment claims — "the toggle side-effects
        // stay render-only". A measure pass draws nothing, so a flag set
        // during one would publish a bar the frame never showed. The
        // protection is that `sizeThatFits` measures the child rather than
        // calling `renderToBuffer`, which is exactly the line a refactor
        // would collapse.
        let statusBar = StatusBarState()
        var context = makeRenderContext { environment, _ in
            environment.statusBar = statusBar
        }
        context.isMeasuring = true

        let modified = Text("Test").statusBarSystemItems(
            theme: true, appearance: true, returnKey: false, escapeKey: false)
        let size = measureChild(
            modified, proposal: ProposedSize(width: 80, height: 24), context: context)

        #expect(!statusBar.showThemeItem)
        #expect(!statusBar.showAppearanceItem)
        #expect(statusBar.showReturnItem, "the defaults are untouched, not merely unset")
        #expect(statusBar.showEscapeItem)
        // And it measures as its content, which is why it may skip the render.
        #expect(
            size == measureChild(
                Text("Test"), proposal: ProposedSize(width: 80, height: 24), context: context))
    }
}
