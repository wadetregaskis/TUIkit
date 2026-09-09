//  🖥️ TUIkit — Terminal UI Kit for Swift
//  String+TerminalSanitizing.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Escape-sequence sanitising for untrusted content

extension String {
    /// Returns a copy with **every** ANSI escape sequence removed, suitable for
    /// rendering content this program did not author.
    ///
    /// Use this on anything a user (or a file, or the network) supplied before
    /// passing it to ``Text`` or any other view, so the content cannot drive the
    /// terminal:
    ///
    /// ```swift
    /// Text(userInput.sanitizedForTerminal)
    /// ```
    ///
    /// ## What it removes
    ///
    /// Every escape family ECMA-48 defines, in both their 7-bit (`ESC`-prefixed)
    /// and 8-bit (C1 control) spellings:
    ///
    /// | Family | 7-bit | 8-bit | Terminated by |
    /// |---|---|---|---|
    /// | CSI — cursor, colour, mode | `ESC [` | `U+009B` | a final byte `0x40…0x7E` |
    /// | OSC — window title, **clipboard writes** | `ESC ]` | `U+009D` | `BEL` or `ST` |
    /// | DCS — device control | `ESC P` | `U+0090` | `ST` |
    /// | APC / PM / SOS | `ESC _` / `ESC ^` / `ESC X` | `U+009F` / `U+009E` / `U+0098` | `ST` |
    /// | Two-byte escapes — `ESC c` (full reset), `ESC 7` / `ESC 8` | `ESC` + one byte | — | — |
    ///
    /// Every other C1 control is dropped too: they are never legitimate text.
    ///
    /// An unterminated sequence is consumed to the end of the string. Content
    /// after a truncated introducer is *inside* the sequence as far as the
    /// terminal is concerned, so leaving it visible would be the same leak by
    /// another route.
    ///
    /// ## What it deliberately leaves alone
    ///
    /// **C0 controls, including `\n`.** A newline is legitimate content — the
    /// text views break lines on it — so removing it here would corrupt ordinary
    /// input. Every C0 control that would move the cursor off its row is
    /// neutralised instead at the write boundary, by
    /// ``String/sanitizedForTerminalRow()``, which no view can bypass.
    ///
    /// ## Why this is not ``String/stripped``
    ///
    /// ``String/stripped`` answers a different question — "what does this
    /// paint?" — for width arithmetic, on output *this framework generated*.
    /// The two now share one rule for where a 7-bit sequence ends
    /// (`String.escapeBodyScan(_:on:)`), because they must: OSC 8
    /// hyperlinks put a string-terminated sequence into that output, and a
    /// measure that took the URI for text would budget columns nothing paints.
    ///
    /// Two things this still reaches that a measure does not, and the asymmetry
    /// is the point. The **8-bit C1 spellings** and the **two-byte escapes**
    /// (`ESC c`, `ESC 7`) cannot occur in output this framework generated, so
    /// recognising them would cost every measure — and every measure runs on
    /// the hot path of every layout pass — to catch a sequence that is not
    /// there. They can certainly occur in what a user pastes, which is what
    /// this is for: it runs once, at the app boundary, and has to assume
    /// hostility.
    ///
    /// - Returns: The string with all escape sequences removed; `self`
    ///   unchanged, without allocating, when there are none — the common case.
    public var sanitizedForTerminal: String {
        // Fast reject. An escape can only start at ESC (0x1B) or at a C1
        // control (U+0080…U+009F), and every C1 scalar encodes to UTF-8 as
        // 0xC2 followed by its low byte — so one contiguous byte scan for 0x1B
        // or 0xC2 clears a clean string without walking scalars at all.
        let mayHaveEscape =
            utf8.withContiguousStorageIfAvailable { buffer -> Bool in
                for byte in buffer where byte == 0x1B || byte == 0xC2 {
                    return true
                }
                return false
            } ?? unicodeScalars.contains { $0.value == 0x1B || (0x80...0x9F).contains($0.value) }
        guard mayHaveEscape else { return self }

        // The scanner mirrors the shape of `forEachVisibleANSIRun` — a single
        // forward pass over the scalar view, appending visible content as
        // borrowed slices — but recognises every introducer rather than CSI
        // alone. Scalar level, not `Character` level, for the same reason given
        // there: a terminator byte must never fuse with a following `Extend`
        // scalar into one `Character`, or the modifier is swallowed with the
        // escape.
        let scalars = unicodeScalars
        var result = ""
        result.reserveCapacity(utf8.count)

        var index = scalars.startIndex
        var runStart = index
        var hasRun = false
        var state = EscapeScanState.normal

        while index < scalars.endIndex {
            let value = scalars[index].value
            switch state {
            case .normal:
                if value == 0x1B {
                    if hasRun {
                        result += self[runStart..<index]
                        hasRun = false
                    }
                    state = .sawESC
                } else if let opened = Self.escapeState(openedByC1: value) {
                    if hasRun {
                        result += self[runStart..<index]
                        hasRun = false
                    }
                    state = opened
                } else if !hasRun {
                    runStart = index
                    hasRun = true
                }

            case .sawESC:
                switch value {
                case 0x5B:  // '[' — CSI
                    state = .csi
                case 0x5D, 0x50, 0x5F, 0x5E, 0x58:  // ']' 'P' '_' '^' 'X'
                    state = .string
                case 0x1B:  // ESC ESC — the first is dropped, re-dispatch
                    state = .sawESC
                case 0x20...0x2F:
                    // An nF escape's intermediate byte — `ESC ( B` (designate
                    // character set), `ESC % G` (select UTF-8). More may
                    // follow before the final byte.
                    state = .escIntermediate
                default:
                    // A two-byte escape: `ESC c` (RIS), `ESC 7` / `ESC 8`
                    // (save / restore cursor), and the rest of the Fp/Fs/Fe
                    // forms. The single following byte belongs to the escape,
                    // so it is consumed here and the next scalar starts fresh.
                    // An `ESC` at the very end of the string simply vanishes,
                    // having never left this state.
                    state = .normal
                }

            case .csi:
                if Self.isCSIBodyByte(value) {
                    break
                }
                if Self.isCSIFinalByte(value) {
                    state = .normal
                } else if value == 0x1B {  // ESC interrupts a malformed CSI
                    state = .sawESC
                } else {
                    // Not a CSI byte where a terminator was expected: the
                    // sequence is malformed, and this scalar is visible again.
                    runStart = index
                    hasRun = true
                    state = .normal
                }

            case .escIntermediate, .string, .stringSawESC:
                // An introducer opened inside an unterminated string is still
                // inside it as far as the terminal is concerned, so there is
                // nothing to dispatch on here — the shared body rule
                // (`String.escapeBodyScan(_:on:)`) says when the
                // sequence ends, and it is the same rule the width scanners
                // use. That is the point of sharing it: a sanitizer that
                // stopped in a different place from the measurer would leave
                // exactly the bytes the measurer had already discounted.
                state = Self.escapeBodyScan(state, on: value)
            }
            index = scalars.index(after: index)
        }
        // An unterminated sequence ends with the string and is dropped; only a
        // visible run still in progress survives.
        if hasRun {
            result += self[runStart..<index]
        }
        return result
    }

    /// The scanner state an 8-bit C1 introducer opens, or `nil` when `value` is
    /// not a C1 control at all.
    ///
    /// C1 controls carry no 7-bit `ESC` prefix; a terminal in 8-bit mode acts on
    /// them directly. They are never legitimate text, so a C1 scalar that
    /// introduces nothing — a stray `U+009C` (ST), say — still returns a state
    /// (`.normal`), which drops it rather than emitting it.
    fileprivate static func escapeState(openedByC1 value: UInt32) -> EscapeScanState? {
        switch value {
        case 0x9B: return .csi  // CSI
        case 0x9D, 0x90, 0x9F, 0x9E, 0x98: return .string  // OSC DCS APC PM SOS
        case 0x80...0x9F: return .normal  // any other C1: dropped, opens nothing
        default: return nil
        }
    }
}
