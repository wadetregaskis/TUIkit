//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HelpTooltipTests.swift
//
//  `help(_:)` publishes a tooltip candidate; it does not draw one. These pin
//  which candidate wins, when the hover delay lets it through, and that the
//  keyboard reveal is a toggle over the FOCUSED view rather than over whatever
//  the pointer last touched.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("help(_:) and tooltip candidates")
struct HelpTooltipTests {

    private static let second: Int64 = 1_000_000_000

    /// A context wired the way a live frame is: a focus manager, a mouse
    /// dispatcher (hover needs one) and a tooltip state.
    private func harness(
        visibility: TooltipVisibility = .automatic, delay: Double = 0.6, now: Int64 = 0
    ) -> (context: RenderContext, tooltips: TooltipState, focus: FocusManager,
        dispatcher: MouseEventDispatcher)
    {
        let tui = TUIContext()
        let focus = FocusManager()
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tui)
        env.focusManager = focus
        env.tooltipVisibility = visibility
        env.tooltipDelay = delay
        env.frameNowNanos = now
        // Motion reporting is unioned in by `AppRunner` each frame from the
        // modifier's `requestFeature(.motion)`; with no run loop here the
        // dispatcher would refuse every `.moved` event, so grant it directly.
        tui.mouseEventDispatcher.setActiveSupport(.full)
        return (
            RenderContext(
                availableWidth: 40, availableHeight: 10, environment: env, tuiContext: tui),
            tui.tooltipState, focus, tui.mouseEventDispatcher
        )
    }

    /// Drives one frame of a view and returns the hit regions it produced, so a
    /// test can synthesise the hover the dispatcher would have delivered.
    private func frame<V: View>(
        _ view: V, _ h: (context: RenderContext, tooltips: TooltipState,
            focus: FocusManager, dispatcher: MouseEventDispatcher)
    ) -> FrameBuffer {
        h.focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: h.context)
        h.focus.endRenderPass()
        h.dispatcher.setRegions(buffer.hitTestRegions)
        return buffer
    }

    // MARK: - The focus half

    /// The natural spelling puts `.help` OUTSIDE the control, so the modifier
    /// cannot read `\.isFocused` — that is published inside the control's own
    /// render. It writes `\.helpText` down instead and the focused control claims
    /// it from `FocusRegistration.register`.
    @Test("A focused control claims the help text written outside it")
    func focusedControlClaimsHelp() {
        let h = harness()
        let view = Button("Rebuild") {}.help("Rebuild the index")
        _ = frame(view, h)
        #expect(
            h.tooltips.focused?.text == "Rebuild the index",
            "the focused button claimed it, got \(String(describing: h.tooltips.focused?.text))")
    }

    /// …and an unfocused one does not, so the candidate always belongs to exactly
    /// one control.
    @Test("An unfocused control publishes no focus candidate")
    func unfocusedControlPublishesNothing() {
        let h = harness()
        let view = VStack {
            Button("First") {}
            Button("Second") {}.help("the second one")
        }
        _ = frame(view, h)
        // The first button takes the focus by default, so the second's help is
        // not the candidate.
        #expect(h.tooltips.focused == nil, "nothing focused carries help")
    }

    /// A hidden subtree publishes nothing at all — checked on the FOCUS half as
    /// well as the hover half, because the two are gated in different files and
    /// only one of them is obvious.
    @Test("tooltips(.hidden) publishes no candidate")
    func hiddenPublishesNothing() {
        let h = harness(visibility: .hidden)
        let view = Button("Rebuild") {}.help("Rebuild the index")
        _ = frame(view, h)
        #expect(h.tooltips.focused == nil, "focus half is gated")
        // The hover half is gated in a different file, and the Button registers a
        // region of its own for clicks — so the check is that hovering publishes
        // nothing, not that the buffer carries no regions at all.
        _ = h.dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 2, y: 0))
        #expect(h.tooltips.hovered == nil, "hover half is gated too")
    }

    // MARK: - The keyboard reveal

    /// Publishing is not showing. A focus candidate needs the help key.
    @Test("A focus candidate is not shown until the keyboard asks")
    func focusCandidateNeedsTheKey() {
        let h = harness()
        _ = frame(Button("Rebuild") {}.help("Rebuild the index"), h)
        #expect(
            h.tooltips.resolved(nowNanos: 0, delaySeconds: 0.6) == nil,
            "focus alone shows nothing")

        #expect(h.tooltips.toggleKeyboardReveal(focusID: h.focus.currentFocusedID))
        #expect(
            h.tooltips.resolved(nowNanos: 0, delaySeconds: 0.6)?.text == "Rebuild the index",
            "the key revealed it")
        #expect(h.tooltips.resolved(nowNanos: 0, delaySeconds: 0.6)?.source == .focus)

        // …and it is a toggle.
        #expect(h.tooltips.toggleKeyboardReveal(focusID: h.focus.currentFocusedID))
        #expect(h.tooltips.resolved(nowNanos: 0, delaySeconds: 0.6) == nil, "toggled off")
    }

    /// Nothing to reveal must report `false`, so the caller lets the key fall
    /// through rather than swallowing it. A key that silently does nothing is the
    /// failure this whole feature is most likely to ship.
    @Test("The help key declines when the focused view has no help")
    func revealDeclinesWithNoHelp() {
        let h = harness()
        _ = frame(Button("Rebuild") {}, h)
        #expect(
            h.tooltips.toggleKeyboardReveal(focusID: h.focus.currentFocusedID) == false,
            "nothing to reveal")
    }

    /// The reveal belongs to the view it was granted for, so moving the focus
    /// drops it rather than carrying the tooltip along.
    @Test("Moving the focus drops a reveal")
    func revealDoesNotFollowFocus() {
        let h = harness()
        _ = frame(Button("Rebuild") {}.help("Rebuild the index"), h)
        #expect(h.tooltips.toggleKeyboardReveal(focusID: h.focus.currentFocusedID))
        #expect(h.tooltips.keyboardRevealed)

        h.tooltips.syncReveal(focusID: "somewhere-else")
        #expect(!h.tooltips.keyboardRevealed, "the reveal did not travel")
    }

    // MARK: - The hover half, and its delay

    @Test("A hover tooltip waits for the delay, then shows")
    func hoverWaitsForTheDelay() {
        let h = harness()
        let buffer = frame(Text("Coverage").help("Lines executed at least once"), h)
        #expect(!buffer.hitTestRegions.isEmpty, "help(_:) gave the Text a hit region")

        _ = h.dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 2, y: 0))
        #expect(h.tooltips.hovered?.text == "Lines executed at least once", "the pointer is on it")

        let since = h.tooltips.hovered!.sinceNanos
        #expect(
            h.tooltips.resolved(nowNanos: since, delaySeconds: 0.6) == nil,
            "not yet — the pointer has not rested")
        #expect(
            h.tooltips.resolved(
                nowNanos: since + Int64(0.6 * Double(Self.second)), delaySeconds: 0.6)?.source
                == .hover,
            "…and now it has")
    }

    /// Hover beats focus: the pointer is a deliberate act aimed at one thing.
    @Test("Hover wins over a revealed focus candidate")
    func hoverBeatsFocus() {
        let h = harness(delay: 0)
        let view = VStack {
            Button("Rebuild") {}.help("Rebuild the index")
            Text("Coverage").help("Lines executed at least once")
        }
        let buffer = frame(view, h)
        #expect(h.tooltips.toggleKeyboardReveal(focusID: h.focus.currentFocusedID))
        #expect(h.tooltips.resolved(nowNanos: 0, delaySeconds: 0)?.source == .focus)

        // Hover the Text on the second row.
        let region = buffer.hitTestRegions.first { $0.offsetY == 1 }
        #expect(region != nil, "the Text's region: \(buffer.hitTestRegions)")
        _ = h.dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 1, y: 1))
        let shown = h.tooltips.resolved(nowNanos: Self.second, delaySeconds: 0)
        #expect(shown?.source == .hover, "the pointer wins, got \(String(describing: shown))")
        #expect(shown?.text == "Lines executed at least once")
    }

    /// Re-entering the same view must not restart the delay — the dispatcher
    /// synthesises `.entered` on every boundary crossing, and a region
    /// re-registered at a new id this frame is still the same view.
    @Test("Re-entering the same view does not restart the delay")
    func reentryKeepsTheDeadline() {
        // Driven through the state directly: the rule under test is this type's
        // idempotence on re-entry, and the synthetic `.entered` that reaches it
        // is already covered above.
        let h = harness()
        h.tooltips.hovering("Lines executed at least once", handlerID: nil, nowNanos: 7)
        h.tooltips.hovering(
            "Lines executed at least once", handlerID: nil, nowNanos: 7 + Self.second)
        #expect(h.tooltips.hovered?.sinceNanos == 7, "the clock did not restart")

        // …but a DIFFERENT view under the pointer does restart it.
        h.tooltips.hovering("Something else", handlerID: nil, nowNanos: 7 + Self.second)
        #expect(h.tooltips.hovered?.sinceNanos == 7 + Self.second, "a new view, a new deadline")
    }
}
