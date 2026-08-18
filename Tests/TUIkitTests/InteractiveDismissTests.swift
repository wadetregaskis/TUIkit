//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InteractiveDismissTests.swift
//
//  `interactiveDismissDisabled(_:)` — a sheet that insists on an answer.
//
//  The two halves that matter are opposite in sign, so both are pinned: the
//  reader's own routes out (Escape, a click outside) STOP working, and every
//  programmatic one — a Done button, `@Environment(\.dismiss)` — keeps
//  working. A modifier that took both away would just be a stuck dialog.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit
@testable import TUIkitView

@MainActor
@Suite("Interactive dismissal can be disabled")
struct InteractiveDismissTests {

    /// A frame rendered the way the run loop does, reporting what the
    /// presentation left behind: the status bar's Escape offer, and the modal's
    /// own rendered height.
    private func present(
        _ view: some View, width: Int = 60, height: Int = 20
    ) -> (escapeLabels: [String], overlayHeight: Int, context: TUIContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        // A status bar of this frame's own. `StatusBarKey`'s default value is a
        // SHARED instance, so without this every test in the suite registers
        // into the same object and a parallel neighbour's "dismiss" is read as
        // this one's. And `RenderLoop` wires the focus manager at the start of
        // every pass: without it the bar cannot resolve which section's items
        // are showing, and every assertion below reads an empty list and passes
        // for the wrong reason.
        let statusBar = StatusBarState()
        statusBar.focusManager = environment.focusManager
        environment.statusBar = statusBar
        let context = RenderContext(
            availableWidth: width, availableHeight: height,
            environment: environment, tuiContext: tui)
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.stateStorage.endRenderPass()
        environment.focusManager?.endRenderPass()

        let escapes = statusBar.currentUserItems
            .filter { $0.shortcut == Shortcut.escape }
            .map { $0.label }
        let tallest = buffer.overlays.map { $0.content.height }.max() ?? 0
        return (escapes, tallest, tui)
    }

    private func sheet(
        _ disabled: Bool?, isPresented: Binding<Bool> = .constant(true)
    ) -> some View {
        Text(verbatim: "page").sheet(isPresented: isPresented) {
            if let disabled {
                Text(verbatim: "body").interactiveDismissDisabled(disabled)
            } else {
                Text(verbatim: "body")
            }
        }
    }

    // MARK: - The status bar's offer

    /// The fixture first: an ordinary sheet really does offer Escape, so the
    /// tests below are measuring its removal rather than its absence.
    @Test("an ordinary sheet offers ESC = dismiss")
    func baselineOffersEscape() {
        #expect(present(sheet(nil)).escapeLabels.contains("dismiss"))
    }

    /// Removing the binding without removing the offer would be worse than
    /// leaving both: the status bar would advertise a way out that does nothing.
    @Test("a dismissal-disabled sheet offers no ESC at all")
    func disabledRemovesEscape() {
        #expect(!present(sheet(true)).escapeLabels.contains("dismiss"))
    }

    @Test("passing false changes nothing")
    func falseIsANoOp() {
        #expect(present(sheet(false)).escapeLabels.contains("dismiss"))
    }

    // MARK: - What still works

    /// The whole point of the modifier rather than a stuck dialog: the app can
    /// still close it, once whatever it was insisting on is done.
    @Test("dismiss() still closes a dismissal-disabled sheet")
    func programmaticStillWorks() {
        let box = StateBox(true)
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        _ = present(sheet(true, isPresented: binding))
        #expect(box.value, "the fixture is presented")
        binding.wrappedValue = false
        #expect(!box.value, "the binding is still the way out")
    }

    // MARK: - Composition with the other presentation trait

    /// Both traits travel as wrapper views the presenter looks for. Applied
    /// together one is necessarily inside the other, so it has to be found
    /// through the outer one — and it has to work identically either way round,
    /// which is exactly the kind of asymmetry nobody would think to check.
    ///
    /// The detent's height is observed through a `Panel`, because that is where
    /// a detent lands: on the sheet's own box. Boxless content has nothing to
    /// stretch and keeps its size, so a bare `Text` would prove nothing here.
    @Test("it composes with presentationDetents in both orders", arguments: [true, false])
    func composesWithDetents(dismissOutermost: Bool) {
        let outcome = present(
            Text(verbatim: "page").sheet(isPresented: .constant(true)) {
                if dismissOutermost {
                    Panel("box") { Text(verbatim: "body") }
                        .presentationDetents([.height(7)])
                        .interactiveDismissDisabled()
                } else {
                    Panel("box") { Text(verbatim: "body") }
                        .interactiveDismissDisabled()
                        .presentationDetents([.height(7)])
                }
            })
        #expect(
            !outcome.escapeLabels.contains("dismiss"),
            "the dismissal trait was found (outermost: \(dismissOutermost))")
        #expect(
            outcome.overlayHeight == 7,
            "…and so was the detent (outermost: \(dismissOutermost))")
    }

    // MARK: - Popover

    /// A popover's Escape is a key handler rather than a status-bar action, so
    /// it is dispatched for real: registering nothing and registering something
    /// inert are indistinguishable from the outside, and only one of them is
    /// what was asked for.
    @Test("Escape does not close a dismissal-disabled popover", arguments: [true, false])
    func popoverEscape(disabled: Bool) {
        let box = StateBox(true)
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        let outcome = present(
            Text(verbatim: "anchor").popover(isPresented: binding) {
                Text(verbatim: "inside").interactiveDismissDisabled(disabled)
            })
        _ = outcome.context.keyEventDispatcher.dispatch(KeyEvent(key: .escape))
        #expect(box.value == disabled, "Escape closes it only when allowed to")
    }
}
