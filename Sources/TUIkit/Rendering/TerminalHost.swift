//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TerminalHost.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

/// Identity of the terminal emulator hosting the process, detected once from
/// the environment.
///
/// Some rendering choices are terminal-specific rather than
/// capability-negotiable: Terminal.app mis-advances the cursor over emoji
/// (see ``FrameDiffWriter``, which carries workarounds gated on this), and
/// conversely draws emoji-repertoire glyphs like ⬛︎ as single seamless
/// multi-cell glyphs where adjacent FULL BLOCK cells show seams (see
/// ``CheckboxStyle/automatic``).
enum TerminalHost {
    /// Whether the host terminal is macOS Terminal.app, detected once from
    /// the process environment.
    static let isAppleTerminal: Bool =
        detectAppleTerminal(environment: ProcessInfo.processInfo.environment)

    /// Whether the host terminal is iTerm2, detected once from the process
    /// environment.
    static let isITerm2: Bool =
        detectITerm2(environment: ProcessInfo.processInfo.environment)

    /// Whether the host terminal is Ghostty, detected once from the process
    /// environment.
    static let isGhostty: Bool =
        detectGhostty(environment: ProcessInfo.processInfo.environment)

    /// Whether the host terminal is Warp, detected once from the process
    /// environment.
    static let isWarp: Bool =
        detectWarp(environment: ProcessInfo.processInfo.environment)

    /// Whether TUIkit is running inside tmux, detected once from the process
    /// environment.
    ///
    /// tmux is a **compositor**, not a passthrough: it parses our output into
    /// its own cell grid using its own width tables and re-renders that grid to
    /// whichever client is attached. So the host that matters is tmux — the
    /// outer terminal's advance quirks apply to *tmux's* output, not ours — and
    /// this must be checked BEFORE the four native detectors would otherwise
    /// win. In practice they cannot: tmux overwrites `TERM_PROGRAM` with its own
    /// name rather than forwarding the outer terminal's (measured, 3.7b), so
    /// running under tmux inside iTerm2 reports `tmux`, not `iTerm.app`.
    static let isTmux: Bool =
        detectTmux(environment: ProcessInfo.processInfo.environment)

    /// Whether the host draws the emoji-repertoire chrome glyphs (⬛︎ / ⬜︎
    /// with the U+FE0E text-presentation selector) correctly: monochrome,
    /// theme-tintable, two cells, no row shear. Verified by eye on every
    /// host listed (Apple Terminal + iTerm2 2026-07-13; Ghostty + Warp
    /// 2026-07-14); terminals not on this allowlist get the universally-safe
    /// non-emoji glyphs instead — mis-measuring the selector shears the whole
    /// row (issue #9), so membership is earned by inspection, not assumed.
    ///
    /// Ghostty qualifies only because ``String/withGhosttyCursorCompensation()``
    /// fixes it up: Ghostty PAINTS ⬛︎ two cells but advances the cursor by
    /// one, so uncompensated the label collides with the glyph (`■On`). Warp
    /// advances these correctly with no help.
    static var supportsEmojiChrome: Bool { isAppleTerminal || isITerm2 || isGhostty || isWarp }

    /// `true` only for macOS Terminal.app (`TERM_PROGRAM == "Apple_Terminal"`).
    /// Compile-time `false` off macOS, where Terminal.app cannot run.
    /// Parameterised over the environment so tests exercise both answers
    /// deterministically regardless of which terminal runs them.
    static func detectAppleTerminal(environment: [String: String]) -> Bool {
        #if os(macOS)
        return environment["TERM_PROGRAM"] == "Apple_Terminal"
        #else
        return false
        #endif
    }

    /// `true` for iTerm2 (`TERM_PROGRAM == "iTerm.app"`), on any platform it
    /// reports itself on (macOS natively; also over ssh with iTerm2's shell
    /// integration propagating the variable).
    static func detectITerm2(environment: [String: String]) -> Bool {
        environment["TERM_PROGRAM"] == "iTerm.app"
    }

    /// `true` for Ghostty (`TERM_PROGRAM == "ghostty"`), on any platform —
    /// Ghostty runs on macOS and Linux and sets the variable on both.
    ///
    /// Ghostty also ships its own terminfo and sets `TERM=xterm-ghostty`, but
    /// `TERM` is not the discriminator: it is routinely overridden to
    /// `xterm-256color` for compatibility with hosts lacking the entry, while
    /// `TERM_PROGRAM` survives.
    static func detectGhostty(environment: [String: String]) -> Bool {
        environment["TERM_PROGRAM"] == "ghostty"
    }

    /// `true` for Warp (`TERM_PROGRAM == "WarpTerminal"`), on any platform.
    ///
    /// Warp reports `TERM=xterm-256color`, so again only `TERM_PROGRAM`
    /// identifies it. (`WARP_TERMINAL_SESSION_UUID` and friends are also
    /// present, but `TERM_PROGRAM` is the stable, documented signal.)
    static func detectWarp(environment: [String: String]) -> Bool {
        environment["TERM_PROGRAM"] == "WarpTerminal"
    }

    /// `true` when running inside tmux, on any platform.
    ///
    /// `$TMUX` (the server socket path) is the primary signal: tmux always sets
    /// it for its panes and nothing else does, so it holds even on an ancient
    /// tmux. `TERM_PROGRAM == "tmux"` is the secondary signal — set since tmux
    /// 3.2 and the same variable the other hosts key off — and covers a pane
    /// whose `$TMUX` was scrubbed (a `env -u`, a `sudo`, some shell wrappers).
    /// Either alone is sufficient; both are checked because the cost of missing
    /// tmux is silently applying the wrong terminal's width model.
    ///
    /// `TERM` is deliberately NOT consulted: it is `tmux-256color` OR
    /// `screen-256color` depending on the user's `default-terminal`, and
    /// `screen*` is also what GNU screen sets — a different compositor with a
    /// different width table that this model does not describe.
    static func detectTmux(environment: [String: String]) -> Bool {
        if let socket = environment["TMUX"], !socket.isEmpty { return true }
        return environment["TERM_PROGRAM"] == "tmux"
    }

    // MARK: - tmux client identification

    /// Whether the terminals currently attached to a tmux session all draw the
    /// emoji chrome glyphs correctly, given what tmux reports each client to be.
    ///
    /// Under tmux the *glyph repertoire* is still the outer terminal's — tmux
    /// composites a grid but the client's font paints it — so the emoji-chrome
    /// question is the one thing that genuinely depends on which client is
    /// attached. (Widths do not: tmux's grid is client-independent, measured.)
    ///
    /// tmux asks each client for XTVERSION and exposes the reply as
    /// `#{client_termtype}` — "iTerm2 3.6.11", "ghostty 1.3.1",
    /// "Warp(v0.2026…)". Terminal.app answers nothing, so an EMPTY termtype is
    /// ambiguous: it is Terminal.app (allowlisted) or an unknown terminal that
    /// also stays silent (not). That ambiguity is unresolvable from here, so an
    /// empty reply is treated as unknown and loses the emoji chrome —
    /// conservative, because mis-measuring the selector shears the whole row
    /// (issue #9), and membership of this allowlist is earned by inspection.
    ///
    /// **Every** attached client must be recognised, not just the active one: a
    /// tmux session can have several clients at once, each with its own font,
    /// painting the same bytes. Requiring unanimity costs the common
    /// single-client case nothing and keeps a stray unknown client from getting
    /// glyphs it cannot draw.
    ///
    /// - Parameter termtypes: one entry per attached client, as
    ///   `#{client_termtype}` reports it. `nil` means the question could not be
    ///   asked; empty means no clients are attached (nothing to please).
    static func emojiChromeSupported(tmuxClientTermtypes termtypes: [String]?) -> Bool {
        guard let termtypes, !termtypes.isEmpty else { return false }
        return termtypes.allSatisfy { termtype in
            let lowered = termtype.lowercased()
            // Prefix-matched, so a version bump does not silently drop support.
            return lowered.hasPrefix("iterm2")
                || lowered.hasPrefix("ghostty")
                || lowered.hasPrefix("warp")
        }
    }

    /// Asks tmux what each attached client is, or `nil` when it cannot be asked.
    ///
    /// There is no in-band way to learn this: tmux overwrites `TERM_PROGRAM`
    /// with its own name, and the leaked per-terminal variables
    /// (`LC_TERMINAL`, `GHOSTTY_*`, …) are frozen at the environment of the
    /// client that STARTED the server — measured to still name Apple Terminal
    /// after iTerm2 attaches to the same session. Only tmux itself knows, and
    /// only by being asked. Hence a subprocess.
    ///
    /// **Cost:** one `fork`/`exec` per call, so callers MUST cache. It is not
    /// safe to call per frame, let alone per view. `RenderLoop` calls it once
    /// and re-probes only when the terminal resizes — which is what a detach or
    /// a re-attach from a different terminal looks like from in here.
    ///
    /// Fails closed: not under tmux, tmux missing from `PATH`, a non-zero exit
    /// or a hang all yield `nil`, which
    /// ``emojiChromeSupported(tmuxClientTermtypes:)`` reads as "unknown" and so
    /// as the safe non-emoji glyphs.
    static func probeTmuxClientTermtypes() -> [String]? {
        guard isTmux else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // One line per attached client; an unanswered XTVERSION is an empty line,
        // which `emojiChromeSupported` correctly reads as unknown.
        process.arguments = ["tmux", "list-clients", "-F", "#{client_termtype}"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil  // no tmux on PATH, or exec refused
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
            let output = String(data: data, encoding: .utf8)
        else { return nil }
        return parseTmuxClientTermtypes(output)
    }

    /// Splits `list-clients` output into one entry per attached client.
    ///
    /// Empty lines are kept — a client whose XTVERSION went unanswered
    /// (Terminal.app) reports an empty termtype and is still a client, and one
    /// that must be counted as unknown. Only the empty element the trailing
    /// newline leaves behind is dropped. Split out from the subprocess so the
    /// parsing is testable without one.
    static func parseTmuxClientTermtypes(_ output: String) -> [String] {
        // No output at all means no clients — distinct from one line that
        // happens to be empty, which IS a client (one that answered no
        // XTVERSION). Without this, `""` would split to a single empty element
        // and be miscounted as an attached unknown terminal.
        guard !output.isEmpty else { return [] }
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        let withoutTrailingNewlineArtefact = output.hasSuffix("\n") ? lines.dropLast() : lines[...]
        return withoutTrailingNewlineArtefact.map(String.init)
    }
}
