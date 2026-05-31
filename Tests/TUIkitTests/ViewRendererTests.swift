//  🖥️ TUIKit — Terminal UI Kit for Swift
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
