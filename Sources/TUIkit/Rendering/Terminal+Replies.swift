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
/// Swallowing one is right for the keyboard, and not the end of it: an answer
/// about the terminal's COLOURS is the only thing in the process that will ever
/// say what the terminal paints, and the startup exchange closes half a second
/// after it asks. So a reply that says something about them is kept here for the
/// run loop (``noteVolunteeredColorReply(_:)``), and everything else is dropped
/// as before.
///
/// Separate from `Terminal.swift` because that file is at its length limit,
/// and this is a coherent thing to lift out: what the terminal says that nobody
/// typed — how far one such sequence reaches, and which of them is worth keeping.
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
    /// Far larger than a keystroke because these are not keystrokes: a graphics
    /// error names itself in words (Warp's is sixty characters), and an OSC
    /// reply can carry a payload. Generous enough that no real reply is
    /// truncated, bounded so a terminal that starts a sequence and never ends
    /// it cannot pin the buffer.
    ///
    /// Both walks are bounded by it — this file's, and ``tryExtractCSI()`` in
    /// `Terminal+Input.swift`. A CSI is not only a key: DA, DSR and DECRPM
    /// answers arrive as CSIs, and the CSI walk's own 32-byte budget used to
    /// truncate a 37-byte device-attributes reply mid-sequence and leak its
    /// tail as typing.
    static let maxReplyBytes = 4096

    // MARK: - Keeping the answers that say what the terminal paints

    /// Keeps the complete escape sequence `bytes` when it answers a colour
    /// question, for the run loop to take.
    ///
    /// Told apart by ``TerminalColorQuery/isReply(_:)``, the rule the startup
    /// exchange keeps its own replies by: an OSC 10, 11 or 4 answer, well formed
    /// or not, and a `CSI ? 997 ; Ps n` appearance report. A graphics
    /// acknowledgement, a DA answer and everything else is not kept, and the
    /// parser drops it as it always has.
    ///
    /// The fence, `CSI 0 n`, is kept too, but apart — see ``takeStatusFence()``.
    /// It says nothing about a colour; it says a request has been answered as
    /// far as it is going to be, which is what `TerminalColorRequester` waits
    /// for before sending the next one.
    func noteVolunteeredColorReply(_ bytes: [UInt8]) {
        if TerminalColorQuery.isStatusFence(bytes[...]) {
            sawVolunteeredStatusFence = true
            return
        }
        guard TerminalColorQuery.isReply(bytes[...]) else { return }
        // A reply nobody takes cannot pin memory: this is dropped rather than
        // buffered forever, the same bargain ``maxReplyBytes`` makes.
        guard volunteeredColorReplies.count + bytes.count <= Self.maxVolunteeredReplyBytes else {
            return
        }
        volunteeredColorReplies.append(contentsOf: bytes)
    }

    /// The same, for the string-terminated sequence of `length` bytes at the head
    /// of the input buffer, before ``tryExtractRegularEvent()`` consumes it.
    ///
    /// Copied out only for an OSC, which is the only string-terminated family a
    /// colour answer comes in. A graphics acknowledgement is an APC and arrives
    /// for every image transmitted unless every one of them says `q=2`, so
    /// copying those out would pay an allocation a frame to learn nothing.
    func noteVolunteeredColorReply(headOfInputLength length: Int) {
        guard length > 1, input.count >= length, input[1] == 0x5D else { return }  // ESC ]
        var sequence: [UInt8] = []
        sequence.reserveCapacity(length)
        for index in 0..<length { sequence.append(input[index]) }
        noteVolunteeredColorReply(sequence)
    }

    /// Everything kept since the last call, emptying the buffer.
    ///
    /// The run loop takes these once per drain, so a burst of eighteen replies is
    /// parsed, published and repainted once. Empty on almost every frame.
    func takeVolunteeredColorReplies() -> [UInt8] {
        guard !volunteeredColorReplies.isEmpty else { return [] }
        defer { volunteeredColorReplies = [] }
        return volunteeredColorReplies
    }

    /// Whether a request's fence arrived since the last call, clearing it.
    ///
    /// A flag of its own rather than a sequence in ``takeVolunteeredColorReplies()``,
    /// because `TerminalColorQuery.parse` stops at the first fence, as the
    /// startup exchange's hand-back does: a fence among a drain's bytes would
    /// hide every reply behind it. Every measured host answers its fence last,
    /// but only because it answers everything it is going to answer first — a
    /// terminal silent on OSC 4 sends the fence with replies to nothing behind
    /// it, and under tmux those two can be half a second apart.
    func takeStatusFence() -> Bool {
        defer { sawVolunteeredStatusFence = false }
        return sawVolunteeredStatusFence
    }

    /// Hard cap on what is held for the run loop, past which a reply is dropped
    /// rather than buffered.
    ///
    /// A reply is about twenty-five bytes and a whole table is eighteen of them,
    /// so this is room for several tables — and a bound on a `Terminal` nobody
    /// drains, which is every `Terminal` outside an app run.
    static let maxVolunteeredReplyBytes = 4096
}
