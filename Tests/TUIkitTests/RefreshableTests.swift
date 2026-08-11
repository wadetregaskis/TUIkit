//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RefreshableTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

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
        nonisolated(unsafe) var release = false
        let view = Text("content").refreshable {
            started += 1
            while !release { await Task.yield() }
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

        release = true
        await settle()

        // Finished: the next one is allowed again.
        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle()
        #expect(started == 2)
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
        let action = RefreshAction {}
        let sameAction = action
        #expect(sameAction == action)
        #expect(action != RefreshAction {})
    }

    @Test("The size does not change while a refresh runs")
    func layoutIsStable() async {
        // The spinner overlays the content. If it insetted instead, starting a
        // refresh would reflow everything below it.
        let harness = Harness()
        nonisolated(unsafe) var release = false
        let view = VStack {
            Text("one")
            Text("two")
        }
        .refreshable { while !release { await Task.yield() } }

        let idle = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle()
        let busy = harness.frame(view)

        #expect(busy.lines.count == idle.lines.count)
        #expect(busy.width == idle.width)
        // …and it IS showing something, or "stable" would be trivially true.
        #expect(busy.lines != idle.lines)

        release = true
        await settle()
    }

    // MARK: - The indicator

    /// Renders a refreshable mid-flight and returns its top row, stripped.
    private func busyTopRow<V: View>(
        _ view: V, harness: Harness, release: @escaping () -> Bool
    ) async -> String {
        _ = harness.frame(view)
        harness.press(.character("r"), ctrl: true)
        await settle()
        let busy = harness.frame(view)
        _ = release()
        await settle()
        return busy.lines.first?.stripped ?? ""
    }

    @Test("The indicator has a blank cell on each side")
    func indicatorIsPadded() async {
        let harness = Harness()
        nonisolated(unsafe) var release = false
        let view = Text("abcdefghij").refreshable { while !release { await Task.yield() } }

        let row = await busyTopRow(view, harness: harness) {
            release = true
            return release
        }
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
        nonisolated(unsafe) var release = false
        let view = Text("abcdefghij")
            .refreshable { while !release { await Task.yield() } }
            .refreshIndicator(style: .line)

        let row = await busyTopRow(view, harness: harness) {
            release = true
            return release
        }
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
