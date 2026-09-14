//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalInputParsingTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Split escape-sequence parsing
//
// The terminal sends arrows, mouse reports, focus events, device replies and
// bracketed paste as `ESC [ …` (CSI) or `ESC O …` (SS3) sequences. A `read()`
// boundary occasionally lands mid-sequence, so the parser sees a lone `ESC`
// first and its tail only on a later read. The lone `ESC` is ambiguous with the
// Escape key, so it times out after two stale frames — and the regression these
// tests pin is that the timed-out `ESC` must NOT strand its `[` / `O` introducer
// to be dispatched as a literal character (which intermittently jumped
// `Example` to its `[` = Sliders page).
//
// The parser reads stdin directly, so these tests drive it through the
// injectable `readSource`, feeding bytes exactly when we choose to model the
// split precisely.

@MainActor
@Suite("Terminal split escape-sequence parsing")
struct TerminalInputParsingTests {

    /// A terminal whose byte source returns whatever the test has staged in
    /// `pending` at each drain (and 0 — "nothing yet" — when it's empty).
    /// Returns the terminal plus a setter to stage the next read's bytes.
    private func makeTerminal() -> (Terminal, ([UInt8]) -> Void) {
        let terminal = Terminal()
        let box = ByteBox()
        terminal.readSource = { buffer in
            guard !box.bytes.isEmpty else { return 0 }
            let count = min(box.bytes.count, buffer.count)
            for index in 0..<count { buffer[index] = box.bytes[index] }
            box.bytes.removeFirst(count)
            return count
        }
        return (terminal, { box.bytes.append(contentsOf: $0) })
    }

    /// Reference box so the read closure and the test share one byte queue.
    private final class ByteBox { var bytes: [UInt8] = [] }

    @Test("A CSI split at the ESC boundary parses as the real key, not '['")
    func splitCSIRecoversAsArrowNotBracket() {
        let (terminal, stage) = makeTerminal()

        // ESC arrives alone; its `[B` tail is still in flight.
        stage([0x1B])
        #expect(terminal.readEvent() == nil)  // partial — one stale frame
        #expect(terminal.readEvent() == nil)  // second stale frame → ESC deferred

        // The tail arrives now. The deferred ESC is re-attached and the whole
        // thing parses as Down — NOT Escape, and NOT a literal '[' (Sliders).
        stage([0x5B, 0x42])  // "[B"
        #expect(terminal.readEvent() == .key(KeyEvent(key: .down)))
    }

    @Test("A truncated ESC[ is dropped as a unit, never leaking '['")
    func truncatedCSINeverLeaksBracket() {
        let (terminal, stage) = makeTerminal()

        // ESC[ arrives together but the terminator never comes.
        stage([0x1B, 0x5B])
        var results: [TerminalInput?] = []
        for _ in 0..<4 { results.append(terminal.readEvent()) }

        // Nothing is surfaced, and crucially never a literal '['.
        #expect(results.allSatisfy { $0 == nil })
        #expect(!results.contains(.key(KeyEvent(character: "["))))
    }

    @Test("ESC+Tab in one read parses as Option-Tab (alt-modified tab)")
    func escTabIsAltTab() {
        // What a meta-capable terminal (Terminal.app with "Use Option as Meta
        // Key", iTerm2 "Esc+") sends for Option-Tab. TextEditor relies on this
        // to insert a literal tab instead of moving focus.
        let (terminal, stage) = makeTerminal()
        stage([0x1B, 0x09])
        #expect(terminal.readEvent() == .key(KeyEvent(key: .tab, alt: true)))
    }

    @Test("ESC then Tab split across reads (within the grace window) is still Option-Tab")
    func splitEscTabWithinWindowIsAltTab() {
        let (terminal, stage) = makeTerminal()
        stage([0x1B])
        #expect(terminal.readEvent() == nil)  // partial — one stale frame
        stage([0x09])                          // tail arrives before the deferral commits
        #expect(terminal.readEvent() == .key(KeyEvent(key: .tab, alt: true)))
    }

    @Test("ESC then Tab far apart resolves as Escape + plain Tab (two real keystrokes)")
    func lateTabAfterDeferredEscIsTwoKeys() {
        // Once the bare ESC has sat unresolved past the grace window it commits
        // as the Escape key; a Tab arriving later is its own keystroke. Unlike
        // a CSI '[' tail, a Tab is a legitimate standalone key, so re-attaching
        // it here would eat real Escape-then-Tab input.
        let (terminal, stage) = makeTerminal()
        stage([0x1B])
        #expect(terminal.readEvent() == nil)  // stale frame 1
        #expect(terminal.readEvent() == nil)  // stale frame 2 → deferred
        stage([0x09])                          // arrives after the window
        #expect(terminal.readEvent() == .key(KeyEvent(key: .escape)))
        #expect(terminal.readEvent() == .key(KeyEvent(key: .tab)))
    }

    @Test("A genuine lone ESC still commits as the Escape key")
    func bareEscapeStillWorks() {
        let (terminal, stage) = makeTerminal()

        // Nothing ever follows the ESC.
        stage([0x1B])
        #expect(terminal.readEvent() == nil)  // stale frame 1
        #expect(terminal.readEvent() == nil)  // stale frame 2 → deferred
        #expect(terminal.readEvent() == .key(KeyEvent(key: .escape)))  // committed
    }

    @Test("A real lone '[' keystroke is still a literal '['")
    func literalBracketStillWorks() {
        let (terminal, stage) = makeTerminal()
        stage([0x5B])
        #expect(terminal.readEvent() == .key(KeyEvent(character: "[")))
    }

    // MARK: - Typed non-ASCII text

    /// The extractor used to consume every non-ESC byte SINGLY, and
    /// `parseSingleByte` returns nil for anything ≥ 0x80 — so every character
    /// a user typed outside ASCII was silently discarded byte by byte. A
    /// framework that ships seven localisations could not accept a single
    /// French, German, or CJK keystroke except via bracketed paste.
    @Test(
        "Typed multi-byte UTF-8 characters arrive as one character event",
        arguments: [
            ("é", [0xC3, 0xA9]),  // 2 bytes — Latin accents
            ("ß", [0xC3, 0x9F]),  // 2 bytes
            ("你", [0xE4, 0xBD, 0xA0]),  // 3 bytes — CJK
            ("🎉", [0xF0, 0x9F, 0x8E, 0x89]),  // 4 bytes — emoji
        ] as [(Character, [UInt8])])
    func typedNonASCIIArrives(_ character: Character, _ bytes: [UInt8]) {
        let (terminal, stage) = makeTerminal()
        stage(bytes)
        #expect(terminal.readEvent() == .key(KeyEvent(character: character)))
    }

    @Test("A UTF-8 character split across reads still arrives whole")
    func splitUTF8ArrivesWhole() {
        let (terminal, stage) = makeTerminal()
        stage([0xC3])  // é's lead byte; the tail is still in flight
        #expect(terminal.readEvent() == nil)
        stage([0xA9])
        #expect(terminal.readEvent() == .key(KeyEvent(character: "é")))
    }

    @Test("Alt + a multi-byte character parses as that character with alt")
    func altNonASCIIParses() {
        // A meta-sending terminal prefixes whatever the layout produced:
        // Option+ß on a German layout is ESC + the two bytes of ß.
        let (terminal, stage) = makeTerminal()
        stage([0x1B, 0xC3, 0x9F])
        #expect(terminal.readEvent() == .key(KeyEvent(key: .character("ß"), alt: true)))
    }

    @Test("Malformed UTF-8 is dropped without swallowing the bytes after it")
    func malformedUTF8DoesNotEatFollowingInput() {
        let (terminal, stage) = makeTerminal()
        // An orphan continuation byte, then a mis-framed lead, then a real key.
        stage([0xA9, 0xC3, 0x61])
        #expect(terminal.readEvent() == .key(KeyEvent(character: "a")))
    }

    @Test("A stranded lead byte resolves via staleness without leaking a key")
    func strandedLeadByteResolves() {
        let (terminal, stage) = makeTerminal()
        stage([0xC3])  // nothing ever follows
        var results: [TerminalInput?] = []
        for _ in 0..<6 { results.append(terminal.readEvent()) }
        #expect(results.allSatisfy { $0 == nil }, "garbage surfaces no event")
        // The buffer made progress: a real key typed afterwards still works.
        stage([0x62])
        #expect(terminal.readEvent() == .key(KeyEvent(character: "b")))
    }

    @Test("A complete CSI delivered in one read is unaffected")
    func completeCSIUnaffected() {
        let (terminal, stage) = makeTerminal()
        stage([0x1B, 0x5B, 0x41])  // ESC [ A = Up
        #expect(terminal.readEvent() == .key(KeyEvent(key: .up)))
    }

    @Test("A mouse report split before its terminator completes, never leaking 'M'")
    func splitMouseReportNeverLeaksTerminator() {
        let (terminal, stage) = makeTerminal()

        // An SGR mouse report "ESC [ < 0 ; 50 ; 20 M" arrives without its final
        // 'M' (the read split right before the terminator).
        stage(Array("\u{1B}[<0;50;20".utf8))
        var results: [TerminalInput?] = []
        for _ in 0..<3 { results.append(terminal.readEvent()) }  // waits, no leak

        // The terminator arrives now and completes the report.
        stage(Array("M".utf8))
        for _ in 0..<2 { results.append(terminal.readEvent()) }

        // Never a literal 'M' (which would flip the Image demo's colour mode),
        // and the report is recognised as a mouse event.
        let leakedM = results.contains(.key(KeyEvent(character: "M")))
        #expect(!leakedM, "a split mouse report leaked its 'M' terminator as a keystroke")
        let mouseEvents = results.filter { if case .mouse = $0 { return true } else { return false } }
        #expect(mouseEvents.count == 1, "the split report should complete as one mouse event")
    }

    /// A device-attributes answer is a CSI, and a real one runs past what used
    /// to be the per-event byte budget. The walk gave up at 32 bytes and
    /// RETURNED the truncated prefix, so `KeyEvent.parse` discarded it (index
    /// 31 can never be a final byte) while the tail — `8;29c` — was left at
    /// the head of the buffer with no `ESC` in front of it, and the next pass
    /// typed it out one character at a time. In `Example`, four of those five
    /// are page shortcuts.
    @Test("A CSI longer than the event budget is dropped whole, not spelled out")
    func overlongCSIDoesNotLeakItsTail() {
        let (terminal, stage) = makeTerminal()

        // What an xterm-class terminal answers `ESC[c` with: 37 bytes.
        stage(Array("\u{1B}[?63;1;2;4;6;9;15;16;18;21;22;28;29c".utf8))

        // Deliberately NOT "pump until nil": the truncated prefix made the
        // first call return nil while the tail was still buffered, which is
        // exactly the shape a quiet-limited drain would have tolerated.
        var events: [TerminalInput] = []
        for _ in 0..<12 {
            if let event = terminal.readEvent() { events.append(event) }
        }

        #expect(events.isEmpty, "an over-long CSI leaked its tail as keystrokes: \(events)")
    }

    @Test("A new sequence after a truncated one is parsed cleanly, no leak")
    func newSequenceAfterTruncatedOneDoesNotLeak() {
        let (terminal, stage) = makeTerminal()

        // A report whose terminator is genuinely lost, immediately followed by a
        // complete report. The truncated one must be abandoned (not have the next
        // report's '[' mistaken for its terminator, leaking the remainder).
        stage(Array("\u{1B}[<0;50;20".utf8))  // truncated (no terminator ever)
        _ = terminal.readEvent()
        _ = terminal.readEvent()
        stage(Array("\u{1B}[<1;5;5M".utf8))  // a fresh, complete report

        var results: [TerminalInput?] = []
        for _ in 0..<4 { results.append(terminal.readEvent()) }

        let leakedKey = results.contains { if case .key = $0 { return true } else { return false } }
        #expect(!leakedKey, "a truncated sequence let the following report leak as keystrokes")
        let mouseEvents = results.filter { if case .mouse = $0 { return true } else { return false } }
        #expect(mouseEvents.count == 1, "the fresh report should still parse as a mouse event")
    }

    @Test("hasPendingInput is true while an ESC is held, false once it resolves")
    func hasPendingInputTracksHeldPartial() {
        // The run loop polls on a bounded deadline only while this is true, so a
        // held ESC resolves promptly without external activity, and a truly idle
        // screen (false) still blocks with no wakeups.
        let (terminal, stage) = makeTerminal()

        stage([0x1B])
        _ = terminal.readEvent()
        #expect(terminal.hasPendingInput, "a buffered lone ESC must keep the loop polling")

        _ = terminal.readEvent()  // deferred (still pending)
        #expect(terminal.hasPendingInput)

        #expect(terminal.readEvent() == .key(KeyEvent(key: .escape)))  // committed
        #expect(!terminal.hasPendingInput, "once resolved the loop can go idle")
    }

    @Test("Escape followed (after the timeout) by a real key yields both")
    func escapeThenKeyYieldsBoth() {
        let (terminal, stage) = makeTerminal()

        stage([0x1B])
        #expect(terminal.readEvent() == nil)
        #expect(terminal.readEvent() == nil)  // ESC deferred

        // A non-introducer key arrives: the deferred Escape commits, then the key.
        stage([0x78])  // 'x'
        #expect(terminal.readEvent() == .key(KeyEvent(key: .escape)))
        #expect(terminal.readEvent() == .key(KeyEvent(character: "x")))
    }

    /// `ESC ESC` is Option+Escape on a meta-sending terminal, and
    /// `KeyEvent.parse` has always decoded it as alt+escape — but the byte
    /// extractor could never hand it both bytes at once, so the live parser
    /// popped them one at a time and one keystroke backed out of two levels
    /// of UI.
    @Test("ESC ESC in one read is alt+escape, not two Escapes")
    func doubledEscapeIsAltEscape() {
        let (terminal, stage) = makeTerminal()

        stage([0x1B, 0x1B])
        #expect(terminal.readEvent() == nil)  // stale frame 1
        #expect(terminal.readEvent() == nil)  // stale frame 2 → deferred
        #expect(terminal.hasPendingInput, "the held chord keeps the loop awake")

        #expect(terminal.readEvent() == .key(KeyEvent(key: .escape, alt: true)))
        #expect(terminal.readEvent() == nil, "and nothing is left over")
    }

    /// The reason the arm is gated on there being nothing behind it: with an
    /// inner sequence still in flight, committing the two ESCs would strand
    /// its tail as literal keystrokes — the `[`-as-a-page-shortcut bug this
    /// whole file exists for.
    @Test("ESC ESC with an inner sequence still in flight waits for it")
    func doubledEscapeWaitsForItsInnerSequence() {
        let (terminal, stage) = makeTerminal()

        // Option-Shift-Tab is ESC ESC [ Z, split before the terminator.
        stage([0x1B, 0x1B, 0x5B])
        for _ in 0..<3 { #expect(terminal.readEvent() == nil) }

        stage([0x5A])  // "Z"
        #expect(terminal.readEvent() == .key(KeyEvent(key: .tab, alt: true, shift: true)))
    }

    /// A paste whose `ESC[201~` never arrives used to swallow every keystroke
    /// after it into the paste buffer — paste mode had no timeout at all, only
    /// the 1 MiB cap, so the app went on rendering while answering no input.
    @Test("An unterminated paste is delivered rather than wedging the keyboard")
    func stalledPasteIsDeliveredAndInputResumes() {
        let (terminal, stage) = makeTerminal()

        // ESC[200~ then content — and no end marker, ever.
        stage([0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E] + Array("hello".utf8))
        var paste: TerminalInput?
        for _ in 0..<60 where paste == nil {
            paste = terminal.readEvent()
        }
        #expect(paste == .key(KeyEvent(key: .paste("hello"))))

        // And the keyboard works again: pre-fix this 'x' vanished into the
        // still-open paste.
        stage([0x78])
        #expect(terminal.readEvent() == .key(KeyEvent(character: "x")))
    }

    /// Paste mode with an EMPTY buffer is the one parser state whose only way
    /// out is a timeout, and `stalledPasteStaleFrames` only advances inside
    /// `readEvent()` — so the parser has to ask the loop for those wakes, or
    /// the escape hatch never ticks. A terminal that emits `ESC[200~` and then
    /// loses the paste (an interrupted paste, a dropped `ESC[201~` on a lossy
    /// link) leaves exactly this state.
    @Test("An empty-buffered paste mode keeps the loop polling")
    func pasteModeWithEmptyBufferKeepsLoopAwake() {
        let (terminal, stage) = makeTerminal()

        // The start marker arrives alone; its content never does.
        stage(Array("\u{1B}[200~".utf8))
        #expect(terminal.readEvent() == nil, "the marker is consumed, paste mode is on")

        #expect(
            terminal.hasPendingInput,
            "paste mode must keep the loop polling or its stall timeout never ticks")

        // And it stops asking once the stall timeout has fired: an idle screen
        // still blocks with no wakeups.
        var pumps = 0
        while terminal.hasPendingInput, pumps < 200 {
            _ = terminal.readEvent()
            pumps += 1
        }
        #expect(!terminal.hasPendingInput, "once the stalled paste is abandoned the loop can idle")
    }

    /// The end-marker scan restarted at byte zero on every `readEvent()`, and a
    /// paste's buffer only grows — nothing is consumed until the marker is
    /// found — so receiving a paste cost O(n²) in its own size, twice per
    /// frame. Measured in a debug build before the cursor was added: 64 KiB
    /// took 0.44 s, 512 KiB took 52.7 s.
    ///
    /// A strictly increasing cursor is the whole mechanism: each pass starts
    /// where the last stopped, so a byte is compared a bounded number of times
    /// however long the paste runs.
    @Test("The end-marker scan resumes rather than restarting each pump")
    func pasteScanResumesAcrossPumps() {
        let (terminal, stage) = makeTerminal()
        stage(Array("\u{1B}[200~".utf8))
        #expect(terminal.readEvent() == nil, "the start marker opens paste mode")

        var cursors: [Int] = []
        for _ in 0..<8 {
            stage([UInt8](repeating: 0x61, count: 1000))
            #expect(terminal.readEvent() == nil, "still mid-paste")
            cursors.append(terminal.pasteScanCursor)
        }

        #expect(cursors.first.map { $0 > 0 } == true, "nothing was ruled out: \(cursors)")
        #expect(
            zip(cursors, cursors.dropFirst()).allSatisfy { $0 < $1 },
            "the scan restarted instead of resuming: \(cursors)")

        // And the content still arrives whole.
        stage(Array("\u{1B}[201~".utf8))
        var event: TerminalInput?
        for _ in 0..<8 where event == nil { event = terminal.readEvent() }
        guard case .key(let key) = event, case .paste(let text) = key.key else {
            Issue.record("no paste event: \(String(describing: event))")
            return
        }
        #expect(text == String(repeating: "a", count: 8000))
    }

    /// The risk the cursor introduces, and the reason it backs up by five: an
    /// end marker SPLIT across two drains — `ESC [ 2` in one, `0 1 ~` in the
    /// next — has to be matched from its first byte, which lives inside the
    /// tail the previous pass already walked past.
    @Test("An end marker split across two drains is still found", arguments: 1...5)
    func pasteEndMarkerSplitAcrossDrainsIsFound(prefixLength: Int) {
        let (terminal, stage) = makeTerminal()
        let content = String(repeating: "x", count: 20)
        let endMarker = Array("\u{1B}[201~".utf8)

        stage(
            Array("\u{1B}[200~".utf8) + Array(content.utf8)
                + Array(endMarker.prefix(prefixLength)))
        #expect(terminal.readEvent() == nil, "the marker is incomplete, so nothing yet")

        stage(Array(endMarker.dropFirst(prefixLength)))
        var event: TerminalInput?
        for _ in 0..<8 where event == nil { event = terminal.readEvent() }
        #expect(event == .key(KeyEvent(key: .paste(content))), "split at \(prefixLength)")
    }

    /// The timeout must not cut a real paste in half: a stream that keeps
    /// delivering bytes keeps resetting the silence count, however long it
    /// takes in total.
    @Test("A slow but steady paste is never cut short")
    func slowPasteIsNotTruncated() {
        let (terminal, stage) = makeTerminal()

        stage([0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E])
        #expect(terminal.readEvent() == nil)

        // Ten chunks, each arriving after a couple of quiet frames.
        for index in 0..<10 {
            #expect(terminal.readEvent() == nil)
            #expect(terminal.readEvent() == nil)
            stage(Array("chunk\(index) ".utf8))
            #expect(terminal.readEvent() == nil, "still mid-paste")
        }

        stage([0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E])  // ESC[201~ at last
        let event = terminal.readEvent()
        guard case .key(let key) = event, case .paste(let text) = key.key else {
            Issue.record("expected a paste event, got \(String(describing: event))")
            return
        }
        #expect(text.hasPrefix("chunk0 "))
        #expect(text.hasSuffix("chunk9 "), "every chunk is in one paste: \(text)")
    }

    /// And the later split: both ESCs go stale and are deferred, THEN the
    /// sequence's introducer turns up. The held chord must give way to the
    /// real sequence rather than emit alt+escape and strand `[Z`.
    @Test("A deferred ESC ESC gives way when its sequence finally arrives")
    func deferredDoubledEscapeYieldsToItsSequence() {
        let (terminal, stage) = makeTerminal()

        stage([0x1B, 0x1B])
        #expect(terminal.readEvent() == nil)  // stale frame 1
        #expect(terminal.readEvent() == nil)  // stale frame 2 → deferred

        stage([0x5B, 0x5A])  // "[Z" — the tail, late
        #expect(terminal.readEvent() == .key(KeyEvent(key: .tab, alt: true, shift: true)))
    }
}

// MARK: - Replies the terminal volunteered
//
// A terminal can send things nobody typed: a graphics acknowledgement, an OSC
// colour answer, a DCS report. They arrive on stdin like keystrokes and are
// not keystrokes, and the parser used to deliver them one character at a time
// — `ESC _ G i=7;OK ESC \` became Alt+underscore and then `G i = 7 ; O K`.
//
// That was always latent. It became live when TUIkit started SENDING graphics
// commands: those are acknowledged unless every command carries `q=2`, and
// "every command" is the kind of claim that holds until it doesn't. The
// observed symptom was an image page zooming on its own, because `=` is the
// zoom-in shortcut and a reply is full of them.

@MainActor
@Suite("Terminal replies are not keystrokes")
struct TerminalReplySwallowingTests {

    private func makeTerminal() -> (Terminal, ([UInt8]) -> Void) {
        let terminal = Terminal()
        let box = ByteBox()
        terminal.readSource = { buffer in
            guard !box.bytes.isEmpty else { return 0 }
            let count = min(box.bytes.count, buffer.count)
            for index in 0..<count { buffer[index] = box.bytes[index] }
            box.bytes.removeFirst(count)
            return count
        }
        return (terminal, { box.bytes.append(contentsOf: $0) })
    }

    private final class ByteBox { var bytes: [UInt8] = [] }

    /// The exact bytes Ghostty answers a graphics command with.
    private let acknowledgement = Array("\u{1B}_Gi=7;OK\u{1B}\\".utf8)

    @Test("A graphics acknowledgement types nothing")
    func graphicsReplyIsSwallowed() {
        let (terminal, stage) = makeTerminal()
        stage(acknowledgement)
        var seen: [TerminalInput?] = []
        for _ in 0..<6 { seen.append(terminal.readEvent()) }
        #expect(seen.allSatisfy { $0 == nil }, "the reply produced \(seen.compactMap { $0 })")
        // The one that moved a slider the user never touched.
        #expect(!seen.contains(.key(KeyEvent(character: "="))))
    }

    @Test("A real keypress behind a reply still arrives")
    func realKeyAfterAReplyStillArrives() {
        let (terminal, stage) = makeTerminal()
        stage(acknowledgement + Array("q".utf8))
        #expect(terminal.readEvent() == .key(KeyEvent(character: "q")))
    }

    /// Several at once — a burst is what a frame full of images would produce
    /// if any command lost its `q=2`.
    @Test("A burst of replies is swallowed whole")
    func burstIsSwallowed() {
        let (terminal, stage) = makeTerminal()
        stage(acknowledgement + acknowledgement + acknowledgement + Array("x".utf8))
        #expect(terminal.readEvent() == .key(KeyEvent(character: "x")))
    }

    /// The other three string-terminated families, and the BEL spelling of the
    /// terminator that OSC is usually written with.
    @Test("OSC, DCS and PM replies are swallowed too, BEL-terminated or not")
    func everyStringFamilyIsSwallowed() {
        for reply in [
            "\u{1B}]11;rgb:1e1e/1e1e/1e1e\u{07}",  // an OSC background answer
            "\u{1B}P1+r5375=31\u{1B}\\",  // an XTGETTCAP answer
            "\u{1B}^status\u{1B}\\",  // PM
        ] {
            let (terminal, stage) = makeTerminal()
            stage(Array(reply.utf8) + Array("z".utf8))
            #expect(
                terminal.readEvent() == .key(KeyEvent(character: "z")),
                "leaked out of \(reply.debugDescription)")
        }
    }

    /// An unterminated reply must not leak either — it is dropped as a unit
    /// after the same grace an unterminated CSI gets, rather than one
    /// character at a time.
    @Test("An unterminated reply is dropped, not spelled out")
    func unterminatedReplyDoesNotLeak() {
        let (terminal, stage) = makeTerminal()
        stage(Array("\u{1B}_Gi=7;OK".utf8))  // no ST
        var seen: [TerminalInput?] = []
        for _ in 0..<12 { seen.append(terminal.readEvent()) }
        #expect(seen.allSatisfy { $0 == nil })
    }

    /// The CSI-family twin of ``realKeyAfterAReplyStillArrives``. A device reply
    /// is a CSI too — DA, DA2, DSR, DECRPM — and `KeyEvent.parseCSISequence`
    /// models none of their final bytes, so `finalize` dropped them and
    /// returned nil. That nil is indistinguishable from "buffer empty" to
    /// `App`'s `while let input = terminal.readEvent()` drain, which therefore
    /// ended the frame with the user's keystrokes still buffered behind the
    /// dropped reply — released one per 25 ms poll after that.
    ///
    /// Deliberately asserted on the FIRST call, not by pumping until nil: a
    /// quiet-limited drain tolerates exactly this, which is why `focus-in`
    /// sat in the split-invariance corpus without failing back when it was
    /// dropped too. (It is delivered now — see ``TerminalFocusReportTests``.)
    @Test("A real keypress behind a CSI device reply still arrives")
    func keyAfterCSIReplyArrives() {
        for reply in [
            "\u{1B}[?62;22c",  // a DA1 answer
            "\u{1B}[>1;4000;0c",  // a DA2 answer
            "\u{1B}[24;80R",  // a late DSR cursor-position answer
            "\u{1B}[?2026;2$y",  // a DECRPM answer to the synchronised-update query
        ] {
            let (terminal, stage) = makeTerminal()
            stage(Array(reply.utf8) + Array("q".utf8))
            #expect(
                terminal.readEvent() == .key(KeyEvent(character: "q")),
                "the drain ended on \(reply.debugDescription)")
        }
    }

    /// The same shape for the other sequence `finalize` drops on purpose: a
    /// legacy mouse report that is recognisably one and malformed.
    @Test("A real keypress behind a malformed legacy mouse report still arrives")
    func keyAfterMalformedLegacyMouseArrives() {
        let (terminal, stage) = makeTerminal()
        // ESC [ M with coordinate bytes below the +32 bias `parseLegacy` needs.
        stage([0x1B, 0x5B, 0x4D, 0x00, 0x00, 0x00] + Array("q".utf8))
        #expect(terminal.readEvent() == .key(KeyEvent(character: "q")))
    }

    /// A reply's `ESC` and its tail can land in different `read()`s — a laggy
    /// ssh hop needs only the two 25 ms polls that arm the deferred bare ESC.
    /// The re-attach then has to recognise the same introducers the rest of
    /// the parser does; it listed only `[` and `O`, so an `ESC` whose tail was
    /// a reply committed as the Escape key and the payload was spelled out
    /// after it (`=` being the zoom shortcut on the image pages).
    @Test("A reply whose ESC arrived in an earlier read is still swallowed")
    func splitReplyIsSwallowed() {
        for tail in ["_Gi=7;OK\u{1B}\\", "]11;rgb:1e1e/1e1e/1e1e\u{07}", "P1+r5375=31\u{1B}\\"] {
            let (terminal, stage) = makeTerminal()
            stage([0x1B])
            // bareEscStaleFrames == 2: two silent pumps arm the deferral.
            #expect(terminal.readEvent() == nil)
            #expect(terminal.readEvent() == nil)

            stage(Array(tail.utf8) + Array("z".utf8))
            #expect(
                terminal.readEvent() == .key(KeyEvent(character: "z")),
                "leaked out of a split \(tail.debugDescription)")
        }
    }

    /// The `pendingAltEsc` twin of the above: `ESC ESC` deferred, then a reply.
    /// Same rule, same one copy of it — what matters is that no character of
    /// the reply is delivered as typing.
    @Test("A deferred ESC ESC does not spell out a reply that follows it")
    func splitDoubledEscapeDoesNotLeakAReply() {
        let (terminal, stage) = makeTerminal()
        stage([0x1B, 0x1B])
        #expect(terminal.readEvent() == nil)
        #expect(terminal.readEvent() == nil)

        stage(Array("_Gi=7;OK\u{1B}\\".utf8))
        var seen: [TerminalInput] = []
        for _ in 0..<16 {
            if let event = terminal.readEvent() { seen.append(event) }
        }
        let leaked = seen.contains { event in
            guard case .key(let key) = event, case .character = key.key else { return false }
            return true
        }
        #expect(!leaked, "the reply was typed out: \(seen)")
    }

    /// And the sequence that INTERRUPTS a reply still parses, rather than
    /// being eaten with it — the rule the CSI walk already follows.
    @Test("A keypress interrupting a reply is not lost with it")
    func interruptingSequenceSurvives() {
        let (terminal, stage) = makeTerminal()
        stage(Array("\u{1B}_Gi=7;OK".utf8) + [0x1B, 0x5B, 0x42])  // truncated, then Down
        #expect(terminal.readEvent() == .key(KeyEvent(key: .down)))
    }
}

// MARK: - Focus reports
//
// A terminal with focus reporting (DEC private mode 1004) on sends `ESC [ I`
// when its window, tab or pane gains focus and `ESC [ O` when it loses it.
// Neither is a keystroke, and `O` is the trap: behind an Escape the parser's
// meta-prefix rule reads `ESC ESC [ O` as one chord, and `KeyEvent.parse`
// then spells that chord Option+Escape — a keystroke nobody pressed, eaten
// together with the Escape somebody did.

@MainActor
@Suite("Terminal focus reports")
struct TerminalFocusReportTests {

    private func makeTerminal() -> (Terminal, ([UInt8]) -> Void) {
        let terminal = Terminal()
        let box = ByteBox()
        terminal.readSource = { buffer in
            guard !box.bytes.isEmpty else { return 0 }
            let count = min(box.bytes.count, buffer.count)
            for index in 0..<count { buffer[index] = box.bytes[index] }
            box.bytes.removeFirst(count)
            return count
        }
        return (terminal, { box.bytes.append(contentsOf: $0) })
    }

    private final class ByteBox { var bytes: [UInt8] = [] }

    private static let focusIn = Array("\u{1B}[I".utf8)
    private static let focusOut = Array("\u{1B}[O".utf8)

    /// Every event `terminal` produces in `pumps` calls, nils dropped.
    private func events(_ terminal: Terminal, pumps: Int = 12) -> [TerminalInput] {
        (0..<pumps).compactMap { _ in terminal.readEvent() }
    }

    @Test("A focus report is a focus event, in and out")
    func reportsAreFocusEvents() {
        let (terminal, stage) = makeTerminal()
        stage(Self.focusIn)
        #expect(terminal.readEvent() == .focusChanged(isFocused: true))
        stage(Self.focusOut)
        #expect(terminal.readEvent() == .focusChanged(isFocused: false))
        #expect(terminal.readEvent() == nil, "and nothing is left over")
    }

    @Test("A key behind a focus report arrives after it")
    func keyBehindAReportArrives() {
        let (terminal, stage) = makeTerminal()
        stage(Self.focusIn + Array("a".utf8))
        #expect(terminal.readEvent() == .focusChanged(isFocused: true))
        #expect(terminal.readEvent() == .key(KeyEvent(character: "a")))
    }

    @Test("A report whose ESC arrived in an earlier read is still a focus event")
    func splitReportIsAFocusEvent() {
        let (terminal, stage) = makeTerminal()
        stage([0x1B])
        #expect(terminal.readEvent() == nil)  // stale frame 1
        #expect(terminal.readEvent() == nil)  // stale frame 2 → ESC deferred
        stage(Array("[O".utf8))
        #expect(events(terminal) == [.focusChanged(isFocused: false)])
    }

    /// The meta-prefix trap in one read: Escape pressed as the window loses
    /// focus. Before, this was one alt+escape and no Escape at all.
    @Test("Escape then a focus report in one read is Escape, then the report", arguments: [false, true])
    func escapeThenReportInOneRead(isFocused: Bool) {
        let (terminal, stage) = makeTerminal()
        stage([0x1B] + (isFocused ? Self.focusIn : Self.focusOut))
        #expect(
            events(terminal) == [.key(KeyEvent(key: .escape)), .focusChanged(isFocused: isFocused)])
    }

    /// The same trap by the `pendingAltEsc` route: `ESC ESC` goes stale and is
    /// held as a chord, then the report's tail turns up and the held pair is
    /// re-attached in front of it.
    @Test("A deferred ESC ESC followed by a report's tail is Escape, then the report")
    func deferredDoubledEscapeThenReportTail() {
        let (terminal, stage) = makeTerminal()
        stage([0x1B, 0x1B])
        #expect(terminal.readEvent() == nil)  // stale frame 1
        #expect(terminal.readEvent() == nil)  // stale frame 2 → deferred
        stage(Array("[O".utf8))
        #expect(events(terminal) == [.key(KeyEvent(key: .escape)), .focusChanged(isFocused: false)])
    }

    /// Wherever the read boundary lands, a report never surfaces as a key —
    /// the only key in any of these is the Escape that was really there. With
    /// an Escape in front, a split after the second byte is the `pendingAltEsc`
    /// route and one after the third is the meta branch waiting for its inner
    /// sequence. (Two Escapes in front are not a question about reports: an
    /// `ESC ESC` in one read is Option+Escape by the parser's documented trade.)
    @Test("No focus report is ever read as a key")
    func noReportIsEverAKey() {
        for report in [Self.focusIn, Self.focusOut] {
            for prefix in [[], [0x1B]] as [[UInt8]] {
                let bytes = prefix + report
                for splitAt in 1...bytes.count {
                    let (terminal, stage) = makeTerminal()
                    stage(Array(bytes[..<splitAt]))
                    // Two pumps: long enough to defer a held ESC or ESC ESC,
                    // not long enough to commit it — a third would commit a
                    // lone ESC ESC as the Option+Escape it then really is.
                    var seen = events(terminal, pumps: 2)
                    stage(Array(bytes[splitAt...]))
                    seen += events(terminal)
                    let keys = seen.filter { if case .key = $0 { return true } else { return false } }
                    let expected = prefix.isEmpty ? 0 : 1
                    #expect(
                        keys.count == expected
                            && keys.allSatisfy { $0 == .key(KeyEvent(key: .escape)) },
                        "\(bytes) split@\(splitAt) gave \(seen)")
                    #expect(seen.contains(.focusChanged(isFocused: report == Self.focusIn)))
                }
            }
        }
    }
}
