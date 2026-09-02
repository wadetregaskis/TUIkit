//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StringTerminalSanitizingTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkitCore

/// `sanitizedForTerminal` is the gate applications put untrusted content
/// through before handing it to a view. It used to be an alias for `stripped`,
/// which recognises **CSI only** — so every other escape family survived it:
/// an OSC clipboard write (`ESC ] 52 ; c ; …`) came out as the visible junk
/// `]52;c;…`, a DCS as `Pq…`, and `ESC c` (full terminal reset) as a stray `c`.
/// Losing the introducer meant the payload could not *execute*, so this was
/// never a live injection — but the API's whole contract is "this content
/// cannot drive the terminal", and printing the payload instead is not that.
///
/// These cover every family in both spellings, 7-bit `ESC`-prefixed and 8-bit
/// C1 — the latter passed through entirely untouched, and was counted as
/// visible width on the way.
@Suite("Terminal sanitising of untrusted content")
struct StringTerminalSanitizingTests {

    // MARK: - Every escape family disappears

    @Test(
        "Every escape family is removed whole",
        arguments: [
            // (input, what should remain)
            ("\u{1B}[31mred\u{1B}[0m", "red"),  // CSI, the case that always worked
            ("\u{1B}[?25lhi", "hi"),  // CSI, private parameter
            ("\u{1B}]52;c;aGVsbG8=\u{07}hi", "hi"),  // OSC clipboard write, BEL-terminated
            ("\u{1B}]0;title\u{1B}\\hi", "hi"),  // OSC window title, ST-terminated
            ("\u{1B}Pq#0;2;0;0;0\u{1B}\\hi", "hi"),  // DCS
            ("\u{1B}_payload\u{1B}\\hi", "hi"),  // APC
            ("\u{1B}^payload\u{1B}\\hi", "hi"),  // PM
            ("\u{1B}Xpayload\u{1B}\\hi", "hi"),  // SOS
            ("\u{1B}chi", "hi"),  // ESC c — RIS, a full terminal reset
            ("\u{1B}7hi\u{1B}8", "hi"),  // ESC 7 / ESC 8 — save / restore cursor
            ("\u{1B}(Bhi", "hi"),  // nF: designate character set
        ])
    func everyEscapeFamilyIsRemoved(input: String, expected: String) {
        #expect(input.sanitizedForTerminal == expected)
    }

    @Test(
        "The 8-bit spelling of each family is removed too",
        arguments: [
            ("\u{9B}31mred", "red"),  // CSI
            ("\u{9D}52;c;aGVsbG8=\u{07}hi", "hi"),  // OSC
            ("\u{90}q#0\u{9C}hi", "hi"),  // DCS, 8-bit ST
            ("\u{9F}payload\u{9C}hi", "hi"),  // APC
            ("\u{9E}payload\u{9C}hi", "hi"),  // PM
            ("\u{98}payload\u{9C}hi", "hi"),  // SOS
            ("hi\u{9C}", "hi"),  // a stray ST introduces nothing, and is not text
            ("hi\u{85}there", "hithere"),  // NEL: a C1 control, never content
        ])
    func eightBitSpellingsAreRemoved(input: String, expected: String) {
        #expect(input.sanitizedForTerminal == expected)
    }

    @Test(
        "What survives measures the cells it paints",
        arguments: [
            "\u{1B}]52;c;aGVsbG8=\u{07}", "\u{1B}Pq#0;2\u{1B}\\", "\u{1B}c", "\u{9B}31m",
            "\u{9D}0;title\u{07}",
        ])
    func removedSequencesOccupyNoCells(sequence: String) {
        let sanitized = sequence.sanitizedForTerminal
        #expect(sanitized.isEmpty, "\(sequence.debugDescription) left \(sanitized.debugDescription)")
        #expect(sanitized.strippedLength == 0)
    }

    // MARK: - Truncated sequences

    /// Content after an introducer with no terminator is *inside* the sequence
    /// as far as the terminal is concerned, so emitting it would be the same
    /// leak by another route. It goes with the sequence.
    @Test(
        "An unterminated sequence takes the rest of the string with it",
        arguments: [
            "before\u{1B}]52;c;never-closed",
            "before\u{1B}Pstill-open",
            "before\u{1B}[38;5;",
            "before\u{9B}38;5;",
        ])
    func unterminatedSequencesConsumeTheirTail(input: String) {
        #expect(input.sanitizedForTerminal == "before")
    }

    @Test("A trailing bare ESC simply vanishes")
    func trailingEscapeVanishes() {
        #expect("hi\u{1B}".sanitizedForTerminal == "hi")
    }

    /// An introducer opened *inside* an unterminated string sequence is still
    /// inside it — the terminal is consuming the string, not dispatching.
    @Test("A nested introducer does not re-open a visible run")
    func nestedIntroducerStaysSwallowed() {
        #expect("a\u{1B}]0;x\u{1B}[31mstill inside".sanitizedForTerminal == "a")
    }

    // MARK: - What it must not touch

    /// A newline is legitimate content — the text views break lines on it. C0
    /// controls that would move the cursor off its row are neutralised at the
    /// write boundary instead, by `sanitizedForTerminalRow()`.
    @Test("Newlines and other C0 controls are left for the row sanitiser")
    func c0ControlsAreLeftAlone() {
        #expect("one\ntwo".sanitizedForTerminal == "one\ntwo")
        #expect("a\tb".sanitizedForTerminal == "a\tb")
        #expect("safe\rEVIL".sanitizedForTerminal == "safe\rEVIL")
        // …and the row sanitiser is what makes those harmless on screen.
        #expect("safe\rEVIL".sanitizedForTerminalRow() == "safe EVIL")
    }

    @Test("Ordinary text is returned unchanged")
    func ordinaryTextIsUntouched() {
        for text in ["", "plain", "héllo wörld", "🎉 emoji 漢字", "a % b & c"] {
            #expect(text.sanitizedForTerminal == text)
        }
    }

    /// The fast path keys on the bytes `0x1B` and `0xC2` (every C1 scalar
    /// encodes as `0xC2` + its low byte). `0xC2` also leads two-byte scalars
    /// that are perfectly ordinary text — U+00A0…U+00FF — so the scan must be a
    /// *reject*, not a decision.
    @Test("Latin-1 text sharing the C1 lead byte is not mistaken for an escape")
    func latin1TextIsNotMistakenForC1() {
        for text in ["café", "naïve", "a\u{A0}b", "\u{FF}"] {
            #expect(text.sanitizedForTerminal == text)
        }
    }

    // MARK: - Its relationship to `stripped`

    /// The two agree about **7-bit escape families** and always must: OSC 8
    /// hyperlinks put a string-terminated sequence into output this framework
    /// generates, so a measure that took the URI for text would budget columns
    /// nothing paints. This pinned the opposite until 2026-09-02, when the two
    /// were given one shared rule for where a sequence ends
    /// (`String.escapeBodyScan(_:on:)`).
    @Test("stripped and the sanitiser agree about where a 7-bit escape ends")
    func strippedAgreesAboutEscapeFamilies() {
        for escaped in [
            "\u{1B}]0;title\u{07}visible",  // OSC, BEL-terminated
            "\u{1B}]8;;https://example.com\u{1B}\\visible",  // OSC 8, ST-terminated
            "\u{1B}P+q544e\u{1B}\\visible",  // DCS
            "\u{1B}(Bvisible",  // an nF escape and its final byte
        ] {
            #expect(escaped.sanitizedForTerminal == "visible")
            #expect(escaped.stripped == "visible")
            #expect(escaped.strippedLength == 7)
        }
        #expect("\u{1B}[31mred\u{1B}[0m".stripped == "red", "and it still handles CSI")
    }

    /// Where they still part company, and why each is right for its own job.
    ///
    /// The sanitiser is the untrusted-input gate: it assumes hostility, so it
    /// takes the 8-bit C1 spellings and the two-byte escapes as well. `stripped`
    /// runs on the hot path of every layout pass over output this framework
    /// generated — which contains neither — so recognising them would cost every
    /// measure to catch a sequence that cannot be there. The gap is closed by
    /// the gate, not by the measure.
    @Test("the sanitiser still reaches two things a measure does not")
    func sanitiserRemainsWider() {
        let c1 = "\u{9B}31mvisible"  // CSI in its 8-bit spelling
        #expect(c1.sanitizedForTerminal == "visible")
        #expect(c1.stripped != "visible", "stripped is not the untrusted-input gate")

        let twoByte = "\u{1B}cvisible"  // RIS — ESC and one following byte
        #expect(twoByte.sanitizedForTerminal == "visible")
        #expect(twoByte.stripped == "cvisible", "the ESC is dropped, the byte is text")
    }
}
