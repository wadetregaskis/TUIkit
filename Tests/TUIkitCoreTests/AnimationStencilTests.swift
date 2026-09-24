//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationStencilTests.swift
//
//  A stencil stamps a stored buffer with the frames its runs show at a later
//  instant, and what it stamps is served where a fresh render would have been.
//  So every expectation here is the line a render would have produced, built by
//  hand from the same pieces, compared byte for byte; and every buffer a stamp
//  could get wrong must get no stencil at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

@Suite("An animation stencil stamps a buffer as a render would draw it")
struct AnimationStencilTests {
    /// A four-frame spinner in one colour: only the glyph changes.
    private static let spin = ["-", "\\", "|", "/"].map { "\u{1B}[38;5;33m\($0)\u{1B}[0m" }

    /// The instant tick `tick` begins, on both clocks.
    private static func instant(atTick tick: Int, cursorTick: Int? = nil) -> AnimationInstant {
        func seconds(_ tick: Int) -> Double { Double(AnimationClock.nanoseconds(atTick: Int64(tick))) / 1e9 }
        return AnimationInstant(content: seconds(tick), cursor: seconds(cursorTick ?? tick))
    }

    /// The row a render draws with the spinner at `frame`: text either side, styled.
    private static func row(showing frame: Int) -> String {
        "ab " + spin[frame] + " \u{1B}[1mcd\u{1B}[0m"
    }

    private static func spinner(frameTicks: Int = 2, clock: AnimationClock = .content, row: Int = 0) -> AnimatedCellRun {
        AnimatedCellRun(offsetX: 3, offsetY: row, width: 1, frames: spin, frameTicks: frameTicks, clock: clock)
    }

    /// A buffer of `lines` carrying `runs`.
    private static func buffer(_ lines: [String], runs: [AnimatedCellRun]) -> FrameBuffer {
        var buffer = FrameBuffer(lines: lines)
        buffer.animatedCells = runs
        return buffer
    }

    @Test("Stamped at every tick of two cycles, the row is the one a render draws there")
    func stampsTheFrameOfEachInstant() throws {
        let run = Self.spinner()
        let stored = Self.buffer([Self.row(showing: 0)], runs: [run])
        let stencil = try #require(AnimationStencil(cutting: stored, drawnAt: Self.instant(atTick: 0)))
        for tick in 0..<16 {
            let at = Self.instant(atTick: tick)
            let showing = run.index(atElapsed: at.content)
            let stamped = stencil.stamping(stored, at: at)
            if showing == 0 {
                #expect(stamped == nil, "tick \(tick): nothing moved, so nothing is built")
            } else {
                #expect(stamped?.lines == [Self.row(showing: showing)], "tick \(tick)")
            }
        }
    }

    /// Bare frames — a spinner under `NO_COLOR`, an `.animatedCells` run of plain
    /// characters — can match bytes inside an escape at the run's column: the `0`
    /// of a reset, the `\` that ends a hyperlink. The cut is the frame's real
    /// place, and the escapes before it come through the stamp whole.
    @Test(
        "A bare frame is cut where it is drawn, not inside an escape that holds the same bytes",
        arguments: [
            // Bold "Job", reset, then a digit spinner showing 0 — `ESC[0m` holds a 0.
            ("\u{1B}[1mJob\u{1B}[0m0", 3, (0..<10).map(String.init), "\u{1B}[1mJob\u{1B}[0m1"),
            // A hyperlink "go", closed by ST, then a line spinner showing \ — the
            // terminator's own backslash.
            (
                "\u{1B}]8;;https://x\u{1B}\\go\u{1B}]8;;\u{1B}\\\\", 2, ["-", "\\", "|", "/"],
                "\u{1B}]8;;https://x\u{1B}\\go\u{1B}]8;;\u{1B}\\|"
            ),
        ])
    func bareFramesAreCutOutsideEscapes(line: String, column: Int, frames: [String], stampedNext: String) throws {
        let run = AnimatedCellRun(offsetX: column, offsetY: 0, width: 1, frames: frames, frameTicks: 1, clock: .content)
        let drawn = try #require(frames.firstIndex { line.hasSuffix($0) })
        let stored = Self.buffer([line], runs: [run])
        let stencil = try #require(AnimationStencil(cutting: stored, drawnAt: Self.instant(atTick: drawn)))
        let stamped = stencil.stamping(stored, at: Self.instant(atTick: drawn + 1))
        #expect(stamped?.lines == [stampedNext])
    }

    @Test("Two runs on one row, on different clocks and rates, are each stamped with their own frame")
    func twoRunsOnOneRow() throws {
        let caret = ["\u{1B}[7m_\u{1B}[0m", "\u{1B}[7mx\u{1B}[0m"]
        let spinner = AnimatedCellRun(offsetX: 1, offsetY: 0, width: 1, frames: Self.spin, frameTicks: 3, clock: .content)
        let blink = AnimatedCellRun(offsetX: 4, offsetY: 0, width: 1, frames: caret, frameTicks: 5, clock: .cursor)
        func line(_ spin: Int, _ blinkFrame: Int) -> String { "a" + Self.spin[spin] + "bc" + caret[blinkFrame] + "d" }
        let stored = Self.buffer([line(0, 0)], runs: [spinner, blink])
        let stencil = try #require(AnimationStencil(cutting: stored, drawnAt: Self.instant(atTick: 0)))
        // Each moved alone, both moved, and both back where they were drawn — where
        // nothing is built and the stored buffer is the answer.
        for (content, cursor) in [(3, 0), (0, 5), (7, 11), (12, 20)] {
            let at = Self.instant(atTick: content, cursorTick: cursor)
            let expected = line(spinner.index(atElapsed: at.content), blink.index(atElapsed: at.cursor))
            #expect((stencil.stamping(stored, at: at) ?? stored).lines == [expected], "content \(content), cursor \(cursor)")
        }
    }

    @Test("Only the rows whose runs moved are rebuilt, and the rest of the buffer is carried as it was")
    func carriesEverythingElse() throws {
        let fast = Self.spinner(frameTicks: 2, row: 0)
        let slow = Self.spinner(frameTicks: 50, row: 2)
        var stored = Self.buffer([Self.row(showing: 0), "plain", Self.row(showing: 0)], runs: [fast, slow])
        stored.hitTestRegions = [
            HitTestRegion(offsetX: 0, offsetY: 1, width: 5, height: 1, handlerID: HitTestRegion.HandlerID(7))
        ]
        stored.opacityRegions = [OpacityRegion(offsetX: 0, offsetY: 1, width: 2, height: 1, opacity: 0.5)]
        let stencil = try #require(AnimationStencil(cutting: stored, drawnAt: Self.instant(atTick: 0)))
        let stamped = try #require(stencil.stamping(stored, at: Self.instant(atTick: 2)))
        #expect(stamped.lines == [Self.row(showing: 1), "plain", Self.row(showing: 0)])
        #expect(stamped.animatedCells == stored.animatedCells)
        #expect(stamped.hitTestRegions == stored.hitTestRegions)
        #expect(stamped.opacityRegions == stored.opacityRegions)
        #expect(stamped.width == stored.width)
    }

    @Test("Wide glyphs are counted in cells, before the run and in it")
    func wideGlyphs() throws {
        let earth = ["🌍", "🌎", "🌏"]
        let run = AnimatedCellRun(offsetX: 2, offsetY: 0, width: 2, frames: earth, frameTicks: 1, clock: .content)
        let stored = Self.buffer(["中" + earth[0] + "x"], runs: [run])
        let stencil = try #require(AnimationStencil(cutting: stored, drawnAt: Self.instant(atTick: 0)))
        #expect(stencil.stamping(stored, at: Self.instant(atTick: 2))?.lines == ["中" + earth[2] + "x"])
    }

    @Test("A run whose frames are all one picture is left out, and does not stop the others")
    func stillRunsAreLeftOut() throws {
        let still = AnimatedCellRun(
            offsetX: 0, offsetY: 0, width: 1, frames: ["\u{1B}[31m*\u{1B}[0m", "\u{1B}[31m*\u{1B}[0m"],
            clock: .content)
        let moving = Self.spinner()
        // The still run's frame is not even in the line: it is never cut, so it
        // cannot refuse the stencil.
        let stored = Self.buffer([Self.row(showing: 0)], runs: [still, moving])
        #expect(AnimationStencil(cutting: stored, drawnAt: Self.instant(atTick: 0)) != nil)
        #expect(AnimationStencil(cutting: Self.buffer(["*"], runs: [still]), drawnAt: Self.instant(atTick: 0)) == nil)
    }

    /// Every shape a stamp could get wrong gets no stencil, and so misses as it did
    /// before stencils existed.
    @Test("No stencil where another frame in the cut might not be the render", arguments: StencilRefusal.allCases)
    func refuses(_ refusal: StencilRefusal) {
        let (lines, runs, regions) = refusal.buffer
        var buffer = Self.buffer(lines, runs: runs)
        buffer.opacityRegions = regions
        #expect(AnimationStencil(cutting: buffer, drawnAt: Self.instant(atTick: 0)) == nil)
    }

    enum StencilRefusal: CaseIterable, CustomTestStringConvertible {
        /// The frames differ in colour — a breath, a sweep: an effect that left the
        /// drawn frame alone need not leave the others.
        case coloursDiffer
        /// A blank frame beside a glyph: something reading whether a cell is blank
        /// would treat them differently.
        case blankAndGlyph
        /// Frames of different widths.
        case widthsDiffer
        /// Frames as wide as each other but not as the run.
        case narrowerThanTheRun
        /// The line shows a frame other than the one the run's clock names.
        case anotherFrameDrawn
        /// The drawn frame's bytes were rewritten on the way: a background restated
        /// after a reset inside it.
        case frameRewritten
        /// The frame is in the line, but not at the run's column.
        case wrongColumn
        /// The run owes a per-frame alpha, which records the frame the lines show.
        case perFrameAlpha
        /// A cycling opacity region records the phase the lines show.
        case cyclingRegion
        /// Two runs claim the same cells.
        case overlappingRuns
        /// The run is on a row the buffer does not have.
        case offTheBuffer

        var testDescription: String { "\(self)" }

        var buffer: (lines: [String], runs: [AnimatedCellRun], regions: [OpacityRegion]) {
            let spin = AnimationStencilTests.spin
            let run = AnimationStencilTests.spinner()
            let row = AnimationStencilTests.row(showing: 0)
            func single(_ frames: [String], width: Int = 1, line: String? = nil) -> ([String], [AnimatedCellRun], [OpacityRegion]) {
                let run = AnimatedCellRun(offsetX: 0, offsetY: 0, width: width, frames: frames, clock: .content)
                return ([line ?? frames[0] + "tail"], [run], [])
            }
            switch self {
            case .coloursDiffer: return single(["\u{1B}[31m*\u{1B}[0m", "\u{1B}[32m*\u{1B}[0m"])
            case .blankAndGlyph: return single(["*", " "])
            case .widthsDiffer: return single(["*", "**"])
            case .narrowerThanTheRun: return single(["*", "+"], width: 2)
            case .anotherFrameDrawn: return ([AnimationStencilTests.row(showing: 2)], [run], [])
            case .frameRewritten:
                let frames = ["\u{1B}[1m-\u{1B}[0m-", "\u{1B}[1m+\u{1B}[0m+"]
                return single(frames, width: 2, line: "\u{1B}[44m\u{1B}[1m-\u{1B}[0m\u{1B}[44m-tail")
            case .wrongColumn:
                var moved = run
                moved.offsetX = 2
                return ([row], [moved], [])
            case .perFrameAlpha:
                var faded = run
                faded.alpha = AnimatedRunAlpha(
                    perFrame: spin.indices.map { [AnimatedRunAlpha.Span(start: 0, cells: 1, ink: $0 == 0 ? 1 : 0.5)] },
                    drawnIndex: 0)
                return ([row], [faded], [])
            case .cyclingRegion:
                let cycle = OpacityCycle(phases: [1, 0.5], clock: .content)
                return ([row], [run], [OpacityRegion(offsetX: 0, offsetY: 0, width: 2, height: 1, opacity: 1, cycle: cycle)])
            case .overlappingRuns: return ([row], [run, run], [])
            case .offTheBuffer: return ([row], [AnimationStencilTests.spinner(row: 1)], [])
            }
        }
    }
}
