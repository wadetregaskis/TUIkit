//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ReplayCursorCompensationTests.swift
//
//  A terminal's cursor-advance model applies to every byte we send it, and the
//  animation replay sends bytes without going through the builder that knows
//  the model. That is one boundary, and it is invisible in a screenshot of the
//  first frame — which is exactly how it survived: the row renders correctly
//  once, and shifts a cell on every tick afterwards.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("A replayed animation frame carries the host's cursor compensation")
struct ReplayCursorCompensationTests {

    /// `CUF(1)` — the cursor push that takes an under-advancing cluster to its
    /// visual end. Its presence is the whole question here.
    private static let cursorForward = "\u{1B}[1C"

    /// A List whose cursor row's label carries a VS-16 cluster: painted 2 cells
    /// by Terminal.app, cursor advanced 1. `⚙️` because that is the row the
    /// report was about — the `.swiftlint.yml` entry of the file browser.
    private func breathingList(width: Int) -> (FrameBuffer, FrameDiffWriter) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.terminalWidth = width
        environment.animationScheduler = AnimationScheduler()
        environment.volatileReadTracker = VolatileReadTracker()
        let context = RenderContext(
            availableWidth: width, availableHeight: 8, environment: environment, tuiContext: tui)

        tui.mouseEventDispatcher.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        environment.focusManager?.beginRenderPass()
        let labels = ["⚙️ .swiftlint.yml", "plain row"]
        let buffer = renderToBuffer(
            List(selection: Binding<Int?>.constant(0)) {
                ForEach(0..<2, id: \.self) { Text(labels[$0]) }
            },
            context: context)
        tui.stateStorage.endRenderPass()
        environment.focusManager?.endRenderPass()

        return (
            buffer,
            FrameDiffWriter(
                isAppleTerminal: true, isITerm2: false, isGhostty: false, isWarp: false,
                isTmux: false)
        )
    }

    /// The run the pulse leaves on the row, and the built line it is spliced
    /// into — the two halves of what a tick puts on screen.
    private func breathingRow(width: Int) throws -> (run: AnimatedCellRun, built: String) {
        let (buffer, writer) = breathingList(width: width)
        let built = writer.buildOutputLines(
            buffer: buffer, terminalWidth: width, terminalHeight: 8,
            bgCode: "\u{1B}[49m", reset: ANSIRenderer.reset, reusingFor: .content)
        let run = try #require(
            buffer.animatedCells.first { $0.frame(atIndex: 0).unicodeScalars.contains("\u{2699}") },
            "the focused row left no animated run carrying the emoji")
        return (run, built[run.offsetY])
    }

    /// The bug, at the boundary it crossed.
    ///
    /// The first frame is built by `FrameDiffWriter` and carries the
    /// compensation; every frame after it is a run's picture spliced into that
    /// line, and the run's frames are rendered content that has never met the
    /// host's advance model. So the row painted correctly once and then, on
    /// Terminal.app, drew everything after the emoji one cell to the left —
    /// which is precisely what an uncompensated emission measures as (77 vs 76
    /// in `Tools/TerminalProbes/row_probe.py`; see
    /// `Documentation/Terminal-compatibility.md`).
    @Test("Every frame of a pulsing row is compensated, not just the first")
    func replayedFramesKeepTheCompensation() throws {
        let (run, built) = try breathingRow(width: 40)
        #expect(
            built.contains(Self.cursorForward),
            "the BUILT row lost its compensation; this test is no longer about the replay")

        // The call the replay makes, on a writer told it is talking to
        // Terminal.app — which a test cannot arrange through `TerminalHost`,
        // whose answer is detected once from the process environment.
        let writer = FrameDiffWriter(
            isAppleTerminal: true, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
        for index in run.frames.indices {
            let patched = writer.patchingAnimatedRun(
                run, showing: run.frame(atIndex: index), in: built, bgCode: "")
            #expect(
                patched.contains(Self.cursorForward),
                "frame \(index) reached the terminal with the cluster uncompensated")
            // The other half of the same question: compensation buys nothing if
            // it moves the row's cells, because then the splice lands the
            // picture — and the border after it — in the wrong column.
            #expect(
                patched.strippedLength == built.strippedLength,
                """
                frame \(index) changed the row from \(built.strippedLength) \
                cells to \(patched.strippedLength)
                """)
        }
    }

    /// The compensation may not move any cell: it paints and steps, it does not
    /// write characters. If it did, the splice would land the run's picture —
    /// and everything after it — in the wrong column, which is the bug in the
    /// other direction.
    @Test("Compensating a frame does not change how many cells it claims")
    func compensationIsWidthNeutral() throws {
        let (run, _) = try breathingRow(width: 40)
        let writer = FrameDiffWriter(
            isAppleTerminal: true, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
        for index in run.frames.indices {
            let raw = run.frame(atIndex: index)
            #expect(
                writer.compensatingCursorAdvance(raw).strippedLength == raw.strippedLength,
                "frame \(index) changed width under compensation")
        }
    }

    /// A host with no measured advance model gets its bytes untouched — the
    /// `else` arm of the dispatch — so the shared entry point must not have
    /// quietly become "always compensate".
    @Test("A host with no advance model is left alone")
    func unmodelledHostsAreUntouched() throws {
        let (run, _) = try breathingRow(width: 40)
        let plain = FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
        let raw = run.frame(atIndex: 0)
        #expect(plain.compensatingCursorAdvance(raw) == raw)
    }

    /// The skin-tone half of Terminal.app's model reads the END of what it is
    /// given, and a run's frame ends where the run does, not where the row
    /// does. Told that the row continues, a cluster at the fragment's end takes
    /// the strip it would have taken as part of a whole row.
    @Test("A compensated fragment keeps the user's scalars and conserves the internal column")
    func fragmentsKeepScalarsAndConserve() {
        let writer = FrameDiffWriter(
            isAppleTerminal: true, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
        let cluster = "\u{270A}\u{1F3FB}"  // ✊🏻 — 2 cells; internal advance 4
        // The tone the user asked for is kept in every position. It used to be
        // stripped whenever the row continued past the cluster, which kept
        // Terminal.app's internal column in sync with the claim by deleting
        // what the user wrote; the walk now pulls the column back with CUB
        // instead, so the cluster survives and the row still cannot wrap.
        for fragment in [cluster, cluster + "x"] {
            let emitted = writer.compensatingCursorAdvance(fragment)
            #expect(emitted.unicodeScalars.contains("\u{1F3FB}"))
            #expect(emitted.contains("\u{1B}[2D"), "internal pulled back to the claim")
        }
    }
}

// MARK: - The row's background

@MainActor
@Suite("A replayed run keeps the row's background")
struct ReplayBackgroundTests {

    /// The page's background, as `buildLine` puts it back after every reset.
    private static let page = "\u{1B}[48;5;16m"

    /// A run over `columns` of a row, showing `frame` — nothing painted under it,
    /// so it sits on whatever page the row was built on.
    private static func run(_ frame: String, at columns: Range<Int>) -> AnimatedCellRun {
        AnimatedCellRun(
            offsetX: columns.lowerBound, offsetY: 0, width: columns.count, frames: [frame, ""],
            clock: .content)
    }

    /// The reported fault: the Animation page's breathing text drawn on a white
    /// band under Apple Terminal.
    ///
    /// Every styled fragment ends in `ESC[0m`, and a reset returns the terminal
    /// to ITS default — white on a light profile. A run's frame comes straight
    /// from the view, and this one OPENS with a reset, in the collapsed spelling
    /// (`ESC[0;…m`) that a search for the literal `ESC[0m` does not see. The
    /// splice restates, after every reset however it is spelled, the field under
    /// the next cell — the page, for a run nothing painted under — so the frame
    /// keeps the row's background.
    @Test("A run's frame keeps the page's background through a collapsed reset")
    func theFrameKeepsThePage() {
        let writer = FrameDiffWriter(
            isAppleTerminal: true, isITerm2: false, isGhostty: false, isWarp: false,
            isTmux: false)
        let row = Self.page + "\u{1B}[2K" + "aaaaa" + ANSIRenderer.reset
        let frame = "\u{1B}[0;38;5;34m" + "bb" + ANSIRenderer.reset
        let run = Self.run(frame, at: 1..<3)

        let bare = writer.patchingAnimatedRun(run, showing: frame, in: row, bgCode: "")
        #expect(
            paintedCells(bare)[1...2].allSatisfy { $0.background.isEmpty },
            "a row built on nothing gave the frame a field: \(bare.debugDescription)")

        let patched = writer.patchingAnimatedRun(run, showing: frame, in: row, bgCode: Self.page)
        #expect(
            paintedCells(patched).map(\.background) == Array(repeating: Self.page, count: 5),
            "the run's frame reached the row with no background: \(patched.debugDescription)")
        // And it does not move a cell — the whole point of the splice.
        #expect(patched.strippedLength == row.strippedLength)
    }

    /// The trailing reset is the other half: whatever follows the run on the row
    /// must not inherit the terminal's background either.
    @Test("The row continues in its background after the run")
    func theRowContinuesInTheBackground() {
        let writer = FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false,
            isTmux: false)
        let row = Self.page + "\u{1B}[2K" + "aaaaa" + ANSIRenderer.reset
        let frame = "\u{1B}[38;5;34m" + "bb" + ANSIRenderer.reset
        let patched = writer.patchingAnimatedRun(
            Self.run(frame, at: 1..<3), showing: frame, in: row, bgCode: Self.page)
        #expect(
            paintedCells(patched).map(\.background) == Array(repeating: Self.page, count: 5),
            "the row resumes in the terminal's background: \(patched.debugDescription)")
    }

    /// What restating the PAGE after every reset in the frame broke: a run inside
    /// a container that paints a background of its own.
    ///
    /// A compact tab chip nested in another tab's panel — `▐`, a label on the
    /// chip's own surface, `▌` — is three fragments with a reset after each, and
    /// both caps are ink with no field, drawn over the outer panel. Handed the
    /// page's background after every reset, the right cap came out in the page's
    /// colour inside the panel, while the left cap, before the first reset, kept
    /// the panel's. The run's ground records the panel, as the panel's
    /// `.background` recorded it (`AnimatedCellRun.ground`); the row is built by
    /// the writer on a page of another colour.
    @Test("A run in a container keeps the container's background after its own resets")
    func aRunKeepsItsContainersBackground() {
        let writer = FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false,
            isTmux: false)
        let panel = "\u{1B}[48;5;22m"
        let chip = "\u{1B}[48;5;28m"
        let row = writer.buildOutputLines(
            buffer: FrameBuffer(lines: ["ab" + panel + "  xx  " + ANSIRenderer.reset + "z"]),
            terminalWidth: 12, terminalHeight: 1, bgCode: Self.page, reset: ANSIRenderer.reset)[0]
        let frame =
            "\u{1B}[38;5;28m▐" + ANSIRenderer.reset
            + "\u{1B}[1;38;5;35m" + chip + "xx" + ANSIRenderer.reset
            + "\u{1B}[38;5;28m▌" + ANSIRenderer.reset
        let run = Self.run(frame, at: 3..<7).paintingGround {
            panel + $0 + ANSIRenderer.reset
        }

        let patched = writer.patchingAnimatedRun(run, showing: frame, in: row, bgCode: Self.page)
        let cells = paintedCells(patched).map(\.background)
        #expect(patched.stripped.hasPrefix("ab ▐xx▌ z"), "the run did not land: \(patched.stripped)")
        #expect(cells.count == 12, "the splice changed the row's width")
        guard cells.count == 12 else { return }
        #expect(cells[3] == panel, "the left cap left the panel: \(cells[3].debugDescription)")
        #expect(cells[4] == chip && cells[5] == chip, "the label lost the chip's own surface")
        #expect(cells[6] == panel, "the right cap left the panel: \(cells[6].debugDescription)")
        #expect(cells[2] == panel && cells[7] == panel, "the panel either side of the run moved")
        #expect(cells[0] == Self.page && cells[8] == Self.page, "the page either side of the panel moved")
    }
}
