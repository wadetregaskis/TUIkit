//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldValueTests.swift
//
//  `TextField(_:value:format:)` — the draft, and the two moments it is
//  reconciled with the bound value.
//
//  These drive a REAL field: rendered into a live focus manager, then typed
//  into through `dispatchKeyEvent`, then re-rendered. That matters more here
//  than usual, because the whole feature is a `@State` draft surviving between
//  frames — a test that called the initializer and inspected the value would
//  pass whether or not any of that worked.
//
//  Every format style is pinned to `en_US` so the expected strings are the
//  same on every host; the grouping separator is exactly what makes formatting
//  visible, so it cannot be dropped to sidestep the locale.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("TextField value formatting")
struct TextFieldValueTests {

    /// A number format whose output does not depend on where the test runs.
    private static let number = IntegerFormatStyle<Int>().locale(Locale(identifier: "en_US"))

    /// One field, one live focus manager, and a context whose state storage
    /// (and render cache) persist across renders — which is the point.
    private struct Harness {
        let context: RenderContext
        let focusManager: FocusManager
        let value: StateBox<Int>
        /// How many times anything wrote through the value binding.
        let writes: StateBox<Int>
    }

    private func makeHarness(initial: Int) -> Harness {
        let focusManager = FocusManager()
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        // Built by hand rather than via `makeRenderContext`: that helper swaps
        // in a render cache that diverges from the `TUIContext`'s, so a
        // `@State` change would not invalidate what the next render serves.
        let context = RenderContext(
            availableWidth: 40, availableHeight: 4,
            environment: environment, tuiContext: TUIContext())
        return Harness(
            context: context, focusManager: focusManager,
            value: StateBox(initial), writes: StateBox(0))
    }

    /// Renders the field once through a full focus pass and returns the text.
    private func render(_ harness: Harness) -> String {
        let binding = Binding(
            get: { harness.value.value },
            set: { harness.writes.value += 1; harness.value.value = $0 })
        let field = TextField("Quantity", value: binding, format: Self.number)
        harness.focusManager.beginRenderPass()
        let buffer = renderToBuffer(field, context: harness.context)
        harness.focusManager.endRenderPass()
        return buffer.lines.map(\.stripped).joined(separator: "\n")
    }

    private func type(_ text: String, into harness: Harness) {
        for character in text {
            _ = harness.focusManager.dispatchKeyEvent(KeyEvent(key: .character(character)))
        }
    }

    /// Ctrl+U erases the field, so a test can type a whole value rather than
    /// insert into the formatted one at whatever the cursor happens to be.
    private func clear(_ harness: Harness) {
        _ = harness.focusManager.dispatchKeyEvent(KeyEvent(key: .character("u"), ctrl: true))
    }

    // MARK: - Display

    @Test("An untouched field shows the value, formatted")
    func showsTheFormattedValue() {
        let harness = makeHarness(initial: 1234)
        #expect(render(harness).contains("1,234"))
        #expect(harness.writes.value == 0, "rendering must not write to the binding")
    }

    // MARK: - The draft

    @Test("While typing, the field shows what was typed — not a re-format")
    func typingIsNotReformatted() {
        let harness = makeHarness(initial: 1234)
        _ = render(harness)
        clear(harness)
        type("5678", into: harness)

        let line = render(harness)
        #expect(line.contains("5678"), "got \(line)")
        #expect(!line.contains("5,678"), "a re-format mid-edit would move the cursor")
        #expect(harness.value.value == 1234, "nothing is committed until the user says so")
    }

    // MARK: - Commit

    @Test("Return commits the draft and the field re-formats")
    func returnCommits() {
        let harness = makeHarness(initial: 1234)
        _ = render(harness)
        clear(harness)
        type("5678", into: harness)
        _ = harness.focusManager.dispatchKeyEvent(KeyEvent(key: .enter))

        #expect(harness.value.value == 5678)
        // The draft is gone, so the value is being formatted again — which is
        // how a successful commit becomes visible.
        #expect(render(harness).contains("5,678"))
    }

    @Test("Leaving the field commits it too")
    func focusLossCommits() {
        let harness = makeHarness(initial: 1234)
        _ = render(harness)
        clear(harness)
        type("42", into: harness)
        // Nothing else is focusable, so drop focus directly — the same
        // transition Tab produces, and the one `onFocusLost` fires on.
        harness.focusManager.relinquishFocus()

        #expect(harness.value.value == 42)
        #expect(render(harness).contains("42"))
    }

    @Test("Text that does not parse leaves the value alone and reverts")
    func unparseableTextReverts() {
        let harness = makeHarness(initial: 1234)
        _ = render(harness)
        clear(harness)
        type("not a number", into: harness)
        _ = harness.focusManager.dispatchKeyEvent(KeyEvent(key: .enter))

        #expect(harness.value.value == 1234, "the value is untouched")
        let line = render(harness)
        #expect(line.contains("1,234"), "and the field snaps back to it — got \(line)")
        #expect(!line.contains("not a number"))
    }

    @Test("An empty field is unparseable, not zero")
    func emptyIsNotZero() {
        let harness = makeHarness(initial: 1234)
        _ = render(harness)
        clear(harness)
        _ = harness.focusManager.dispatchKeyEvent(KeyEvent(key: .enter))

        #expect(harness.value.value == 1234, "erasing a field must not mean 0")
    }

    @Test("Committing an untouched field does not write to the binding")
    func untouchedCommitDoesNotWrite() {
        let harness = makeHarness(initial: 1234)
        _ = render(harness)
        _ = harness.focusManager.dispatchKeyEvent(KeyEvent(key: .enter))
        harness.focusManager.relinquishFocus()
        _ = render(harness)

        // A write here would be harmless-looking and wrong: it republishes the
        // value, so anything observing the binding re-renders for no reason.
        #expect(harness.writes.value == 0)
        #expect(harness.value.value == 1234)
    }

    // MARK: - The app's own handlers still run

    @Test("An app's onSubmit runs alongside the commit")
    func appSubmitActionStillRuns() {
        let harness = makeHarness(initial: 1)
        let submits = StateBox(0)
        let binding = Binding(
            get: { harness.value.value }, set: { harness.value.value = $0 })

        func renderOnce() {
            let field = TextField("Quantity", value: binding, format: Self.number)
                .onSubmit { submits.value += 1 }
            harness.focusManager.beginRenderPass()
            _ = renderToBuffer(field, context: harness.context)
            harness.focusManager.endRenderPass()
        }

        renderOnce()
        clear(harness)
        type("7", into: harness)
        _ = harness.focusManager.dispatchKeyEvent(KeyEvent(key: .enter))

        #expect(harness.value.value == 7, "the commit happened")
        #expect(submits.value == 1, "and so did the app's action")
    }
}
