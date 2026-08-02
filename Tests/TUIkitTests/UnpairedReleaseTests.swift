//  🖥️ TUIKit — Terminal UI Kit for Swift
//  UnpairedReleaseTests.swift
//
//  A click is a press AND a release on the same control. A release whose press
//  went somewhere else — the page background, another control, a menu that has
//  since closed — is not a click on whatever the pointer happens to be over
//  when the button comes up.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("A release without its press")
struct UnpairedReleaseTests {

    private final class Counter {
        var taps = 0
    }

    /// Renders `view`, wires its regions to the dispatcher, and returns both.
    private func harness(
        _ view: some View, width: Int = 30, height: Int = 6
    ) -> (dispatcher: MouseEventDispatcher, regions: [HitTestRegion]) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)

        var context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment,
            tuiContext: tui)
        context.hasExplicitWidth = true
        context.hasExplicitHeight = true

        let buffer = renderToBuffer(view, context: context)
        let dispatcher = tui.mouseEventDispatcher
        dispatcher.setActiveSupport(.standard)
        dispatcher.setRegions(buffer.hitTestRegions)
        return (dispatcher, buffer.hitTestRegions)
    }

    /// Press on the page background, drag across, release over a button. On
    /// every platform that is a cancelled click, not that button's click.
    @Test("A release that lands on a Button it was not pressed on does nothing")
    func releaseWithoutPressDoesNotActivate() {
        let counter = Counter()
        let view = VStack(alignment: .leading) {
            Text("somewhere else")
            Button("Press me") { counter.taps += 1 }
        }
        let (dispatcher, regions) = harness(view)
        guard let button = regions.last else {
            Issue.record("expected the button's hit-test region")
            return
        }

        // The press lands on the Text — no region, nothing captures it.
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: 0, y: 0))
        // The pointer travels to the button and the finger comes up there.
        _ = dispatcher.dispatch(
            MouseEvent(
                button: .left, phase: .released, x: button.offsetX + 1, y: button.offsetY))

        #expect(counter.taps == 0, "the press was never on this button")
    }

    /// The control case, so the assertion above cannot pass by the button
    /// simply being unreachable.
    @Test("A press and release on the Button does activate it")
    func pairedPressAndReleaseActivates() {
        let counter = Counter()
        let view = VStack(alignment: .leading) {
            Text("somewhere else")
            Button("Press me") { counter.taps += 1 }
        }
        let (dispatcher, regions) = harness(view)
        guard let button = regions.last else {
            Issue.record("expected the button's hit-test region")
            return
        }

        let x = button.offsetX + 1
        let y = button.offsetY
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))

        #expect(counter.taps == 1, "an ordinary click still works")
    }

    /// Press on the button, drag off it, release elsewhere: macOS cancels the
    /// click. TUIkit deliberately does not — the press captures the gesture, so
    /// the release comes back to the button wherever the pointer ended up.
    /// Pinned here so the change above cannot quietly take it away.
    @Test("A press on the Button still activates it if the pointer drifts off")
    func pressCapturesEvenIfTheReleaseDrifts() {
        let counter = Counter()
        let view = VStack(alignment: .leading) {
            Text("somewhere else")
            Button("Press me") { counter.taps += 1 }
        }
        let (dispatcher, regions) = harness(view)
        guard let button = regions.last else {
            Issue.record("expected the button's hit-test region")
            return
        }

        _ = dispatcher.dispatch(
            MouseEvent(
                button: .left, phase: .pressed, x: button.offsetX + 1, y: button.offsetY))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: 0, y: 0))

        #expect(counter.taps == 1, "the press owns the gesture wherever it ends")
    }
}
