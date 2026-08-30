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
                in: built, with: run.frame(atIndex: index), atColumn: run.offsetX,
                width: run.width, terminalWidth: 40, bgCode: "")
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

    /// The reported fault: the Animation page's breathing text drawn on a white
    /// band under Apple Terminal.
    ///
    /// Every styled fragment ends in `ESC[0m`, and a reset returns the terminal
    /// to ITS default — white on a light profile. A rendered row has the page's
    /// background put back after every reset by `buildLine`; a run's frame comes
    /// straight from the view and is spliced into that row having been through
    /// nothing, so its own cells reset to the terminal's.
    @Test("A run's frame carries the page background into the row")
    func theFrameCarriesTheBackground() {
        let writer = FrameDiffWriter(
            isAppleTerminal: true, isITerm2: false, isGhostty: false, isWarp: false,
            isTmux: false)
        let background = "\u{1B}[48;5;16m"
        let row = background + "\u{1B}[2K" + "aaaaa" + ANSIRenderer.reset
        let frame = "\u{1B}[0;38;5;34m" + "bb" + ANSIRenderer.reset

        let bare = writer.patchingAnimatedRun(
            in: row, with: frame, atColumn: 1, width: 2, terminalWidth: 20, bgCode: "")
        #expect(!bare.contains("48;5;16m\u{1B}[38;5;34"), "nothing to restore without a bgCode")

        let patched = writer.patchingAnimatedRun(
            in: row, with: frame, atColumn: 1, width: 2, terminalWidth: 20, bgCode: background)
        // The run's OWN cells are painted with the page's background: the
        // collapsed reset the frame opens with is split apart, the background
        // put between the halves, and the two collapsed together again.
        #expect(
            patched.contains("48;5;16"),
            "the run's frame reached the row with no background: \(patched.debugDescription)")
        // And it does not move a cell — the whole point of the splice.
        #expect(patched.strippedLength == row.strippedLength)
    }

    /// The trailing reset is the other half: whatever follows the run on the row
    /// must not inherit the terminal's background either.
    @Test("The row continues in the page's background after the run")
    func theRowContinuesInTheBackground() {
        let writer = FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false,
            isTmux: false)
        let background = "\u{1B}[48;5;16m"
        let row = background + "\u{1B}[2K" + "aaaaa" + ANSIRenderer.reset
        let frame = "\u{1B}[38;5;34m" + "bb" + ANSIRenderer.reset
        let patched = writer.patchingAnimatedRun(
            in: row, with: frame, atColumn: 1, width: 2, terminalWidth: 20, bgCode: background)
        guard let end = patched.range(of: "bb") else {
            Issue.record("the run is not in the row: \(patched.debugDescription)")
            return
        }
        let after = String(patched[end.upperBound...])
        #expect(
            after.hasPrefix(ANSIRenderer.reset + background),
            "the row resumes in the terminal's background: \(after.debugDescription)")
    }
}
