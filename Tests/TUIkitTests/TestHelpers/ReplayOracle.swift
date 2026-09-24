//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReplayOracle.swift
//
//  The one question every replayed tick has to answer: does the screen show
//  what a render at that instant would have drawn?
//
//  Two loops over the same app, with the same focus. One renders once and then
//  REPLAYS every later tick, the way the run loop serves an animation; the other
//  RENDERS at each of those instants. Every row a run sits on is compared cell by
//  cell — the glyph and the field — so a replay that gets a field wrong anywhere
//  on the row, under the run or beside it, shows up as the first column where the
//  two disagree. The render is the oracle rather than the row the replay started
//  from, because only a render knows what the screen should show at a later
//  step; the row the replay starts from is what it patches, and asking it would
//  only check that the replay reads what it reads.
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
//  Fast by construction: each loop is built once, and each instant costs one
//  render of the one app and one replay of the other, plus a render of the
//  replaying one for each firing its last frame asked for.
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

    /// Where every replayed row disagrees with a render at the same instant.
    ///
    /// - Parameters:
    ///   - make: Builds the app. Called twice, once per loop.
    ///   - focusSteps: How many times the focus moves on from where it starts
    ///     before the first frame the comparison starts from.
    ///   - ticks: How many instants to compare, one every three 1/60 s ticks —
    ///     the step every standard cycle moves on — each half a tick into its
    ///     step, so no rounding at a boundary lands the two on neighbours.
    ///   - size: The terminal.
    /// - Returns: One line per disagreeing row and instant, naming the first
    ///   column that differs and what each side has there. Empty when the replay
    ///   drew what a render draws, and also when nothing was replayed — ask
    ///   ``replayedRows(of:focusSteps:ticks:size:)`` for that.
    static func mismatches<A: App>(
        _ make: () -> A, focusSteps: Int = 0, ticks: Int = 24, size: (width: Int, height: Int) = (80, 30)
    ) -> [String] {
        compare(make, focusSteps: focusSteps, ticks: ticks, size: size).mismatches
    }

    /// How many (row, instant) pairs were replayed and compared — so a test can
    /// require that the comparison had something to compare.
    static func replayedRows<A: App>(
        of make: () -> A, focusSteps: Int = 0, ticks: Int = 24, size: (width: Int, height: Int) = (80, 30)
    ) -> Int {
        compare(make, focusSteps: focusSteps, ticks: ticks, size: size).compared
    }

    /// Both answers from one walk, and how many times the replaying loop rendered
    /// because a firing its last frame asked for fell due, as the run loop would —
    /// so a test can tell a replay that went right from one that never happened.
    static func compare<A: App>(
        _ make: () -> A, focusSteps: Int, ticks: Int, size: (width: Int, height: Int)
    ) -> (mismatches: [String], compared: Int, scheduledRenders: Int) {
        let replaying = Driven(make(), focusSteps: focusSteps, size: size)
        let rendering = Driven(make(), focusSteps: focusSteps, size: size)
        guard let first = replaying.loop.replayable, !first.runs.isEmpty else { return ([], 0, 0) }
        let cursorAtStart = replaying.timer.elapsed(for: .cursor)
        let tick = AnimationClock.nanoseconds(AnimationClock.seconds(forTicks: 1))
        var mismatches: [String] = []
        var compared = 0
        var scheduledRenders = 0
        for step in 1...max(1, ticks) {
            let now = start + Int64(step * AnimationClock.standardFrameTicks) * tick + tick / 2
            let since = Double(now - start) / 1_000_000_000
            scheduledRenders += replaying.renderWhatFellDue(by: now)
            guard
                replaying.loop.replayAnimations(elapsed: [
                    .content: Double(now) / 1_000_000_000, .cursor: cursorAtStart + since,
                ])
            else { continue }
            rendering.render(at: now)
            guard let replayed = replaying.loop.replayable, let rendered = rendering.loop.replayable
            else { continue }
            // The rows of the frame being replayed: a render since the walk began
            // may have moved a run.
            let rows = Set(replayed.runs.map(\.offsetY)).sorted()
            for row in rows where replayed.contentLines.indices.contains(row) {
                let shown = paintedCells(replayed.lastPatched[row]?.line ?? replayed.contentLines[row])
                let expected = paintedCells(rendered.contentLines[row])
                compared += 1
                guard
                    let column = shown.indices.first(where: {
                        !expected.indices.contains($0) || shown[$0].glyph != expected[$0].glyph
                            || shown[$0].background != expected[$0].background
                    }) ?? (shown.count == expected.count ? nil : min(shown.count, expected.count))
                else { continue }
                func describe(_ cells: [PaintedCell]) -> String {
                    guard cells.indices.contains(column) else { return "nothing" }
                    return "'\(cells[column].glyph)' on \(cells[column].background.debugDescription)"
                }
                mismatches.append(
                    "tick \(step), row \(row), column \(column): replayed \(describe(shown)), rendered \(describe(expected))")
            }
        }
        return (mismatches, compared, scheduledRenders)
    }

    /// A loop over an app, and what it renders with: the cursor timer, and an
    /// animation scheduler fenced around every render as the run loop fences it
    /// (`AppRunner.renderFrame`), so what the last frame asked for is what is
    /// live. Without a scheduler a render asks for nothing at all.
    @MainActor
    private final class Driven<A: App> {
        let loop: RenderLoop<A>
        let timer: CursorTimer
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
            render(at: start)
            for _ in 0..<focusSteps { harness.focusManager.focusNext() }
            render(at: start)
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
