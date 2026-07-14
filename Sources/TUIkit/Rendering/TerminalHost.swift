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

    /// Whether the host draws the emoji-repertoire chrome glyphs (⬛︎ / ⬜︎
    /// with the U+FE0E text-presentation selector) correctly: monochrome,
    /// theme-tintable, two cells, no row shear. Verified by eye on both
    /// hosts (iTerm2 evaluated 2026-07-13); terminals not on this allowlist
    /// get the universally-safe non-emoji glyphs instead — mis-measuring
    /// the selector shears the whole row (issue #9), so membership is
    /// earned by inspection, not assumed.
    static var supportsEmojiChrome: Bool { isAppleTerminal || isITerm2 }

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
}
