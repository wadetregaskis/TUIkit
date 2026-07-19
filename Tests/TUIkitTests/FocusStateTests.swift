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
        var body: some View {
            binding.value = $field
            return VStack {
                TextField("name", text: .constant("")).focused($field, equals: .name)
                TextField("email", text: .constant("")).focused($field, equals: .email)
            }
            .defaultFocus($field, applyDefault ? .email : .name)
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
}
