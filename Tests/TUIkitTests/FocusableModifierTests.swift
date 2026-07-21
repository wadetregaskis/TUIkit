//  🖥️ TUIKit — Terminal UI Kit for Swift
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
