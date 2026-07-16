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

import Foundation  // pid_t
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

    // MARK: - tmux wins over a native host flag that leaked into the pane

    @Test(
        "Under tmux, a leaked native-host flag changes NOTHING in the output",
        arguments: [
            // (isAppleTerminal, isITerm2, isGhostty, isWarp)
            (true, false, false, false),  // tmux < 3.2 from Apple Terminal: $TMUX set, TERM_PROGRAM=Apple_Terminal
            (false, true, false, false),  // a re-exported iTerm.app
            (false, false, true, false),  // ditto Ghostty
            (false, false, false, true),  // ditto Warp
        ] as [(Bool, Bool, Bool, Bool)])
    @MainActor
    func leakedNativeFlagIsInertUnderTmux(
        apple: Bool, iterm: Bool, ghostty: Bool, warp: Bool
    ) {
        // The bug: only the compensation dispatch checked isTmux. The right-edge
        // clip (FrameDiffWriter :297) and repaintRightEdge (:516) branched on the
        // bare native flag, so a pane where BOTH isTmux and a native flag are true
        // — a live case on tmux < 3.2, which never overwrote TERM_PROGRAM — applied
        // the outer terminal's advance model to tmux's grid.
        //
        // The invariant: under tmux, tmux owns the grid, so which native terminal
        // the flag names must make no difference to a single emitted byte.
        let pureTmux = FrameDiffWriter(
            isAppleTerminal: false, isITerm2: false, isGhostty: false, isWarp: false, isTmux: true)
        let leaked = FrameDiffWriter(
            isAppleTerminal: apple, isITerm2: iterm, isGhostty: ghostty, isWarp: warp, isTmux: true)

        // A line that fills to the right edge and ends in a cursor-advance quirk —
        // exactly what the Terminal.app clip and repaintRightEdge special-case, so
        // any leak of their behaviour shows up as a divergent line.
        for raw in [
            String(repeating: "x", count: 18) + "\u{1F919}\u{1F3FD}",  // …🤙🏽 at the edge
            String(repeating: "x", count: 18) + "\u{2B1B}\u{FE0E}",    // …⬛︎ VS-15 chrome
            "\u{261D}\u{1F3FD}" + String(repeating: "y", count: 16),   // ☝🏽 BMP skin tone
        ] {
            #expect(
                buildLine(leaked, raw: raw) == buildLine(pureTmux, raw: raw),
                "the native flag must be inert under tmux: \(raw.debugDescription)")
        }
    }

    /// Renders one raw line through the writer's real build path.
    @MainActor
    private func buildLine(_ writer: FrameDiffWriter, raw: String) -> String {
        var buffer = FrameBuffer(emptyWithWidth: 20, height: 1)
        buffer.lines = [raw]
        return writer.buildOutputLines(
            buffer: buffer, terminalWidth: 20, terminalHeight: 1,
            bgCode: "", reset: "\u{1B}[0m"
        ).joined()
    }

    // MARK: - Identifying the client terminal(s)

    /// A client that answered XTVERSION, so it needs no process to identify it.
    private static func talkative(_ termtype: String) -> TerminalHost.TmuxClient {
        TerminalHost.TmuxClient(termtype: termtype, pid: nil)
    }

    @Test(
        "Emoji chrome follows the attached client(s), and every one must be known",
        arguments: [
            // The single-client case — the common one, and the one that matters.
            (["iTerm2 3.6.11"], true, "iTerm2"),
            // Ghostty is allowlisted NATIVELY (our CUF patches its VS-15
            // under-advance) but not through tmux: no compensation can reach
            // the client, and tmux's re-emission of a VS-15 cell
            // (`base BS BS base+VS15`) nets advance 1 on Ghostty where tmux
            // believes 2 — measured, and observed as every toggle row shearing
            // left by one with the scrollbar checkering row by row.
            (["ghostty 1.3.1"], false, "Ghostty — correct natively, sheared through tmux"),
            (["Warp(v0.2026.07.08.17.54.stable_02)"], true, "Warp"),
            (["xterm"], false, "a terminal not on the allowlist"),
            // Silent AND unidentifiable — no pid here, so the process walk that
            // rescues a local Terminal.app has nothing to work with. This is a
            // terminal over ssh that answers no XTVERSION: genuinely unknown.
            ([""], false, "silent, and no process to identify it by"),
            // Several clients, each with its own font, painting the same bytes.
            (["iTerm2 3.6.11", "Warp(v0.2026)"], true, "two allowlisted clients"),
            (["iTerm2 3.6.11", ""], false, "one unknown among them spoils it"),
            (["iTerm2 3.6.11", "xterm"], false, "ditto for a known-bad one"),
            // Degenerate.
            (nil, false, "tmux could not be asked"),
            ([], false, "no clients attached"),
        ] as [([String]?, Bool, String)])
    func emojiChromeFollowsTheClients(termtypes: [String]?, expected: Bool, what: String) {
        let clients = termtypes?.map(Self.talkative)
        #expect(TerminalHost.emojiChromeSupported(tmuxClients: clients) == expected, "\(what)")
    }

    @Test("A newer version of a known client keeps its support")
    func versionsArePrefixMatched() {
        // Prefix-matched so a version bump doesn't silently downgrade the glyphs.
        #expect(TerminalHost.termtypeDrawsEmojiChrome("iTerm2 99.0"))
        #expect(TerminalHost.termtypeDrawsEmojiChrome("Warp(v2030.01.01)"))
        // And the through-tmux EXCLUSION is version-independent the same way:
        // no Ghostty version is assumed fixed until re-measured.
        #expect(!TerminalHost.termtypeDrawsEmojiChrome("ghostty 2.0.0-dev"))
    }

    @Test(
        "A silent client is identified by the application that owns it",
        arguments: [
            // The whole point: Terminal.app answers no XTVERSION, so under tmux
            // it used to be indistinguishable from an unknown terminal and lost
            // the emoji chrome it draws perfectly well. Its bundle names it.
            ("/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", true, "Terminal.app"),
            ("/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", true, "Terminal.app, pre-Ventura path"),
            // The other three answer XTVERSION so are normally caught earlier,
            // but a version that stayed silent should still be recognised.
            ("/Applications/iTerm.app/Contents/MacOS/iTerm2", true, "iTerm2"),
            // Excluded through tmux despite native support — see
            // termtypeDrawsEmojiChrome; ancestry must not re-admit it.
            ("/Applications/Ghostty.app/Contents/MacOS/ghostty", false, "Ghostty — sheared through tmux"),
            ("/Applications/Warp.app/Contents/MacOS/stable", true, "Warp"),
            // Not terminals we've inspected, or not terminals at all.
            ("/Applications/Alacritty.app/Contents/MacOS/alacritty", false, "a terminal not on the allowlist"),
            ("/usr/bin/login", false, "a process on the way up the chain"),
            ("/usr/sbin/sshd", false, "an ssh hop — the real terminal is elsewhere"),
            ("/bin/zsh", false, "a shell"),
            // The allowlist is anchored at a bundle boundary, so a name that
            // merely ENDS in an allowlisted one must not match.
            ("/Applications/My Terminal.app/Contents/MacOS/Terminal", false, "an impostor bundle"),
        ] as [(String, Bool, String)])
    func applicationsAreIdentifiedByTheirBundle(path: String, expected: Bool, what: String) {
        #expect(TerminalHost.applicationDrawsEmojiChrome(executablePath: path) == expected, "\(what)")
    }

    @Test("Walking up from a process that can't lead to a terminal ends, and says so")
    func theProcessWalkTerminates() {
        // launchd roots every chain and is not a terminal.
        #expect(TerminalHost.owningApplicationPath(ofTmuxClient: 1) == nil)
        // A client that exited between tmux answering and us asking.
        #expect(TerminalHost.owningApplicationPath(ofTmuxClient: 0x7FFF_FFFE) == nil)
        // Deliberately NOT asserted: the walk from our own pid. It finds
        // whatever terminal happens to be running the suite — Terminal.app on a
        // developer's machine, nothing at all in CI — so any expectation here
        // would be a coin toss. The live tmux probe covers the real chain.
    }

    @Test(
        "list-clients output parses to one client per line, pid first",
        arguments: [
            // tmux emits "#{client_pid} #{client_termtype}" per client,
            // newline-terminated. The termtype takes the rest of the line
            // because it contains spaces; the pid never does.
            ("32465 iTerm2 3.6.11\n", [(32465 as pid_t?, "iTerm2 3.6.11")]),
            // Apple Terminal: a real client, pid present, termtype empty. This
            // is the line that used to be written off as unknown.
            ("32465 \n", [(32465 as pid_t?, "")]),
            (
                "1 iTerm2 3.6.11\n2 ghostty 1.3.1\n",
                [(1 as pid_t?, "iTerm2 3.6.11"), (2 as pid_t?, "ghostty 1.3.1")]
            ),
            ("1 \n2 ghostty 1.3.1\n", [(1 as pid_t?, ""), (2 as pid_t?, "ghostty 1.3.1")]),
            ("", []),
            ("32465 iTerm2 3.6.11", [(32465 as pid_t?, "iTerm2 3.6.11")]),  // no trailing newline
            // A tmux too old to know `client_pid` leaves it empty rather than
            // wrong, and identification falls back to the termtype alone.
            (" iTerm2 3.6.11\n", [(nil as pid_t?, "iTerm2 3.6.11")]),
        ] as [(String, [(pid_t?, String)])])
    func clientListParsing(output: String, expected: [(pid_t?, String)]) {
        let parsed = TerminalHost.parseTmuxClients(output)
        #expect(parsed == expected.map { TerminalHost.TmuxClient(termtype: $0.1, pid: $0.0) })
    }
}
