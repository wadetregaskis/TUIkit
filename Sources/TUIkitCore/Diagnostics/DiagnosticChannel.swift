//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DiagnosticChannel.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Diagnostic channel

/// Where the framework's opt-in diagnostics are written.
///
/// One channel for every report the framework makes about the app rather than
/// for it, so a user who has pointed one diagnostic at a file has pointed them
/// all there. It lives in `TUIkitCore` so that every module can report through
/// it, whichever layer notices the problem.
package enum DiagnosticChannel {
    /// Where reports go. `TUIKIT_DIAGNOSTICS_FILE` names a file; otherwise
    /// stderr, matching `TUIKIT_DEBUG_RENDER`.
    ///
    /// A file is the better channel and the reason is the same one that makes
    /// this whole area awkward: a TUI owns the terminal, so stderr lands on the
    /// screen it is drawing unless the caller redirects — and under a PTY probe
    /// there is nothing to redirect *to*, since stderr and stdout are the same
    /// pseudo-terminal. A path sidesteps that entirely.
    ///
    /// Read once: the environment cannot change what a run already reported.
    package static let destination: String? =
        ProcessInfo.processInfo.environment["TUIKIT_DIAGNOSTICS_FILE"]

    /// Appends `text` wherever reports are configured to go.
    package static func emit(_ text: String) {
        emit(text, to: destination)
    }

    /// Appends `text` to the file at `destination`, creating it if need be, or
    /// writes it to stderr when `destination` is `nil`.
    ///
    /// The destination is a parameter so that the file path can be tested
    /// without setting the process's environment.
    package static func emit(_ text: String, to destination: String?) {
        guard let destination else {
            FileHandle.standardError.write(Data(text.utf8))
            return
        }
        if let handle = FileHandle(forWritingAtPath: destination) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(toFile: destination, atomically: true, encoding: .utf8)
        }
    }
}
