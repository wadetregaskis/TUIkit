//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TmuxCompatibilityTests.swift
//
//  Pins tmux 3.7b's DSR-measured cursor advance against TUIkit's width claims,
//  and the detection that selects it.
//
//  tmux is a COMPOSITOR: it parses our output into its own grid with its own
//  width table and re-renders to whichever client is attached. The measurement
//  behind these numbers was taken five ways — with Apple Terminal, iTerm2,
//  Ghostty and Warp attached, and with no client at all — and all five agree on
//  all 58 probed clusters, so this model is client-independent by measurement.
//  See Documentation/Terminal-compatibility.md.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@Suite("tmux compatibility")
struct TmuxCompatibilityTests {

    // MARK: - Detection

    @Test(
        "tmux is detected from $TMUX or TERM_PROGRAM, never from TERM",
        arguments: [
            // $TMUX alone is enough — holds even on a tmux too old to set
            // TERM_PROGRAM, and nothing else sets it.
            (["TMUX": "/private/tmp/tmux-501/default,123,0"], true),
            (["TERM_PROGRAM": "tmux"], true),
            (["TMUX": "/tmp/x,1,0", "TERM_PROGRAM": "tmux"], true),
            // A pane whose $TMUX was scrubbed still reports TERM_PROGRAM.
            (["TMUX": "", "TERM_PROGRAM": "tmux"], true),
            // Not tmux:
            ([:], false),
            (["TERM_PROGRAM": "iTerm.app"], false),
            (["TERM_PROGRAM": "Apple_Terminal"], false),
            (["TMUX": ""], false),
            // TERM must NOT be a signal: `screen-256color` is also GNU screen,
            // a different compositor with a different table.
            (["TERM": "tmux-256color"], false),
            (["TERM": "screen-256color"], false),
        ] as [([String: String], Bool)])
    func detection(environment: [String: String], expected: Bool) {
        #expect(TerminalHost.detectTmux(environment: environment) == expected)
    }

    @Test("tmux overwrites TERM_PROGRAM, so no native host is detected inside it")
    func tmuxMasksTheOuterTerminal() {
        // Measured: a pane inside tmux reports TERM_PROGRAM=tmux even when the
        // client is iTerm2 — tmux does not forward the outer terminal's value.
        let env = ["TERM_PROGRAM": "tmux", "TERM_PROGRAM_VERSION": "3.7b",
                   "TERM": "tmux-256color", "TMUX": "/tmp/s,1,0"]
        #expect(TerminalHost.detectTmux(environment: env))
        #expect(!TerminalHost.detectITerm2(environment: env))
        #expect(!TerminalHost.detectAppleTerminal(environment: env))
        #expect(!TerminalHost.detectGhostty(environment: env))
        #expect(!TerminalHost.detectWarp(environment: env))
    }

    // MARK: - The measured advance table

    @Test(
        "tmux under-advances these against TUIkit's 2-cell claim",
        arguments: [
            ("\u{100038}", "SF Symbol (Plane-16 PUA)"),
            ("\u{101867}", "Plane-16 PUA, lower"),
            ("\u{102446}", "Plane-16 PUA"),
            ("\u{1F5A5}", "bare 🖥 (Emoji=Yes, Presentation=No)"),
            ("\u{1F6E1}", "bare 🛡"),
            ("\u{1F579}", "bare 🕹"),
            ("\u{1F577}", "bare 🕷"),
            ("\u{1F39E}", "bare 🎞"),
            ("\u{1F3D9}", "bare 🏙"),
            ("\u{1F060}", "🁠 domino — Emoji=NO, so not a 'bare pictograph'"),
            ("\u{1F0A1}", "🂡 playing card — Emoji=NO"),
            ("\u{1F1E6}", "lone regional indicator"),
        ] as [(String, String)])
    func underAdvancers(text: String, what: String) {
        let character = Character(text)
        #expect(character.terminalWidth == 2, "\(what): TUIkit claims 2 cells")
        #expect(character.tmuxCursorAdvance == 1, "\(what): tmux advances only 1")
    }

    @Test(
        "tmux agrees with TUIkit on everything else",
        arguments: [
            ("a", 1, "ASCII"),
            ("中", 2, "CJK"),
            ("👍", 2, "emoji presentation"),
            ("\u{1F3FD}", 2, "standalone skin-tone swatch"),
            ("\u{23F0}", 2, "⏰ BMP emoji presentation"),
            ("\u{231A}", 2, "⌚ watch"),
            ("👍🏽", 2, "SMP base + skin tone — tmux joins these"),
            ("🇺🇸", 2, "flag pair"),
            ("👩‍🚀", 2, "ZWJ family"),
            ("e\u{301}", 1, "NFD combining"),
            ("\u{E0B0}", 1, "powerline"),
            ("█", 1, "block"),
            ("─", 1, "box drawing"),
            ("\u{2592}", 1, "shade"),
        ] as [(String, Int, String)])
    func agreements(text: String, expected: Int, what: String) {
        let character = Character(text)
        #expect(character.tmuxCursorAdvance == expected, "\(what)")
        #expect(character.terminalWidth == expected, "\(what): claim matches")
    }

    // MARK: - Compensation

    @Test("A CUF is injected after each under-advancer, and nowhere else")
    func compensationInjectsCUF() {
        // Three SF Symbols in a row: the exact shape of the example's
        // "Supports SF Symbols" box, whose right border landed 3 cells early.
        let symbols = "\u{100038}\u{101867}\u{102446}"
        let compensated = symbols.withTmuxCursorCompensation()
        let cufCount = compensated.components(separatedBy: "\u{1B}[1C").count - 1
        #expect(cufCount == 3, "one CUF per symbol, got \(cufCount)")

        // Plain text must be untouched — no cost, no corruption.
        #expect("hello world".withTmuxCursorCompensation() == "hello world")
        #expect("中文字".withTmuxCursorCompensation() == "中文字")
        #expect("👍🏽 ok".withTmuxCursorCompensation() == "👍🏽 ok")
    }

    @Test("The compensated run occupies exactly the width the layout claimed")
    func compensatedRunMatchesTheClaim() {
        // This is the invariant the border alignment actually depends on: after
        // compensation, tmux's cursor ends where TUIkit's layout expects it.
        for text in ["\u{100038}", "\u{1F5A5}", "\u{1F060}", "\u{1F1E6}",
                     "\u{100038}\u{101867}\u{102446}", "ab\u{1F5A5}cd"] {
            let claimed = text.reduce(0) { $0 + $1.terminalWidth }
            var advanced = 0
            var pendingCUF = 0
            var index = text.startIndex
            while index < text.endIndex {
                advanced += text[index].tmuxCursorAdvance
                index = text.index(after: index)
            }
            // Each injected CUF adds exactly one column.
            pendingCUF =
                text.withTmuxCursorCompensation()
                .components(separatedBy: "\u{1B}[1C").count - 1
            let scalars = text.unicodeScalars.map { String($0.value, radix: 16) }
            let message = "\(scalars): tmux advances \(advanced) + \(pendingCUF) CUF vs claim \(claimed)"
            #expect(advanced + pendingCUF == claimed, "\(message)")
        }
    }

    // MARK: - Skin tones: strip only what tmux actually gets wrong

    @Test(
        "A BMP-based skin tone is stripped — tmux over-advances those to 4",
        arguments: ["\u{270A}\u{1F3FB}", "\u{261D}\u{1F3FD}", "\u{261D}\u{FE0F}\u{1F3FD}"])
    func bmpBasedSkinTonesAreStripped(text: String) {
        let stripped = text.withSkinToneFallback(basePlane: .bmpOnly)
        #expect(
            !stripped.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) },
            "the modifier must go — tmux would give this cluster 4 cells against our 2")
        let advance = stripped.reduce(0) { $0 + $1.tmuxCursorAdvance }
        let claim = stripped.reduce(0) { $0 + $1.terminalWidth }
        #expect(advance == claim, "after the strip, tmux agrees with the claim")
    }

    @Test(
        "An SMP-based skin tone SURVIVES — tmux joins those correctly",
        arguments: [
            "\u{1F44D}\u{1F3FD}",                               // 👍🏽
            "\u{1F469}\u{1F3FD}\u{200D}\u{1F680}",              // 👩🏽‍🚀
            "\u{1F919}\u{1F3FD}",                               // 🤙🏽 (the main menu's)
        ])
    func smpBasedSkinTonesSurvive(text: String) {
        // The regression this guards: the tmux path first took the blanket
        // strip, so 👍🏽 was flattened to 👍 even though tmux allocates it
        // exactly the 2 cells we claim and every client renders it correctly.
        // Stripping a cluster the terminal gets RIGHT is a silent loss of the
        // user's content, not a compensation.
        let stripped = text.withSkinToneFallback(basePlane: .bmpOnly)
        #expect(stripped == text, "must pass through untouched")
        #expect(
            stripped.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) },
            "the skin tone must survive")
        let advance = stripped.reduce(0) { $0 + $1.tmuxCursorAdvance }
        #expect(advance == 2, "and tmux still advances it by the claimed 2")
    }

    @Test("The blanket strip still strips everything, for iTerm2 and Warp")
    func blanketStripIsUnchanged() {
        // `.all` is the default and must keep its old behaviour: iTerm2/Warp
        // split EVERY skin-tone cluster, SMP bases included.
        for text in ["\u{1F44D}\u{1F3FD}", "\u{270A}\u{1F3FB}", "\u{1F919}\u{1F3FD}"] {
            let stripped = text.withSkinToneFallback()
            #expect(
                !stripped.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) },
                "the default must still strip every base plane")
        }
    }

    @Test("A standalone swatch is content, and survives either way")
    func standaloneSwatchSurvives() {
        #expect("\u{1F3FD}".withSkinToneFallback(basePlane: .bmpOnly) == "\u{1F3FD}")
        #expect("\u{1F3FD}".withSkinToneFallback() == "\u{1F3FD}")
    }

    // MARK: - Identifying the client terminal(s)

    @Test(
        "Emoji chrome follows the attached client(s), and every one must be known",
        arguments: [
            // The single-client case — the common one, and the one that matters.
            (["iTerm2 3.6.11"], true, "iTerm2"),
            (["ghostty 1.3.1"], true, "Ghostty"),
            (["Warp(v0.2026.07.08.17.54.stable_02)"], true, "Warp"),
            // Terminal.app answers no XTVERSION, so an empty termtype is
            // ambiguous — Terminal.app, or an unknown terminal that is also
            // silent. Unresolvable, so: conservative.
            ([""], false, "Apple Terminal (empty) — indistinguishable from unknown"),
            (["xterm"], false, "a terminal not on the allowlist"),
            // Several clients, each with its own font, painting the same bytes.
            (["iTerm2 3.6.11", "ghostty 1.3.1"], true, "two allowlisted clients"),
            (["iTerm2 3.6.11", ""], false, "one unknown among them spoils it"),
            (["iTerm2 3.6.11", "xterm"], false, "ditto for a known-bad one"),
            // Degenerate.
            (nil, false, "tmux could not be asked"),
            ([], false, "no clients attached"),
        ] as [([String]?, Bool, String)])
    func emojiChromeFollowsTheClients(termtypes: [String]?, expected: Bool, what: String) {
        #expect(TerminalHost.emojiChromeSupported(tmuxClientTermtypes: termtypes) == expected, "\(what)")
    }

    @Test("A newer version of a known client keeps its support")
    func versionsArePrefixMatched() {
        // Prefix-matched so a version bump doesn't silently downgrade the glyphs.
        #expect(TerminalHost.emojiChromeSupported(tmuxClientTermtypes: ["iTerm2 99.0"]))
        #expect(TerminalHost.emojiChromeSupported(tmuxClientTermtypes: ["ghostty 2.0.0-dev"]))
        #expect(TerminalHost.emojiChromeSupported(tmuxClientTermtypes: ["Warp(v2030.01.01)"]))
    }

    @Test(
        "list-clients output parses to one entry per client",
        arguments: [
            // tmux emits one line per client, newline-terminated. The empty
            // line is Apple Terminal's unanswered XTVERSION — a real client.
            ("iTerm2 3.6.11\n", ["iTerm2 3.6.11"]),
            ("\n", [""]),
            ("iTerm2 3.6.11\nghostty 1.3.1\n", ["iTerm2 3.6.11", "ghostty 1.3.1"]),
            ("\nghostty 1.3.1\n", ["", "ghostty 1.3.1"]),
            ("", []),
            ("iTerm2 3.6.11", ["iTerm2 3.6.11"]),  // no trailing newline
        ] as [(String, [String])])
    func clientListParsing(output: String, expected: [String]) {
        #expect(TerminalHost.parseTmuxClientTermtypes(output) == expected)
    }
}
