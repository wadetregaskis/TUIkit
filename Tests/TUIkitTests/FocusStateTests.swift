//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FocusStateTests.swift
//
//  The SwiftUI-shaped declarative focus API: `@FocusState`, `.focused(_:)`,
//  `.focused(_:equals:)`, `.defaultFocus(_:_:)`. Driven through the real render
//  path (bindStateProperties + FocusManager), so the value↔focusID wiring and
//  the default-focus override are exercised end to end.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

// MARK: - Harness

private enum Field: Hashable { case name, email }

/// A reference cell so a test can capture a value produced inside a view body.
private final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

@MainActor
@Suite("@FocusState declarative focus")
struct FocusStateTests {
    /// Renders `view` one frame with a real focus manager + storage, returning
    /// the manager so the test can inspect / drive focus.
    @discardableResult
    private func render<V: View>(
        _ view: V, tuiContext: TUIContext, focusManager: FocusManager
    ) -> FocusManager {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 12,
            environment: environment, tuiContext: tuiContext)
        tuiContext.stateStorage.beginRenderPass()
        focusManager.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        return focusManager
    }

    // MARK: Bool binding

    private struct BoolHarness: View {
        @FocusState var active: Bool
        let binding: Box<FocusState<Bool>.Binding?>
        var body: some View {
            binding.value = $active
            return TextField("field", text: .constant("")).focused($active)
        }
    }

    @Test("A Bool @FocusState reflects and drives its control's focus")
    func boolBinding() {
        let tui = TUIContext()
        let manager = FocusManager()
        let bindingBox = Box<FocusState<Bool>.Binding?>(nil)
        let view = BoolHarness(binding: bindingBox)

        render(view, tuiContext: tui, focusManager: manager)
        // The single field auto-focuses, so the bound Bool reads true.
        #expect(bindingBox.value?.wrappedValue == true, "the focused field reads true")

        // Set it false → focus is relinquished.
        bindingBox.value?.wrappedValue = false
        render(view, tuiContext: tui, focusManager: manager)
        #expect(
            bindingBox.value?.wrappedValue == true,
            "a lone focusable re-auto-focuses after the frame, so it reads true again")
    }

    // MARK: Optional binding

    private struct FieldHarness: View {
        @FocusState var field: Field?
        let binding: Box<FocusState<Field?>.Binding?>
        var applyDefault = false
        var priority: DefaultFocusEvaluationPriority = .automatic
        var body: some View {
            binding.value = $field
            return VStack {
                TextField("name", text: .constant("")).focused($field, equals: .name)
                TextField("email", text: .constant("")).focused($field, equals: .email)
            }
            .defaultFocus($field, applyDefault ? .email : .name, priority: priority)
        }
    }

    /// The default's target (`.email`) is only shown when `showEmail` is set.
    private struct ConditionalHarness: View {
        @FocusState var field: Field?
        let binding: Box<FocusState<Field?>.Binding?>
        let showEmail: Box<Bool>
        var body: some View {
            binding.value = $field
            return VStack {
                TextField("name", text: .constant("")).focused($field, equals: .name)
                if showEmail.value {
                    TextField("email", text: .constant("")).focused($field, equals: .email)
                }
            }
            .defaultFocus($field, .email)
        }
    }

    @Test("An optional @FocusState reports and moves focus between controls")
    func optionalBinding() {
        let tui = TUIContext()
        let manager = FocusManager()
        let bindingBox = Box<FocusState<Field?>.Binding?>(nil)
        let view = FieldHarness(binding: bindingBox)

        render(view, tuiContext: tui, focusManager: manager)
        // First bound field is the default focus → the optional reads .name.
        #expect(
            bindingBox.value?.wrappedValue == .name,
            "the first field holds focus, round-tripped through the optional value")

        // Move focus to .email via the binding.
        bindingBox.value?.wrappedValue = .email
        render(view, tuiContext: tui, focusManager: manager)
        #expect(bindingBox.value?.wrappedValue == .email, "setting the binding moved focus")

        // Setting nil relinquishes focus.
        bindingBox.value?.wrappedValue = nil
        // Read the value BEFORE re-rendering (a re-render re-auto-focuses the
        // first field); the relinquish itself must have taken hold.
        #expect(bindingBox.value?.wrappedValue == nil, "nil clears focus")
    }

    @Test("defaultFocus picks the initial control, overriding the first-registrant default")
    func defaultFocusOverridesFirst() {
        let tui = TUIContext()
        let manager = FocusManager()
        let bindingBox = Box<FocusState<Field?>.Binding?>(nil)
        // .defaultFocus($field, .email): the SECOND field should hold the
        // initial focus, not the first-registered one.
        let view = FieldHarness(binding: bindingBox, applyDefault: true)

        render(view, tuiContext: tui, focusManager: manager)
        #expect(
            bindingBox.value?.wrappedValue == .email,
            "the .email field is the declared default focus")
    }

    @Test("defaultFocus applies once, then leaves the user in control")
    func defaultFocusAppliesOnce() {
        let tui = TUIContext()
        let manager = FocusManager()
        let bindingBox = Box<FocusState<Field?>.Binding?>(nil)
        let view = FieldHarness(binding: bindingBox, applyDefault: true)

        render(view, tuiContext: tui, focusManager: manager)
        #expect(bindingBox.value?.wrappedValue == .email)

        // The user moves focus to .name; a subsequent render must NOT drag it
        // back to the .email default.
        bindingBox.value?.wrappedValue = .name
        render(view, tuiContext: tui, focusManager: manager)
        #expect(
            bindingBox.value?.wrappedValue == .name,
            "the default focus is initial-only; it does not re-steal focus")
    }

    @Test("A default whose target appears on a later frame does not steal focus (finding 1/4)")
    func conditionalDefaultTargetDoesNotSteal() {
        let tui = TUIContext()
        let manager = FocusManager()
        let bindingBox = Box<FocusState<Field?>.Binding?>(nil)
        let showEmail = Box(false)
        let view = ConditionalHarness(binding: bindingBox, showEmail: showEmail)

        // Frame 1: the .email default target isn't shown yet, so the default
        // shot is spent and .name (the only focusable) auto-focuses.
        render(view, tuiContext: tui, focusManager: manager)
        #expect(bindingBox.value?.wrappedValue == .name, "the shown field auto-focuses")

        // The .email field appears on a later frame; the already-spent default
        // must NOT yank focus off .name.
        showEmail.value = true
        render(view, tuiContext: tui, focusManager: manager)
        #expect(
            bindingBox.value?.wrappedValue == .name,
            "a conditionally-appearing default target does not steal focus later")
    }

    @Test("defaultFocus re-applies when its focus scope disappears and reappears (finding 3)")
    func defaultFocusReAppliesOnScopeReappear() {
        let tui = TUIContext()
        let manager = FocusManager()
        let bindingBox = Box<FocusState<Field?>.Binding?>(nil)
        let view = FieldHarness(binding: bindingBox, applyDefault: true)

        render(view, tuiContext: tui, focusManager: manager)
        #expect(bindingBox.value?.wrappedValue == .email)

        // The user moves off the default, then the whole scope leaves the tree.
        bindingBox.value?.wrappedValue = .name
        render(Text("elsewhere"), tuiContext: tui, focusManager: manager)

        // Re-presenting the scope re-applies its default (not left "applied").
        render(view, tuiContext: tui, focusManager: manager)
        #expect(
            bindingBox.value?.wrappedValue == .email,
            "a re-presented scope's default focus applies again")
    }

    @Test(".userInitiated defaultFocus re-asserts focus every render (finding 7)")
    func userInitiatedDefaultReAsserts() {
        let tui = TUIContext()
        let manager = FocusManager()
        let bindingBox = Box<FocusState<Field?>.Binding?>(nil)
        let view = FieldHarness(
            binding: bindingBox, applyDefault: true, priority: .userInitiated)

        render(view, tuiContext: tui, focusManager: manager)
        #expect(bindingBox.value?.wrappedValue == .email)

        // The user moves to .name; .userInitiated drags it back on the next render.
        bindingBox.value?.wrappedValue = .name
        render(view, tuiContext: tui, focusManager: manager)
        #expect(
            bindingBox.value?.wrappedValue == .email,
            ".userInitiated re-asserts the default even after the user moved focus")
    }

    @Test("defaultFocus lands directly on its target — no transient focus on the wrong control (finding 6)")
    func defaultFocusDoesNotTransientlyFocusFirstControl() {
        let manager = FocusManager()
        let first = MockFocusable(id: "a")
        let target = MockFocusable(id: "b")

        // Simulate one render pass: .defaultFocus declares the value BEFORE the
        // controls register (it wraps them), then each .focused registers its
        // binding and its control.
        manager.beginRenderPass()
        manager.setDefaultFocusValue(AnyHashable(2), priority: .automatic, forStore: "s")
        manager.registerFocusBinding(store: "s", value: AnyHashable(1), focusID: "a")
        manager.register(first)
        manager.registerFocusBinding(store: "s", value: AnyHashable(2), focusID: "b")
        manager.register(target)
        manager.endRenderPass()

        #expect(target.focusReceivedCount == 1, "the default target receives focus")
        #expect(
            first.focusReceivedCount == 0,
            "the first control is never transiently focused (no spurious editing began/ended)")
        #expect(first.focusLostCount == 0)
    }
}
