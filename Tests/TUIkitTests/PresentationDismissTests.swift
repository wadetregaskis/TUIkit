//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationDismissTests.swift
//
//  `@Environment(\.dismiss)` inside a presentation used to QUIT THE APP.
//
//  `DismissAction`'s default action is `nil`, and calling a `nil` one exits the
//  run loop — correct at the top level, where dismissing a terminal app is
//  quitting it. But no presentation modifier replaced it, so the shape
//  SwiftUI's own documentation teaches —
//
//      .sheet(isPresented: $showing) {
//          Button("Done") { dismiss() }        // @Environment(\.dismiss)
//      }
//
//  — terminated the program instead of closing the sheet. Only
//  `NavigationStack` installed a real action, so only a pushed screen behaved.
//
//  These pin the fix at the seam that broke: whether the presented content's
//  environment carries an action at all. `requestExit()` is the failure mode,
//  so the test asserts the binding closes AND that nothing asked to exit.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit
@testable import TUIkitView

@MainActor
@Suite("dismiss() closes the presentation, not the app")
struct PresentationDismissTests {

    /// Captures whatever `\.dismiss` means where it is placed.
    private struct Capture: View {
        @Environment(\.dismiss) private var dismiss
        let sink: DismissSink

        var body: some View {
            sink.captured = dismiss
            return Text(verbatim: "presented")
        }
    }

    /// A box, because the capture happens during a render and is read after.
    private final class DismissSink: @unchecked Sendable {
        var captured: DismissAction?
    }

    private struct Presented: Hashable, Identifiable {
        let id = 1
    }

    /// Renders `view` one frame the way the run loop does.
    private func frame(_ view: some View) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = 60
        let context = RenderContext(
            availableWidth: 60, availableHeight: 20, environment: environment, tuiContext: tui)
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        environment.focusManager?.beginRenderPass()
        _ = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        environment.focusManager?.endRenderPass()
    }

    /// Presents `content` through `present`, runs the `\.dismiss` it saw, and
    /// reports what that did.
    ///
    /// - Returns: Whether the presentation binding closed, and whether anything
    ///   asked the run loop to exit — the bug's signature.
    private func dismissFromInside(
        _ present: (Binding<Bool>, @escaping () -> AnyView) -> AnyView
    ) throws -> (closed: Bool, askedToExit: Bool) {
        let sink = DismissSink()
        let box = StateBox(true)
        let binding = Binding(get: { box.value }, set: { box.value = $0 })

        frame(present(binding, { AnyView(Capture(sink: sink)) }))

        // Clear any exit request left by an earlier test before measuring ours.
        _ = AppState.shared.consumeShouldExit()
        let dismiss = try #require(sink.captured, "the presented content never rendered")
        dismiss()
        return (closed: !box.value, askedToExit: AppState.shared.consumeShouldExit())
    }

    @Test("a sheet's own Done button closes the sheet")
    func sheet() throws {
        let result = try dismissFromInside { isPresented, content in
            AnyView(Text(verbatim: "page").sheet(isPresented: isPresented) { content() })
        }
        #expect(result.closed, "dismiss() should close the sheet")
        #expect(!result.askedToExit, "dismiss() must NOT quit the application")
    }

    @Test("a full-screen cover dismisses itself")
    func fullScreenCover() throws {
        let result = try dismissFromInside { isPresented, content in
            AnyView(
                Text(verbatim: "page").fullScreenCover(isPresented: isPresented) { content() })
        }
        #expect(result.closed)
        #expect(!result.askedToExit)
    }

    @Test("a modal dismisses itself")
    func modal() throws {
        let result = try dismissFromInside { isPresented, content in
            AnyView(Text(verbatim: "page").modal(isPresented: isPresented) { content() })
        }
        #expect(result.closed)
        #expect(!result.askedToExit)
    }

    @Test("a popover dismisses itself")
    func popover() throws {
        let result = try dismissFromInside { isPresented, content in
            AnyView(Text(verbatim: "page").popover(isPresented: isPresented) { content() })
        }
        #expect(result.closed)
        #expect(!result.askedToExit)
    }

    /// The `item:` form funnels through the same modifier, but its binding is
    /// derived — worth pinning that clearing it is what dismissal does.
    @Test("a sheet presented by item clears the item")
    func sheetByItem() throws {
        let sink = DismissSink()
        let box = StateBox<Presented?>(Presented())
        let item = Binding(get: { box.value }, set: { box.value = $0 })

        frame(Text(verbatim: "page").sheet(item: item) { _ in Capture(sink: sink) })

        _ = AppState.shared.consumeShouldExit()
        let dismiss = try #require(sink.captured)
        dismiss()
        #expect(box.value == nil, "dismiss() should clear the item binding")
        #expect(!AppState.shared.consumeShouldExit(), "and must not quit the application")
    }

    /// `\.isPresented` is the read-only companion: the same presentations that
    /// publish a dismissal publish the flag, so a view can tell whether
    /// `dismiss()` will close something or quit.
    @Test("isPresented is true inside a presentation and false outside one")
    func isPresentedFlag() throws {
        let sink = FlagSink()
        let box = StateBox(true)
        let binding = Binding(get: { box.value }, set: { box.value = $0 })

        frame(Text(verbatim: "page").sheet(isPresented: binding) { FlagProbe(sink: sink) })
        #expect(sink.inside == true, "inside a sheet")

        frame(FlagProbe(sink: sink))
        #expect(sink.inside == false, "at the top level, nothing presented it")
    }

    private final class FlagSink: @unchecked Sendable {
        var inside: Bool?
    }

    private struct FlagProbe: View {
        @Environment(\.isPresented) private var isPresented
        let sink: FlagSink

        var body: some View {
            sink.inside = isPresented
            return Text(verbatim: "probe")
        }
    }

    /// The top-level meaning is unchanged: outside any presentation, dismissing
    /// a terminal app IS quitting it, and that is what `DismissAction()` means.
    @Test("outside a presentation, dismiss() still means quit")
    func topLevelStillExits() {
        _ = AppState.shared.consumeShouldExit()
        DismissAction()()
        #expect(AppState.shared.consumeShouldExit(), "the default action must still exit")
    }
}
