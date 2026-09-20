//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RefreshableTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// `.refreshable` — SwiftUI's pull-to-refresh, minus the pull.
///
/// The gesture is the part a terminal cannot have, so the key binding IS the
/// feature and is pinned here: Ctrl-R runs it, a bare `r` must not (that would
/// eat an ordinary keystroke), and a second one mid-flight must not stack a
/// refresh on a refresh.
@MainActor
@Suite("Refreshable")
struct RefreshableTests {

    /// One frame of a real render pass, so handler registration and `@State`
    /// pruning behave as they do in the app rather than in a bare buffer call.
    @MainActor
    private final class Harness {
        let tuiContext = TUIContext()

        func frame<V: View>(_ view: V, width: Int = 30, height: Int = 6) -> FrameBuffer {
            var environment = EnvironmentValues()
            environment.focusManager = FocusManager()
            environment.applyRuntimeServices(from: tuiContext)
            let context = RenderContext(
                availableWidth: width, availableHeight: height,
                environment: environment, tuiContext: tuiContext)
            tuiContext.keyEventDispatcher.clearHandlers()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            defer {
                tuiContext.stateStorage.endRenderPass()
                tuiContext.renderCache.removeInactive()
            }
            return renderToBuffer(view, context: context)
        }

        func press(_ key: Key, ctrl: Bool = false) {
            _ = tuiContext.keyEventDispatcher.dispatch(
                KeyEvent(key: key, ctrl: ctrl, alt: false, shift: false))
        }
    }

    /// The gate a refresh body waits at is `RefreshGate` in `TestHelpers`,
    /// shared with `RefreshableMemoTests` and `TerminalFocusPhaseTests`, which
    /// each had a copy of it. What a test waits ON is an edge that gate records
    /// — not a count of yields; see `AsyncSettling.swift`.

    @Test("Ctrl-R runs the action")
    func controlRRefreshes() async {
        let harness = Harness()
        nonisolated(unsafe) var refreshes = 0
        let view = Text("content").refreshable { refreshes += 1 }

        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle(until: { refreshes == 1 })
        #expect(refreshes == 1)
    }

    @Test("A bare r is left alone")
    func bareRIsNotARefresh() async {
        // Refreshable content is usually a list, and a list's rows are
        // reachable by typing. Claiming an unmodified letter would swallow it.
        let harness = Harness()
        nonisolated(unsafe) var refreshes = 0
        _ = harness.frame(Text("content").refreshable { refreshes += 1 })

        harness.press(.character("r"))
        harness.press(.character("x"), ctrl: true)
        harness.press(.enter)
        // A budget, deliberately: the claim is that nothing ran, so waiting too
        // little can only weaken it — never make it fail.
        await yieldToSpawnedWork()
        #expect(refreshes == 0)
    }

    @Test("A second Ctrl-R during a refresh does not start another")
    func noOverlappingRefreshes() async {
        // SwiftUI will not run a second refresh over a running one either, and
        // an app's reload is rarely re-entrant.
        let harness = Harness()
        nonisolated(unsafe) var started = 0
        let gate = RefreshGate()
        let view = Text("content").refreshable {
            started += 1
            await gate.hold()
        }

        let idle = harness.frame(view).lines
        harness.press(.character("r"), ctrl: true)
        await settle(until: { started == 1 })
        #expect(started == 1)

        // Still in flight: the handler must consume the key, not queue work.
        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await yieldToSpawnedWork()
        #expect(started == 1)

        // The run has to have ENDED before the next request, and the body
        // returning is not that edge — `RefreshAction` clears the run state
        // after it. The frame losing its indicator is.
        gate.release()
        await settle(until: { harness.frame(view).lines == idle })

        // Finished: the next one is allowed again.
        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle(until: { started == 2 })
        #expect(started == 2)
    }

    /// Coalescing must not depend on HOW the refresh was asked for. The
    /// in-flight guard used to live in the Ctrl-R handler, so a "Reload" button
    /// reaching the same action through `\.refresh` stacked a second run on the
    /// first — same refresh, different answer depending on the route.
    @Test("The environment action coalesces exactly as Ctrl-R does")
    func environmentRouteCoalesces() async {
        let harness = Harness()
        nonisolated(unsafe) var runs = 0
        let gate = RefreshGate()
        let action = RefreshAction(
            {
                runs += 1
                await gate.hold()
            }, state: RefreshAction.RunState())

        // Two calls through the environment, the second while the first is in
        // flight — the shape a second click on "Refresh Now" makes.
        let first = Task { @MainActor in await action() }
        await settle(until: { runs == 1 })
        #expect(runs == 1)
        // Spawned rather than awaited: if coalescing breaks, this call runs the
        // action body and blocks on the gate, so awaiting it here would HANG a
        // regression instead of failing it.
        let second = Task { @MainActor in await action() }
        await yieldToSpawnedWork()
        #expect(runs == 1, "a second request while running started another")
        #expect(action.isRunning)

        gate.release()
        await first.value
        await second.value
        // Both calls have returned, so the run state is settled by construction
        // — there is nothing left to wait for.
        #expect(!action.isRunning)

        // …and once it has finished, it can run again.
        gate.reset()
        let third = Task { @MainActor in await action() }
        await settle(until: { runs == 2 })
        #expect(runs == 2)
        gate.release()
        await third.value
        _ = harness
    }

    /// Both routes share one flag, so MIXING them coalesces too — which is the
    /// case the Example hits: Ctrl-R, then a click on "Refresh Now".
    @Test("The environment route does not stack onto a Ctrl-R refresh")
    func mixedRoutesCoalesce() async {
        struct Reader: View {
            @Environment(\.refresh) private var refresh
            let report: (RefreshAction?) -> Void
            var body: some View {
                report(refresh)
                return Text("inner")
            }
        }

        let harness = Harness()
        nonisolated(unsafe) var runs = 0
        let gate = RefreshGate()
        nonisolated(unsafe) var seen: RefreshAction?
        let view = Reader(report: { seen = $0 }).refreshable {
            runs += 1
            await gate.hold()
        }

        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle(until: { runs == 1 })
        #expect(runs == 1)

        guard let action = seen else {
            Issue.record("the subtree saw no refresh action")
            return
        }
        // Spawned, not awaited: a broken guard would block here forever, and a
        // hang is a much worse regression signal than a failed expectation.
        let viaEnvironment = Task { @MainActor in await action() }
        await yieldToSpawnedWork()
        #expect(runs == 1, "the environment route stacked onto a running refresh")

        gate.release()
        await viaEnvironment.value
    }

    @Test("The action reaches the subtree through the environment")
    func publishedToDescendants() async {
        // The point of `\.refresh`: a Reload button nested anywhere inside can
        // run the same refresh the key does.
        let harness = Harness()
        nonisolated(unsafe) var refreshes = 0
        nonisolated(unsafe) var seen: RefreshAction?

        struct Reader: View {
            @Environment(\.refresh) private var refresh
            let report: (RefreshAction?) -> Void
            var body: some View {
                report(refresh)
                return Text("inner")
            }
        }

        _ = harness.frame(
            Reader(report: { seen = $0 }).refreshable { refreshes += 1 })
        guard let action = seen else {
            Issue.record("the subtree saw no refresh action")
            return
        }
        await action()
        #expect(refreshes == 1)
    }

    @Test("Outside a refreshable there is nothing to refresh")
    func absentByDefault() {
        // `nil` is load-bearing: it is how a view disables its own Reload
        // button when it isn't inside anything refreshable.
        let harness = Harness()
        nonisolated(unsafe) var seen: RefreshAction??

        struct Reader: View {
            @Environment(\.refresh) private var refresh
            let report: (RefreshAction?) -> Void
            var body: some View {
                report(refresh)
                return Text("inner")
            }
        }

        _ = harness.frame(Reader(report: { seen = .some($0) }))
        #expect(seen == .some(nil))
    }

    @Test("Two handles to the same refreshable are equal, two refreshables are not")
    func identityEquality() {
        // Closures cannot be compared; identity can, and identity is what
        // SwiftUI's Equatable conformance means — it lets `onChange(of:)` see
        // a genuinely different refreshable rather than firing every frame.
        //
        // The identity is the RUN STATE, not the closure: the closure is
        // rebuilt with the view every frame, and two frames of the same
        // `.refreshable` have to compare equal.
        let state = RefreshAction.RunState()
        let handle = RefreshAction({}, state: state)
        let nextFrame = RefreshAction({}, state: state)
        let other = RefreshAction({}, state: RefreshAction.RunState())
        #expect(handle == nextFrame)
        #expect(handle != other)
    }

    @Test("The in-flight state survives the view being rebuilt each frame")
    func inFlightSurvivesRebuild() async {
        // Every other test here renders ONE stored view value twice, which is
        // the single shape in which a flag stored beside the closure appears to
        // work. An app rebuilds `body` every frame, so the modifier — and the
        // flag with it — was a new value each time: the run set the flag on the
        // frame that started it, and every frame after asked a freshly-zeroed
        // one. The indicator never drew.
        let harness = Harness()
        let gate = RefreshGate()
        func rebuilt() -> some View {
            VStack {
                Text("one")
                Text("two")
            }
            .refreshable { await gate.hold() }
        }

        let idle = harness.frame(rebuilt())
        harness.press(.character("r"), ctrl: true)
        await settle(until: { gate.entered == 1 })
        let busy = harness.frame(rebuilt())

        #expect(
            busy.lines != idle.lines,
            "a rebuilt frame still has to know a refresh is running: \(busy.lines)")

        gate.release()
        await yieldToSpawnedWork()
    }

    @Test("The size does not change while a refresh runs")
    func layoutIsStable() async {
        // The spinner overlays the content. If it insetted instead, starting a
        // refresh would reflow everything below it.
        let harness = Harness()
        let gate = RefreshGate()
        let view = VStack {
            Text("one")
            Text("two")
        }
        .refreshable { await gate.hold() }

        let idle = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle(until: { gate.entered == 1 })
        let busy = harness.frame(view)

        #expect(busy.lines.count == idle.lines.count)
        #expect(busy.width == idle.width)
        // …and it IS showing something, or "stable" would be trivially true.
        #expect(busy.lines != idle.lines)

        gate.release()
        await yieldToSpawnedWork()
    }

    // MARK: - The indicator

    /// Renders a refreshable mid-flight and returns its top row, stripped.
    private func busyTopRow<V: View>(
        _ view: V, harness: Harness, gate: RefreshGate
    ) async -> String {
        let entered = gate.entered
        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle(until: { gate.entered > entered })
        let busy = harness.frame(view)
        gate.release()
        await yieldToSpawnedWork()
        return busy.lines.first?.stripped ?? ""
    }

    @Test("The indicator has a blank cell on each side")
    func indicatorIsPadded() async {
        let harness = Harness()
        let gate = RefreshGate()
        let view = Text("abcdefghij").refreshable { await gate.hold() }

        let row = await busyTopRow(view, harness: harness, gate: gate)
        // "abcdefghij" with a three-cell badge over its middle (`.top` centres
        // horizontally): blank, glyph, blank. Without the padding the glyph
        // replaces one letter and reads as part of the word.
        let cells = Array(row)
        let at = cells.firstIndex { SpinnerStyle.dots.frames.contains(String($0)) }
        #expect(at != nil, "no spinner glyph in \(row.debugDescription)")
        guard let at else { return }
        #expect(at > 0 && cells[at - 1] == " ", "row: \(row.debugDescription)")
        #expect(at + 1 < cells.count && cells[at + 1] == " ", "row: \(row.debugDescription)")
        // …and it is an OVERLAY: the content it does not cover is still there,
        // and the row did not get wider.
        #expect(cells.count == 10, "row: \(row.debugDescription)")
        #expect(row.hasPrefix("abc"), "row: \(row.debugDescription)")
        #expect(row.hasSuffix("ghij"), "row: \(row.debugDescription)")
    }

    /// Content 1 or 2 cells wide has no room to spare for the badge — one
    /// blank either side of the glyph needs three — so `renderToBuffer`'s
    /// guard withholds it entirely rather than drawing a blank cell where the
    /// indicator should be. Three cells is the boundary where it first fits.
    /// Pins both sides: `indicatorAppearsAtThreeCellsMinimum` below is what
    /// establishes that 3, rather than the boundary, is the right number.
    @Test("The indicator is withheld below three cells, shown at three")
    func indicatorBoundaryAtThreeCells() async {
        for width in 1...2 {
            let harness = Harness()
            let gate = RefreshGate()
            let content = String(repeating: "x", count: width)
            let view = Text(content).refreshable { await gate.hold() }

            let row = await busyTopRow(view, harness: harness, gate: gate)
            #expect(
                row == content,
                "\(width)-cell content must draw no indicator at all: \(row.debugDescription)")
        }

        let harness = Harness()
        let gate = RefreshGate()
        let view = Text("xyz").refreshable { await gate.hold() }

        let row = await busyTopRow(view, harness: harness, gate: gate)
        let cells = Array(row)
        #expect(cells.count == 3, "row: \(row.debugDescription)")
        let at = cells.firstIndex { SpinnerStyle.dots.frames.contains(String($0)) }
        #expect(at != nil, "a 3-cell-wide refreshable must draw the indicator: \(row.debugDescription)")
    }

    /// `RefreshableModifier`'s guard hard-codes `buffer.width >= 3`. That 3 is
    /// not asserted here — it is DERIVED: the padded badge
    /// (`Spinner(style:).padding(.horizontal, 1)`, exactly what the modifier
    /// composites) is rendered for every named `SpinnerStyle` case, and the
    /// narrowest of them must be 3 cells — one blank, one glyph, one blank.
    /// If a style's glyph ever grew past one cell by mistake, or the padding
    /// changed, this fails instead of a stale comment saying otherwise.
    @Test("Three cells is the narrowest padded indicator across every named style")
    func indicatorAppearsAtThreeCellsMinimum() {
        let namedStyles: [SpinnerStyle] = [
            .dots, .line, .dancingLine, .bouncing, .pie, .beachball, .box, .curve,
            .column, .bar, .shade, .blockWedge, .spinningTriangle, .moon, .earth, .clock,
        ]
        let widths = namedStyles.map { style in
            (style, renderToBuffer(Spinner(style: style).padding(.horizontal, 1), context: makeBareRenderContext()).width)
        }
        #expect(
            widths.map(\.1).min() == 3,
            "narrowest padded indicator across styles: \(widths.map { "\($0.0): \($0.1)" })")
    }

    @Test("refreshIndicator chooses the spinner")
    func indicatorIsCustomisable() async {
        let harness = Harness()
        let gate = RefreshGate()
        let view = Text("abcdefghij")
            .refreshable { await gate.hold() }
            .refreshIndicator(style: .line)

        let row = await busyTopRow(view, harness: harness, gate: gate)
        let cells = Array(row).map(String.init)
        #expect(
            cells.contains { SpinnerStyle.line.frames.contains($0) },
            "row: \(row.debugDescription)")
        // The default's glyphs and `.line`'s share nothing, so this genuinely
        // distinguishes them rather than passing on a coincidence.
        #expect(
            !cells.contains { SpinnerStyle.dots.frames.contains($0) },
            "row: \(row.debugDescription)")
    }

    @Test("Two refresh indicators are equal when they draw the same frames, at the same interval, in the same colour")
    func indicatorEqualityIsByWhatIsDrawn() {
        // Two values built separately, so `==` is what decides and not identity.
        let first = RefreshIndicator(style: .custom("ab"))
        let second = RefreshIndicator(style: .custom("ab"))
        #expect(first == second)
        // `.line`'s frames as a `.custom` sequence step at `.custom`'s 7 ticks, not 8.
        #expect(
            RefreshIndicator(style: .custom(SpinnerStyle.line.frames.joined()))
                != RefreshIndicator(style: .line))
        #expect(RefreshIndicator(style: .line) != RefreshIndicator(style: .dots))
        #expect(RefreshIndicator(color: .red) != RefreshIndicator())
    }

    /// The indicator is a `Spinner` composed inside the refreshable's subtree, so
    /// the speed set for spinners there reaches it without anything of its own.
    @Test("The indicator animates at the speed set for spinners")
    func indicatorFollowsSpinnerSpeed() async {
        let harness = Harness()
        let gate = RefreshGate()
        let view = Text("abcdefghij")
            .refreshable { await gate.hold() }
            .indicatorAnimationSpeed(2, for: .spinners)

        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle(until: { gate.entered == 1 })
        let busy = harness.frame(view)
        gate.release()
        await yieldToSpawnedWork()
        // `.dots` is 7 ticks a frame at the standard speed; at twice it, 3.5 rounds to 4.
        #expect(busy.animatedCells.map { $0.frameTicks } == [4])
    }

    @Test("A running refresh renders its content once")
    func runningRefreshDoesNotDoubleRenderContent() async {
        // The spinner is an OVERLAY on the content, and an overlay renders its
        // base — so building it out of `content` a second time walked the whole
        // subtree twice within one pass. Every render-pass side effect below a
        // running `.refreshable` then ran twice: `.onChange` claims its slot by
        // POSITION (`nextOnChangeIndex`, reset per pass and not per render), so
        // the second walk claimed a fresh, empty slot and fired the `initial`
        // call again for a value that never changed.
        let harness = Harness()
        let gate = RefreshGate()
        nonisolated(unsafe) var fires = 0
        // `_, _ in` rather than a bare `{ }`: both `onChange` overloads accept
        // a closure literal, and only the arity disambiguates them.
        let view = Text("abcdefghij")
            .onChange(of: 0, initial: true) { _, _ in fires += 1 }
            .refreshable { await gate.hold() }

        _ = harness.frame(view)
        #expect(fires == 1, "the `initial` call, once")

        harness.press(.character("r"), ctrl: true)
        await settle(until: { gate.entered == 1 })
        _ = harness.frame(view)
        gate.release()
        await yieldToSpawnedWork()

        #expect(fires == 1, "nothing changed, so the running frame must add no calls")
    }

    @Test("A render-to-measure pass registers no handler of its own")
    func measurePassDoesNotDuplicate() async {
        // A view that cannot be measured analytically is RENDERED to measure
        // it, with `isMeasuring` set. Without the guard that extra render
        // registers a second Ctrl-R handler and one keypress starts two
        // refreshes — the exact bug `onKeyPress` had.
        let harness = Harness()
        nonisolated(unsafe) var refreshes = 0
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: harness.tuiContext)
        var measuring = RenderContext(
            availableWidth: 30, availableHeight: 6,
            environment: environment, tuiContext: harness.tuiContext)
        measuring.isMeasuring = true
        let real = RenderContext(
            availableWidth: 30, availableHeight: 6,
            environment: environment, tuiContext: harness.tuiContext)
        let view = Text("content").refreshable { refreshes += 1 }

        harness.tuiContext.keyEventDispatcher.clearHandlers()
        harness.tuiContext.stateStorage.beginRenderPass()
        _ = renderToBuffer(view, context: measuring)
        _ = renderToBuffer(view, context: real)
        harness.tuiContext.stateStorage.endRenderPass()

        harness.press(.character("r"), ctrl: true)
        await settle(until: { refreshes == 1 })
        #expect(refreshes == 1)
    }

    @Test("A view that is only measured answers no keys")
    func measuredButNotRenderedIsInert() async {
        // The other half of the same guard, and the one the in-flight check
        // cannot cover: a subtree can be measured and then NOT rendered — a
        // ViewThatFits candidate that lost, a row outside the window. It is
        // not on screen, so Ctrl-R must not reach it.
        let harness = Harness()
        nonisolated(unsafe) var refreshes = 0
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: harness.tuiContext)
        var measuring = RenderContext(
            availableWidth: 30, availableHeight: 6,
            environment: environment, tuiContext: harness.tuiContext)
        measuring.isMeasuring = true

        harness.tuiContext.keyEventDispatcher.clearHandlers()
        harness.tuiContext.stateStorage.beginRenderPass()
        _ = renderToBuffer(
            Text("content").refreshable { refreshes += 1 }, context: measuring)
        harness.tuiContext.stateStorage.endRenderPass()

        harness.press(.character("r"), ctrl: true)
        await yieldToSpawnedWork()
        #expect(refreshes == 0)
    }
}
