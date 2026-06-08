//  🖥️ TUIKit — Terminal UI Kit for Swift
//  InputHandlerTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling

/// Tests for `InputHandler`'s five-layer key-dispatch priority chain.
///
/// The chain is: 0 text input (a focused `TextFieldHandler`) → 1 status
/// bar → 2 view handlers (`onKeyPress`) → 3 focus system → 4 default
/// bindings (`q`/`t`/`a`). A consuming layer short-circuits the rest.
/// These tests wire each layer with a double that records whether it
/// ran and consumes the event, then assert which layer actually fired.
///
/// Layer 0 isn't exercised here: `hasTextInputFocus` is specifically
/// `currentFocused is TextFieldHandler`, so it needs a real text-field
/// handler focused (covered by the TextField tests); a generic focusable
/// exercises layer 3 instead.
@MainActor
@Suite("InputHandler dispatch chain")
struct InputHandlerTests {

    /// A focusable test double that records whether it was asked to
    /// handle a key and consumes it on request.
    private final class FakeFocusable: Focusable {
        let focusID: String
        var canBeFocused = true
        let consumes: Bool
        private(set) var sawEvent = false

        init(focusID: String, consumes: Bool) {
            self.focusID = focusID
            self.consumes = consumes
        }

        func onFocusReceived() {}
        func onFocusLost() {}
        func handleKeyEvent(_ event: KeyEvent) -> Bool {
            sawEvent = true
            return consumes
        }
    }

    /// A minimal ``Cyclable`` for theme/appearance managers.
    private struct FakeCyclable: Cyclable {
        let id: String
        let name: String
    }

    /// Collects per-layer side effects.
    private final class Probe {
        var statusBarRan = false
        var dispatcherRan = false
        var quitCount = 0
    }

    /// An `InputHandler` over fresh collaborators, bundled with the
    /// pieces a test configures and inspects.
    private struct Fixture {
        let handler: InputHandler
        let statusBar: StatusBarState
        let dispatcher: KeyEventDispatcher
        let focus: FocusManager
        let palette: ThemeManager
        let appearance: ThemeManager
        let probe: Probe
    }

    private func makeFixture() -> Fixture {
        let statusBar = StatusBarState()
        let dispatcher = KeyEventDispatcher()
        let focus = FocusManager()
        let palette = ThemeManager(items: [
            FakeCyclable(id: "p1", name: "p1"), FakeCyclable(id: "p2", name: "p2"),
        ])
        let appearance = ThemeManager(items: [
            FakeCyclable(id: "a1", name: "a1"), FakeCyclable(id: "a2", name: "a2"),
        ])
        let probe = Probe()
        let handler = InputHandler(
            statusBar: statusBar,
            keyEventDispatcher: dispatcher,
            focusManager: focus,
            paletteManager: palette,
            appearanceManager: appearance,
            onQuit: { probe.quitCount += 1 }
        )
        return Fixture(
            handler: handler, statusBar: statusBar, dispatcher: dispatcher,
            focus: focus, palette: palette, appearance: appearance, probe: probe)
    }

    /// Registers a focused, consuming focusable so layer 3 would fire
    /// if reached.
    @discardableResult
    private func focusConsumer(_ focus: FocusManager, key: String = "f") -> FakeFocusable {
        let element = FakeFocusable(focusID: key, consumes: true)
        focus.register(element)
        focus.focus(element)
        return element
    }

    @Test("Layer 1 (status bar) wins over view handlers and focus")
    func statusBarWins() {
        let fixture = makeFixture()
        fixture.statusBar.setItemsSilently([
            StatusBarItem(shortcut: "x", label: "X", action: { fixture.probe.statusBarRan = true })
        ])
        fixture.dispatcher.addHandler { _ in fixture.probe.dispatcherRan = true; return true }
        let focusable = focusConsumer(fixture.focus)

        fixture.handler.handle(KeyEvent(key: .character("x")))

        #expect(fixture.probe.statusBarRan)
        #expect(!fixture.probe.dispatcherRan)
        #expect(!focusable.sawEvent)
    }

    @Test("Layer 2 (view handlers) wins over focus")
    func dispatcherWinsOverFocus() {
        let fixture = makeFixture()
        fixture.dispatcher.addHandler { _ in fixture.probe.dispatcherRan = true; return true }
        let focusable = focusConsumer(fixture.focus)

        fixture.handler.handle(KeyEvent(key: .character("x")))

        #expect(fixture.probe.dispatcherRan)
        #expect(!focusable.sawEvent)
    }

    @Test("Layer 3 (focus) consumes when no higher layer does")
    func focusConsumesWhenHigherLayersDont() {
        let fixture = makeFixture()
        // No status-bar item; a view handler that declines the event.
        fixture.dispatcher.addHandler { _ in false }
        let focusable = focusConsumer(fixture.focus)

        // A focusable consuming the key is the List/Table-navigation case: the
        // handler mutates plain (non-`@State`) focus/scroll state, so `handle`
        // returning `true` is the run loop's only signal to repaint.
        let consumed = fixture.handler.handle(KeyEvent(key: .character("x")))

        #expect(consumed, "a consumed key must report true so the run loop repaints")
        #expect(focusable.sawEvent)
        #expect(fixture.probe.quitCount == 0)
    }

    @Test("Layer 4 quit binding fires onQuit when nothing else consumes")
    func quitBindingFires() {
        let fixture = makeFixture()

        fixture.handler.handle(KeyEvent(key: .character("q")))

        #expect(fixture.probe.quitCount == 1)
    }

    @Test("Layer 4 't' cycles the palette when the theme item is shown")
    func themeKeyCyclesPalette() {
        let fixture = makeFixture()
        fixture.statusBar.showThemeItem = true
        let before = fixture.palette.current.id

        fixture.handler.handle(KeyEvent(key: .character("t")))

        #expect(fixture.palette.current.id != before)
        #expect(fixture.palette.current.id == "p2")
    }

    @Test("Layer 4 'a' cycles the appearance")
    func appearanceKeyCyclesAppearance() {
        let fixture = makeFixture()
        let before = fixture.appearance.current.id

        fixture.handler.handle(KeyEvent(key: .character("a")))

        #expect(fixture.appearance.current.id != before)
        #expect(fixture.appearance.current.id == "a2")
    }

    @Test("An unhandled key with no consumers is a no-op")
    func unhandledKeyIsNoOp() {
        let fixture = makeFixture()
        let paletteBefore = fixture.palette.current.id
        let appearanceBefore = fixture.appearance.current.id

        let consumed = fixture.handler.handle(KeyEvent(key: .character("z")))

        #expect(!consumed, "an unconsumed key must report false so the loop doesn't repaint needlessly")
        #expect(fixture.probe.quitCount == 0)
        #expect(fixture.palette.current.id == paletteBefore)
        #expect(fixture.appearance.current.id == appearanceBefore)
    }

    @Test("A modal-claimed Escape routes to the focus system before the status bar")
    func modalEscapeRoutesToFocusFirst() {
        let fixture = makeFixture()
        // A page-level status-bar Escape handler that must NOT fire while
        // a modal owns Escape.
        fixture.statusBar.setItemsSilently([
            StatusBarItem(shortcut: "esc", label: "Back", key: .escape,
                action: { fixture.probe.statusBarRan = true })
        ])
        fixture.statusBar.escapeLabelOverride = "Close"
        let focusable = focusConsumer(fixture.focus)

        fixture.handler.handle(KeyEvent(key: .escape))

        #expect(focusable.sawEvent, "focus system should receive the modal-claimed Escape")
        #expect(!fixture.probe.statusBarRan, "the page-level Escape handler must not fire")
    }
}
