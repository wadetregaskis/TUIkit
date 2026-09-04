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
}
