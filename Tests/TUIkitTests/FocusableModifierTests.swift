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
        var environment = EnvironmentValues()
        environment.focusManager = manager
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12,
            environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        manager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        manager.endRenderPass()
        tui.stateStorage.endRenderPass()
        return manager
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
