//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ViewRendererTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Tests for `ViewRenderer`, the one-off renderer behind `renderOnce(_:)`.
///
/// It queries the terminal size, renders the view to a `FrameBuffer`,
/// and flushes the buffer line-by-line (moving the cursor before each
/// line). A `MockTerminal` is injected via the `TerminalProtocol`
/// parameter; it records cursor moves and captures every write
/// (including the cursor-positioning escape sequences, which strip to
/// empty visible text).
@MainActor
@Suite("ViewRenderer")
struct ViewRendererTests {

    private let sampleView = VStack {
        Text("one")
        Text("two")
    }

    /// The visible (ANSI-stripped) content lines written to the mock,
    /// dropping the empty strings the cursor-move sequences strip to.
    private func visibleWrites(_ mock: MockTerminal) -> [String] {
        mock.writtenOutput.compactMap {
            let stripped = $0.stripped
            return stripped.isEmpty ? nil : stripped
        }
    }

    /// The live pipeline neutralises a cursor-moving control at its write
    /// boundary; this one-off path is a second boundary and skipped it, so a
    /// tab in user data shoved the row to the next tab stop.
    @Test("A snapshot neutralises a control character in a row")
    func snapshotSanitisesControls() {
        let mock = MockTerminal()
        mock.size = (20, 4)
        let userData = "a\tb"
        ViewRenderer(terminal: mock).render(Text(userData))
        #expect(
            !mock.writtenOutput.contains { $0.unicodeScalars.contains("\u{09}") },
            "a tab reached the terminal raw")
        #expect(mock.outputContains("a b"))
    }

    /// A terminal that under-advances a glyph does so however the bytes were
    /// produced, and this path builds none of a frame: no diff, no reuse cache,
    /// no padding — and, until this was added, no advance model either. So a
    /// `renderOnce` snapshot containing `⚙️` put the rest of its line one cell
    /// to the left on Terminal.app, in exactly the way the animation replay did
    /// (`ReplayCursorCompensationTests`) and for exactly the same reason: it
    /// wrote content the writer never saw.
    @Test("A snapshot carries the host's cursor compensation")
    func snapshotsAreCompensated() throws {
        let mock = MockTerminal()
        mock.size = (30, 4)
        // The host is detected once from the process environment, so which
        // model is under test has to be said rather than arranged.
        let appleTerminal = FrameDiffWriter(
            isAppleTerminal: true, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)

        ViewRenderer(terminal: mock, writer: appleTerminal).render(Text("⚙️ settings"))

        let line = try #require(
            mock.writtenOutput.first { $0.unicodeScalars.contains("\u{2699}") },
            "no write carried the cluster at all")
        #expect(line.contains("\u{1B}[1C"), "the cluster reached the terminal bare")
    }

    /// …and a host with no measured model still gets its bytes untouched, so
    /// the line above is a compensation test and not a "compensate everything"
    /// test.
    @Test("A snapshot on an unmodelled host is written verbatim")
    func unmodelledHostsAreUntouched() {
        let mock = MockTerminal()
        mock.size = (30, 4)
        let plain = FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)

        ViewRenderer(terminal: mock, writer: plain).render(Text("⚙️ settings"))

        #expect(!mock.writtenOutput.contains { $0.contains("\u{1B}[1C") })
    }

    @Test("Renders without crashing and writes the view's content")
    func rendersContent() {
        let mock = MockTerminal()
        mock.size = (20, 6)

        // Regression guard: this used to crash because ViewRenderer
        // built a context with no stateStorage, which the render pass
        // force-unwraps.
        ViewRenderer(terminal: mock).render(sampleView)

        #expect(visibleWrites(mock) == ["one", "two"])
    }

    @Test("Positions each line at the default origin (row 1, column 1)")
    func positionsAtDefaultOrigin() {
        let mock = MockTerminal()
        mock.size = (20, 6)

        ViewRenderer(terminal: mock).render(sampleView)

        #expect(mock.cursorMoves.map(\.row) == [1, 2])
        #expect(mock.cursorMoves.allSatisfy { $0.column == 1 })
    }

    @Test("Offsets every line by the given row and column")
    func positionsAtOffset() {
        let mock = MockTerminal()
        mock.size = (20, 6)

        ViewRenderer(terminal: mock).render(sampleView, atRow: 5, column: 3)

        #expect(mock.cursorMoves.map(\.row) == [5, 6])
        #expect(mock.cursorMoves.allSatisfy { $0.column == 3 })
    }

    @Test("Queries the terminal size so a greedy layout fills it")
    func usesTerminalSize() {
        let mock = MockTerminal()
        mock.size = (40, 10)
        let greedy = VStack {
            Text("top")
            Spacer()
        }

        ViewRenderer(terminal: mock).render(greedy)

        // 10 lines of content area → 10 cursor moves, one per line.
        #expect(mock.cursorMoves.count == 10)
        #expect(mock.cursorMoves.map(\.row) == Array(1...10))
    }

    @Test("Snapshot render does not fire onAppear")
    func doesNotFireOnAppear() {
        final class Flag {
            var fired = false
        }
        let flag = Flag()
        let mock = MockTerminal()
        mock.size = (20, 6)
        let view = Text("hi").onAppear { flag.fired = true }

        ViewRenderer(terminal: mock).render(view)

        #expect(flag.fired == false, "a one-off snapshot must not fire onAppear")
        // …but the view still renders.
        #expect(visibleWrites(mock).contains { $0.contains("hi") })
    }

    /// A snapshot is a second screen root, and the root is where a displaced
    /// drawing lands: `.offset` paints NOTHING at its natural position and puts
    /// the glyphs in an `OverlayLayer`, so a flush that walked only
    /// `buffer.lines` wrote one empty row and the "A" reached the terminal
    /// never. Same mechanism for `.position`, `.popover`, `.sheet`, `.alert`.
    @Test("A snapshot composites a displaced drawing")
    func snapshotCompositesOverlayLayers() {
        let mock = MockTerminal()
        mock.size = (20, 4)

        ViewRenderer(terminal: mock).render(Text("A").offset(x: 2))

        // Column 2, which is the whole point of the offset: the composite pads
        // the one-cell placeholder out to three and inserts the layer at x = 2.
        // `stripped` removes ANSI and not whitespace, so this pins the COLUMN —
        // a composite at x = 0 still fails.
        #expect(visibleWrites(mock) == ["  A"])
    }

    /// …and the other half of the same root: `.opacity` records a region for a
    /// compositor to blend and leaves its cells at full strength, so a snapshot
    /// that resolved no region printed the faded row byte-for-byte identically
    /// to the unfaded one.
    ///
    /// Under a PINNED depth, because the assertion is that the row's colour
    /// changed and at ``ColorDepth/noColor`` a blend emits no colour at all —
    /// `Color.foregroundCodes()` returns `[]` there and `SGRState` deliberately
    /// does nothing with an empty list. Unpinned, this would pass in a
    /// developer's terminal and fail wherever `TERM=dumb`, which is what
    /// `ColorDepth.detect()` reads as `.noColor`.
    @Test("A snapshot resolves an opacity region")
    func snapshotResolvesOpacityRegions() throws {
        try withColorDepth(.truecolor) {
            let plain = MockTerminal()
            plain.size = (20, 4)
            let faded = MockTerminal()
            faded.size = (20, 4)

            ViewRenderer(terminal: plain).render(Text("faint"))
            ViewRenderer(terminal: faded).render(Text("faint").opacity(0.3))

            // The same glyphs — a fade is a colour, not a substitution …
            #expect(visibleWrites(faded) == visibleWrites(plain))
            // … and different bytes, because the blend names a colour 30% of the
            // way from the palette's foreground toward its background. The span
            // is uniform, so the escape lands once at column 0 and "faint" stays
            // contiguous.
            let fadedRow = try #require(faded.writtenOutput.first { $0.contains("faint") })
            let plainRow = try #require(plain.writtenOutput.first { $0.contains("faint") })
            #expect(fadedRow != plainRow, "the region was never resolved: \(fadedRow.debugDescription)")
        }
    }
}
