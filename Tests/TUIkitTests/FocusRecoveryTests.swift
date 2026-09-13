//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusRecoveryTests.swift
//
//  Where the keyboard goes when the control holding it can no longer hold it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// A control that disables itself hands the focus to its NEIGHBOUR — the next focusable
/// in the ring, else the previous — rather than to the top of its section.
///
/// Reported by the owner against the gradient editor: pressing ▶ until the selected stop
/// reached the end disabled ▶, and the keyboard jumped to the "Gradient" toggle at the top
/// of the dialog. `endRenderPass` dropped a present-but-unfocusable control's focus and
/// then auto-focused the section's FIRST control; `unregister` promised "the next
/// available" and walked from nowhere, which is also the first.
@MainActor
@Suite("Focus recovery goes to the neighbour")
struct FocusRecoveryTests {

    /// One pass registering `controls` in one section, in order.
    private func pass(_ manager: FocusManager, _ controls: [MockFocusable]) {
        manager.beginRenderPass()
        manager.registerSection(id: "dialog")
        for control in controls { manager.register(control, inSection: "dialog") }
        manager.endRenderPass()
    }

    @Test("A control that disables itself hands focus to the next one, not the first")
    func disabledHandsFocusForward() {
        let manager = FocusManager()
        let top = MockFocusable(id: "toggle")
        let left = MockFocusable(id: "left")
        let right = MockFocusable(id: "right")
        let preset = MockFocusable(id: "preset")
        pass(manager, [top, left, right, preset])
        manager.focus(id: "right")
        #expect(manager.currentFocusedID == "right", "sanity")

        right.canBeFocused = false
        pass(manager, [top, left, right, preset])

        #expect(manager.currentFocusedID == "preset", "the next control, not the toggle at the top")
    }

    @Test("The last control disabling itself hands focus back to the previous one")
    func lastHandsFocusBackward() {
        let manager = FocusManager()
        let top = MockFocusable(id: "toggle")
        let left = MockFocusable(id: "left")
        let right = MockFocusable(id: "right")
        pass(manager, [top, left, right])
        manager.focus(id: "right")

        right.canBeFocused = false
        pass(manager, [top, left, right])

        #expect(manager.currentFocusedID == "left", "nothing after it, so the one before")
    }

    /// A control that has LEFT the tree has no place in this pass's ring to be a
    /// neighbour of, and keeps the first-focusable fallback.
    @Test("A control that left the tree still falls back to the first")
    func goneFallsBackToFirst() {
        let manager = FocusManager()
        let top = MockFocusable(id: "toggle")
        let middle = MockFocusable(id: "middle")
        let bottom = MockFocusable(id: "bottom")
        pass(manager, [top, middle, bottom])
        manager.focus(id: "middle")

        pass(manager, [top, bottom])

        #expect(manager.currentFocusedID == "toggle")
    }

    @Test("Unregistering the focused control focuses its successor")
    func unregisterFocusesSuccessor() {
        let manager = FocusManager()
        let first = MockFocusable(id: "first")
        let second = MockFocusable(id: "second")
        let third = MockFocusable(id: "third")
        pass(manager, [first, second, third])
        manager.focus(id: "second")

        manager.unregister(second)

        #expect(manager.currentFocusedID == "third", "the next available, as the comment always said")
    }
}
