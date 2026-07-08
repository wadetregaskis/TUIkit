//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FocusEdgeCaseTests.swift
//
//  Minimized regressions from the focus storm (FocusStormTests):
//  - Tab section-cycling used to land in a section with no focusable
//    element (all disabled, or all absent this frame) and stop there,
//    leaving the app with nothing focused - the focus indicator vanished
//    for a keypress. Such sections are not Tab stops.
//  - endRenderPass validated only the focused element's *presence*, not its
//    focusability, so an element registering with a dynamic canBeFocused
//    (a ScrollView is focusable only while its content overflows) kept a
//    phantom focus after turning non-focusable: no indicator anywhere,
//    while still receiving every key event.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Focus edge cases")
struct FocusEdgeCaseTests {
    @Test("Tab skips a section whose elements are all disabled")
    func tabSkipsAllDisabledSection() {
        let manager = FocusManager()
        for section in ["one", "two", "three"] { manager.registerSection(id: section) }
        let first = MockFocusable(id: "a")
        let disabled = MockFocusable(id: "b", canBeFocused: false)
        let third = MockFocusable(id: "c")
        manager.register(first, inSection: "one")
        manager.register(disabled, inSection: "two")
        manager.register(third, inSection: "three")

        #expect(manager.isFocused(first))

        // Tab: section "two" has nothing focusable, so the ring skips to "three".
        _ = manager.dispatchKeyEvent(KeyEvent(key: .tab))
        #expect(manager.isFocused(third), "the all-disabled section is not a Tab stop")
        #expect(manager.isActiveSection("three"))

        // Shift+Tab: back over the empty section to "one".
        _ = manager.dispatchKeyEvent(KeyEvent(key: .tab, shift: true))
        #expect(manager.isFocused(first))
        #expect(manager.isActiveSection("one"))
    }

    @Test("Tab stays put when no other section has a focusable element")
    func tabStaysWhenAllOtherSectionsEmpty() {
        let manager = FocusManager()
        for section in ["one", "two"] { manager.registerSection(id: section) }
        let only = MockFocusable(id: "a")
        let disabled = MockFocusable(id: "b", canBeFocused: false)
        manager.register(only, inSection: "one")
        manager.register(disabled, inSection: "two")

        _ = manager.dispatchKeyEvent(KeyEvent(key: .tab))
        #expect(manager.isFocused(only), "focus does not vanish into the empty section")
        #expect(manager.isActiveSection("one"))
    }

    @Test("A focused element that turns non-focusable loses focus at render end")
    func nonFocusableElementLosesFocus() {
        let manager = FocusManager()
        let scrollLike = MockFocusable(id: "scroll")
        let button = MockFocusable(id: "button")

        // Frame 1: both focusable; the scroll-like element holds focus.
        manager.beginRenderPass()
        manager.register(scrollLike)
        manager.register(button)
        manager.endRenderPass()
        #expect(manager.isFocused(scrollLike))

        // Frame 2: its content now fits - it re-registers as non-focusable
        // (exactly what ScrollView does when overflow disappears).
        scrollLike.canBeFocused = false
        manager.beginRenderPass()
        manager.register(scrollLike)
        manager.register(button)
        manager.endRenderPass()

        #expect(!manager.isFocused(scrollLike), "phantom focus on a non-focusable element")
        #expect(manager.isFocused(button), "focus recovers to the first focusable element")
    }
}
