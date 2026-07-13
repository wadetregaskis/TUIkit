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
}
