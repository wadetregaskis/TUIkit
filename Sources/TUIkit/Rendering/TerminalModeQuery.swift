//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalModeQuery.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// Asking a terminal whether a DEC private mode is set, and reading the answer.
///
/// Only one mode needs this today — 2027, grapheme clustering — and it needs it
/// for a specific reason: **TUIkit's Ghostty advance model is only valid while
/// mode 2027 is set.** Measured 2026-08-26 on Ghostty 1.3.1, resetting it moves
/// six of eleven probed classes:
///
/// | cluster | 2027 set | 2027 reset |
/// |---|---|---|
/// | 🖥️ VS-16 pictograph | 2 | **1** |
/// | ⬛︎ VS-15 chrome | 1 | **2** |
/// | 🇺🇸 flag pair | 2 | **4** |
/// | 👍🏽 skin tone | 2 | **4** |
/// | 👩‍🚀 ZWJ | 2 | **4** |
/// | 1️⃣ keycap | 2 | **1** |
///
/// In that state TUIkit's compensation is wrong in *both* directions: it emits
/// no CUF for a VS-16 cluster that now under-advances, and emits one for a
/// VS-15 glyph that no longer does. And the mode **persists across processes** —
/// measured by resetting it in one program and reading it back in another — so
/// any program that resets it and exits without restoring leaves every later
/// Ghostty session in a state this framework mis-describes.
///
/// ## Why this is not sent to everything
///
/// DECRQM is `CSI ? Ps $ p`: a private-parameter marker *and* an intermediate
/// byte, which is precisely the shape Apple Terminal's parser fails to consume —
/// it prints the final `p` on the user's screen. See
/// `Documentation/Terminal-compatibility.md`. So this is asked only of a host
/// already identified as one that answers it, never blind.
enum TerminalModeQuery {

    /// DEC mode 2027, "grapheme clustering": the terminal groups a UAX-#29
    /// cluster into one cell group and gives emoji presentation two columns.
    static let graphemeClustering = 2027

    /// A DECRPM reply value (`CSI ? Ps ; Pm $ y`).
    enum State: Int, Equatable {
        case notRecognised = 0
        case set = 1
        case reset = 2
        case permanentlySet = 3
        case permanentlyReset = 4

        /// Whether the terminal implements the mode at all. `notRecognised` and
        /// `permanentlyReset` both mean "asking for it will achieve nothing" —
        /// the universal reading of DECRPM, and what libvaxis and Bubble Tea
        /// both apply.
        var isSupported: Bool {
            switch self {
            case .set, .reset, .permanentlySet: true
            case .notRecognised, .permanentlyReset: false
            }
        }

        /// Whether the mode needs turning on: supported, and currently off.
        /// `permanentlySet` needs nothing; `permanentlyReset` cannot be helped.
        var needsSetting: Bool { self == .reset }
    }

    /// The query for `mode`, fenced with DSR so a terminal that ignores DECRQM
    /// reports silence instead of hanging — the same fence the identity query
    /// uses, and for the same reason.
    static func request(mode: Int) -> String {
        "\u{1B}[?\(mode)$p\u{1B}[6n"
    }

    /// The reply's `Pm`, or `nil` if `bytes` carries no DECRPM for `mode`.
    ///
    /// Silence is a real answer — a terminal that does not implement DECRQM
    /// answers the fence and nothing else — so this returning `nil` means "it
    /// did not say", which the caller must treat as "change nothing".
    static func parse(_ bytes: [UInt8], mode: Int) -> State? {
        let prefix = Array("\u{1B}[?\(mode);".utf8)
        var index = 0
        while index + prefix.count < bytes.count {
            guard Array(bytes[index..<(index + prefix.count)]) == prefix else {
                index += 1
                continue
            }
            var cursor = index + prefix.count
            var value = 0
            var sawDigit = false
            while cursor < bytes.count, bytes[cursor] >= 0x30, bytes[cursor] <= 0x39 {
                value = value * 10 + Int(bytes[cursor] - 0x30)
                sawDigit = true
                cursor += 1
            }
            // The reply ends `$ y`; anything else with this prefix is not one.
            guard sawDigit, cursor + 1 < bytes.count,
                bytes[cursor] == 0x24, bytes[cursor + 1] == 0x79
            else {
                index += 1
                continue
            }
            return State(rawValue: value)
        }
        return nil
    }

    /// Whether `bytes` contains a cursor-position report — the fence, which
    /// every terminal answers whether or not it understood the question.
    static func sawFence(_ bytes: [UInt8]) -> Bool {
        var index = 0
        while index + 1 < bytes.count {
            guard bytes[index] == 0x1B, bytes[index + 1] == 0x5B else {
                index += 1
                continue
            }
            var cursor = index + 2
            while cursor < bytes.count, !(0x40...0x7E).contains(bytes[cursor]) {
                cursor += 1
            }
            if cursor < bytes.count, bytes[cursor] == 0x52 { return true }  // 'R'
            index = cursor + 1
        }
        return false
    }
}

// MARK: - Asking, and pinning

extension Terminal {

    /// Asks whether a DEC private mode is set, or `nil` if the terminal did not
    /// say — which a terminal that does not implement DECRQM will not.
    ///
    /// Same shape as ``queryIdentity(timeout:)``: one write, then read until
    /// the DSR fence comes back or the deadline passes. Unlike it, a keystroke
    /// that arrives during the round trip is DISCARDED with the reply: handing
    /// it back needs the input buffer, which is private to the file that owns
    /// it. Only the identity exchange preserves them, and it is the one that
    /// runs before a host is known at all; this one runs on Ghostty alone, a
    /// sub-millisecond window at startup.
    func queryMode(_ mode: Int, timeout: Double = 0.5) -> TerminalModeQuery.State? {
        guard isatty(STDIN_FILENO) == 1, isRawMode else { return nil }

        writeImmediate(TerminalModeQuery.request(mode: mode))

        var collected: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 512)
        let deadline = Date().addingTimeInterval(timeout)
        while !TerminalModeQuery.sawFence(collected) {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, Int32(remaining * 1000)) > 0 else { break }
            let read = chunk.withUnsafeMutableBufferPointer { readSource($0) }
            guard read > 0 else { break }
            collected.append(contentsOf: chunk[0..<read])
        }
        return TerminalModeQuery.parse(collected, mode: mode)
    }

    /// Pins grapheme clustering on, for the one host whose advance model
    /// depends on it, and remembers to put it back.
    ///
    /// TUIkit's Ghostty model was measured with mode 2027 set, which is
    /// Ghostty's default — but the mode persists across processes, so a program
    /// that reset it and exited leaves later sessions in a state where six of
    /// eleven measured classes move and the compensation is wrong in both
    /// directions. See ``TerminalModeQuery`` for the table.
    ///
    /// Asked only of Ghostty, and only because DECRQM's `CSI ? Ps $ p` carries
    /// both a private marker and an intermediate byte — the shape Apple
    /// Terminal prints to the screen instead of consuming.
    ///
    /// Does nothing unless the terminal says the mode is supported and off, so
    /// silence, "not recognised" and "permanently reset" all leave it alone.
    func pinGraphemeClusteringIfNeeded() {
        guard TerminalHost.isGhostty, !TerminalHost.isTmux else { return }
        guard let state = queryMode(TerminalModeQuery.graphemeClustering),
            state.needsSetting
        else { return }
        writeImmediate("\u{1B}[?\(TerminalModeQuery.graphemeClustering)h")
        pinnedGraphemeClustering = true
    }
}
