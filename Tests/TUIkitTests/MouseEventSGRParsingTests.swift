//  🖥️ TUIKit — Terminal UI Kit for Swift
//  MouseEventSGRParsingTests.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Parser tests for SGR-encoded mouse-event escape sequences.
//  Extracted from MouseEventTests.swift to keep that file under
//  the 600-line lint threshold.

import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - SGR Parsing

@Suite("Mouse Event SGR Parsing")
struct MouseEventSGRParsingTests {

    /// SGR sequences (`ESC [ < b ; col ; row M/m`) that parse to a
    /// well-formed event. Coordinates are 1-based in the wire format
    /// and 0-based in the parsed event.
    @Test(
        "SGR sequences parse to the expected button, phase, and 0-based position",
        arguments: [
            // ESC [ < 0 ; 1 ; 1 M — left press at origin
            ([0x1B, 0x5B, 0x3C, 0x30, 0x3B, 0x31, 0x3B, 0x31, 0x4D] as [UInt8],
                MouseButton.left, MousePhase.pressed, 0, 0),
            // ESC [ < 0 ; 5 ; 3 m — lowercase m = release, col 5 row 3
            ([0x1B, 0x5B, 0x3C, 0x30, 0x3B, 0x35, 0x3B, 0x33, 0x6D],
                .left, .released, 4, 2),
            // ESC [ < 64 ; 1 ; 1 M — wheel up (button code 64)
            ([0x1B, 0x5B, 0x3C, 0x36, 0x34, 0x3B, 0x31, 0x3B, 0x31, 0x4D],
                .scrollUp, .scrolled, 0, 0),
            // ESC [ < 65 ; 1 ; 1 M — wheel down (64 + 1)
            ([0x1B, 0x5B, 0x3C, 0x36, 0x35, 0x3B, 0x31, 0x3B, 0x31, 0x4D],
                .scrollDown, .scrolled, 0, 0),
            // ESC [ < 35 ; 10 ; 5 M — motion with no button (3 + 32)
            ([0x1B, 0x5B, 0x3C, 0x33, 0x35, 0x3B, 0x31, 0x30, 0x3B, 0x35, 0x4D],
                MouseButton.none, .moved, 9, 4),
            // ESC [ < 32 ; 7 ; 4 M — drag with left button (0 + 32 motion)
            ([0x1B, 0x5B, 0x3C, 0x33, 0x32, 0x3B, 0x37, 0x3B, 0x34, 0x4D],
                .left, .dragged, 6, 3),
            // ESC [ < 35 ; 120 ; 48 M — three-digit coords. Regression
            // guard: Terminal.readBytes once capped at 8 bytes, which
            // truncated this report and leaked the tail as keystrokes.
            ([0x1B, 0x5B, 0x3C, 0x33, 0x35, 0x3B, 0x31, 0x32, 0x30, 0x3B, 0x34, 0x38, 0x4D],
                MouseButton.none, .moved, 119, 47),
        ])
    func parsesSGR(_ bytes: [UInt8], _ button: MouseButton, _ phase: MousePhase, _ x: Int, _ y: Int) {
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == button)
        #expect(event?.phase == phase)
        #expect(event?.x == x)
        #expect(event?.y == y)
    }

    /// Shift modifier: button code 0 + shift bit 4 → `ESC [ < 4 ; 1 ; 1 M`.
    @Test(
        "Horizontal wheel buttons 66/67 decode as left/right (xterm axis-in-button encoding)",
        arguments: [
            // macOS translates Shift+wheel into horizontal wheel deltas, so
            // iTerm2 reports Shift+wheel as 66/67 (+4 for the Shift flag).
            // Decoding these as vertical collapsed both directions into
            // .scrollDown, and the shift-scrolls-horizontally convention
            // then scrolled RIGHT for every tick.
            (Array("\u{1B}[<66;10;5M".utf8), MouseButton.scrollLeft, false),
            (Array("\u{1B}[<67;10;5M".utf8), MouseButton.scrollRight, false),
            (Array("\u{1B}[<70;10;5M".utf8), MouseButton.scrollLeft, true),   // 66+4 shift
            (Array("\u{1B}[<71;10;5M".utf8), MouseButton.scrollRight, true),  // 67+4 shift
            (Array("\u{1B}[<68;10;5M".utf8), MouseButton.scrollUp, true),     // 64+4 shift
            (Array("\u{1B}[<69;10;5M".utf8), MouseButton.scrollDown, true),   // 65+4 shift
        ])
    func parsesHorizontalWheel(_ bytes: [UInt8], _ button: MouseButton, _ shift: Bool) {
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == button)
        #expect(event?.phase == .scrolled)
        #expect(event?.shift == shift)
    }

    @Test("Legacy X10 horizontal wheel buttons decode as left/right too")
    func parsesLegacyHorizontalWheel() {
        // ESC [ M <button+32> <x+32> <y+32>; wheel-left = 66, wheel-right = 67.
        let left = MouseEvent.parseLegacy([0x1B, 0x5B, 0x4D, UInt8(66 + 32), 42, 38])
        let right = MouseEvent.parseLegacy([0x1B, 0x5B, 0x4D, UInt8(67 + 32), 42, 38])
        #expect(left?.button == .scrollLeft)
        #expect(right?.button == .scrollRight)
    }

    @Test("Shift modifier flag is decoded")
    func shiftModifier() {
        let bytes: [UInt8] = [0x1B, 0x5B, 0x3C, 0x34, 0x3B, 0x31, 0x3B, 0x31, 0x4D]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.shift == true)
        #expect(event?.button == .left)
    }

    /// Sequences that must be rejected (return `nil`): non-escape
    /// input, a wrong terminator, and a truncated report with no
    /// terminator (the old 8-byte readBytes cap would deliver these).
    @Test(
        "Malformed or truncated SGR sequences are rejected",
        arguments: [
            [0x41, 0x42] as [UInt8],  // not an escape sequence
            [0x1B, 0x5B, 0x3C, 0x30, 0x3B, 0x31, 0x3B, 0x31, 0x58],  // wrong terminator 'X'
            [0x1B, 0x5B, 0x3C, 0x33, 0x35, 0x3B, 0x31, 0x30],  // truncated, no terminator
        ])
    func rejectsSGR(_ bytes: [UInt8]) {
        #expect(MouseEvent.parseSGR(bytes) == nil)
    }

    // MARK: - Legacy (X10) Mouse Parsing

    /// Legacy `ESC [ M b col row` reports (each byte biased by +32).
    /// Button code 3 is "any release", which the parser attributes to
    /// `.left` so drag-capture can route it.
    @Test(
        "Legacy sequences parse to the expected button, phase, and 0-based position",
        arguments: [
            // ESC [ M (0+32)(1+32)(1+32) — left press at origin
            ([0x1B, 0x5B, 0x4D, 0x20, 0x21, 0x21] as [UInt8],
                MouseButton.left, MousePhase.pressed, 0, 0),
            // ESC [ M (64+32)(10+32)(5+32) — wheel up at col 10 row 5
            ([0x1B, 0x5B, 0x4D, 0x60, 0x2A, 0x25],
                .scrollUp, .scrolled, 9, 4),
            // ESC [ M (3+32)(5+32)(3+32) — "any release" at col 5 row 3
            ([0x1B, 0x5B, 0x4D, 0x23, 0x25, 0x23],
                .left, .released, 4, 2),
        ])
    func parsesLegacy(_ bytes: [UInt8], _ button: MouseButton, _ phase: MousePhase, _ x: Int, _ y: Int) {
        let event = MouseEvent.parseLegacy(bytes)
        #expect(event?.button == button)
        #expect(event?.phase == phase)
        #expect(event?.x == x)
        #expect(event?.y == y)
    }

    /// Too-short or wrong-header legacy byte runs are rejected.
    @Test(
        "Malformed legacy bytes are rejected",
        arguments: [
            [0x1B, 0x5B] as [UInt8],  // too short
            [0x1B, 0x5B, 0x41, 0x20, 0x21, 0x21],  // wrong third byte ('A', not 'M')
        ])
    func rejectsLegacy(_ bytes: [UInt8]) {
        #expect(MouseEvent.parseLegacy(bytes) == nil)
    }
}
