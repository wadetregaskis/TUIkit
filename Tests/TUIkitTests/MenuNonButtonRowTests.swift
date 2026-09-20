//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuNonButtonRowTests.swift
//
//  A pop-up menu's rows are not focus stops: each one claims an ordinal from the
//  menu's own `MenuRowSink` and publishes its action there. Whatever does not
//  make that claim still DRAWS — the column is a view, and every view in it is
//  rendered — but the highlight has no ordinal to rest on and the sliced click
//  map has no row to hit, so it lands on screen looking exactly like a control
//  and answering nothing.
//
//  These pin the claim for a `Toggle`, the one non-`Button` row TUIkit accepts.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("Menu rows that are not Buttons")
struct MenuNonButtonRowTests {

    // MARK: - Harness

    private func harness(width: Int = 40, height: Int = 24) -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        // A status bar of this frame's own: a shared one would let a parallel
        // neighbour's items be read back as this test's.
        environment.statusBar = StatusBarState()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return (
            tui,
            RenderContext(
                availableWidth: width, availableHeight: height, environment: environment,
                tuiContext: tui)
        )
    }

    /// Renders `view` through a full frame and arms the mouse dispatcher, so a
    /// following click lands on the regions this frame published.
    private func renderArmed(_ view: some View, tui: TUIContext, context: RenderContext)
        -> FrameBuffer
    {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        // Composite before arming: a presented menu's regions live inside its
        // overlay until the overlays are flattened, which is what the run loop
        // does before it hands the frame to the dispatcher.
        let composited = buffer.compositingOverlays(
            maxWidth: context.availableWidth, maxHeight: context.availableHeight,
            palette: context.environment.palette)
        tui.mouseEventDispatcher.setRegions(composited.hitTestRegions)
        context.environment.focusManager?.endRenderPass()
        tui.stateStorage.endRenderPass()
        return buffer
    }

    /// Opens `view`'s pop-up from the KEYBOARD, so it comes up with its first
    /// row already highlighted.
    private func openPopup(_ view: some View, tui: TUIContext, context: RenderContext) {
        _ = renderArmed(view, tui: tui, context: context)
        context.environment.focusManager?.noteInputSource(.keyboard)
        _ = tui.mouseEventDispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 2, y: 0))
        _ = tui.mouseEventDispatcher.dispatch(
            MouseEvent(button: .left, phase: .released, x: 2, y: 0))
        _ = renderArmed(view, tui: tui, context: context)
    }

    /// Renders `items` as an open pop-up column and hands back the controller
    /// the rows reported to — the row registry itself, rather than a picture of
    /// one.
    private func openColumn(@ViewBuilder _ items: () -> some View) -> MenuPopupController {
        let (_, context) = harness()
        let controller = MenuPopupController()
        _ = renderMenuPopup(
            VStack(alignment: .leading, spacing: 0, content: items),
            context: context, controller: controller, dismiss: {})
        return controller
    }

    // MARK: - The row registry

    @Test("A Toggle in a pop-up menu claims a row, and choosing it flips the binding")
    func togglePublishesARow() {
        var isOn = false
        let binding = Binding(get: { isOn }, set: { isOn = $0 })
        let controller = openColumn {
            Button("Rename") {}
            Toggle("Show hidden", isOn: binding)
        }

        #expect(
            controller.sink.selectableOrdinals == [0, 1],
            "the Button and the Toggle are both rows the highlight can rest on")
        controller.sink.activate(ordinal: 1)
        #expect(isOn, "choosing the Toggle's row flips its binding")
    }

    /// The same rule a `.disabled()` `Button` row follows: it takes an ordinal
    /// (so the rows below keep the numbers they drew at) and declines to be one
    /// the highlight can land on.
    @Test("A disabled Toggle takes its row and declines it")
    func disabledTogglePublishesButDeclines() {
        var isOn = false
        let binding = Binding(get: { isOn }, set: { isOn = $0 })
        let controller = openColumn {
            Toggle("Unavailable", isOn: binding).disabled()
            Button("Rename") {}
        }

        #expect(
            controller.sink.selectableOrdinals == [1],
            "only the Button; the disabled Toggle holds ordinal 0 without offering it")
        controller.sink.activate(ordinal: 0)
        #expect(!isOn, "and a request to run it anyway does nothing")
    }

    // MARK: - The whole keyboard route

    @Test("Arrow keys reach a Toggle in a pop-up menu, and Return flips it")
    func arrowsReachTheToggle() {
        let (tui, context) = harness()
        var isOn = false
        let binding = Binding(get: { isOn }, set: { isOn = $0 })
        let view = Menu("Actions") {
            Button("Rename") {}
            Toggle("Show hidden", isOn: binding)
        }

        openPopup(view, tui: tui, context: context)
        // Opened from the keyboard, so the first row is already highlighted;
        // one Down is the step onto the Toggle.
        #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .down)))
        _ = renderArmed(view, tui: tui, context: context)
        #expect(tui.keyEventDispatcher.dispatch(KeyEvent(key: .enter)))
        #expect(isOn, "Return on the highlighted Toggle row flips its binding")
    }

    /// The other half of the pop-up contract: a menu row is not a page focus
    /// stop. A `Toggle` that registered with the ring instead was a Tab stop
    /// inside a section that has grabbed the keyboard — reachable by nothing,
    /// and the one thing that section is documented never to hold.
    @Test("A Toggle row stays out of the focus ring")
    func toggleRowIsNotAFocusStop() throws {
        let (tui, context) = harness()
        let focusManager = try #require(context.environment.focusManager)
        let view = Menu("Actions") {
            Button("Rename") {}
            Toggle("Show hidden", isOn: .constant(false))
        }

        openPopup(view, tui: tui, context: context)
        #expect(
            focusManager.registeredFocusIDsInActiveSection().isEmpty,
            "the menu's section holds no focusable rows")
    }

    // MARK: - Sticky toggles

    /// `.menuActionDismissBehavior(_:)`'s reason for existing, per
    /// `Documentation/SwiftUI-compatibility.md`: "a sticky toggle and an
    /// ordinary `Done` share a menu". Until a `Toggle` could be a row at all,
    /// the sticky half of that sentence had nothing to be true of.
    @Test(
        "A chosen Toggle closes the menu, unless the menu says otherwise",
        arguments: [
            (MenuActionDismissBehavior.automatic, true), (.enabled, true), (.disabled, false),
        ])
    func dismissBehaviourGovernsTheToggleRow(
        behavior: MenuActionDismissBehavior, dismisses: Bool
    ) {
        var (_, context) = harness()
        let controller = MenuPopupController()
        var dismissed = false
        // The presenter is what puts the dismiss in the environment for the
        // rows (`presentMenuPopover`); the column below it only passes it to
        // the drop-down's own backdrop.
        context.environment.dismissMenu = DismissMenuAction(action: { dismissed = true })
        _ = renderMenuPopup(
            VStack(alignment: .leading, spacing: 0) {
                Toggle("Show hidden", isOn: .constant(false))
                    .menuActionDismissBehavior(behavior)
            },
            context: context, controller: controller, dismiss: {})
        controller.sink.activate(ordinal: 0)
        #expect(dismissed == dismisses)
    }

    // MARK: - Nothing else moved

    /// An INLINE menu's rows really are page focus stops, which is why the sink
    /// is deliberately absent there — so a `Toggle` in one stays the control it
    /// has always been, registered by its own id.
    @Test("A Toggle in an inline menu is still a page focus stop")
    func inlineMenuToggleKeepsItsFocusStop() throws {
        let (tui, context) = harness()
        let focusManager = try #require(context.environment.focusManager)
        let view = Menu("Settings") {
            Button("Rename") {}
            Toggle("Show hidden", isOn: .constant(false))
        }
        .menuStyle(.inline)

        _ = renderArmed(view, tui: tui, context: context)
        let registered = focusManager.registeredFocusIDsInActiveSection()
        #expect(
            registered.contains { $0.hasPrefix("toggle-") },
            "the toggle registers by its own id: \(registered)")
    }
}
