//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReplayOracle.swift
//
//  The one question every replayed tick has to answer: does the screen show
//  what a render at that instant would have drawn?
//
//  Two loops over the same app, moving the focus in step. One renders once per
//  focus stop and then REPLAYS every later tick, the way the run loop serves an
//  animation; the other RENDERS at each of those instants. Every row a run sits
//  on is compared cell by cell — the glyph and the field — so a replay that gets
//  a field wrong anywhere on the row, under the run or beside it, shows up as the
//  first column where the two disagree. The render is the oracle rather than the
//  row the replay started from, because only a render knows what the screen
//  should show at a later step; the row the replay starts from is what it
//  patches, and asking it would only check that the replay reads what it reads.
//
//  The replaying loop keeps the run loop's schedule, not just its ticks: a render
//  may ask for another at a given instant (a wake, `RenderContext.requestWake`)
//  or on a lattice (`requestAnimation`), and the run loop renders when one falls
//  due (`AnimationScheduler.nextFiring(after:)`, `FramePacer`), so this one
//  renders there too before it replays the instant after. That is not a
//  nicety: a view can hand an animation to a wake instead of leaving it in a
//  run — a breathing `List` cursor row drops its row's own runs, which its
//  whole-row breath would paint over, and asks for a render at their next step
//  — and replayed straight through, such a row held the glyph it was drawn
//  with where the app draws the next one.
//
//  Fast by construction: each loop is built once for the whole walk, and each
//  instant costs one render of one app and one replay of the other, plus a
//  render of the replaying one for each firing its last frame asked for.
//
//  Created by Wade Tregaskis
//  License: MIT

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
enum ReplayOracle {

    /// The instant both loops first render at: far enough from zero that no
    /// clock arithmetic meets a boundary case.
    static let start: Int64 = 10_000_000_000

    /// What a walk found.
    struct Findings {
        /// One line per disagreeing row and instant, naming the focus stop, the
        /// first column that differs and what each side has there.
        var mismatches: [String] = []
        /// How many (row, instant) pairs were replayed and compared — so a test
        /// can require that the comparison had something to compare.
        var compared = 0
        /// How many times the replaying loop rendered because a firing its last
        /// frame asked for fell due, as the run loop would — so a test can tell
        /// a replay that went right from one that never happened.
        var scheduledRenders = 0
    }

    /// Replays every run of `make`'s app at each focus stop and compares each
    /// replayed row with a render at the same instant.
    ///
    /// - Parameters:
    ///   - make: Builds the app. Called twice, once per loop.
    ///   - focusSteps: How many times the focus moves on before the first stop.
    ///   - stops: How many focus stops to walk, the focus moving on once between
    ///     each; the walk wraps like Tab does.
    ///   - ticks: How many instants to compare at each stop, one every three
    ///     1/60 s ticks — the step every standard cycle moves on — each half a
    ///     tick into its step, so no rounding at a boundary lands the two on
    ///     neighbours.
    ///   - size: The terminal.
    ///   - reportOncePerRow: Keep only the first disagreement on each row, for a
    ///     walk that would otherwise report one fault at every tick of every stop.
    static func compare<A: App>(
        _ make: () -> A, focusSteps: Int = 0, stops: Int = 1, ticks: Int = 24,
        size: (width: Int, height: Int) = (80, 30), reportOncePerRow: Bool = false
    ) -> Findings {
        let replaying = Driven(make(), focusSteps: focusSteps, size: size)
        let rendering = Driven(make(), focusSteps: focusSteps, size: size)
        let tick = AnimationClock.nanoseconds(AnimationClock.seconds(forTicks: 1))
        let step = Int64(AnimationClock.standardFrameTicks) * tick
        var findings = Findings()
        var reported = Set<Int>()
        for stop in 0..<max(1, stops) {
            // Each stop begins a step past the last instant the one before used.
            let base = start + Int64(stop * (ticks + 1)) * step
            if stop > 0 {
                replaying.moveFocus()
                rendering.moveFocus()
                replaying.render(at: base)
                rendering.render(at: base)
            }
            guard let first = replaying.loop.replayable, !first.runs.isEmpty else { continue }
            let cursorAtBase = replaying.timer.elapsed(for: .cursor)
            for tickIndex in 1...max(1, ticks) {
                let now = base + Int64(tickIndex) * step + tick / 2
                let since = Double(now - base) / 1_000_000_000
                findings.scheduledRenders += replaying.renderWhatFellDue(by: now)
                guard
                    replaying.loop.replayAnimations(elapsed: [
                        .content: Double(now) / 1_000_000_000, .cursor: cursorAtBase + since,
                    ])
                else { continue }
                rendering.render(at: now)
                guard let replayed = replaying.loop.replayable, let rendered = rendering.loop.replayable
                else { continue }
                // The rows of the frame being replayed: a render since the stop began
                // may have moved a run.
                let rows = Set(replayed.runs.map(\.offsetY)).sorted()
                for row in rows where replayed.contentLines.indices.contains(row) {
                    findings.compared += 1
                    let shown = paintedCells(replayed.lastPatched[row]?.line ?? replayed.contentLines[row])
                    let expected = paintedCells(rendered.contentLines[row])
                    guard let column = firstDifference(shown, expected) else { continue }
                    guard !reportOncePerRow || reported.insert(row).inserted else { continue }
                    func describe(_ cells: [PaintedCell]) -> String {
                        guard cells.indices.contains(column) else { return "nothing" }
                        return "'\(cells[column].glyph)' on \(cells[column].background.debugDescription)"
                    }
                    findings.mismatches.append(
                        """
                        stop \(stop), tick \(tickIndex), row \(row), column \(column): replayed \
                        \(describe(shown)), rendered \(describe(expected))
                        """)
                }
            }
        }
        return findings
    }

    /// The first column where the two rows paint a different glyph or field.
    private static func firstDifference(_ shown: [PaintedCell], _ expected: [PaintedCell]) -> Int? {
        let common = min(shown.count, expected.count)
        if let column = (0..<common).first(where: {
            shown[$0].glyph != expected[$0].glyph || shown[$0].background != expected[$0].background
        }) {
            return column
        }
        return shown.count == expected.count ? nil : common
    }

    /// A loop over an app, and what it renders with: the cursor timer, and an
    /// animation scheduler — without one a render cannot animate at all
    /// (`canAnimate`), and a `withAnimation` lands on its end value at once —
    /// fenced around every render as the run loop fences it, so what the last
    /// frame asked for is what is live.
    @MainActor
    private final class Driven<A: App> {
        let loop: RenderLoop<A>
        let timer: CursorTimer
        let focusManager: FocusManager
        let scheduler = AnimationScheduler()
        /// The instant of the last render, which the next firing is counted after.
        private var renderedAt = start

        /// A loop over `app` that has rendered at ``start`` with the focus moved on
        /// `focusSteps` times.
        init(_ app: A, focusSteps: Int, size: (width: Int, height: Int)) {
            let harness = RenderLoopHarness()
            harness.terminal.size = (size.width, size.height)
            loop = harness.loop(app)
            timer = CursorTimer(renderNotifier: harness.appState)
            focusManager = harness.focusManager
            render(at: start)
            for _ in 0..<focusSteps { moveFocus() }
            // Twice: the first frame after the focus moves may settle state (an
            // `onAppear`'s `withAnimation`, a focus binding) that the second draws.
            render(at: start)
            render(at: start)
        }

        /// Tab: the focus moves on, and the focus-relative clock restarts at its
        /// bright end, as the app restarts it on every focus move — so the frame
        /// after a move draws a caret visible and a breath at its brightest.
        func moveFocus() {
            focusManager.focusNext()
            timer.restartFocusPhase()
        }

        func render(at instant: Int64) {
            scheduler.beginFrame()
            loop.render(cursorTimer: timer, animationScheduler: scheduler, frameNowNanos: instant)
            scheduler.endFrame()
            renderedAt = instant
        }

        /// Renders at each firing the frames so far asked for — a wake, or a
        /// lattice's next multiple — that falls due by `instant`, each at its own
        /// instant, as the run loop's pacer does (`AppRunner.renderFrame`: the
        /// deadline is `nextFiring(after:)` the frame's own instant).
        ///
        /// - Returns: How many renders that took.
        func renderWhatFellDue(by instant: Int64) -> Int {
            var renders = 0
            while let due = scheduler.nextFiring(after: renderedAt), due <= instant {
                render(at: due)
                renders += 1
            }
            return renders
        }
    }
}
