//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EditorPanelChromeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

/// "Cancel means the edit never happened" — the rule the four live-editing
/// panels share, tested here because there is now one copy of it to test.
///
/// It was written out four times and asserted **nowhere**: the only test that
/// went near it checked that the word "Cancel" appears in a footer. The rule is
/// not about the footer. These panels write every drag straight through the
/// caller's binding — that is the live preview, and the reason the undo has to
/// exist at all — so a broken revert means an editor that silently keeps changes
/// the user cancelled, and nothing in the picture says so.
@MainActor
@Suite("Cancel means the edit never happened", .serialized, .rendersEnglishUI)
struct EditorPanelChromeTests {

    /// A host that can take the panel away, which is how every dismissal that is
    /// not a button ends: `Esc`, the modal closing, the page going away.
    private struct Host: View {
        let value: Binding<Int>
        let presented: Binding<Bool>
        var body: some View {
            VStack {
                if presented.wrappedValue {
                    _EditorPanelChrome(
                        title: "Edit", edited: value, isPresented: presented
                    ) {
                        // Wide enough that the footer draws both labels in
                        // full: the dialog hugs its content, and a narrow
                        // one truncates "Done" to "D…".
                        Text("value \(value.wrappedValue) — a body wide enough to name")
                    }
                }
            }
        }
    }

    /// One context whose state and lifecycle persist across frames, as the run
    /// loop's does — the panel's `@State` session and its `onAppear`/
    /// `onDisappear` pair are the whole mechanism, and neither survives a fresh
    /// context per frame.
    @MainActor
    private final class Harness {
        let tui = TUIContext()
        let context: RenderContext

        init() {
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tui)
            context = RenderContext(
                availableWidth: 60, availableHeight: 20, environment: environment,
                tuiContext: tui)
        }

        /// One frame, with the brackets the run loop puts around it, and the
        /// pointer armed from the composited result so a test can click.
        @discardableResult
        func frame(_ view: some View) -> FrameBuffer {
            tui.mouseEventDispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            context.environment.lifecycle?.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            let composited = buffer.compositingOverlays(
                maxWidth: context.availableWidth, maxHeight: context.availableHeight,
                palette: context.environment.palette)
            tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
            context.environment.lifecycle?.endRenderPass()
            tui.stateStorage.endRenderPass()
            return composited
        }

        /// Clicks the middle of the first line containing `label`.
        func click(_ label: String, in buffer: FrameBuffer) -> Bool {
            guard let row = buffer.lines.firstIndex(where: { $0.stripped.contains(label) }),
                let column = buffer.lines[row].stripped.range(of: label)
            else { return false }
            let stripped = buffer.lines[row].stripped
            let x = stripped.distance(from: stripped.startIndex, to: column.lowerBound)
                + label.count / 2
            _ = tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: .left, phase: .pressed, x: x, y: row))
            return tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: .left, phase: .released, x: x, y: row))
        }
    }

    @Test("A dismissal that is not Done puts the opening value back")
    func dismissalReverts() {
        var value = 1
        var presented = true
        let host = Host(
            value: Binding(get: { value }, set: { value = $0 }),
            presented: Binding(get: { presented }, set: { presented = $0 }))
        let harness = Harness()

        harness.frame(host)
        harness.frame(host)
        value = 42  // the live edit, written straight through as a drag would
        presented = false  // Esc, the modal closing, the page going away
        harness.frame(host)

        #expect(value == 1, "the edit was undone on dismissal, got \(value)")
    }

    @Test("Done keeps the edit")
    func doneKeepsTheEdit() throws {
        var value = 1
        var presented = true
        let host = Host(
            value: Binding(get: { value }, set: { value = $0 }),
            presented: Binding(get: { presented }, set: { presented = $0 }))
        let harness = Harness()

        harness.frame(host)
        let armed = harness.frame(host)
        value = 42
        // `try #require`, not `#expect`: `click` matches the footer button by
        // its TEXT, which is the framework's own word, so a miss means no mouse
        // event was ever dispatched. Left as an `#expect`, the two assertions
        // below still ran and reported "Done dismissed the panel" == false and
        // a lost edit — a modal-dismissal regression that had not happened. A
        // click that found nothing must fail as a click that found nothing.
        try #require(harness.click("Done", in: armed), "the Done button is hittable")
        #expect(presented == false, "Done dismissed the panel")
        harness.frame(host)  // the frame the panel is gone from

        #expect(value == 42, "Done kept the edit, got \(value)")
    }

    @Test("Cancel is a dismissal like any other: the edit is undone")
    func cancelReverts() throws {
        var value = 1
        var presented = true
        let host = Host(
            value: Binding(get: { value }, set: { value = $0 }),
            presented: Binding(get: { presented }, set: { presented = $0 }))
        let harness = Harness()

        harness.frame(host)
        let armed = harness.frame(host)
        value = 42
        try #require(harness.click("Cancel", in: armed), "the Cancel button is hittable")
        #expect(presented == false, "Cancel dismissed the panel")
        harness.frame(host)

        #expect(value == 1, "Cancel undid the edit, got \(value)")
    }

    @Test("Done's extra work runs on Done and only on Done")
    func onDoneRunsOnlyOnDone() throws {
        /// `GradientEditorPanel` hangs its recents bookkeeping here, and a
        /// recents list is a history of what the user KEPT.
        final class Tally { var applies = 0 }

        struct TallyingHost: View {
            let value: Binding<Int>
            let presented: Binding<Bool>
            let tally: Tally
            var body: some View {
                VStack {
                    if presented.wrappedValue {
                        _EditorPanelChrome(
                            title: "Edit", edited: value, isPresented: presented
                        ) {
                            Text("value \(value.wrappedValue) — a body wide enough to name")
                        }
                        .onDone { tally.applies += 1 }
                    }
                }
            }
        }

        var value = 1
        var presented = true
        let tally = Tally()
        let host = TallyingHost(
            value: Binding(get: { value }, set: { value = $0 }),
            presented: Binding(get: { presented }, set: { presented = $0 }),
            tally: tally)
        let harness = Harness()

        harness.frame(host)
        let armed = harness.frame(host)
        #expect(tally.applies == 0, "not while the panel is open")
        try #require(harness.click("Cancel", in: armed), "the Cancel button is hittable")
        harness.frame(host)
        #expect(tally.applies == 0, "not on Cancel")

        presented = true
        harness.frame(host)
        let reopened = harness.frame(host)
        try #require(harness.click("Done", in: reopened), "the Done button is hittable")
        harness.frame(host)
        #expect(tally.applies == 1, "once on Done, got \(tally.applies)")
    }
}
