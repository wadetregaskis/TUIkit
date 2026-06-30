//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TerminalInputParsingTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Split escape-sequence parsing
//
// The terminal sends arrows, mouse reports, focus events, device replies and
// bracketed paste as `ESC [ …` (CSI) or `ESC O …` (SS3) sequences. A `read()`
// boundary occasionally lands mid-sequence, so the parser sees a lone `ESC`
// first and its tail only on a later read. The lone `ESC` is ambiguous with the
// Escape key, so it times out after two stale frames — and the regression these
// tests pin is that the timed-out `ESC` must NOT strand its `[` / `O` introducer
// to be dispatched as a literal character (which intermittently jumped
// `TUIkitExample` to its `[` = Sliders page).
//
// The parser reads stdin directly, so these tests drive it through the
// injectable `readSource`, feeding bytes exactly when we choose to model the
// split precisely.

@MainActor
@Suite("Terminal split escape-sequence parsing")
struct TerminalInputParsingTests {

    /// A terminal whose byte source returns whatever the test has staged in
    /// `pending` at each drain (and 0 — "nothing yet" — when it's empty).
    /// Returns the terminal plus a setter to stage the next read's bytes.
    private func makeTerminal() -> (Terminal, ([UInt8]) -> Void) {
        let terminal = Terminal()
        let box = ByteBox()
        terminal.readSource = { buffer in
            guard !box.bytes.isEmpty else { return 0 }
            let count = min(box.bytes.count, buffer.count)
            for index in 0..<count { buffer[index] = box.bytes[index] }
            box.bytes.removeFirst(count)
            return count
        }
        return (terminal, { box.bytes.append(contentsOf: $0) })
    }

    /// Reference box so the read closure and the test share one byte queue.
    private final class ByteBox { var bytes: [UInt8] = [] }

    @Test("A CSI split at the ESC boundary parses as the real key, not '['")
    func splitCSIRecoversAsArrowNotBracket() {
        let (terminal, stage) = makeTerminal()

        // ESC arrives alone; its `[B` tail is still in flight.
        stage([0x1B])
        #expect(terminal.readEvent() == nil)  // partial — one stale frame
        #expect(terminal.readEvent() == nil)  // second stale frame → ESC deferred

        // The tail arrives now. The deferred ESC is re-attached and the whole
        // thing parses as Down — NOT Escape, and NOT a literal '[' (Sliders).
        stage([0x5B, 0x42])  // "[B"
        #expect(terminal.readEvent() == .key(KeyEvent(key: .down)))
    }

    @Test("A truncated ESC[ is dropped as a unit, never leaking '['")
    func truncatedCSINeverLeaksBracket() {
        let (terminal, stage) = makeTerminal()

        // ESC[ arrives together but the terminator never comes.
        stage([0x1B, 0x5B])
        var results: [TerminalInput?] = []
        for _ in 0..<4 { results.append(terminal.readEvent()) }

        // Nothing is surfaced, and crucially never a literal '['.
        #expect(results.allSatisfy { $0 == nil })
        #expect(!results.contains(.key(KeyEvent(character: "["))))
    }

    @Test("A genuine lone ESC still commits as the Escape key")
    func bareEscapeStillWorks() {
        let (terminal, stage) = makeTerminal()

        // Nothing ever follows the ESC.
        stage([0x1B])
        #expect(terminal.readEvent() == nil)  // stale frame 1
        #expect(terminal.readEvent() == nil)  // stale frame 2 → deferred
        #expect(terminal.readEvent() == .key(KeyEvent(key: .escape)))  // committed
    }

    @Test("A real lone '[' keystroke is still a literal '['")
    func literalBracketStillWorks() {
        let (terminal, stage) = makeTerminal()
        stage([0x5B])
        #expect(terminal.readEvent() == .key(KeyEvent(character: "[")))
    }

    @Test("A complete CSI delivered in one read is unaffected")
    func completeCSIUnaffected() {
        let (terminal, stage) = makeTerminal()
        stage([0x1B, 0x5B, 0x41])  // ESC [ A = Up
        #expect(terminal.readEvent() == .key(KeyEvent(key: .up)))
    }

    @Test("Escape followed (after the timeout) by a real key yields both")
    func escapeThenKeyYieldsBoth() {
        let (terminal, stage) = makeTerminal()

        stage([0x1B])
        #expect(terminal.readEvent() == nil)
        #expect(terminal.readEvent() == nil)  // ESC deferred

        // A non-introducer key arrives: the deferred Escape commits, then the key.
        stage([0x78])  // 'x'
        #expect(terminal.readEvent() == .key(KeyEvent(key: .escape)))
        #expect(terminal.readEvent() == .key(KeyEvent(character: "x")))
    }
}
