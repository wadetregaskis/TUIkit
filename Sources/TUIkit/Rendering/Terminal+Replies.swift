//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Terminal+Replies.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Things the terminal says that nobody typed

/// Terminals volunteer output on the input stream: a graphics acknowledgement,
/// an OSC colour answer, a DCS capability report. It arrives on stdin exactly
/// as a keystroke does, and it is not one — the input parser used to spell
/// `ESC _ G i=7;OK ESC \` out as Alt+underscore followed by `G i = 7 ; O K`,
/// and `=` is a shortcut on more than one page.
///
/// That was latent for as long as TUIkit only ever ASKED questions and read
/// the answers itself. It went live when the framework started sending
/// graphics commands, which are acknowledged unless every one of them carries
/// `q=2` — and "every one of them" is the kind of claim that holds until it
/// does not.
///
/// Separate from `Terminal.swift` because that file is at its length limit,
/// and this is a coherent thing to lift out: one question, asked of the head
/// of the input buffer.
extension Terminal {

    /// How many bytes the string-terminated sequence at the head of the input
    /// buffer occupies, or `nil` while its terminator has not arrived.
    ///
    /// OSC, DCS, APC, PM and SOS end at `BEL` or `ST` (`ESC \`) rather than at
    /// a final byte, which is why they cannot go through ``tryExtractCSI()``.
    ///
    /// A new `ESC` before the terminator means the sequence was truncated:
    /// only the malformed prefix is reported, so the sequence that interrupted
    /// it parses from its own `ESC`. That is the rule the CSI walk already
    /// applies, and for the same reason — anything else leaks the newcomer's
    /// bytes as keystrokes.
    func stringSequenceLength() -> Int? {
        var index = 2
        let cap = min(input.count, Self.maxReplyBytes)
        while index < cap {
            if input[index] == 0x07 { return index + 1 }  // BEL
            if input[index] == 0x1B {
                guard index + 1 < input.count else { return nil }  // ST's tail is still coming
                return input[index + 1] == 0x5C ? index + 2 : index
            }
            index += 1
        }
        // Past the cap it is not a reply any more, whatever it started as.
        return input.count >= Self.maxReplyBytes ? Self.maxReplyBytes : nil
    }

    /// Hard cap on a terminal reply, past which the bytes are dropped rather
    /// than buffered forever.
    ///
    /// Far larger than ``maxEventBytes`` because these are not events: a
    /// graphics error names itself in words (Warp's is sixty characters), and
    /// an OSC reply can carry a payload. Generous enough that no real reply is
    /// truncated, bounded so a terminal that starts a sequence and never ends
    /// it cannot pin the buffer.
    static let maxReplyBytes = 4096
}
