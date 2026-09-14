//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusRecoveryTests.swift
//
//  Where the keyboard goes when the control holding it can no longer hold it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// Whether the card in ``DisablingRow`` is disabled, flipped between frames.
private final class Switch {
    var isOn = false
}

/// Two buttons, a card that can be disabled, and (unless `atEnd`) a button after it.
/// The card is a `.focusable()` view or a `Button`.
private struct DisablingRow: View {
    let disabled: Switch
    let asFocusable: Bool
    let atEnd: Bool

    var body: some View {
        VStack {
            Button("top") {}
            Button("before") {}
            card
            if !atEnd { Button("after") {} }
        }
    }

    @ViewBuilder private var card: some View {
        if asFocusable {
            Text("card").focusable().disabled(disabled.isOn)
        } else {
            Button("card") {}.disabled(disabled.isOn)
        }
    }
}

/// A control that disables itself or leaves the tree hands the focus to its NEIGHBOUR
/// (the next focusable in the ring, else the previous) rather than to the top of its
/// section.
///
/// Reported by the owner against the gradient editor: pressing ▶ until the selected stop
/// reached the end disabled ▶, and the keyboard jumped to the "Gradient" toggle at the top
/// of the dialog. `endRenderPass` dropped a present-but-unfocusable control's focus and
/// then auto-focused the section's FIRST control; `unregister` promised "the next
/// available" and walked from nowhere, which is also the first. A control that left the
/// tree kept that first-focusable fallback until it, too, walked from where it stood.
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

    /// A control that has LEFT the tree has no place in this pass's ring, so it walks
    /// from the place it had in LAST frame's ring. It used to fall back to the first
    /// focusable, which a disabled `.focusable()` (it stops registering) hit and a
    /// disabled `Button` (it stays registered) did not.
    @Test("A control that left the tree hands focus to the one after where it stood")
    func goneHandsFocusForward() {
        let manager = FocusManager()
        let top = MockFocusable(id: "toggle")
        let middle = MockFocusable(id: "middle")
        let bottom = MockFocusable(id: "bottom")
        pass(manager, [top, middle, bottom])
        manager.focus(id: "middle")

        pass(manager, [top, bottom])

        #expect(manager.currentFocusedID == "bottom", "its neighbour, not the toggle at the top")
    }

    @Test("The last control leaving the tree hands focus back to the one before it")
    func goneLastHandsFocusBackward() {
        let manager = FocusManager()
        let top = MockFocusable(id: "toggle")
        let middle = MockFocusable(id: "middle")
        let bottom = MockFocusable(id: "bottom")
        pass(manager, [top, middle, bottom])
        manager.focus(id: "bottom")

        pass(manager, [top, middle])

        #expect(manager.currentFocusedID == "middle", "nothing after it, so the one before")
    }

    /// An `if`/`else` that swaps one button for another gives the new one a new
    /// focus id. It sits where the old one stood, so it is the old one's neighbour.
    @Test("A control swapped for another hands focus to its replacement")
    func goneHandsFocusToReplacement() {
        let manager = FocusManager()
        let top = MockFocusable(id: "toggle")
        let edit = MockFocusable(id: "edit")
        let after = MockFocusable(id: "after")
        pass(manager, [top, edit, after])
        manager.focus(id: "edit")

        pass(manager, [top, MockFocusable(id: "save"), after])

        #expect(manager.currentFocusedID == "save")
    }

    /// Nothing that stood before it survived, so its place is the top of the ring.
    @Test("A control whose whole neighbourhood was replaced falls back to the first")
    func goneWithNothingLeftFallsBackToFirst() {
        let manager = FocusManager()
        pass(manager, [MockFocusable(id: "old-1"), MockFocusable(id: "old-2")])
        manager.focus(id: "old-2")

        pass(manager, [MockFocusable(id: "new-1"), MockFocusable(id: "new-2")])

        #expect(manager.currentFocusedID == "new-1")
    }

    /// The case the owner asked to line up: `.focusable()` does not register at all
    /// while disabled, and `Button` registers as unfocusable. Both must hand the
    /// focus to the same neighbour.
    @Test("A disabled .focusable() hands focus where a disabled Button does", arguments: [false, true])
    func disabledFocusableMatchesDisabledButton(atEnd: Bool) throws {
        let button = try landing(asFocusable: false, atEnd: atEnd)
        let focusable = try landing(asFocusable: true, atEnd: atEnd)
        let neighbour = atEnd ? 1 : 3
        #expect(button == neighbour, "a disabled Button: stop \(String(describing: button))")
        #expect(focusable == neighbour, "a disabled .focusable(): stop \(String(describing: focusable))")
    }

    /// Renders top, before, card and (unless `atEnd`) after, focuses the card, disables
    /// it, and returns the index of the stop the focus ended on.
    private func landing(asFocusable: Bool, atEnd: Bool) throws -> Int? {
        let tui = TUIContext()
        let manager = FocusManager()
        let disabled = Switch()
        let view = DisablingRow(disabled: disabled, asFocusable: asFocusable, atEnd: atEnd)
        render(view, tui, manager)
        let stops = manager.registeredFocusIDsInActiveSection()
        try #require(stops.count == (atEnd ? 3 : 4), "the arrangement's stops: \(stops)")
        manager.focus(id: stops[2])
        render(view, tui, manager)
        try #require(manager.currentFocusedID == stops[2], "the card holds the focus")

        disabled.isOn = true
        render(view, tui, manager)
        return manager.currentFocusedID.flatMap { stops.firstIndex(of: $0) }
    }

    /// One live-loop-shaped frame with a real focus manager and state storage.
    private func render(_ view: some View, _ tui: TUIContext, _ manager: FocusManager) {
        var environment = EnvironmentValues()
        environment.focusManager = manager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        manager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        manager.endRenderPass()
        tui.stateStorage.endRenderPass()
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
