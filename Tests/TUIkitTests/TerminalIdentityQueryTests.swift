//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalIdentityQueryTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// Identifying the host from what it answers, rather than from an environment
/// variable ssh does not forward.
///
/// The stakes are asymmetric and the tests are written accordingly: failing to
/// identify Apple Terminal leaves rows shifted, but identifying the WRONG
/// terminal applies a compensation to a host that does not need it and breaks
/// rows that were fine. So every terminal below gets a "must not be named" test.
@Suite("Terminal identity query")
struct TerminalIdentityQueryTests {

    private static let fence = "\u{1B}[24;1R"

    private static func parse(_ stream: String) -> TerminalIdentity {
        TerminalIdentityQuery.parse(Array(stream.utf8))
    }

    private static func name(_ stream: String) -> String? {
        TerminalHost.nameFromDeviceAttributes(parse(stream))
    }

    // MARK: - The one host this names

    /// Measured 2026-08-26 with `Tools/TerminalProbes/identity_probe.py`,
    /// Terminal.app 455.1 on macOS 15.7, through an ssh hop.
    private static let appleTerminal = "\u{1B}[?1;2c" + "\u{1B}[>1;95;0c" + fence

    @Test("Apple Terminal's measured replies name it")
    func namesAppleTerminal() {
        let identity = Self.parse(Self.appleTerminal)
        #expect(identity.primaryAttributes == "\u{1B}[?1;2c")
        #expect(identity.secondaryAttributes == "\u{1B}[>1;95;0c")
        #expect(!identity.answeredVersion)
        #expect(identity.sawFence)
        #expect(TerminalHost.nameFromDeviceAttributes(identity) == "Apple_Terminal")
    }

    @Test("A firmware bump does not silently switch the compensation off")
    func firmwareFieldIsNotPinned() {
        // DA2's middle field is a version number by definition. Pinning it to
        // the measured 95 would mean a macOS update quietly returning every
        // emoji row to its shifted state — the exact failure this path exists
        // to end.
        #expect(Self.name("\u{1B}[?1;2c\u{1B}[>1;96;0c" + Self.fence) == "Apple_Terminal")
        #expect(Self.name("\u{1B}[?1;2c\u{1B}[>1;1000;0c" + Self.fence) == "Apple_Terminal")
    }

    // MARK: - The hosts it must not name

    @Test(
        "No other terminal is mistaken for Apple Terminal",
        arguments: [
            // Ghostty 1.3.1 — DA strings read from the shipped binary; answers
            // XTVERSION (Documentation/Terminal-compatibility.md).
            ("ghostty", "\u{1B}P>|ghostty 1.3.1\u{1B}\\\u{1B}[?62;22c\u{1B}[>1;10;0c"),
            // Warp — DA1 read from the shipped binary; answers XTVERSION.
            ("warp", "\u{1B}P>|Warp(v0.2026.07)\u{1B}\\\u{1B}[?62c\u{1B}[>0;95;0c"),
            // iTerm2 3.6.11 — answers XTVERSION; DA2 uses the `>%d;%d;0c`
            // format found in its binary.
            ("iterm2", "\u{1B}P>|iTerm2 3.6.11\u{1B}\\\u{1B}[?62;4c\u{1B}[>0;95;0c"),
            // GNU screen: the real collision risk for the DA1 clause — it also
            // reports VT100+AVO — but identifies as terminal type 83 ('S').
            // Compensating inside a multiplexer would corrupt its grid.
            ("screen", "\u{1B}[?1;2c\u{1B}[>83;40802;0c"),
            // xterm: terminal type 41, and a VT420-class DA1.
            ("xterm", "\u{1B}[?63;1;2;4;6;9;15;22;29c\u{1B}[>41;376;0c"),
            // A terminal that answers only the fence — the honest unknown.
            ("silent", ""),
        ])
    func namesNoOneElse(host: String, replies: String) {
        #expect(Self.name(replies + Self.fence) == nil, "\(host) must not be named Apple Terminal")
    }

    @Test("Each clause of the fingerprint is load-bearing")
    func everyClauseMatters() {
        // Drop one clause at a time from the real Apple Terminal answer; each
        // omission alone must be enough to withhold the name.
        #expect(Self.name("\u{1B}[?1;2c\u{1B}[>1;95;0c" + Self.fence) == "Apple_Terminal")
        // …but answering XTVERSION rules it out,
        #expect(
            Self.name("\u{1B}P>|Something 1.0\u{1B}\\\u{1B}[?1;2c\u{1B}[>1;95;0c" + Self.fence)
                == nil)
        // …as does any other DA1,
        #expect(Self.name("\u{1B}[?62;22c\u{1B}[>1;95;0c" + Self.fence) == nil)
        // …as does a missing DA1,
        #expect(Self.name("\u{1B}[>1;95;0c" + Self.fence) == nil)
        // …as does a missing or differently-shaped DA2.
        #expect(Self.name("\u{1B}[?1;2c" + Self.fence) == nil)
        #expect(Self.name("\u{1B}[?1;2c\u{1B}[>1;95;1c" + Self.fence) == nil)
    }

    // MARK: - Not eating the user's keystrokes

    @Test("Keystrokes that land during the exchange are handed back")
    func keystrokesArePreserved() {
        // Someone typing "q" and pressing Down while the app starts. Both are
        // bytes the input parser owns; the identity walk must not swallow them.
        let stream = "\u{1B}[?1;2c" + "q" + "\u{1B}[>1;95;0c" + "\u{1B}[B" + Self.fence
        let identity = Self.parse(stream)
        #expect(TerminalHost.nameFromDeviceAttributes(identity) == "Apple_Terminal")
        #expect(identity.unconsumed == Array("q\u{1B}[B".utf8))
    }

    @Test("Everything after the fence belongs to the input parser")
    func bytesAfterTheFenceAreNotOurs() {
        let identity = Self.parse(Self.appleTerminal + "hello")
        #expect(identity.unconsumed == Array("hello".utf8))
    }

    @Test(
        "A truncated reply is handed back rather than guessed at",
        arguments: [
            "\u{1B}",  // a bare ESC — a split sequence's first byte
            "\u{1B}[",  // CSI with nothing after it
            "\u{1B}[>1;95",  // a DA2 cut mid-parameters
            "\u{1B}P>|ghostty",  // a DCS with no terminator
        ])
    func truncatedRepliesAreReturned(partial: String) {
        let identity = Self.parse(partial)
        #expect(!identity.sawFence)
        #expect(identity.unconsumed == Array(partial.utf8))
        #expect(TerminalHost.nameFromDeviceAttributes(identity) == nil)
    }

    @Test("A DCS terminated by BEL is still an answer")
    func belTerminatedDCS() {
        // Not every terminal closes a DCS with ST; treating a BEL-terminated
        // one as unterminated would strand the rest of the buffer.
        let identity = Self.parse("\u{1B}P>|kitty 0.4\u{07}\u{1B}[?1;2c" + Self.fence)
        #expect(identity.answeredVersion)
        #expect(TerminalHost.nameFromDeviceAttributes(identity) == nil)
    }

    // MARK: - Through to the bytes

    @Test("An identified Apple Terminal compensates the row it was shifting")
    @MainActor
    func identificationReachesTheWire() {
        let discovered = Self.name(Self.appleTerminal)
        #expect(discovered == "Apple_Terminal")
        // The seed goes into the environment, so spell out what the detectors
        // then see rather than mutating this process's own.
        let environment = ["TUIKIT_TERM_PROGRAM": discovered ?? ""]
        let writer = FrameDiffWriter(
            isAppleTerminal: TerminalHost.detectAppleTerminal(environment: environment),
            isITerm2: false, isGhostty: false, isWarp: false, isTmux: false)
        let line = writer.buildOutputLines(
            buffer: FrameBuffer(text: "🖥️X"), terminalWidth: 8, terminalHeight: 1,
            bgCode: "", reset: "")[0]
        #expect(line.contains("\u{1B}[1C"))
    }

    @Test("setenv is visible through ProcessInfo, which the seed depends on")
    func seedingMechanismWorks() {
        // `seedDiscoveredHost` puts the discovered name in the process
        // environment so the existing `TerminalHost` detectors find it. That
        // rests on ProcessInfo not serving a cached snapshot — a scratch key,
        // not the real one, because writing the real one would leak into every
        // other suite in this process (the detectors are `static let`, and
        // whichever suite reads one first freezes it).
        let key = "TUIKIT_SEED_MECHANISM_PROBE"
        setenv(key, "Apple_Terminal", 1)
        defer { unsetenv(key) }
        #expect(ProcessInfo.processInfo.environment[key] == "Apple_Terminal")
    }

    /// Apple Terminal's CSI parser leaks a sequence's final byte onto the
    /// screen when the sequence carries BOTH a `?` private-parameter marker
    /// and an ECMA-48 intermediate byte (0x20…0x2F) — measured 2026-08-26 on
    /// 455.1 across all sixteen intermediates, with either half alone
    /// consumed correctly. See `Documentation/Terminal-compatibility.md`.
    ///
    /// The startup query runs before anything is on screen and its whole
    /// point is to be harmless to a terminal that answers none of it, so a
    /// leak here is a stray glyph in the user's shell. `CSI ? Ps $ p` —
    /// DECRQM, the way modes 2026 and 2027 are negotiated — is exactly the
    /// forbidden shape, which is the addition this guards against.
    @Test("No query carries both a private marker and an intermediate byte")
    func requestAvoidsAppleTerminalsCSILeak() {
        var offending: [String] = []
        let scalars = Array(TerminalIdentityQuery.request.unicodeScalars)
        var index = 0
        while index < scalars.count {
            guard scalars[index].value == 0x1B, index + 1 < scalars.count,
                scalars[index + 1] == "["
            else {
                index += 1
                continue
            }
            var cursor = index + 2
            var isPrivate = false
            var hasIntermediate = false
            while cursor < scalars.count {
                let value = scalars[cursor].value
                if (0x3C...0x3F).contains(value) { isPrivate = true }
                if (0x20...0x2F).contains(value) { hasIntermediate = true }
                if (0x40...0x7E).contains(value) { break }
                cursor += 1
            }
            if isPrivate && hasIntermediate {
                offending.append(String(String.UnicodeScalarView(scalars[index...min(cursor, scalars.count - 1)])))
            }
            index = cursor + 1
        }
        #expect(offending.isEmpty,
                "these leak their final byte on Apple Terminal: \(offending)")
    }
}
