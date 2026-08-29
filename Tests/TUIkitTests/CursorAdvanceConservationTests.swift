//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CursorAdvanceConservationTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

// MARK: - The conservation law

/// The contract between the layout and the output path, as an assertion:
/// **whatever a host's compensation walk emits must land the cursor exactly
/// where the layout claimed it would.**
///
/// The layout allocates `strippedLength` cells for a row and puts the next
/// thing — padding, a border, the next column — at that offset. The output path
/// is free to rewrite the row however the host needs: push the cursor forward
/// past a glyph the terminal draws narrow, erase cells so a wide glyph takes
/// the right background, even substitute a cluster the host cannot place. What
/// it is not free to do is finish somewhere else. When it does, every cell after
/// it on the row is displaced, which is the shape of nearly every rendering bug
/// this project has had.
///
/// ## What this can and cannot find
///
/// It is a **consistency** check: the claim and the advance model are both
/// TUIkit's, so a model that is wrong *about the terminal* satisfies this
/// perfectly and still renders wrong. Only a measurement against the terminal
/// separates consistent from correct — that is what the probes in
/// `Tools/TerminalProbes` and the records in their `data/` directory are for,
/// and `TerminalLedgerConformanceTests` is the half of this pair that reads
/// them.
///
/// What it does find, instantly and with no terminal at all, is the two halves
/// of the pipeline disagreeing with each other: a claim widened without the
/// walk that emits it being told, a strip that fires under a claim that no
/// longer needs it, a CUF counted twice. That class is invisible to
/// per-character tests, because every individual number in it is right.
@Suite("Cursor advance conservation")
struct CursorAdvanceConservationTests {

    /// The cursor advance of `text` on `program`, counting the escapes the
    /// compensation walks inject.
    private func landing(_ text: String, on program: TerminalClient.Program) -> Int {
        text.cursorAdvance { TerminalClient.cursorAdvance(of: $0, on: program) }
    }

    // MARK: - Every cluster, every host

    @Test(
        "A cluster followed by content lands where the claim says",
        arguments: TerminalClient.Program.allCases, WidthCorpus.clusters)
    func followedByContent(program: TerminalClient.Program, entry: WidthCorpus.Entry) {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: program)) {
            // The bracket is what makes this the interesting case: Apple
            // Terminal's walk asks whether anything follows the cluster, and
            // takes a different branch when something does.
            let row = entry.text + "]"
            let claim = row.strippedLength
            let emitted = TerminalClient.compensating(row, for: program)
            #expect(
                landing(emitted, on: program) == claim,
                """
                \(entry) on \(program.rawValue): claimed \(claim) cells, \
                emitted output lands at \(landing(emitted, on: program))
                """)
        }
    }

    @Test(
        "A cluster at the end of a row lands where the claim says",
        arguments: TerminalClient.Program.allCases, WidthCorpus.clusters)
    func atEndOfRow(program: TerminalClient.Program, entry: WidthCorpus.Entry) {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: program)) {
            let claim = entry.text.strippedLength
            let emitted = TerminalClient.compensating(entry.text, for: program)
            #expect(
                landing(emitted, on: program) == claim,
                """
                \(entry) on \(program.rawValue): claimed \(claim) cells, \
                emitted output lands at \(landing(emitted, on: program))
                """)
        }
    }

    // MARK: - Whole rows

    /// A row is not just its clusters in sequence: the walks carry state (the
    /// "is anything after this" question, the SGR skipping), and a fragment
    /// that conserves on its own can stop doing so with a neighbour.
    @Test("A mixed row of every corpus class conserves", arguments: TerminalClient.Program.allCases)
    func mixedRow(program: TerminalClient.Program) {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: program)) {
            let row = WidthCorpus.clusters.map(\.text).joined(separator: " ")
            let claim = row.strippedLength
            let emitted = TerminalClient.compensating(row, for: program)
            #expect(landing(emitted, on: program) == claim, "\(program.rawValue) mixed row")
        }
    }

    /// SGR runs are what a real row is made of, and the walks skip escapes by
    /// hand — a walk that mis-parses one counts its bytes as visible cells.
    @Test("Colour escapes around a cluster change nothing", arguments: TerminalClient.Program.allCases)
    func colouredRow(program: TerminalClient.Program) {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: program)) {
            for entry in WidthCorpus.clusters {
                let row = "\u{1B}[31m\(entry.text)\u{1B}[0m]"
                let claim = row.strippedLength
                let emitted = TerminalClient.compensating(row, for: program)
                #expect(
                    landing(emitted, on: program) == claim,
                    "\(entry) on \(program.rawValue), inside an SGR run")
            }
        }
    }

    // MARK: - Degenerate joiner clusters

    /// A truncated or stray-joiner cluster — a family emoji cut at a byte
    /// limit ("👨‍👩‍"), a letter with a trailing ZWJ from Arabic-style
    /// joining ("x‍"), a doubled joiner — is a single grapheme cluster that
    /// reaches the width scan and the walks like any other user data. The
    /// joiner summers used to build a `Character` from the empty segment such
    /// a cluster leaves, which is a stdlib `fatalError`: measuring the string
    /// alone crashed on the hosts whose traits decompose ZWJ (Apple Terminal,
    /// Warp), and `warpCursorAdvance` crashed on ANY letter+ZWJ cluster. They
    /// now decline the cluster (same answer as `emojiZWJSegments`), so it
    /// prices and emits as an ordinary unmeasured cluster: nothing to pin but
    /// no-trap and conservation.
    @Test(
        "A degenerate joiner cluster neither traps nor drifts",
        arguments: TerminalClient.Program.allCases,
        ["👨\u{200D}👩\u{200D}", "👍\u{200D}", "👍\u{200C}", "x\u{200D}", "👨\u{200D}\u{200D}"])
    func degenerateJoinerCluster(program: TerminalClient.Program, cluster: String) {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: program)) {
            #expect(cluster.count == 1, "not one grapheme — the case tests nothing")
            let row = cluster + "|"
            let claim = row.strippedLength
            let emitted = TerminalClient.compensating(row, for: program)
            #expect(
                landing(emitted, on: program) == claim,
                "\(cluster.unicodeScalars.map { String(format: "U+%04X", $0.value) }) on \(program.rawValue)")
        }
    }

    // MARK: - The oracle itself

    /// `cursorAdvance(perCharacter:)` is what every expectation above is
    /// measured with, so it gets its own checks — an oracle that miscounts
    /// makes the whole suite agree with itself about nothing.
    @Test("The advance oracle counts cursor moves and ignores everything else")
    func oracleCountsMovesOnly() {
        let ascii: (Character) -> Int = { _ in 1 }
        #expect("abc".cursorAdvance(perCharacter: ascii) == 3)
        #expect("a\u{1B}[31mb".cursorAdvance(perCharacter: ascii) == 2, "SGR moves nothing")
        #expect("a\u{1B}[2Xb".cursorAdvance(perCharacter: ascii) == 2, "ECH paints without moving")
        #expect("a\u{1B}[3Cb".cursorAdvance(perCharacter: ascii) == 5, "CUF(3)")
        #expect("a\u{1B}[Cb".cursorAdvance(perCharacter: ascii) == 3, "CUF with no parameter is 1")
        #expect("a\u{1B}[2Db".cursorAdvance(perCharacter: ascii) == 0, "CUB(2)")
        #expect("\u{1B}[?25l".cursorAdvance(perCharacter: ascii) == 0, "a private-marker sequence")
    }

    // MARK: - The replay patch

    /// A row is compensated when it is RENDERED, and the frame an animation
    /// replay splices into it is compensated again — and both walks own the same
    /// cells. So the pair the render put around them has to come out before the
    /// frame's pair goes in, or the row keeps two `CUF`s where it claimed one
    /// advance, and every cell after the run sits one place to the right.
    ///
    /// Reported as a focused `Toggle`'s label shifting one cell right in
    /// Ghostty, appearing and disappearing as renders and replays alternated on
    /// that row. Ghostty alone because it is the only measured host that
    /// compensates `⬜︎` — a chrome glyph under VS-15 — so on Apple Terminal,
    /// iTerm2 and Warp the same row goes out bare and there was nothing to
    /// duplicate.
    ///
    /// Asserted against the RENDERED row rather than against a number: the
    /// replay's job is to change the picture and nothing else, so the two must
    /// land in the same column whatever the host's model says that column is.
    @MainActor
    @Test(
        "A replayed run lands the row exactly where the render did",
        arguments: TerminalClient.Program.allCases,
        ["\u{2B1C}\u{FE0E}", "\u{2699}\u{FE0F}", "x", "\u{1F600}"])
    func replayPatchConservesTheAdvance(program: TerminalClient.Program, glyph: String) {
        TerminalWidthTraits.withTraits(TerminalClient.widthTraits(of: program)) {
            let writer = FrameDiffWriter(
                isAppleTerminal: program == .appleTerminal,
                isITerm2: program == .iTerm2,
                isGhostty: program == .ghostty,
                isWarp: program == .warp,
                isTmux: false)
            // The shape of a Toggle's row: the animated glyph at column 1, its
            // label after it. The label is what moves when the arithmetic slips.
            let raw = " " + glyph + " Enable Notifications"
            let width = glyph.strippedLength
            let rendered = writer.buildOutputLines(
                buffer: FrameBuffer(lines: [raw]),
                terminalWidth: 40, terminalHeight: 1,
                bgCode: "\u{1B}[48;5;16m", reset: "\u{1B}[0m")[0]
            // The run replaces the glyph's cells with the same glyph in another
            // colour, which is what a focus pulse is.
            let frame = "\u{1B}[38;5;35m" + glyph + "\u{1B}[0m"
            let patched = writer.patchingAnimatedRun(
                in: rendered, with: frame, atColumn: 1, width: width, terminalWidth: 40)

            let claim = landing(rendered, on: program)
            #expect(
                landing(patched, on: program) == claim,
                """
                \(program) \(glyph.unicodeScalars.map { "U+\(String($0.value, radix: 16, uppercase: true))" }.joined(separator: " ")): \
                the render lands at \(claim) and the replay at \
                \(landing(patched, on: program))
                """)
            // And the label is still there, unshifted — the symptom itself.
            #expect(patched.stripped.contains("Enable Notifications"))
        }
    }
}
