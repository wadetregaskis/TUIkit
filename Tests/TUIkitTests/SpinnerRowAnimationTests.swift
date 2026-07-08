//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SpinnerRowAnimationTests.swift
//
//  Regression tests for GitHub issue #1: spinners nested inside ForEach rows
//  (a Card's VStack, a List) must keep animating. The row-level value memo
//  (`_MemoizedRow`, and `EquatableView` for explicit `.equatable()`) used to
//  cache any row whose element compared equal — but a Spinner's output is a
//  function of *time*, and serving the cached buffer both froze the glyph and
//  skipped the spinner's per-frame `requestAnimation` re-declaration, so the
//  scheduler dropped its grid and the demand-driven loop stopped ticking it.
//  `requestAnimation` now records on the `VolatileReadTracker`, which declines
//  the cache for time-varying subtrees.
//
//  Each test drives the same per-frame lifecycle the live RenderLoop uses
//  (state storage + render cache + animation scheduler begin/end) around
//  repeated headless renders with real wall-clock time in between, and checks
//  that the nested spinner advances its frame and keeps its animation token.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// An `Equatable` view wrapping a Spinner, for the explicit `.equatable()`
/// variant of the row-memo freeze.
private struct SpinnerBadge: View, Equatable {
    let label: String

    var body: some View {
        HStack {
            Text(label)
            Spinner(style: .line)
        }
    }
}

@MainActor
@Suite("Spinner animation in memoized rows (issue #1)")
struct SpinnerRowAnimationTests {
    /// One simulated live-loop frame: the exact begin/end sequence
    /// `RenderLoop.render` + `App` use around a render pass.
    private func renderFrame<V: View>(
        _ view: V,
        tuiContext: TUIContext,
        scheduler: AnimationScheduler,
        focusManager: FocusManager,
        nowNanos: Int64
    ) -> FrameBuffer {
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        scheduler.beginFrame()

        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.animationScheduler = scheduler
        environment.frameNowNanos = nowNanos
        environment.volatileReadTracker = VolatileReadTracker()  // as RenderLoop.render does

        let context = RenderContext(
            availableWidth: 60,
            availableHeight: 40,
            environment: environment,
            tuiContext: tuiContext)

        let buffer = renderToBuffer(view, context: context)

        scheduler.endFrame()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return buffer
    }

    /// Extracts the `.line`-style spinner glyph (one of `| / - \`) from the
    /// first stripped line containing `marker`. ASCII `|` is distinct from the
    /// box-drawing border `│`, so borders never match.
    private func spinnerGlyph(in buffer: FrameBuffer, onLineContaining marker: String) -> Character? {
        let lineFrames: Set<Character> = ["|", "/", "-", "\\"]
        for line in buffer.lines {
            let stripped = line.stripped
            if stripped.contains(marker) {
                return stripped.reversed().first { lineFrames.contains($0) }
            }
        }
        return nil
    }

    /// Renders `view` once, then keeps re-rendering (a full simulated frame
    /// each time) until every marker line's spinner glyph differs from its
    /// first-frame glyph, or a generous timeout lapses.
    ///
    /// A fixed sleep is not sound here: the Spinner's frame index is real
    /// wall-clock elapsed time over the style interval *modulo the frame
    /// count*, so a loaded machine that stretches one sleep to a multiple of
    /// the full cycle (`.line`: 4 x 140 ms) aliases a healthy spinner back to
    /// its old glyph. Polling across many distinct offsets cannot alias — while
    /// a frozen (wrongly memoized) spinner never changes no matter how long we
    /// poll, so the regression still fails deterministically.
    private func pollForGlyphChanges<V: View>(
        _ view: V,
        markers: [String]
    ) async throws -> (changed: Set<String>, live1: Int, liveFinal: Int) {
        let tuiContext = TUIContext()
        let scheduler = AnimationScheduler()
        let focusManager = FocusManager()

        let frame1 = renderFrame(
            view, tuiContext: tuiContext, scheduler: scheduler,
            focusManager: focusManager, nowNanos: 0)
        let live1 = scheduler.liveCount
        let initial = markers.reduce(into: [String: Character?]()) {
            $0[$1] = spinnerGlyph(in: frame1, onLineContaining: $1)
        }

        var changed = Set<String>()
        var liveFinal = live1
        var nowNanos: Int64 = 0
        for _ in 0..<40 where changed.count < markers.count {
            try await Task.sleep(for: .milliseconds(60))
            nowNanos += 60_000_000
            let frame = renderFrame(
                view, tuiContext: tuiContext, scheduler: scheduler,
                focusManager: focusManager, nowNanos: nowNanos)
            liveFinal = scheduler.liveCount
            for marker in markers where !changed.contains(marker) {
                if spinnerGlyph(in: frame, onLineContaining: marker) != initial[marker] {
                    changed.insert(marker)
                }
            }
        }
        return (changed, live1, liveFinal)
    }

    @Test("Spinners inside ForEach rows (Card) keep animating")
    func spinnersInCardForEachAnimate() async throws {
        // The issue's repro, trimmed: a top-level spinner (control) plus
        // spinners inside a ForEach in a Card.
        let view = VStack {
            HStack {
                Text("Welcome")
                Spinner(style: .line)
            }
            Card(title: "Items") {
                VStack(spacing: 0) {
                    ForEach(["Alpha", "Bravo", "Charlie"], id: \.self) { item in
                        HStack(spacing: 0) {
                            Text(item)
                            Spacer()
                            Spinner(style: .line)
                        }
                    }
                }
            }
        }

        let result = try await pollForGlyphChanges(view, markers: ["Welcome", "Alpha"])

        // Control: the top-level spinner must animate.
        #expect(result.changed.contains("Welcome"), "control failed: top-level spinner did not animate")

        // The bug: the ForEach-row spinner must animate too…
        #expect(result.changed.contains("Alpha"), "nested (ForEach-row) spinner frozen")

        // …and its animation token must stay declared (4 spinners on screen).
        #expect(result.liveFinal == result.live1, "nested spinners' animation tokens dropped")
    }

    @Test("Spinners inside List rows keep animating")
    func spinnersInListRowsAnimate() async throws {
        let view = List("Items", selection: Binding<String?>.constant(nil)) {
            ForEach(["Alpha", "Bravo", "Charlie"], id: \.self) { item in
                HStack(spacing: 0) {
                    Text(item)
                    Spacer()
                    Spinner(style: .line)
                }
            }
        }

        let result = try await pollForGlyphChanges(view, markers: ["Alpha"])

        #expect(result.changed.contains("Alpha"), "List-row spinner frozen (or not visible)")
        #expect(result.liveFinal == result.live1, "List-row spinners' animation tokens dropped")
    }

    @Test("A Spinner inside .equatable() content keeps animating")
    func spinnerInEquatableViewAnimates() async throws {
        let view = VStack {
            SpinnerBadge(label: "Working").equatable()
        }

        let result = try await pollForGlyphChanges(view, markers: ["Working"])

        #expect(result.changed.contains("Working"), "spinner frozen inside an EquatableView")
        #expect(result.liveFinal == result.live1, "EquatableView dropped the spinner's animation token")
    }
}
