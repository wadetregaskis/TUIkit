//  🖥️ TUIkit — Terminal UI Kit for Swift
//  KeyboardShortcutDefaultTierTests.swift
//
//  Shortcuts the framework registers for itself (a split view's sidebar chord)
//  sit in a tier below the app's. Under the default `.commandKey(.control)`,
//  SwiftUI's ⌃⌘S and an app's plain ⌘S resolve to the same trigger, ⌃S, and the
//  registry's last-registration-wins rule would hand the app's Save to whichever
//  registered later in render order.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Framework-default shortcuts yield to the app's")
struct KeyboardShortcutDefaultTierTests {

    private let controlS = KeyEvent(key: .character("s"), ctrl: true)

    /// Records which registered action ran.
    private final class Log {
        var ran: [String] = []
    }

    @Test("An app shortcut registered BEFORE a default on the same key wins")
    func appBeforeDefault() {
        let registry = KeyboardShortcutRegistry()
        let log = Log()
        registry.register(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("app") }
        registry.registerDefault(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("default") }
        #expect(registry.trigger(for: controlS))
        #expect(log.ran == ["app"])
    }

    @Test("An app shortcut registered AFTER a default on the same key wins")
    func appAfterDefault() {
        let registry = KeyboardShortcutRegistry()
        let log = Log()
        registry.registerDefault(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("default") }
        registry.register(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("app") }
        #expect(registry.trigger(for: controlS))
        #expect(log.ran == ["app"])
    }

    @Test("A default fires when no app shortcut has the key")
    func defaultAlone() {
        let registry = KeyboardShortcutRegistry()
        let log = Log()
        registry.register(KeyboardShortcut("d", modifiers: .control)) { log.ran.append("app") }
        registry.registerDefault(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("default") }
        #expect(registry.trigger(for: controlS))
        #expect(log.ran == ["default"])
    }

    @Test("Of two defaults on one key, the first registered wins")
    func firstDefaultWins() {
        let registry = KeyboardShortcutRegistry()
        let log = Log()
        registry.registerDefault(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("first") }
        registry.registerDefault(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("second") }
        #expect(registry.trigger(for: controlS))
        #expect(log.ran == ["first"])
    }

    @Test("A default registered by a view holding the focus beats earlier and later ones that do not")
    func focusedDefaultWins() {
        let registry = KeyboardShortcutRegistry()
        let log = Log()
        let shortcut = KeyboardShortcut("s", modifiers: .control)
        registry.registerDefault(shortcut) { log.ran.append("unfocused first") }
        registry.registerDefault(shortcut, holdsFocus: true) { log.ran.append("focused") }
        registry.registerDefault(shortcut, holdsFocus: true) { log.ran.append("focused second") }
        registry.registerDefault(shortcut) { log.ran.append("unfocused last") }
        #expect(registry.trigger(for: controlS))
        #expect(log.ran == ["focused"])
    }

    @Test("A new render pass clears the defaults too")
    func beginRenderPassClears() {
        let registry = KeyboardShortcutRegistry()
        let log = Log()
        registry.registerDefault(KeyboardShortcut("s", modifiers: .control)) { log.ran.append("default") }
        registry.beginRenderPass()
        #expect(!registry.trigger(for: controlS))
        #expect(log.ran.isEmpty)
    }
}
