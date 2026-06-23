//  TUIKit - Terminal UI Kit for Swift
//  FocusManagerTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

// MARK: - Mock Focusable

/// A mock focusable element for testing.
final class MockFocusable: Focusable {
    let focusID: String
    var canBeFocused: Bool
    var focusReceivedCount = 0
    var focusLostCount = 0
    var lastKeyEvent: KeyEvent?
    var shouldConsumeEvents: Bool

    init(id: String, canBeFocused: Bool = true, shouldConsumeEvents: Bool = false) {
        self.focusID = id
        self.canBeFocused = canBeFocused
        self.shouldConsumeEvents = shouldConsumeEvents
    }

    func onFocusReceived() {
        focusReceivedCount += 1
    }

    func onFocusLost() {
        focusLostCount += 1
    }

    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        lastKeyEvent = event
        return shouldConsumeEvents
    }
}

// MARK: - Focus Manager Tests

@MainActor
@Suite("Focus Manager Tests")
struct FocusManagerTests {

    @Test("Register focusable element")
    func registerFocusable() {
        let manager = FocusManager()

        let element = MockFocusable(id: "test-element")
        manager.register(element)

        // First registered element should be auto-focused
        #expect(manager.isFocused(element))
        #expect(manager.currentFocusedID == "test-element")
    }

    @Test("Register multiple elements")
    func registerMultipleElements() {
        let manager = FocusManager()

        let element1 = MockFocusable(id: "element-1")
        let element2 = MockFocusable(id: "element-2")

        manager.register(element1)
        manager.register(element2)

        // First element should be focused
        #expect(manager.isFocused(element1))
        #expect(!manager.isFocused(element2))
    }

    @Test("Page/Home/End the focused control ignores scroll the enclosing container")
    func pageKeysScrollEnclosingContainer() {
        let manager = FocusManager()
        // A scroll container with content taller than its viewport (can scroll).
        let scroller = ScrollViewHandler(focusID: "scroll")
        scroller.contentHeight = 100
        scroller.viewportHeight = 10
        manager.register(scroller)
        // A non-scrollable control that does NOT consume keys, holding focus.
        let button = MockFocusable(id: "button", shouldConsumeEvents: false)
        manager.register(button)
        manager.focus(button)
        #expect(manager.currentFocusedID == "button")

        // Page Down: the button ignores it, so it scrolls the container one viewport.
        #expect(manager.dispatchKeyEvent(KeyEvent(key: .pageDown)))
        #expect(scroller.scrollOffset == 10, "pageDown should scroll one viewport, got \(scroller.scrollOffset)")
        #expect(manager.currentFocusedID == "button", "scrolling must not move focus")

        // End jumps to the bottom; Home back to the top.
        #expect(manager.dispatchKeyEvent(KeyEvent(key: .end)))
        #expect(scroller.scrollOffset == scroller.maxOffset)
        #expect(manager.dispatchKeyEvent(KeyEvent(key: .home)))
        #expect(scroller.scrollOffset == 0)
    }

    @Test("Page-key scroll fallback yields to a focused control that consumes the key")
    func pageKeyConsumedByFocusedControl() {
        let manager = FocusManager()
        let scroller = ScrollViewHandler(focusID: "scroll")
        scroller.contentHeight = 100
        scroller.viewportHeight = 10
        manager.register(scroller)
        // A control that consumes every key (e.g. a TextField's Home/End).
        let field = MockFocusable(id: "field", shouldConsumeEvents: true)
        manager.register(field)
        manager.focus(field)

        #expect(manager.dispatchKeyEvent(KeyEvent(key: .pageDown)))
        #expect(scroller.scrollOffset == 0, "a consuming control keeps the key; the container must not scroll")
    }

    @Test("Page-key scroll fallback stays inert when several scrollers could move")
    func pageKeyAmbiguousScrollersInert() {
        let manager = FocusManager()
        let scrollerA = ScrollViewHandler(focusID: "scrollA")
        scrollerA.contentHeight = 100
        scrollerA.viewportHeight = 10
        let scrollerB = ScrollViewHandler(focusID: "scrollB")
        scrollerB.contentHeight = 100
        scrollerB.viewportHeight = 10
        manager.register(scrollerA)
        manager.register(scrollerB)
        let button = MockFocusable(id: "button", shouldConsumeEvents: false)
        manager.register(button)
        manager.focus(button)

        // Two scrollers can move → ambiguous → the fallback declines, leaving both put.
        #expect(!manager.dispatchKeyEvent(KeyEvent(key: .pageDown)))
        #expect(scrollerA.scrollOffset == 0 && scrollerB.scrollOffset == 0)
    }

    @Test("Unregister focusable element")
    func unregisterFocusable() {
        let manager = FocusManager()

        let element1 = MockFocusable(id: "elem-1")
        let element2 = MockFocusable(id: "elem-2")

        manager.register(element1)
        manager.register(element2)
        manager.unregister(element1)

        // element2 should now be focused (focusNext called)
        #expect(!manager.isFocused(element1))
    }

    @Test("Clear all focusables")
    func clearAll() {
        let manager = FocusManager()

        let element = MockFocusable(id: "to-clear")
        manager.register(element)
        manager.clear()

        #expect(manager.currentFocusedID == nil)
        #expect(manager.currentFocused == nil)
    }

    @Test("Focus specific element")
    func focusSpecific() {
        let manager = FocusManager()

        let element1 = MockFocusable(id: "first")
        let element2 = MockFocusable(id: "second")

        manager.register(element1)
        manager.register(element2)
        manager.focus(element2)

        #expect(manager.isFocused(element2))
        #expect(!manager.isFocused(element1))
    }

    @Test("Focus by ID")
    func focusByID() {
        let manager = FocusManager()

        let element1 = MockFocusable(id: "id-a")
        let element2 = MockFocusable(id: "id-b")

        manager.register(element1)
        manager.register(element2)
        manager.focus(id: "id-b")

        #expect(manager.isFocused(id: "id-b"))
        #expect(!manager.isFocused(id: "id-a"))
    }

    @Test("Focus next wraps around")
    func focusNextWrapsAround() {
        let manager = FocusManager()

        let element1 = MockFocusable(id: "nav-1")
        let element2 = MockFocusable(id: "nav-2")
        let element3 = MockFocusable(id: "nav-3")

        manager.register(element1)
        manager.register(element2)
        manager.register(element3)

        // Start at element1
        #expect(manager.isFocused(element1))

        manager.focusNext()
        #expect(manager.isFocused(element2))

        manager.focusNext()
        #expect(manager.isFocused(element3))

        manager.focusNext()  // Should wrap to element1
        #expect(manager.isFocused(element1))
    }

    @Test("Focus previous wraps around")
    func focusPreviousWrapsAround() {
        let manager = FocusManager()

        let element1 = MockFocusable(id: "prev-1")
        let element2 = MockFocusable(id: "prev-2")
        let element3 = MockFocusable(id: "prev-3")

        manager.register(element1)
        manager.register(element2)
        manager.register(element3)

        // Explicitly start at element1
        manager.focus(element1)
        #expect(manager.isFocused(element1))

        manager.focusPrevious()  // Should wrap to element3
        #expect(manager.isFocused(element3))

        manager.focusPrevious()
        #expect(manager.isFocused(element2))

        manager.focusPrevious()
        #expect(manager.isFocused(element1))
    }

    @Test("Skip non-focusable elements")
    func skipNonFocusable() {
        let manager = FocusManager()

        let element1 = MockFocusable(id: "focusable-1")
        let element2 = MockFocusable(id: "disabled", canBeFocused: false)
        let element3 = MockFocusable(id: "focusable-2")

        manager.register(element1)
        manager.register(element2)
        manager.register(element3)

        // Start at element1
        manager.focusNext()
        // Should skip element2 and go to element3
        #expect(manager.isFocused(element3))
    }

    @Test("Cannot focus disabled element")
    func cannotFocusDisabled() {
        let manager = FocusManager()

        let disabled = MockFocusable(id: "disabled", canBeFocused: false)
        manager.register(disabled)

        // Should not be focused
        #expect(!manager.isFocused(disabled))
        #expect(manager.currentFocusedID == nil)
    }

    @Test("Focus callbacks are called")
    func focusCallbacks() {
        let manager = FocusManager()

        let element1 = MockFocusable(id: "callback-1")
        let element2 = MockFocusable(id: "callback-2")

        // Register element1 - it should be auto-focused since manager was just created
        manager.register(element1)
        // Note: focusReceivedCount should be 1 after registration auto-focus
        #expect(element1.focusReceivedCount == 1, "Element1 should receive focus when registered as first element")

        manager.register(element2)
        // Explicitly focus element2
        manager.focus(element2)

        // element1 should have lost focus, element2 should have received it
        #expect(element1.focusLostCount == 1, "Element1 should lose focus when element2 is focused")
        #expect(element2.focusReceivedCount == 1, "Element2 should receive focus when explicitly focused")
    }

    @Test("Tab key moves focus next")
    func tabKeyMovesFocusNext() {
        let manager = FocusManager()

        let element1 = MockFocusable(id: "tab-1")
        let element2 = MockFocusable(id: "tab-2")

        manager.register(element1)
        manager.register(element2)

        let tabEvent = KeyEvent(key: .tab, ctrl: false, alt: false, shift: false)
        let handled = manager.dispatchKeyEvent(tabEvent)

        #expect(handled)
        #expect(manager.isFocused(element2))
    }

    @Test("Shift+Tab moves focus previous")
    func shiftTabMovesFocusPrevious() {
        let manager = FocusManager()

        let element1 = MockFocusable(id: "shift-1")
        let element2 = MockFocusable(id: "shift-2")

        manager.register(element1)
        manager.register(element2)
        manager.focus(element2)

        let shiftTabEvent = KeyEvent(key: .tab, ctrl: false, alt: false, shift: true)
        let handled = manager.dispatchKeyEvent(shiftTabEvent)

        #expect(handled)
        #expect(manager.isFocused(element1))
    }

    @Test("Key events dispatched to focused element")
    func keyEventsDispatched() {
        let manager = FocusManager()

        let element = MockFocusable(id: "dispatch-test", shouldConsumeEvents: true)
        manager.register(element)

        let event = KeyEvent(key: .enter, ctrl: false, alt: false, shift: false)
        let handled = manager.dispatchKeyEvent(event)

        #expect(handled)
        #expect(element.lastKeyEvent?.key == .enter)
    }

    @Test("onFocusChange callback triggered")
    func onFocusChangeCallback() {
        let manager = FocusManager()

        var callbackCount = 0
        manager.onFocusChange = {
            callbackCount += 1
        }

        let element = MockFocusable(id: "callback-test")
        manager.register(element)

        #expect(callbackCount == 1)

        // Cleanup
        manager.onFocusChange = nil
    }
}

// MARK: - Focus Manager Environment Tests

@MainActor
@Suite("Focus Manager Environment Tests")
struct FocusManagerEnvironmentTests {

    @Test("FocusManager is accessible via environment key")
    func focusManagerEnvironmentKey() {
        let manager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = manager

        #expect(environment.focusManager === manager)
    }

    @Test("Multiple tests can have independent FocusManagers")
    func independentManagers() {
        let manager1 = FocusManager()
        let manager2 = FocusManager()

        let element1 = MockFocusable(id: "test-1")
        let element2 = MockFocusable(id: "test-2")

        manager1.register(element1)
        manager2.register(element2)

        // Each manager should have its own focused element
        #expect(manager1.currentFocusedID == "test-1")
        #expect(manager2.currentFocusedID == "test-2")

        // Clearing one shouldn't affect the other
        manager1.clear()
        #expect(manager1.currentFocusedID == nil)
        #expect(manager2.currentFocusedID == "test-2")
    }
}
