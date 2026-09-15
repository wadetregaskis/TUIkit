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

    /// Lets the `Task` the handler spawned run to completion.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    /// The gate a refresh body waits on, so the test decides when it finishes.
    ///
    /// A refresh action is `@Sendable` and runs off the test's own actor, so a
    /// captured `nonisolated(unsafe) var` opened afterwards is precisely the
    /// mutation-after-capture the compiler warns about. Reference semantics
    /// behind a lock are what these tests always meant —
    /// ``RefreshAction/RunState`` is the same shape for the same reason.
    private final class Latch: @unchecked Sendable {
        private let lock = NSLock()
        private var open = false

        /// Whether a body waiting on this latch must keep waiting.
        var isClosed: Bool { lock.withLock { !open } }
        /// Lets every waiting body finish.
        func release() { lock.withLock { open = true } }
        /// Shuts the gate again, for a test that runs a second body.
        func reset() { lock.withLock { open = false } }
    }

    @Test("Ctrl-R runs the action")
    func controlRRefreshes() async {
        let harness = Harness()
        nonisolated(unsafe) var refreshes = 0
        let view = Text("content").refreshable { refreshes += 1 }

        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle()
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
        await settle()
        #expect(refreshes == 0)
    }

    @Test("A second Ctrl-R during a refresh does not start another")
    func noOverlappingRefreshes() async {
        // SwiftUI will not run a second refresh over a running one either, and
        // an app's reload is rarely re-entrant.
        let harness = Harness()
        nonisolated(unsafe) var started = 0
        let gate = Latch()
        let view = Text("content").refreshable {
            started += 1
            while gate.isClosed { await Task.yield() }
        }

        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle()
        #expect(started == 1)

        // Still in flight: the handler must consume the key, not queue work.
        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle()
        #expect(started == 1)

        gate.release()
        await settle()

        // Finished: the next one is allowed again.
        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle()
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
        let gate = Latch()
        let action = RefreshAction(
            {
                runs += 1
                while gate.isClosed { await Task.yield() }
            }, state: RefreshAction.RunState())

        // Two calls through the environment, the second while the first is in
        // flight — the shape a second click on "Refresh Now" makes.
        let first = Task { @MainActor in await action() }
        await settle()
        #expect(runs == 1)
        // Spawned rather than awaited: if coalescing breaks, this call runs the
        // action body and blocks on the latch, so awaiting it here would HANG a
        // regression instead of failing it.
        let second = Task { @MainActor in await action() }
        await settle()
        #expect(runs == 1, "a second request while running started another")
        #expect(action.isRunning)

        gate.release()
        await first.value
        await second.value
        await settle()
        #expect(!action.isRunning)

        // …and once it has finished, it can run again.
        gate.reset()
        let third = Task { @MainActor in await action() }
        await settle()
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
        let gate = Latch()
        nonisolated(unsafe) var seen: RefreshAction?
        let view = Reader(report: { seen = $0 }).refreshable {
            runs += 1
            while gate.isClosed { await Task.yield() }
        }

        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle()
        #expect(runs == 1)

        guard let action = seen else {
            Issue.record("the subtree saw no refresh action")
            return
        }
        // Spawned, not awaited: a broken guard would block here forever, and a
        // hang is a much worse regression signal than a failed expectation.
        let viaEnvironment = Task { @MainActor in await action() }
        await settle()
        #expect(runs == 1, "the environment route stacked onto a running refresh")

        gate.release()
        await viaEnvironment.value
        await settle()
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
        let gate = Latch()
        func rebuilt() -> some View {
            VStack {
                Text("one")
                Text("two")
            }
            .refreshable { while gate.isClosed { await Task.yield() } }
        }

        let idle = harness.frame(rebuilt())
        harness.press(.character("r"), ctrl: true)
        await settle()
        let busy = harness.frame(rebuilt())

        #expect(
            busy.lines != idle.lines,
            "a rebuilt frame still has to know a refresh is running: \(busy.lines)")

        gate.release()
        await settle()
    }

    @Test("The size does not change while a refresh runs")
    func layoutIsStable() async {
        // The spinner overlays the content. If it insetted instead, starting a
        // refresh would reflow everything below it.
        let harness = Harness()
        let gate = Latch()
        let view = VStack {
            Text("one")
            Text("two")
        }
        .refreshable { while gate.isClosed { await Task.yield() } }

        let idle = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle()
        let busy = harness.frame(view)

        #expect(busy.lines.count == idle.lines.count)
        #expect(busy.width == idle.width)
        // …and it IS showing something, or "stable" would be trivially true.
        #expect(busy.lines != idle.lines)

        gate.release()
        await settle()
    }

    // MARK: - The indicator

    /// Renders a refreshable mid-flight and returns its top row, stripped.
    private func busyTopRow<V: View>(
        _ view: V, harness: Harness, gate: Latch
    ) async -> String {
        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle()
        let busy = harness.frame(view)
        gate.release()
        await settle()
        return busy.lines.first?.stripped ?? ""
    }

    @Test("The indicator has a blank cell on each side")
    func indicatorIsPadded() async {
        let harness = Harness()
        let gate = Latch()
        let view = Text("abcdefghij").refreshable { while gate.isClosed { await Task.yield() } }

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

    @Test("refreshIndicator chooses the spinner")
    func indicatorIsCustomisable() async {
        let harness = Harness()
        let gate = Latch()
        let view = Text("abcdefghij")
            .refreshable { while gate.isClosed { await Task.yield() } }
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
        #expect(RefreshIndicator(color: .ansi(.red)) != RefreshIndicator())
    }

    /// The indicator is a `Spinner` composed inside the refreshable's subtree, so
    /// the speed set for spinners there reaches it without anything of its own.
    @Test("The indicator animates at the speed set for spinners")
    func indicatorFollowsSpinnerSpeed() async {
        let harness = Harness()
        let gate = Latch()
        let view = Text("abcdefghij")
            .refreshable { while gate.isClosed { await Task.yield() } }
            .indicatorAnimationSpeed(2, for: .spinners)

        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle()
        let busy = harness.frame(view)
        gate.release()
        await settle()
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
        let gate = Latch()
        nonisolated(unsafe) var fires = 0
        // `_, _ in` rather than a bare `{ }`: both `onChange` overloads accept
        // a closure literal, and only the arity disambiguates them.
        let view = Text("abcdefghij")
            .onChange(of: 0, initial: true) { _, _ in fires += 1 }
            .refreshable { while gate.isClosed { await Task.yield() } }

        _ = harness.frame(view)
        #expect(fires == 1, "the `initial` call, once")

        harness.press(.character("r"), ctrl: true)
        await settle()
        _ = harness.frame(view)
        gate.release()
        await settle()

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
        await settle()
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
        await settle()
        #expect(refreshes == 0)
    }
}
