//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusableModifierTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  `.focusable()` makes an otherwise non-interactive view a focus stop, which is
//  what lets `.focused($x)` bind to a plain view like Text.

import Testing

@testable import TUIkit
@testable import TUIkitView

@MainActor
@Suite("focusable")
struct FocusableModifierTests {
    /// A reference cell so a test can capture a value produced inside a body.
    private final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }

    /// Renders one frame with a real focus manager + storage.
    @discardableResult
    private func render(_ view: some View, _ tui: TUIContext, _ manager: FocusManager) -> FocusManager {
        _ = renderBuffer(view, tui, manager)
        return manager
    }

    /// ``render(_:_:_:)``, keeping the frame it drew — for the cases that ask
    /// what the buffer carries rather than what the ring holds.
    private func renderBuffer(
        _ view: some View, _ tui: TUIContext, _ manager: FocusManager
    ) -> FrameBuffer {
        var environment = EnvironmentValues()
        environment.focusManager = manager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12,
            environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        manager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        manager.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer
    }

    @Test("focusable() registers a focus stop, and a lone one auto-focuses")
    func registersAndAutoFocuses() {
        let manager = render(Text("x").focusable(), TUIContext(), FocusManager())
        let ids = manager.registeredFocusIDsInActiveSection()
        #expect(ids.count == 1, "one focus stop is registered")
        #expect(
            ids.first.map { manager.isFocused(id: $0) } == true,
            "a lone focusable auto-focuses")
    }

    @Test("focusable(false) registers nothing")
    func falseFlagRegistersNothing() {
        let manager = render(Text("x").focusable(false), TUIContext(), FocusManager())
        #expect(manager.registeredFocusIDsInActiveSection().isEmpty)
    }

    @Test("focusable(false) takes its content out of the Tab ring")
    func falseFlagSuppressesContentStops() {
        // `Text` was never focusable, so the test above passes whatever the
        // modifier does with its content. The case the parameter is FOR is a
        // control that registers a stop of its own: SwiftUI's `isFocusable`
        // says "`false` otherwise", and a button told that must not be
        // somewhere Tab can land.
        let manager = render(
            VStack {
                Button("Alpha") {}
                Button("Beta") {}.focusable(false)
            }, TUIContext(), FocusManager())
        let ids = manager.registeredFocusIDsInActiveSection()
        #expect(ids.count == 1, "only Alpha is a focus stop, but the ring holds \(ids)")

        // The ring is one stop long, so Tab cycles back onto Alpha rather than
        // landing on Beta.
        let before = manager.currentFocusedID
        manager.focusNext()
        #expect(
            manager.currentFocusedID == before,
            "Tab moved off Alpha onto \(manager.currentFocusedID ?? "nil")")
    }

    @Test("An inner focusable(true) does not re-open a focusable(false) subtree")
    func innerTrueDoesNotReopen() {
        // The suppression is ADDITIVE, like `.disabled(_:)` and unlike SwiftUI,
        // where the modifier speaks for one node and a descendant declares its
        // own focusability. It has to be: it is the same flag `.hidden()` sets,
        // so a `true` that cleared it would put a hidden view back in the ring.
        let manager = render(
            VStack {
                Text("Alpha").focusable()
                Text("Beta").focusable()
            }.focusable(false), TUIContext(), FocusManager())
        #expect(manager.registeredFocusIDsInActiveSection().isEmpty)
    }

    @Test("focusable() inside .hidden() stays out of the ring")
    func hiddenSuppressesAnInnerFocusable() {
        // The reason the `true` case writes nothing rather than writing `false`.
        // A hidden view is no Tab stop — there is no picture for the ring to
        // land on — and an explicit `.focusable()` inside one must not undo that.
        let manager = render(Text("x").focusable().hidden(), TUIContext(), FocusManager())
        #expect(manager.registeredFocusIDsInActiveSection().isEmpty)
    }

    @Test("A suppressed focusable offers no click-to-focus region")
    func suppressedFocusableTakesNoClicks() {
        // `.activate` (in `.automatic`) makes the content clickable to focus it.
        // Nothing filed the stop, so the click would reach
        // `FocusManager.focus(id:)` with an id no section holds — a pending
        // intent that repaints for a couple of passes looking for it.
        let buffer = renderBuffer(
            VStack { Text("x").focusable() }.focusable(false),
            TUIContext(), FocusManager())
        #expect(buffer.hitTestRegions.isEmpty)
    }

    @Test("A disabled focusable does not register")
    func disabledDoesNotRegister() {
        let manager = render(Text("x").focusable().disabled(true), TUIContext(), FocusManager())
        #expect(manager.registeredFocusIDsInActiveSection().isEmpty)
    }

    // MARK: - \.isFocused

    /// Records what `\.isFocused` read inside a focusable's content.
    private struct FocusReporter: View {
        let seen: Box<Bool?>
        @Environment(\.isFocused) private var isFocused
        var body: some View {
            seen.value = isFocused
            return Text("x")
        }
    }

    @Test("A focusable publishes \\.isFocused to its content")
    func publishesIsFocused() {
        // Without this, `.focusable()` makes a view reachable by Tab and gives
        // it no way to say so — an app's own control could hold the focus and
        // draw exactly as it does when it does not. SwiftUI's `.focusable()`
        // sets `\.isFocused` for the same reason.
        let seen = Box<Bool?>(nil)
        render(FocusReporter(seen: seen).focusable(), TUIContext(), FocusManager())
        #expect(seen.value == true, "the lone focusable auto-focuses")
    }

    @Test("An UNfocused focusable publishes false")
    func publishesIsFocusedFalse() {
        // Two stops, and the first takes the focus — so the second must report
        // false rather than simply never being told.
        let seen = Box<Bool?>(nil)
        render(
            VStack {
                Text("first").focusable()
                FocusReporter(seen: seen).focusable()
            }, TUIContext(), FocusManager())
        #expect(seen.value == false)
    }

    @Test("A view that is not focusable is told nothing")
    func nonFocusableIsUnchanged() {
        // The value defaults to false and nothing sets it — so a plain view
        // inside a focused control does not inherit the control's answer.
        let seen = Box<Bool?>(nil)
        render(FocusReporter(seen: seen), TUIContext(), FocusManager())
        #expect(seen.value == false)
    }

    // MARK: - .focused($x) round-trip

    private struct FocusableBoolHarness: View {
        @FocusState var active: Bool
        let binding: Box<FocusState<Bool>.Binding?>
        var body: some View {
            binding.value = $active
            // `.focused` outermost so it plants the forced id before the inner
            // `.focusable` adopts it.
            return Text("x").focusable().focused($active)
        }
    }

    @Test("focused($x) works on a plain view once it is focusable")
    func focusedBindingRoundTrips() {
        let box = Box<FocusState<Bool>.Binding?>(nil)
        let manager = render(FocusableBoolHarness(binding: box), TUIContext(), FocusManager())
        _ = manager
        #expect(
            box.value?.wrappedValue == true,
            "the lone focusable auto-focuses, so the bound @FocusState reads true — .focused now works on a non-control view")
    }
}
