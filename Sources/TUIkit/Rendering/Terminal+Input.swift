//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Terminal+Input.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Turning bytes from stdin into events

/// The input parser: bracketed paste, CSI / SS3 / meta sequences, mouse
/// reports, typed UTF-8, and the Escape-versus-sequence disambiguation that
/// holds a lone `ESC` for a round rather than committing it.
///
/// Split out of `Terminal.swift` because that file had reached its length
/// limit and this is the coherent half to lift: everything here reads and
/// consumes ``Terminal/input``, and nothing here writes to the terminal. The
/// state it works on has to stay on the type itself — an extension cannot hold
/// stored properties — which is why the buffer, the paste flag, the stale
/// counter and the two deferred-`ESC` flags are declared over there and are
/// module-internal rather than private. Nothing outside this module can see
/// ``Terminal`` at all.
extension Terminal {
    /// The bracketed-paste start marker (`ESC [ 2 0 0 ~`).
    private static let pasteStart: [UInt8] = [
        0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E,
    ]

    /// The bracketed-paste end marker (`ESC [ 2 0 1 ~`).
    private static let pasteEnd: [UInt8] = [
        0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E,
    ]

    /// Maximum bytes we'll accumulate while waiting for a paste end
    /// marker. Anything beyond this is treated as a misbehaving
    /// terminal and discarded so it can't pin memory forever.
    private static let maxPasteBytes = 1 << 20  // 1 MiB

    /// Whether `byte` turns a preceding `ESC` into the introducer of a
    /// sequence, rather than leaving that `ESC` standing as the Escape key:
    /// CSI `[`, SS3 `O`, or one of the string-terminated families' introducers
    /// (`] P X ^ _`).
    ///
    /// One copy of the rule because three places have to ask it — the two
    /// deferred-`ESC` re-attaches in ``readEvent()`` and the stale-partial arm
    /// in ``resolveStuckPartial()``. The re-attaches used to list only `[` and
    /// `O`, so a reply split across two `read()`s — its `ESC` in the first,
    /// `_Gi=1;OK ESC \` in the second — committed the Escape key and then
    /// typed the payload out, which is exactly what the string-family branch
    /// of ``tryExtractRegularEvent()`` exists to prevent.
    private static func continuesEscapeSequence(_ byte: UInt8) -> Bool {
        byte == 0x5B || byte == 0x4F || String.isStringFamilyIntroducer(UInt32(byte))
    }

    /// Stale frames before a lone `ESC` is committed (the Escape-vs-sequence
    /// timeout). Short, so Escape stays responsive.
    private static let bareEscStaleFrames = 2

    /// Stale frames of TOTAL silence before an unterminated bracketed paste is
    /// delivered anyway. At the loop's ~24 ms cadence this is about a second —
    /// far longer than any gap inside a real paste, which arrives as a
    /// continuous stream, and short enough that a user does not sit in front of
    /// an app that has stopped answering the keyboard.
    ///
    /// Without it the ONLY way out of paste mode was the end marker or the 1 MiB
    /// cap: a paste whose `ESC[201~` never arrived swallowed every subsequent
    /// keystroke into the paste buffer, forever, and the app looked frozen to
    /// input while still rendering.
    private static let stalledPasteStaleFrames = 40

    /// Stale frames before an incomplete `ESC [` / `ESC O` is abandoned as a
    /// dead sequence. Generous: a read-split sequence's tail arrives within a
    /// frame or two, so by the time we reach this any real terminator is long
    /// present — we only get here for a sequence the terminal truly never
    /// finished. Until then we keep waiting rather than stranding its bytes
    /// (the leak that turned a split mouse report's `M` into a keystroke).
    private static let deadSequenceStaleFrames = 8

    /// Tries to peel one complete regular (non-paste) event off the
    /// front of ``input``. Returns the raw bytes, or `nil` if
    /// the buffer doesn't have a complete sequence yet — in which
    /// case the bytes already there stay put for the next call.
    private func tryExtractRegularEvent() -> [UInt8]? {
        guard !input.isEmpty else { return nil }
        let first = input[0]

        // Plain (non-escape) byte: an ASCII event, or the lead of a multi-byte
        // UTF-8 character (typed é/ß/中/emoji — anything a keyboard layout or
        // IME produces beyond ASCII).
        if first != 0x1B {
            return tryExtractPlainText()
        }

        // ESC + ?  — need at least the byte after ESC.
        guard input.count >= 2 else { return nil }
        let second = input[1]

        if second == 0x5B {  // ESC [ = CSI
            return tryExtractCSI()
        }

        if second == 0x4F {  // ESC O = SS3 (F1-F4 etc.)
            guard input.count >= 3 else { return nil }
            let bytes = [first, second, input[2]]
            consume(3)
            return bytes
        }

        if second == 0x1B {
            // Meta-prefixed escape sequence ("option as meta key"): ESC + a
            // full CSI/SS3 sequence, e.g. Option-Shift-Tab = ESC ESC [ Z.
            // Consuming just the two ESCs here stranded the sequence's tail
            // as literal keystrokes — the `[` then fired a page shortcut.
            // Extract the INNER event and re-attach the meta prefix; if the
            // inner sequence hasn't fully arrived, put the prefix back and
            // wait (the stale-partial machinery handles a dead one).
            consume(1)
            if let inner = tryExtractRegularEvent() {
                return [0x1B] + inner
            }
            input.insert(0x1B, at: 0)
            return nil
        }

        // A reply the application never asked for — a graphics acknowledgement,
        // an OSC colour answer, a DCS report. These are OUTPUT the terminal
        // volunteered, and the parser used to hand them to the app as TYPING:
        // `ESC _ G i=7;OK ESC \` arrived as Alt+underscore followed by the
        // keystrokes `G i = 7 ; O K`, and `=` is a shortcut (zoom, on the image
        // pages) — so a single stray acknowledgement moved a control the user
        // never touched.
        //
        // It was always possible for a terminal to volunteer one. It became
        // likely when TUIkit started sending graphics commands, which are
        // acknowledged unless every one of them says `q=2`, and "every one" is
        // exactly the kind of thing that is true until it is not. Swallowing
        // the reply is right whether or not it was asked for: this parser reads
        // the keyboard, and nothing here is the keyboard.
        //
        // Recursion, like the meta-prefix branch above, and bounded by the same
        // thing: each pass consumes bytes, and the buffer is finite.
        if String.isStringFamilyIntroducer(UInt32(second)) {
            guard let length = stringSequenceLength() else { return nil }
            consume(length)
            return tryExtractRegularEvent()
        }

        // Alt + a multi-byte character: a meta-sending terminal prefixes
        // whatever the keyboard produced, ASCII or not (Option+ß under a
        // German layout arrives as ESC + the two bytes of ß). Same
        // put-the-prefix-back dance as the meta-escape path above when the
        // character's tail hasn't arrived yet.
        if second >= 0x80 {
            consume(1)
            if let inner = tryExtractPlainText() {
                return [0x1B] + inner
            }
            input.insert(0x1B, at: 0)
            return nil
        }

        // Alt+key — 2 bytes total.
        let bytes = [first, second]
        consume(2)

        return bytes
    }

    /// Peels one complete plain-text event off the front of the buffer: a
    /// single ASCII byte, or the full byte run of one multi-byte UTF-8
    /// scalar. Returns `nil` when a scalar's continuation bytes are still in
    /// flight (a split read — the stale-partial machinery bounds the wait,
    /// popping a truly stranded lead via its "any other stuck byte" arm).
    ///
    /// The old path consumed ONE byte unconditionally, and
    /// `KeyEvent.parseSingleByte` returns nil for anything ≥ 0x80 — so every
    /// non-ASCII character a user typed was discarded byte by byte. The
    /// multi-byte branch in `KeyEvent.parse` existed but was unreachable from
    /// the live parser; only bracketed paste could deliver non-ASCII text.
    ///
    /// Malformed bytes (an orphan continuation, an overlong or out-of-range
    /// lead, a lead whose followers aren't continuations) are dropped one at
    /// a time in the loop, so garbage can't swallow the innocent bytes after
    /// it — and can't recurse either, which a self-call here would on a long
    /// garbage run.
    private func tryExtractPlainText() -> [UInt8]? {
        while !input.isEmpty, input[0] != 0x1B {
            let first = input[0]
            if first < 0x80 {
                consume(1)
                return [first]
            }
            guard let length = Self.utf8SequenceLength(lead: first) else {
                consume(1)  // orphan continuation / invalid lead: drop it
                continue
            }
            guard input.count >= length else { return nil }  // tail in flight
            var isValid = true
            for index in 1..<length where input[index] & 0xC0 != 0x80 {
                isValid = false
                break
            }
            guard isValid else {
                consume(1)  // mis-framed lead: drop it, re-parse what follows
                continue
            }
            var bytes = [UInt8]()
            bytes.reserveCapacity(length)
            for index in 0..<length { bytes.append(input[index]) }
            consume(length)
            return bytes
        }
        // Empty, or dropping garbage uncovered an ESC — the next call's
        // escape paths own that.
        return nil
    }

    /// The byte length of the UTF-8 sequence this lead byte begins, or `nil`
    /// when it cannot begin one (a bare continuation byte, the overlong
    /// C0/C1 leads, or leads beyond U+10FFFF's F4).
    private static func utf8SequenceLength(lead: UInt8) -> Int? {
        switch lead {
        case 0x00...0x7F: return 1
        case 0xC2...0xDF: return 2
        case 0xE0...0xEF: return 3
        case 0xF0...0xF4: return 4
        default: return nil
        }
    }

    /// CSI extractor — assumes `input` starts with `ESC [`
    /// and the buffer has at least 2 bytes. Returns the full
    /// sequence bytes on success or `nil` if the terminator hasn't
    /// arrived yet.
    private func tryExtractCSI() -> [UInt8]? {
        guard input.count >= 3 else { return nil }
        let firstParam = input[2]

        // Legacy ("X10") mouse: ESC [ M <button+32> <x+32> <y+32>
        // M is the *introducer*, not the terminator, and the three
        // trailing coord bytes can take any value, so we just
        // require six bytes total.
        if firstParam == 0x4D {
            guard input.count >= 6 else { return nil }
            var bytes = [UInt8]()
            bytes.reserveCapacity(6)
            for i in 0..<6 { bytes.append(input[i]) }
            consume(6)
            return bytes
        }

        // Single-letter CSI (e.g. ESC[A for Up Arrow): the first
        // byte after `[` is already a terminator.
        if firstParam >= 0x40 && firstParam <= 0x7E {
            let bytes = [input[0], input[1], firstParam]
            consume(3)
            return bytes
        }

        // Scan forward for a real terminator (letter or `~`).
        //
        // Bounded by ``maxReplyBytes``, NOT by a keystroke-sized budget: a CSI
        // is not only a key. DA, DSR and DECRPM answers are CSIs too, and a
        // real xterm-class `ESC[?63;1;2;4;6;9;15;16;18;21;22;28;29c` is 37
        // bytes. The old 32-byte cap truncated it and RETURNED the prefix,
        // which the key parser then discarded — stranding `8;29c` at the head
        // of the buffer with no `ESC` in front of it, to be typed out as five
        // keystrokes.
        var i = 3
        let cap = min(input.count, Self.maxReplyBytes)

        while i < cap {
            let b = input[i]
            if b == 0x1B {
                // A new escape sequence started before this one terminated, so
                // this one was truncated (its terminator never arrived). Drop
                // just the malformed prefix and let the new sequence parse from
                // its `ESC` — otherwise its `[` would be mistaken for this
                // sequence's terminator and the rest would leak as keystrokes.
                consume(i)
                return nil
            }
            if b >= 0x40 && b <= 0x7E {
                var bytes = [UInt8]()
                bytes.reserveCapacity(i + 1)
                for j in 0...i { bytes.append(input[j]) }
                consume(i + 1)
                return bytes
            }
            i += 1
        }

        // Past the cap with no terminator: not a control sequence any more,
        // whatever it started as. DROP the prefix rather than returning it —
        // returning is what leaked the tail, because the caller only ever
        // discards bytes it cannot parse, while `consume` has already moved
        // the buffer past them.
        if input.count >= Self.maxReplyBytes { consume(Self.maxReplyBytes) }

        // Otherwise the buffer simply doesn't have the terminator yet. (The
        // wait is bounded by `deadSequenceStaleFrames`, not by the cap: the cap
        // only catches a terminal that keeps sending, since bytes arriving keep
        // resetting the stale count.)
        return nil
    }

    /// While `inPasteMode` is set, scans ``input`` for the
    /// paste end marker. If found, builds a paste event from the
    /// content between markers and consumes through the end marker.
    /// Otherwise returns `nil` and leaves the buffer intact.
    private func tryExtractPaste() -> TerminalInput? {
        let endMarker = Self.pasteEnd
        guard input.count >= endMarker.count else { return nil }

        // Scan for the end marker. Note: the start marker is no
        // longer in the buffer — `readEvent()` consumed it before
        // setting `inPasteMode = true`.
        let searchEnd = input.count - endMarker.count + 1
        for start in 0..<searchEnd {
            var match = true
            for i in 0..<endMarker.count where input[start + i] != endMarker[i] {
                match = false
                break
            }
            if !match { continue }

            // Content is everything before the marker.
            var content = [UInt8]()
            content.reserveCapacity(start)
            for i in 0..<start { content.append(input[i]) }
            consume(start + endMarker.count)
            inPasteMode = false

            let text = String(bytes: content, encoding: .utf8)
                ?? String(content.map { Character(UnicodeScalar($0)) })
            return .key(KeyEvent(key: .paste(text)))
        }

        // No end marker yet. Safety: if a runaway paste fills more
        // than the cap, give up on it so we don't pin memory.
        if input.count > Self.maxPasteBytes {
            consume(input.count)
            inPasteMode = false
        }
        return nil
    }

    /// Ends a paste whose end marker never arrived, delivering whatever was
    /// buffered as the paste it evidently was.
    ///
    /// Delivering beats discarding: the bytes are the user's pasted text, and
    /// the alternative to both is the wedge this exists to prevent. An empty
    /// buffer just leaves paste mode — there is nothing to deliver, and a paste
    /// event carrying "" would be noise.
    private func abandonStalledPaste() -> TerminalInput? {
        inPasteMode = false
        guard !input.isEmpty else { return nil }

        var content = [UInt8]()
        content.reserveCapacity(input.count)
        for index in 0..<input.count { content.append(input[index]) }
        consume(input.count)

        let text = String(bytes: content, encoding: .utf8)
            ?? String(content.map { Character(UnicodeScalar($0)) })
        return .key(KeyEvent(key: .paste(text)))
    }

    /// Whether the parser is holding something that needs another
    /// ``readEvent()`` soon to resolve, even if no new bytes arrive: a lone
    /// `ESC` mid Escape-vs-sequence disambiguation, a deferred bare `ESC`, an
    /// incomplete escape sequence awaiting its terminator, or an open paste.
    ///
    /// The run loop reads this to schedule a bounded wake while it's true, so
    /// these resolve on a wall-clock deadline (a prompt Escape, a dropped dead
    /// sequence) instead of waiting for unrelated input or animation to tick the
    /// loop. It's `false` the rest of the time, so a genuinely idle screen still
    /// blocks with zero wakeups.
    ///
    /// ``inPasteMode`` is here even though it is not "bytes we are holding":
    /// paste mode with an EMPTY buffer is the one state whose only exit is a
    /// timeout, and ``stalledPasteStaleFrames`` advances only inside
    /// ``readEvent()``. Leaving it out meant a terminal that emitted `ESC[200~`
    /// and then lost the paste wedged the parser — the loop blocked, so the
    /// timeout that exists precisely to escape that state never ticked, and the
    /// user's next keystroke was swallowed as paste content instead of being
    /// dispatched.
    var hasPendingInput: Bool {
        !input.isEmpty || pendingBareEsc || pendingAltEsc || inPasteMode
    }

    /// Peels sequences off the front of the buffer until one of them is
    /// something the app can be told about, and returns it — `nil` once the
    /// buffer runs out of complete sequences, or once paste mode opens.
    ///
    /// The LOOP is the point. ``finalize(bytes:)`` returns nil for sequences it
    /// recognises and deliberately drops: a CSI whose final byte
    /// `KeyEvent.parseCSISequence` does not model (a `ESC[?62;22c` device
    /// answer, a late `ESC[24;80R`, xterm's `ESC[1;5P`), and a legacy mouse
    /// report that is malformed. Returning that nil straight to the caller made
    /// it indistinguishable from "the buffer is empty", so `App`'s
    /// `while let input = terminal.readEvent()` ended the frame's drain with
    /// the user's real keystrokes still buffered behind the dropped sequence —
    /// and `appendDrain` had already emptied the kernel buffer, so no stdin
    /// wake could arrive and they came out one per 25 ms poll.
    ///
    /// The string-terminated families already avoid this by recursing inside
    /// ``tryExtractRegularEvent()``; the CSI drop happens inside `finalize`,
    /// where it cannot, so the recovery belongs here.
    private func extractDeliverableEvent() -> TerminalInput? {
        while let bytes = tryExtractRegularEvent() {
            staleFrames = 0
            if let event = finalize(bytes: bytes) { return event }
            // STOP, rather than go round again, when that was the paste-start
            // marker and its content has not all arrived: the bytes behind it
            // are the paste, not keystrokes.
            if inPasteMode { return nil }
        }
        return nil
    }

    /// One `readEvent()` round while a bracketed paste is open: everything in
    /// the buffer is paste content, so no key parsing happens here at all.
    ///
    /// Lifted out of ``readEvent()`` rather than left inline because it always
    /// returns, so it is a whole branch rather than a step, and because
    /// ``readEvent()`` was at its cyclomatic limit.
    private func pumpPasteMode() -> TerminalInput? {
        if let event = tryExtractPaste() {
            staleFrames = 0
            return event
        }
        // Paste content is still in flight. Give the kernel one
        // chance to deliver more right now, but don't sleep —
        // the main loop will spin again in ~24ms.
        let added = appendDrain()
        if added > 0, let event = tryExtractPaste() {
            staleFrames = 0
            return event
        }
        // A real paste arrives as a continuous stream, so a frame that
        // brought NO bytes at all is the only thing that counts against
        // it; a slow one simply keeps resetting the count. Total silence
        // for a second means the end marker is not coming — a dropped
        // `ESC[201~`, or a terminal that abandoned the paste — and paste
        // mode must end, or every keystroke from here on is swallowed into
        // the buffer and the app stops answering the keyboard entirely.
        if added > 0 {
            staleFrames = 0
        } else {
            staleFrames += 1
            if staleFrames >= Self.stalledPasteStaleFrames {
                staleFrames = 0
                return abandonStalledPaste()
            }
        }
        return nil
    }

    /// Reads up to one complete event from the input stream.
    /// Returns `nil` when nothing is ready right now.
    ///
    /// This is the single entry point for the input pipeline. It
    /// drains stdin opportunistically (once per call, only when
    /// the buffer is empty or a partial sequence needs more
    /// bytes), parses events out of the buffer, and never blocks
    /// the run loop.
    func readEvent() -> TerminalInput? {
        // Make sure there's something to inspect.
        if input.isEmpty {
            appendDrain()
        }

        // Resolve a deferred bare ESC (armed by `resolveStuckPartial`). If a
        // sequence introducer is now at the front, the earlier `ESC` was that
        // sequence's introducer, split into a later read — re-attach it and
        // parse the real sequence (no Escape emitted, no `[` leaked as a literal
        // page shortcut). Otherwise the `ESC` really was the Escape key: commit
        // it now (the next byte, if any, is handled on the following call).
        if pendingBareEsc {
            pendingBareEsc = false
            if !input.isEmpty, Self.continuesEscapeSequence(input[0]) {
                input.insert(0x1B, at: 0)
            } else {
                return finalize(bytes: [0x1B])
            }
        }

        // The same one-round hold for a deferred `ESC ESC`. The ambiguity is
        // the same shape one level in: the second ESC may be the Escape key
        // (Option+Escape) or the introducer of a sequence whose tail is still
        // in flight (`ESC ESC [ Z` is Option-Shift-Tab). Re-attach both when an
        // introducer turns up; otherwise the chord stands.
        if pendingAltEsc {
            pendingAltEsc = false
            if !input.isEmpty, Self.continuesEscapeSequence(input[0]) {
                input.insert(copying: [0x1B, 0x1B], at: 0)
            } else {
                return finalize(bytes: [0x1B, 0x1B])
            }
        }

        if inPasteMode { return pumpPasteMode() }

        if let event = extractDeliverableEvent() { return event }
        // `finalize` may have just opened paste mode with the content still in
        // flight. Everything left in the buffer is that content, so leave it to
        // the paste branch above on the next pump rather than parsing it here.
        if inPasteMode { return nil }

        // No complete event yet. Try one more drain in case the
        // kernel has the missing bytes ready right now.
        let added = appendDrain()
        if added > 0 {
            if let event = extractDeliverableEvent() { return event }
            if inPasteMode { return nil }
        }

        // Still nothing. If the buffer's empty there's no partial to
        // worry about; just return nil.
        guard !input.isEmpty else {
            staleFrames = 0
            return nil
        }

        // We have a stuck partial at the front. Wait one more frame
        // for the rest; if still nothing comes, give up on the front
        // of the buffer. This recovers bare Esc (which looks identical
        // to a partial CSI introducer until something definitive
        // arrives) and any truncated sequence the terminal will
        // never finish.
        if added == 0 {
            staleFrames += 1
            return resolveStuckPartial()
        }

        return nil
    }

    /// Called once per stale frame while a partial sits at the front of the
    /// buffer, and decides — based on how long it has been stuck — how to make
    /// progress without ever stranding part of a split escape sequence as a
    /// literal keystroke. Returns an event only when it pops a lone non-ESC
    /// byte; otherwise `nil` (still waiting, or it deferred/discarded).
    ///
    /// - A lone `ESC` is *deferred* (``pendingBareEsc``) after the short
    ///   ``bareEscStaleFrames`` timeout, not committed outright: its
    ///   continuation may be a CSI/SS3 sequence — or a terminal reply — split
    ///   into a later read. The next ``readEvent()`` re-attaches it if an
    ///   introducer arrived, else commits the Escape.
    /// - An incomplete `ESC [` / `ESC O` is unambiguously a control sequence, so
    ///   we KEEP WAITING for its terminator — a read-split sequence's tail
    ///   (arrow, mouse report, …) arrives on a later read and completes it.
    ///   Stranding it instead leaked bytes as keystrokes: the introducer `[`
    ///   (→ Sliders page) or, for a mouse drag, the terminator `M` (→ a stray
    ///   key). Only after the generous ``deadSequenceStaleFrames`` timeout — by
    ///   which point any real terminator has long arrived — is a truly dead
    ///   sequence dropped as a unit.
    /// - Any other stuck byte is consumed singly to make progress.
    private func resolveStuckPartial() -> TerminalInput? {
        let first = input[0]

        if first == 0x1B {
            if input.count == 1 {
                // Lone ESC — Escape-vs-sequence ambiguity. Defer after the
                // short timeout so a split sequence's tail can still cancel it.
                if staleFrames >= Self.bareEscStaleFrames {
                    staleFrames = 0
                    input.removeFirst(1)
                    pendingBareEsc = true
                }
                return nil
            }
            if Self.continuesEscapeSequence(input[1]) {
                // Incomplete CSI/SS3, or a terminal reply whose terminator has
                // not arrived: wait for it; drop only a long-dead sequence.
                if staleFrames >= Self.deadSequenceStaleFrames {
                    staleFrames = 0
                    consume(input.count)
                }
                return nil
            }
            if input[1] == 0x1B {
                // ESC ESC — a meta prefix in front of another escape sequence.
                // With something behind it the inner sequence is simply
                // incomplete, and the same rule applies as for a bare CSI: keep
                // waiting, because committing now strands the tail as literal
                // keystrokes.
                guard input.count == 2 else {
                    if staleFrames >= Self.deadSequenceStaleFrames {
                        staleFrames = 0
                        consume(input.count)
                    }
                    return nil
                }
                // With nothing behind it once the wait is up, the inner event
                // IS the Escape key: Option+Escape on a meta-sending terminal,
                // which `KeyEvent.parse` decodes as alt+escape. Popping one
                // byte at a time (the generic stuck-byte arm below) instead
                // delivered TWO Escapes, so one keystroke backed out of two
                // levels of UI — and made the parser's alt+escape decoding
                // unreachable from a live terminal.
                //
                // The trade: an Escape pressed twice fast enough that both land
                // in ONE read now reads as that chord instead. A human's two
                // presses are milliseconds apart and land in separate reads
                // unless a slow frame batches them, and the recovery is to
                // press Escape again — against one keystroke reliably doing
                // two things.
                if staleFrames >= Self.bareEscStaleFrames {
                    staleFrames = 0
                    consume(2)
                    pendingAltEsc = true
                }
                return nil
            }
        }

        // Any other stuck byte (not a recognised escape introducer): make
        // progress by popping one, after the short timeout.
        if staleFrames >= Self.bareEscStaleFrames {
            staleFrames = 0
            if let byte = input.popFirst() {
                return finalize(bytes: [byte])
            }
        }
        return nil
    }

    /// Wraps raw event bytes into a ``TerminalInput``. Detects
    /// the bracketed-paste start marker and flips into paste mode.
    private func finalize(bytes: [UInt8]) -> TerminalInput? {
        // SGR mouse report: ESC [ < … M / m
        if bytes.count >= 9, bytes[0] == 0x1B, bytes[1] == 0x5B, bytes[2] == 0x3C {
            if let mouse = MouseEvent.parseSGR(bytes) {
                return .mouse(mouse)
            }
        }

        // Legacy mouse report: ESC [ M <b> <x> <y>
        if bytes.count == 6, bytes[0] == 0x1B, bytes[1] == 0x5B, bytes[2] == 0x4D {
            if let mouse = MouseEvent.parseLegacy(bytes) {
                return .mouse(mouse)
            }
            // Recognisably a legacy report but malformed — drop it
            // rather than letting the coord bytes leak as keystrokes.
            return nil
        }

        // Bracketed paste start: switch into paste mode and try to
        // extract the content right now if it's already buffered.
        if bytes == Self.pasteStart {
            inPasteMode = true
            return tryExtractPaste()
        }

        if let key = KeyEvent.parse(bytes) {
            // Apple Terminal encodes Shift on a function key by sending a
            // DIFFERENT function key (Shift+F5…F12 → the VT220 F13…F20
            // sequences), so the chord has to be reassembled here rather than
            // by whoever binds it. Measured; see Terminal-compatibility.md.
            return .key(
                TerminalHost.isAppleTerminal
                    ? key.normalizingLegacyShiftedFunctionKeys() : key)
        }
        return nil
    }

    /// Reads raw event bytes — back-compat for the
    /// ``TerminalProtocol`` interface. New code should prefer
    /// ``readEvent()`` which gives you parsed events directly and
    /// handles bracketed paste, mouse reports, and the bare-Esc
    /// disambiguation in one place.
    ///
    /// - Returns: One event's bytes, or `[]` if no complete event
    ///   is buffered.
    func readBytes(maxBytes: Int = 32) -> [UInt8] {
        if input.isEmpty { appendDrain() }
        return tryExtractRegularEvent() ?? []
    }

    /// Reads a key event from the terminal — back-compat for the
    /// ``TerminalProtocol`` interface. New code should call
    /// ``readEvent()`` and switch on the returned ``TerminalInput``.
    ///
    /// If the next event is a mouse event it is consumed and `nil`
    /// is returned — the legacy interface has nowhere to surface it.
    /// Callers that care about mouse events must use `readEvent()`.
    func readKeyEvent() -> KeyEvent? {
        guard let event = readEvent() else { return nil }
        if case .key(let key) = event { return key }
        return nil
    }
}
