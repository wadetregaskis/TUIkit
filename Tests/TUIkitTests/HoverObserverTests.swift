//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HoverObserverTests.swift
//
//  `.onHover` and `help(_:)` watch the pointer without taking the hover from
//  the controls they wrap.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

/// A hover OBSERVER — `.onHover`, `help(_:)` — hears the pointer enter and
/// leave without taking the hover from the controls it wraps.
///
/// Both append a full-size region after their content's, which makes them the
/// innermost match on every cell, and hover resolves one region per point. As
/// ordinary regions they took every `.entered` / `.exited` the wrapped control
/// needed for its own hover face: `Button("Save") {}.onHover { … }` never lit
/// up. `OnHoverClickThroughTests` builds exactly that tree, but asserts only
/// the click and throws the hover away.
///
/// The oracle is the SAME tree without the observer, driven along the same
/// pointer path: an observer draws nothing, so every frame must match, and any
/// difference is a hover it took.
@MainActor
@Suite("Hover observers leave the control its hover")
struct HoverObserverTests {

    /// One live frame's services, all from ONE `TUIContext` — the render cache
    /// included. A control's hover is state it keeps between frames, and
    /// `makeRenderContext`'s isolated cache is documented to diverge from
    /// state-driven invalidation.
    private struct Harness {
        let context: RenderContext
        let dispatcher: MouseEventDispatcher
        let tooltips: TooltipState
    }

    /// Well clear of every control in a 40×10 frame.
    private let away = (x: 39, y: 9)

    private func harness() -> Harness {
        let tui = TUIContext()
        let focus = FocusManager()
        // Park the focus, so no control under test draws a focus face where
        // this is looking for a hover face.
        focus.register(FocusSentinel())
        var env = EnvironmentValues()
        env.applyRuntimeServices(from: tui)
        env.focusManager = focus
        // No run loop unions in the modifiers' `.motion` request; without it
        // the dispatcher refuses every `.moved`.
        tui.mouseEventDispatcher.setActiveSupport(.full)
        return Harness(
            context: RenderContext(
                availableWidth: 40, availableHeight: 10, environment: env, tuiContext: tui),
            dispatcher: tui.mouseEventDispatcher,
            tooltips: tui.tooltipState)
    }

    /// Draws `view` as the live loop does — a fresh handler table, the render,
    /// its regions — then moves the pointer to each point in turn and draws the
    /// frame that answers the move. Every frame, the resting one first.
    private func frames(
        of view: some View, pointer path: [(x: Int, y: Int)], in h: Harness
    ) -> [[String]] {
        func frame() -> [String] {
            h.dispatcher.beginRenderPass()
            let buffer = renderToBuffer(view, context: h.context)
            h.dispatcher.setRegions(buffer.hitTestRegions)
            return buffer.lines
        }
        var drawn = [frame()]
        for point in path {
            _ = h.dispatcher.dispatch(
                MouseEvent(button: .none, phase: .moved, x: point.x, y: point.y))
            drawn.append(frame())
        }
        return drawn
    }

    /// A cell inside each hit region of `view`, top row first. Taken from the
    /// bare tree, which lays out exactly as the observed one.
    private func controlCells(of view: some View) -> [(x: Int, y: Int)] {
        let h = harness()
        h.dispatcher.beginRenderPass()
        return renderToBuffer(view, context: h.context).hitTestRegions
            .sorted { ($0.offsetY, $0.offsetX) < ($1.offsetY, $1.offsetX) }
            .map { (x: $0.offsetX + 1, y: $0.offsetY) }
    }

    @Test("A Button under .onHover still lights under the pointer")
    func onHoverKeepsTheButtonsHover() {
        var log: [Bool] = []
        let bare = Button("Save") {}
        let observed = Button("Save") {}.onHover { log.append($0) }
        guard let cell = controlCells(of: bare).first else {
            Issue.record("the Button drew no hit region")
            return
        }
        let path = [cell, away]
        let (expected, got) = withColorDepth(.truecolor) {
            (frames(of: bare, pointer: path, in: harness()),
                frames(of: observed, pointer: path, in: harness()))
        }
        #expect(expected[1] != expected[0], "precondition: a bare Button lights under the pointer")
        #expect(got[1] == expected[1], "the .onHover wrapper took the Button's hover: \(got[1])")
        #expect(got[2] == expected[2], "leaving must put the Button back: \(got[2])")
        #expect(log == [true, false], "the observer itself still hears enter, then exit: \(log)")
    }

    /// Forwarding the transitions down to the content is not enough, and this
    /// is why: the pointer moving from one control to its neighbour never
    /// leaves the wrapper's region.
    @Test("Moving between two controls inside one .onHover moves the hover with the pointer")
    func hoverMovesBetweenObservedControls() {
        var log: [Bool] = []
        let bare = VStack(alignment: .leading, spacing: 1) {
            Button("Alpha") {}
            Button("Beta") {}
        }
        let observed = bare.onHover { log.append($0) }
        let cells = controlCells(of: bare)
        guard let alpha = cells.first, let beta = cells.last, alpha.y != beta.y else {
            Issue.record("expected the two buttons on two rows: \(cells)")
            return
        }
        let path = [alpha, beta, away]
        let (expected, got) = withColorDepth(.truecolor) {
            (frames(of: bare, pointer: path, in: harness()),
                frames(of: observed, pointer: path, in: harness()))
        }
        #expect(expected[1] != expected[0], "precondition: Alpha lights under the pointer")
        #expect(expected[2] != expected[1], "precondition: the hover moves on to Beta")
        for index in expected.indices {
            #expect(
                got[index] == expected[index],
                "frame \(index): the observer changed what the controls drew: \(got[index])")
        }
        #expect(log == [true, false], "one enter for the column and one exit, not one per control: \(log)")
    }

    @Test("help(_:) leaves the control it explains its hover")
    func helpKeepsTheButtonsHover() {
        let bare = Button("Save") {}
        let observed = Button("Save") {}.help("Saves your work")
        guard let cell = controlCells(of: bare).first else {
            Issue.record("the Button drew no hit region")
            return
        }
        let observedHarness = harness()
        let (expected, got) = withColorDepth(.truecolor) {
            (frames(of: bare, pointer: [cell], in: harness()),
                frames(of: observed, pointer: [cell], in: observedHarness))
        }
        #expect(expected[1] != expected[0], "precondition: a bare Button lights under the pointer")
        #expect(got[1] == expected[1], "help(_:) took the Button's hover: \(got[1])")
        #expect(
            observedHarness.tooltips.hovered?.text == "Saves your work",
            "…while still publishing its own hover candidate")
    }

    /// The guard on the other side, and not the red: an observer BEHIND a
    /// region that is not one — a page's `.onHover` under a modal's consuming
    /// backdrop — must stay as silent as it always was. Only the control behind
    /// an observer gains a hover.
    @Test("An observer behind a consuming region still hears nothing")
    func observerBehindABackdropIsOccluded() {
        var log: [Bool] = []
        var backdropHeard: [MousePhase] = []
        let h = harness()
        h.dispatcher.beginRenderPass()
        let buffer = renderToBuffer(
            Text("under the backdrop").onHover { log.append($0) }, context: h.context)
        let backdrop = h.dispatcher.register { event in
            backdropHeard.append(event.phase)
            return true
        }
        h.dispatcher.setRegions(
            buffer.hitTestRegions
                + [HitTestRegion(offsetX: 0, offsetY: 0, width: 40, height: 10, handlerID: backdrop)])
        _ = h.dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 2, y: 0))
        let heard = backdropHeard
        #expect(heard == [MousePhase.entered], "the backdrop in front takes the hover: \(heard)")
        #expect(log.isEmpty, "an observer behind a consuming region must stay silent: \(log)")
    }
}
