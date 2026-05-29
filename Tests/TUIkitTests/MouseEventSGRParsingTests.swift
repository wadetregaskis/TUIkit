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

    /// Left button press at column 1, row 1 → 0-indexed (0, 0).
    @Test("Left button press at origin parses to (0, 0)")
    func leftPressOrigin() {
        // ESC [ < 0 ; 1 ; 1 M
        let bytes: [UInt8] = [0x1B, 0x5B, 0x3C, 0x30, 0x3B, 0x31, 0x3B, 0x31, 0x4D]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == .left)
        #expect(event?.phase == .pressed)
        #expect(event?.x == 0)
        #expect(event?.y == 0)
    }

    /// Lowercase 'm' terminator marks a release.
    @Test("Lowercase m terminator parses as release")
    func releaseTerminator() {
        // ESC [ < 0 ; 5 ; 3 m
        let bytes: [UInt8] = [0x1B, 0x5B, 0x3C, 0x30, 0x3B, 0x35, 0x3B, 0x33, 0x6D]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == .left)
        #expect(event?.phase == .released)
        #expect(event?.x == 4)
        #expect(event?.y == 2)
    }

    /// Wheel up: button code 64.
    @Test("Scroll wheel up parses to .scrollUp")
    func scrollUp() {
        // ESC [ < 64 ; 1 ; 1 M
        let bytes: [UInt8] = [0x1B, 0x5B, 0x3C, 0x36, 0x34, 0x3B, 0x31, 0x3B, 0x31, 0x4D]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == .scrollUp)
        #expect(event?.phase == .scrolled)
    }

    /// Wheel down: button code 65 (64 + 1).
    @Test("Scroll wheel down parses to .scrollDown")
    func scrollDown() {
        // ESC [ < 65 ; 1 ; 1 M
        let bytes: [UInt8] = [0x1B, 0x5B, 0x3C, 0x36, 0x35, 0x3B, 0x31, 0x3B, 0x31, 0x4D]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == .scrollDown)
        #expect(event?.phase == .scrolled)
    }

    /// Motion with no button held: button code 35 (3 + 32).
    @Test("Motion with no button parses as moved")
    func motionNoButton() {
        // ESC [ < 35 ; 10 ; 5 M
        let bytes: [UInt8] = [
            0x1B, 0x5B, 0x3C, 0x33, 0x35, 0x3B, 0x31, 0x30, 0x3B, 0x35, 0x4D
        ]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == MouseButton.none)
        #expect(event?.phase == .moved)
        #expect(event?.x == 9)
        #expect(event?.y == 4)
    }

    /// Drag with left button: button code 32 (0 + 32 motion).
    @Test("Drag with left button parses as dragged + .left")
    func leftDrag() {
        // ESC [ < 32 ; 7 ; 4 M
        let bytes: [UInt8] = [
            0x1B, 0x5B, 0x3C, 0x33, 0x32, 0x3B, 0x37, 0x3B, 0x34, 0x4D
        ]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == .left)
        #expect(event?.phase == .dragged)
    }

    /// Shift modifier: button code 4 added.
    @Test("Shift modifier flag")
    func shiftModifier() {
        // ESC [ < 4 ; 1 ; 1 M  (button 0 + shift bit 4)
        let bytes: [UInt8] = [0x1B, 0x5B, 0x3C, 0x34, 0x3B, 0x31, 0x3B, 0x31, 0x4D]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.shift == true)
        #expect(event?.button == .left)
    }

    /// Malformed input returns nil.
    @Test("Malformed input returns nil")
    func malformed() {
        #expect(MouseEvent.parseSGR([0x41, 0x42]) == nil)
        // Wrong terminator.
        let bad: [UInt8] = [0x1B, 0x5B, 0x3C, 0x30, 0x3B, 0x31, 0x3B, 0x31, 0x58]
        #expect(MouseEvent.parseSGR(bad) == nil)
    }

    /// Three-digit coordinates — the longest realistic SGR sequence.
    ///
    /// Regression guard: `Terminal.readBytes` previously defaulted to
    /// an 8-byte buffer cap, which truncated mouse reports at the
    /// first digit and let the trailing bytes leak back as bogus
    /// ASCII keystrokes. Confirms the parser at least accepts the
    /// full sequence; the buffer-size fix lives in `Terminal.swift`.
    @Test("Three-digit coordinates parse correctly")
    func threeDigitCoords() {
        // ESC [ < 35 ; 120 ; 48 M  (15 bytes — would have been
        // truncated by the old 8-byte readBytes default).
        let bytes: [UInt8] = [
            0x1B, 0x5B, 0x3C,
            0x33, 0x35,   // "35"
            0x3B,
            0x31, 0x32, 0x30,  // "120"
            0x3B,
            0x34, 0x38,   // "48"
            0x4D,
        ]
        let event = MouseEvent.parseSGR(bytes)
        #expect(event?.button == MouseButton.none)
        #expect(event?.phase == .moved)
        #expect(event?.x == 119)
        #expect(event?.y == 47)
    }

    /// Truncated SGR mouse report must NOT be parsed as a successful
    /// event — the old 8-byte readBytes cap would deliver one of
    /// these to parseSGR and we want the parser to bail rather than
    /// invent coordinates.
    @Test("Truncated SGR sequence is rejected")
    func truncatedRejected() {
        // ESC [ < 35 ; 10  (8 bytes — no terminator at all).
        let truncated: [UInt8] = [
            0x1B, 0x5B, 0x3C, 0x33, 0x35, 0x3B, 0x31, 0x30,
        ]
        #expect(MouseEvent.parseSGR(truncated) == nil)
    }

    // MARK: - Legacy (X10) Mouse Parsing

    /// Legacy left-press at column 1, row 1 → 0-indexed (0, 0).
    @Test("Legacy left press at origin")
    func legacyLeftPress() {
        // ESC [ M  (0+32)  (1+32)  (1+32)  =  1B 5B 4D 20 21 21
        let bytes: [UInt8] = [0x1B, 0x5B, 0x4D, 0x20, 0x21, 0x21]
        let event = MouseEvent.parseLegacy(bytes)
        #expect(event?.button == .left)
        #expect(event?.phase == .pressed)
        #expect(event?.x == 0)
        #expect(event?.y == 0)
    }

    /// Legacy wheel up: button code 64, x=10, y=5.
    @Test("Legacy scroll wheel up")
    func legacyScrollUp() {
        // ESC [ M  (64+32)=96  (10+32)=42  (5+32)=37
        let bytes: [UInt8] = [0x1B, 0x5B, 0x4D, 0x60, 0x2A, 0x25]
        let event = MouseEvent.parseLegacy(bytes)
        #expect(event?.button == .scrollUp)
        #expect(event?.phase == .scrolled)
    }

    /// Legacy "any release" (button 3) at column 5, row 3.
    @Test("Legacy release maps to .released")
    func legacyRelease() {
        // ESC [ M  (3+32)=35  (5+32)=37  (3+32)=35
        let bytes: [UInt8] = [0x1B, 0x5B, 0x4D, 0x23, 0x25, 0x23]
        let event = MouseEvent.parseLegacy(bytes)
        #expect(event?.phase == .released)
        #expect(event?.x == 4)
        #expect(event?.y == 2)
    }

    /// Malformed (too short / wrong header) legacy bytes are rejected.
    @Test("Malformed legacy bytes are rejected")
    func legacyMalformed() {
        #expect(MouseEvent.parseLegacy([0x1B, 0x5B]) == nil)
        #expect(MouseEvent.parseLegacy([0x1B, 0x5B, 0x41, 0x20, 0x21, 0x21]) == nil)
    }
}
