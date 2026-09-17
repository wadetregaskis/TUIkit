//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MouseRegionMemoTests.swift
//
//  A buffer carrying hit-test regions used to be refused by the render cache
//  outright: a region names its handler by an id, and the closure behind it is
//  registered by the render a hit skips. The registration is replayed now, at
//  the point in the walk where the control would have rendered, so the rows an
//  app is mostly made of — a `Button` with a mouse wired — can be served.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitView

/// What a row's `Button` did, kept outside the memo's key so nothing in the
/// view value changes when it runs.
private final class Tally: @unchecked Sendable {
    var clicks: [String] = []
}

/// A memoizable card holding one `Button`. Equality is by title alone — the
/// tally is the view's construction, not its content — which is what lets two
/// separately-built values compare equal and hit.
private struct ButtonCard: View, @MainActor Equatable {
    let title: String
    let tally: Tally

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

    var body: some View {
        Button(title) { tally.clicks.append(title) }
    }
}

/// Renders frames the way `RenderLoop` brackets them — every per-walk registry
/// emptied first — and publishes the frame's regions to the dispatcher as the
/// loop publishes the composited root buffer's.
@MainActor
private final class LoopHarness {
    let tui = TUIContext()
    let focusManager = FocusManager()

    /// The dispatcher's clock, advanced by hand so two clicks in a test are two
    /// clicks rather than a double click.
    private final class Clock: @unchecked Sendable {
        var now: UInt64 = 0
    }
    private let clock = Clock()

    var cache: RenderCache { tui.renderCache }
    var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }

    init() {
        let clock = self.clock
        dispatcher.nowNanos = { clock.now }
        dispatcher.setActiveSupport(.full)
    }

    /// Renders one frame and returns its buffer.
    @discardableResult
    func frame(_ view: some View) -> FrameBuffer {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        environment.installVolatileReadTracker(VolatileReadTracker())
        let context = RenderContext(
            availableWidth: 40, availableHeight: 20,
            environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        cache.beginRenderPass()
        focusManager.beginRenderPass()
        focusManager.beginSceneRender()
        dispatcher.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        cache.removeInactive()
        dispatcher.setRegions(buffer.hitTestRegions)
        return buffer
    }

    /// Presses and releases the left button at `(x, y)`, as the run loop routes
    /// the two reports a click arrives as.
    func click(x: Int, y: Int) {
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        _ = dispatcher.dispatch(MouseEvent(button: .left, phase: .released, x: x, y: y))
        clock.now &+= 1_000_000_000
    }

    /// Moves the pointer to `(x, y)`, which is what synthesises the enter and
    /// exit transitions a hover is made of.
    func move(x: Int, y: Int) {
        _ = dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: x, y: y))
    }
}

/// Where `label` is drawn, found IN the rendered lines rather than computed: a
/// test that adds up the stack's own padding is testing its copy of the
/// arithmetic.
@MainActor
private func cell(of label: String, in buffer: FrameBuffer) -> (x: Int, y: Int)? {
    for (y, line) in buffer.lines.enumerated() {
        let stripped = line.stripped
        guard let range = stripped.range(of: label) else { continue }
        return (stripped.distance(from: stripped.startIndex, to: range.lowerBound), y)
    }
    return nil
}

@MainActor
@Suite("Mouse regions through the render memo")
struct MouseRegionMemoTests {

    /// One focus stop outside the memo: it takes the focus as the first
    /// registrant of an empty section, so the memoized `Button` renders
    /// unfocused and its own focus registration is one a hit can make again.
    @MainActor
    private static func page(_ tally: Tally) -> some View {
        VStack {
            Text("ahead").focusable()
            ButtonCard(title: "press me", tally: tally).equatable()
        }
    }

    @Test("A memoized Button is stored, and a click on a served frame still activates it")
    func servedButtonStillClicks() {
        let harness = LoopHarness()
        let tally = Tally()
        harness.frame(Self.page(tally))
        #expect(!harness.cache.isEmpty, "the Button's buffer was never stored")

        // Nothing under the memo renders on this frame, so the click can only
        // reach the action if the registration was made again from the journal.
        let missesBefore = harness.cache.stats.misses
        let hitsBefore = harness.cache.stats.hits
        let served = harness.frame(Self.page(tally))
        #expect(harness.cache.stats.misses == missesBefore, "the memoized Button rendered again")
        #expect(harness.cache.stats.hits > hitsBefore, "no memo hit on the second frame")

        guard let spot = cell(of: "press me", in: served) else {
            Issue.record("the Button was not drawn: \(served.lines.map(\.stripped))")
            return
        }
        harness.click(x: spot.x, y: spot.y)
        #expect(tally.clicks == ["press me"], "the click on the served frame reached nothing")
    }

    @Test("A served frame publishes the region and the handler behind it")
    func servedRegionResolvesToItsHandler() {
        let harness = LoopHarness()
        let tally = Tally()
        let rendered = harness.frame(Self.page(tally))
        guard let first = rendered.hitTestRegions.first(where: { $0.focusID?.hasPrefix("button-") == true })
        else {
            Issue.record("the Button registered no region: \(rendered.hitTestRegions)")
            return
        }

        let served = harness.frame(Self.page(tally))
        guard let again = served.hitTestRegions.first(where: { $0.focusID == first.focusID }) else {
            Issue.record("the served frame carried no region for the Button")
            return
        }
        // The id is interned per `(identity, slot)`, so the one baked into the
        // stored buffer still names this control — and the replay is what puts
        // a closure back under it.
        #expect(again.handlerID == first.handlerID, "the served region named a different handler")
        #expect(
            harness.dispatcher.handler(for: again.handlerID) != nil,
            "the served region names a handler nothing registered")
    }

    @Test("A served frame still asks for motion reporting")
    func servedFrameKeepsAskingForMotion() {
        let harness = LoopHarness()
        let tally = Tally()
        harness.frame(Self.page(tally))
        harness.frame(Self.page(tally))
        // Asked for per frame by every control that lifts under the pointer,
        // and emptied with the rest of the dispatcher's per-walk state — so a
        // page whose only such control is memoized would stop being told where
        // the pointer is at all.
        #expect(
            harness.dispatcher.effectiveSupport(baseConfig: .disabled).motion,
            "a served frame asked for no motion reporting")
    }

    @Test("The pointer reaches a served Button, and the frame after draws it hovered")
    func hoverReachesTheServedButton() {
        let harness = LoopHarness()
        let tally = Tally()
        harness.frame(Self.page(tally))
        let served = harness.frame(Self.page(tally))
        guard let spot = cell(of: "press me", in: served) else {
            Issue.record("the Button was not drawn: \(served.lines.map(\.stripped))")
            return
        }

        // The pointer entering is delivered to the replayed handler, which
        // writes the hover box — a `@State` write, so the entry is cleared and
        // the next frame renders the row again, hovered.
        harness.move(x: spot.x, y: spot.y)
        let hovered = harness.frame(Self.page(tally))
        #expect(
            hovered.lines[spot.y] != served.lines[spot.y],
            "the pointer entered a served Button and it drew unchanged")
    }

    @Test("A ForEach row's Button is served, and a click picks the row under the pointer")
    func servedForEachRowClicksItsOwnButton() {
        let harness = LoopHarness()
        let tally = Tally()
        let titles = ["alpha", "bravo", "charlie"]
        // `ForEach` wraps each `Equatable` element's row in `_MemoizedRow`, so
        // these are memoized without anybody asking — the shape most rows in an
        // app have.
        @MainActor func page() -> some View {
            VStack {
                Text("ahead").focusable()
                ForEach(titles, id: \.self) { title in
                    ButtonCard(title: title, tally: tally)
                }
            }
        }

        harness.frame(page())
        let missesBefore = harness.cache.stats.misses
        let served = harness.frame(page())
        #expect(harness.cache.stats.misses == missesBefore, "the memoized rows rendered again")

        guard let spot = cell(of: "bravo", in: served) else {
            Issue.record("the rows were not drawn: \(served.lines.map(\.stripped))")
            return
        }
        harness.click(x: spot.x, y: spot.y)
        // The middle row, not its neighbours: each row's handler is its own,
        // under the id its own region carries.
        #expect(tally.clicks == ["bravo"], "the click landed on \(tally.clicks)")
    }
}
