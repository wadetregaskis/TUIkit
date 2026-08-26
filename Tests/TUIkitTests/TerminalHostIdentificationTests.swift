//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHostIdentificationTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// Whether the host terminal is *identified* — which every other compensation
/// test takes as given, by injecting `isAppleTerminal:` directly into
/// `FrameDiffWriter`.
///
/// That gap is why an ssh session rendered emoji one cell short for every
/// cluster while 126 width and compensation tests passed: they all proved the
/// compensation correct *given* a known host, and nothing proved the host was
/// known. The last test here closes the loop the others leave open — from an
/// environment dictionary to the bytes on the wire.
@Suite("Terminal host identification")
struct TerminalHostIdentificationTests {

    /// The environment of a real `ssh` session into macOS from Terminal.app,
    /// captured verbatim (2026-08-26). The point of it is what is ABSENT:
    /// OpenSSH forwards `LANG` and `LC_*` only, so `TERM_PROGRAM` — the
    /// variable every terminal sets — does not survive the hop.
    private static let sshSession = [
        "LANG": "en_AU.UTF-8",
        "TERM": "xterm-256color",
        "SSH_CLIENT": "192.168.72.1 49252 22",
        "SSH_CONNECTION": "192.168.72.1 49252 192.168.72.4 22",
        "SSH_TTY": "/dev/ttys008",
        "SHELL": "/bin/zsh",
    ]

    @Test("An ssh session names no terminal, and TERM is not a substitute")
    func sshSessionNamesNothing() {
        let env = Self.sshSession
        #expect(TerminalHost.hostProgram(environment: env) == nil)
        #expect(!TerminalHost.detectAppleTerminal(environment: env))
        #expect(!TerminalHost.detectITerm2(environment: env))
        #expect(!TerminalHost.detectGhostty(environment: env))
        #expect(!TerminalHost.detectWarp(environment: env))
        #expect(!TerminalHost.detectTmux(environment: env))
    }

    @Test(
        "TUIKIT_TERM_PROGRAM names the host an ssh hop stripped",
        arguments: [
            ("Apple_Terminal", true, false, false, false),
            ("iTerm.app", false, true, false, false),
            ("ghostty", false, false, true, false),
            ("WarpTerminal", false, false, false, true),
        ])
    func overrideNamesTheHost(
        forced: String, apple: Bool, iterm: Bool, ghostty: Bool, warp: Bool
    ) {
        var env = Self.sshSession
        env["TUIKIT_TERM_PROGRAM"] = forced
        #expect(TerminalHost.detectAppleTerminal(environment: env) == apple)
        #expect(TerminalHost.detectITerm2(environment: env) == iterm)
        #expect(TerminalHost.detectGhostty(environment: env) == ghostty)
        #expect(TerminalHost.detectWarp(environment: env) == warp)
    }

    @Test("The override outranks a TERM_PROGRAM that disagrees with it")
    func overrideOutranksNative() {
        // The case this exists for: a terminal multiplexer, a wrapper, or a
        // remote shell that sets TERM_PROGRAM to something other than the
        // terminal actually painting the glyphs. The person who set the
        // override has said which one that is.
        let env = ["TERM_PROGRAM": "iTerm.app", "TUIKIT_TERM_PROGRAM": "Apple_Terminal"]
        #expect(TerminalHost.detectAppleTerminal(environment: env))
        #expect(!TerminalHost.detectITerm2(environment: env))
    }

    @Test("LC_TERMINAL carries iTerm2 across a hop, in its own vocabulary")
    func forwardedITerm2() {
        var env = Self.sshSession
        env["LC_TERMINAL"] = "iTerm2"  // NOT "iTerm.app" — the variable spells it differently
        #expect(TerminalHost.detectITerm2(environment: env))
        #expect(!TerminalHost.detectAppleTerminal(environment: env))
    }

    @Test("A local TERM_PROGRAM beats a forwarded LC_TERMINAL")
    func nativeBeatsForwarded() {
        // LC_TERMINAL survives an ssh hop, so it can arrive stale — exported by
        // an iTerm2 several hops back while the terminal actually painting this
        // session is something else, which said so locally.
        let env = ["TERM_PROGRAM": "ghostty", "LC_TERMINAL": "iTerm2"]
        #expect(TerminalHost.detectGhostty(environment: env))
        #expect(!TerminalHost.detectITerm2(environment: env))
    }

    @Test("An unmeasured LC_TERMINAL names nothing rather than guessing")
    func unknownForwardedNameIsNotGuessed() {
        let env = ["LC_TERMINAL": "SomeFutureTerminal"]
        #expect(TerminalHost.hostProgram(environment: env) == nil)
    }

    @Test("An empty value is not a name")
    func emptyValuesAreIgnored() {
        // An exported-but-empty variable must fall through to the next signal,
        // not mask it — `export TUIKIT_TERM_PROGRAM=` is a common way to
        // "unset" something in a shell profile.
        let env = ["TUIKIT_TERM_PROGRAM": "", "TERM_PROGRAM": "Apple_Terminal"]
        #expect(TerminalHost.detectAppleTerminal(environment: env))
        #expect(TerminalHost.hostProgram(environment: ["TERM_PROGRAM": ""]) == nil)
    }

    @Test("tmux is still recognised by $TMUX, and nameable by the override")
    func tmuxUnaffected() {
        #expect(TerminalHost.detectTmux(environment: ["TMUX": "/tmp/tmux-501/default,1,0"]))
        #expect(TerminalHost.detectTmux(environment: ["TUIKIT_TERM_PROGRAM": "tmux"]))
        #expect(!TerminalHost.detectTmux(environment: Self.sshSession))
    }

    // MARK: - Environment to bytes

    /// The link nothing else tests: an environment, through detection, into the
    /// bytes a row is written with.
    ///
    /// `🖥️` (U+1F5A5 U+FE0F) paints two cells on Terminal.app and advances the
    /// cursor by one, so its row needs `ESC[1C` after the glyph. Unidentified,
    /// the row goes out bare and everything after the emoji sits one cell left —
    /// which is exactly what an ssh session rendered, silently, while every
    /// compensation test passed.
    @Test("An identified host compensates the row an unidentified one leaves bare")
    @MainActor
    func environmentReachesTheWire() {
        func row(environment: [String: String]) -> String {
            let writer = FrameDiffWriter(
                isAppleTerminal: TerminalHost.detectAppleTerminal(environment: environment),
                isITerm2: TerminalHost.detectITerm2(environment: environment),
                isGhostty: TerminalHost.detectGhostty(environment: environment),
                isWarp: TerminalHost.detectWarp(environment: environment),
                isTmux: TerminalHost.detectTmux(environment: environment))
            return writer.buildOutputLines(
                buffer: FrameBuffer(text: "🖥️X"), terminalWidth: 8, terminalHeight: 1,
                bgCode: "", reset: "")[0]
        }

        let cursorForward = "\u{1B}[1C"
        // The state that shipped: an ssh session, no compensation, row shifted.
        #expect(!row(environment: Self.sshSession).contains(cursorForward))

        var named = Self.sshSession
        named["TUIKIT_TERM_PROGRAM"] = "Apple_Terminal"
        #expect(row(environment: named).contains(cursorForward))
        // And it is the same row a local Terminal.app would have produced.
        #expect(row(environment: named) == row(environment: ["TERM_PROGRAM": "Apple_Terminal"]))
    }
}
