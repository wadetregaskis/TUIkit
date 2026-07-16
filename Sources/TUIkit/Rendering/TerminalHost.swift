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
}
