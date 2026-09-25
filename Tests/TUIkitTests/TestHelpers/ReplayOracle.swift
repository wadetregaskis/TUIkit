//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReplayOracle.swift
//
//  The one question every replayed tick has to answer: does the screen show
//  what a render at that instant would have drawn?
//
//  Two loops over the same app, moving the focus in step. One renders once per
//  focus stop and then REPLAYS every later tick, the way the run loop serves an
//  animation; the other RENDERS at each of those instants. Every row a run sits
//  on is compared cell by cell — the glyph, the field, and the ink a glyph is
//  drawn in — so a replay that gets a field wrong anywhere on the row, under the
//  run or beside it, or replays a frame some pass recoloured in the lines and not
//  in the run, shows up as the first column where the two disagree. Not compared:
//  the ink of a blank cell, which nothing shows, and the attributes (bold, dim,
//  reverse video), which the replay does not restate — a run in a reversed row
//  replays unreversed (`Documentation/Terminal-compatibility.md`, the ground
//  note). The render is the oracle rather than the
//  row the replay started from, because only a render knows what the screen
//  should show at a later step; the row the replay starts from is what it
//  patches, and asking it would only check that the replay reads what it reads.
//  And every row a render at the instant has moved is compared as well, run or
//  no run — a glyph, or only a colour: a run the resolution dropped leaves its
//  row with nothing to replay, frozen where a render moves it.
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
        /// The rows where the caller's `holding` excused a disagreement, each with
        /// the text the render draws on it — so a caller can assert WHICH rows it
        /// held, and that it held no more. A held cell is not a mismatch, and does
        /// not stop the comparison: the row's first disagreement it does not excuse
        /// is still one, at that instant and every later one.
        var held: [Int: String] = [:]
        /// One line per held disagreement, as ``mismatches`` spells them, for a
        /// caller that records them as a known issue.
        var heldMismatches: [String] = []
        /// How many (row, instant) pairs were replayed and compared — so a test
        /// can require that the comparison had something to compare.
        var compared = 0
        /// How many times the replaying loop rendered because a firing its last
        /// frame asked for fell due, as the run loop would — so a test can tell
        /// a replay that went right from one that never happened.
        var scheduledRenders = 0
        /// How many compared rows a replay had moved a glyph on since the render
        /// it patched — the ticks that actually tested something.
        var movedGlyphs = 0
    }

    /// Where the truth for a replayed cell's COLOURS comes from. Its glyph always
    /// comes from a render at the replayed instant.
    enum ColourTruth {
        /// The same render: right wherever nothing but the runs changes between
        /// one render and the next.
        case renderedThen
        /// A render at the instant the replaying loop last rendered, for an app
        /// whose colours move on a LATTICE rather than in runs — a transition's
        /// fade, which renders every 2 ticks. Between two of those renders the
        /// run loop draws nothing but the runs, so every colour on screen, the
        /// runs' included, is the last render's, while a run's glyph moves on; a
        /// render at the replayed instant has faded further, on every cell. Only
        /// for runs whose frames differ in their glyph alone — a spinner.
        case lastRendered
    }

    /// Replays every run of `make`'s app at each focus stop and compares each
    /// replayed row with a render at the same instant — its colours with a render
    /// where `colours` says.
    ///
    /// - Parameters:
    ///   - make: Builds the app. Called once per loop: twice, or three times for
    ///     ``ColourTruth/lastRendered``.
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
    ///     Held disagreements are counted apart, so a held row still reports the
    ///     first one it does not excuse.
    ///   - colours: Where a replayed cell's colours are checked against.
    ///   - holding: A disagreement the caller knows about and excuses, cell by cell
    ///     — given what the replay shows and what the render draws. Excused cells
    ///     land in ``Findings/held``, and the comparison goes on past them.
    static func compare<A: App>(
        _ make: () -> A, focusSteps: Int = 0, stops: Int = 1, ticks: Int = 24,
        size: (width: Int, height: Int) = (80, 30), reportOncePerRow: Bool = false,
        colours: ColourTruth = .renderedThen,
        holding: ((_ shown: PaintedCell, _ expected: PaintedCell) -> Bool)? = nil
    ) -> Findings {
        let replaying = Driven(make(), focusSteps: focusSteps, size: size)
        let rendering = Driven(make(), focusSteps: focusSteps, size: size)
        // A third loop for `.lastRendered`, rendering only where the replaying one
        // did, so the rendering loop's clocks never run backwards.
        let colouring = colours == .lastRendered ? Driven(make(), focusSteps: focusSteps, size: size) : nil
        let tick = AnimationClock.nanoseconds(AnimationClock.seconds(forTicks: 1))
        let step = Int64(AnimationClock.standardFrameTicks) * tick
        var findings = Findings()
        var reported = Set<Int>()
        var reportedHeld = Set<Int>()
        for stop in 0..<max(1, stops) {
            // Each stop begins a step past the last instant the one before used.
            let base = start + Int64(stop * (ticks + 1)) * step
            if stop > 0 {
                for driven in [replaying, rendering] + (colouring.map { [$0] } ?? []) {
                    driven.moveFocus()
                    driven.render(at: base)
                }
            }
            // A stop with no run at all is walked too: nothing replays there, so the
            // screen holds the last render until a firing it asked for, and a row a
            // render at the instant has moved since is a row that froze.
            guard replaying.loop.replayable != nil else { continue }
            let cursorAtBase = replaying.timer.elapsed(for: .cursor)
            for tickIndex in 1...max(1, ticks) {
                let now = base + Int64(tickIndex) * step + tick / 2
                let since = Double(now - base) / 1_000_000_000
                findings.scheduledRenders += replaying.renderWhatFellDue(by: now)
                // What it replays, if anything: a tick that lands on the picture
                // already showing, or finds no run to replay, leaves the screen as it
                // is, and that is still the screen to compare.
                _ = replaying.loop.replayAnimations(elapsed: [
                    .content: Double(now) / 1_000_000_000, .cursor: cursorAtBase + since,
                ])
                rendering.render(at: now)
                if let colouring, colouring.renderedAt != replaying.renderedAt {
                    colouring.render(at: replaying.renderedAt)
                }
                guard let replayed = replaying.loop.replayable, let rendered = rendering.loop.replayable
                else { continue }
                let coloured = colouring?.loop.replayable
                // The rows of the frame being replayed — a render since the stop began
                // may have moved a run — and every row a render at this instant has
                // moved since the render the replay patches: a glyph, or only how a
                // cell looks. A run the resolution dropped leaves its row with nothing
                // to replay, frozen there while a render moves it; only rows a run sits
                // on were compared until 2026-09-26, so such a row was never looked at,
                // and then only rows whose GLYPHS moved, so a fade that froze over a
                // row's fill, moving no glyph, was not either.
                let moved = rendered.contentLines.indices.filter { row in
                    replayed.contentLines.indices.contains(row)
                        && firstDifference(
                            paintedCells(rendered.contentLines[row]), paintedCells(replayed.contentLines[row]),
                            holding: nil
                        ).column != nil
                }
                let rows = Set(replayed.runs.map(\.offsetY) + moved).sorted()
                for row in rows where replayed.contentLines.indices.contains(row) {
                    findings.compared += 1
                    let shown = paintedCells(replayed.lastPatched[row]?.line ?? replayed.contentLines[row])
                    if shown.map(\.glyph) != paintedCells(replayed.contentLines[row]).map(\.glyph) {
                        findings.movedGlyphs += 1
                    }
                    var expected = paintedCells(rendered.contentLines[row])
                    if let coloured, coloured.contentLines.indices.contains(row) {
                        let colours = paintedCells(coloured.contentLines[row])
                        expected = zip(expected, colours).map { PaintedCell(glyph: $0.glyph, state: $1.state) }
                    }
                    func describe(_ cells: [PaintedCell], at column: Int) -> String {
                        guard cells.indices.contains(column) else { return "nothing" }
                        let cell = cells[column]
                        let ink = cell.glyph == " " ? "" : " in \(spelledInk(cell.ink).debugDescription)"
                        // Said, because the comparison reads the two colours as
                        // spelled and a reversal exchanges what they show.
                        let reversed = cell.state.reversesVideo ? ", reversed" : ""
                        return "'\(cell.glyph)'\(ink) on \(cell.background.debugDescription)\(reversed)"
                    }
                    func mismatch(at column: Int) -> String {
                        """
                        stop \(stop), tick \(tickIndex), row \(row), column \(column): replayed \
                        \(describe(shown, at: column)), rendered \(describe(expected, at: column))
                        """
                    }
                    let (column, excused) = firstDifference(shown, expected, holding: holding)
                    if let excused {
                        findings.held[row] = String(expected.map(\.glyph))
                        if !reportOncePerRow || reportedHeld.insert(row).inserted {
                            findings.heldMismatches.append(mismatch(at: excused))
                        }
                    }
                    guard let column else { continue }
                    guard !reportOncePerRow || reported.insert(row).inserted else { continue }
                    findings.mismatches.append(mismatch(at: column))
                }
            }
        }
        return findings
    }

    /// The first column where the two rows paint a different glyph or field, or
    /// draw a glyph in a different ink, that `holding` does not excuse — and the
    /// first it does excuse, if any.
    private static func firstDifference(
        _ shown: [PaintedCell], _ expected: [PaintedCell],
        holding: ((PaintedCell, PaintedCell) -> Bool)?
    ) -> (column: Int?, excused: Int?) {
        let common = min(shown.count, expected.count)
        var excused: Int?
        for column in 0..<common where !looksAlike(shown[column], expected[column]) {
            guard holding?(shown[column], expected[column]) == true else { return (column, excused) }
            if excused == nil { excused = column }
        }
        return (shown.count == expected.count ? nil : common, excused)
    }

    /// Whether two cells show the same thing: the glyph, the field, and — where
    /// there is a glyph to draw it — the ink.
    private static func looksAlike(_ shown: PaintedCell, _ expected: PaintedCell) -> Bool {
        guard shown.glyph == expected.glyph, shown.background == expected.background else { return false }
        return shown.glyph == " " || shown.ink == expected.ink
    }

    /// `ink` spelled as the foreground escape that states it, `""` for the
    /// terminal's own — for a message.
    private static func spelledInk(_ ink: SGRState.Colour?) -> String {
        var state = SGRState()
        state.setForeground(ink)
        return state.rendered
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
        private(set) var renderedAt = start

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
