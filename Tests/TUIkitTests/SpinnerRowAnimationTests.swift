//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SpinnerRowAnimationTests.swift
//
//  Regression tests for GitHub issue #1: spinners nested inside ForEach rows
//  (a Card's VStack, a List) must keep animating. The row-level value memo
//  (`_MemoizedRow`, and `EquatableView` for explicit `.equatable()`) used to
//  cache any row whose element compared equal — and a Spinner's output was a
//  function of TIME, so the cached buffer froze the glyph.
//
//  What "keeps animating" MEANS changed when the spinner stopped asking to be
//  re-rendered and started leaving an `AnimatedCellRun` behind instead. The
//  glyph on the buffer is now just the frame showing at this tick; what makes
//  the spinner move is the run, replayed by the loop without consulting the
//  view. So these tests measure the run: it must be there, on the right line,
//  actually varying, on EVERY frame including the ones served from a memo.
//
//  That is a stronger check than the old one, not a weaker one. The old test
//  asked whether the glyph differed between two renders; a cached row could
//  pass it by accident if the cache happened to miss. This asks whether the
//  thing that drives the animation survived the cache, every single frame.
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

    /// The animated runs sitting on the first line whose text contains
    /// `marker` — the line the spinner shares with its label.
    private func runs(in buffer: FrameBuffer, onLineContaining marker: String)
        -> [AnimatedCellRun]
    {
        guard let line = buffer.lines.firstIndex(where: { $0.stripped.contains(marker) })
        else { return [] }
        return buffer.animatedCells.filter { $0.offsetY == line }
    }

    /// Renders `view` repeatedly — a full simulated frame each time, with real
    /// time in between so the memo has every chance to serve a cached row — and
    /// reports, for each marker, the number of frames on which an ANIMATING run
    /// sat on its line.
    ///
    /// A frozen (wrongly memoized, or dropped by a container) spinner shows up
    /// as a count below the frame count: the run is what moves it, so a frame
    /// without one is a frame in which nothing will.
    private func pollForRuns<V: View>(
        _ view: V, markers: [String], frames: Int = 8
    ) async throws -> (framesWithRun: [String: Int], frames: Int, sample: AnimatedCellRun?) {
        let tuiContext = TUIContext()
        let scheduler = AnimationScheduler()
        let focusManager = FocusManager()
        var counts = markers.reduce(into: [String: Int]()) { $0[$1] = 0 }
        var sample: AnimatedCellRun?
        var nowNanos: Int64 = 0

        for frame in 0..<frames {
            if frame > 0 {
                try await Task.sleep(for: .milliseconds(40))
                nowNanos += 40_000_000
            }
            let buffer = renderFrame(
                view, tuiContext: tuiContext, scheduler: scheduler,
                focusManager: focusManager, nowNanos: nowNanos)
            for marker in markers {
                let animating = runs(in: buffer, onLineContaining: marker).filter(\.isAnimating)
                if !animating.isEmpty {
                    counts[marker, default: 0] += 1
                    sample = sample ?? animating.first
                }
            }
        }
        return (counts, frames, sample)
    }

    /// Every marker must carry an animating run on every frame.
    private func expectAnimating(
        _ result: (framesWithRun: [String: Int], frames: Int, sample: AnimatedCellRun?),
        _ markers: [String], _ what: String
    ) {
        for marker in markers {
            #expect(
                result.framesWithRun[marker] == result.frames,
                """
                \(what): "\(marker)" carried an animating run on \
                \(result.framesWithRun[marker] ?? 0) of \(result.frames) frames
                """)
        }
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

        // "Welcome" is the control — a top-level spinner, never memoized —
        // and "Alpha" is the bug: a spinner inside a ForEach row.
        let result = try await pollForRuns(view, markers: ["Welcome", "Alpha"])
        expectAnimating(result, ["Welcome", "Alpha"], "ForEach row")

        // And the run is a real cycle over the style's glyphs, not a
        // single-frame placeholder that would satisfy the count above.
        let run = try #require(result.sample)
        #expect(run.width == 1, "a `.line` spinner is one cell wide, not \(run.width)")
        #expect(Set(run.frames).count == 4, "expected the four `| / - \\` glyphs")
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

        let result = try await pollForRuns(view, markers: ["Alpha"])
        expectAnimating(result, ["Alpha"], "List row")
    }

    @Test("Spinners inside a ScrollView's rows keep animating")
    func spinnersInScrollViewAnimate() async throws {
        let view = ScrollView {
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
        .frame(height: 10)

        let result = try await pollForRuns(view, markers: ["Alpha"])
        expectAnimating(result, ["Alpha"], "ScrollView row")
    }

    @Test("Spinners inside a LazyVStack's rendered rows keep animating")
    func spinnersInLazyVStackAnimate() async throws {
        let view = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(["Alpha", "Bravo", "Charlie"], id: \.self) { item in
                HStack(spacing: 0) {
                    Text(item)
                    Spacer()
                    Spinner(style: .line)
                }
            }
        }
        .frame(height: 10)

        let result = try await pollForRuns(view, markers: ["Alpha"])
        expectAnimating(result, ["Alpha"], "LazyVStack row")
    }

    @Test("A Spinner inside .equatable() content keeps animating")
    func spinnerInEquatableViewAnimates() async throws {
        let view = VStack {
            SpinnerBadge(label: "Working").equatable()
        }

        let result = try await pollForRuns(view, markers: ["Working"])
        expectAnimating(result, ["Working"], "EquatableView")
    }
}
