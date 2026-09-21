//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ANSIPrefixKnownWidthTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// Pins `ansiAwarePrefix(visibleCount:knownVisibleWidth:)` — the
/// trailing-plain-spaces byte-drop fast path — to the exact walk it
/// short-cuts: for every input, at every cut point, the two must be
/// **byte-identical**, fast path taken or not. The corpus deliberately mixes
/// the shapes that could break the equivalence: styled tails, resets before
/// and after padding, wide characters at the cut, spaces inside escape
/// sequences (CSI intermediate bytes), and cuts that land on, inside, and
/// past the trailing space run.
@Suite("ANSI prefix with known width")
struct ANSIPrefixKnownWidthTests {

    private let corpus: [String] = [
        // The motivating shape: a padded row line one cell over its slot.
        "\u{1B}[38;5;40m status\u{1B}[0m ",
        " plain content with trailing pad   ",
        // Reset AFTER the padding (a persistent-background row): the walk
        // drops it with the pad; the fast path must agree byte-for-byte.
        "\u{1B}[48;5;17m selected row   \u{1B}[0m",
        // Escape at the very end of the kept region.
        "abc\u{1B}[31mdef\u{1B}[0m   ",
        // Wide characters near the cut.
        "日本語テスト ",
        "mix 日本 and ascii  ",
        // A CSI sequence carrying an INTERMEDIATE space byte (cursor style),
        // right before trailing spaces: the byte-drop must not mistake the
        // escape's space for a cell (the verification re-scan catches it).
        "content\u{1B}[0 q  ",
        // Nothing but spaces.
        "        ",
        // Styled spaces (the escape precedes them, so they are still plain
        // bytes at the tail).
        "\u{1B}[7m ok \u{1B}[0m    ",
        // Empty and tiny.
        "",
        "x",
        " ",
        // ── The byte-wise clip's own boundaries ──────────────────────────
        // It runs the CSI state machine over UTF-8 and stops at the cut, so
        // what has to be pinned is every shape that decides whether it may.
        //
        // Plain and styled ASCII: the shapes it is FOR.
        "the quick brown fox jumps over the lazy dog, twice over",
        "\u{1B}[31mr\u{1B}[32me\u{1B}[33md\u{1B}[0m \u{1B}[1mbold\u{1B}[22m tail",
        // A hyperlink: ASCII, and it must still decline — the walk carries the
        // link across the cut and closes it, which a byte prefix cannot.
        "\u{1B}]8;;https://example.com\u{1B}\\link text\u{1B}]8;;\u{1B}\\ after",
        // An nF escape: also ASCII, also outside what the byte walk decides.
        "\u{1B}(Bhello there",
        // A private-marker CSI, which paints nothing and is not SGR.
        "\u{1B}[?25lhidden cursor",
        // ASCII controls: one cell each to the measurers, so the clip must
        // agree with them rather than with what a terminal would do.
        "tab\there\u{07}bell\u{7F}del",
        // Malformed: a CSI interrupted by ESC, and one truncated at the end.
        "\u{1B}[31\u{1B}[32mrecovered",
        "ends mid-sequence\u{1B}[",
        "lone escape \u{1B} here",
    ]

    @Test("Byte-identical to the exact walk at every cut point")
    func matchesExactWalk() {
        for string in corpus {
            let width = string.strippedLength
            for cut in 0...(width + 2) {
                // The oracle is the walk ITSELF, not the other fast path.
                // Both public entry points now short-circuit a line that
                // already fits, so comparing them to each other would agree
                // by construction over exactly the cuts that matters most.
                let walk = string.exactAnsiAwarePrefixWithWidth(visibleCount: cut)
                let plain = string.ansiAwarePrefixWithWidth(visibleCount: cut)
                let known = string.ansiAwarePrefixWithWidth(
                    visibleCount: cut, knownVisibleWidth: width)
                #expect(
                    walk.prefix == plain.prefix && walk.visibleWidth == plain.visibleWidth,
                    """
                    cut \(cut) of \(string.debugDescription): \
                    walk \(walk.prefix.debugDescription) (\(walk.visibleWidth)) \
                    vs fits-fast-path \(plain.prefix.debugDescription) (\(plain.visibleWidth))
                    """)
                #expect(
                    walk.prefix == known.prefix && walk.visibleWidth == known.visibleWidth,
                    """
                    cut \(cut) of \(string.debugDescription): \
                    walk \(walk.prefix.debugDescription) (\(walk.visibleWidth)) \
                    vs known-width \(known.prefix.debugDescription) (\(known.visibleWidth))
                    """)
            }
        }
    }

    /// The Terminal.app clip's fast path carries a second obligation the
    /// plain one does not: that walk substitutes plain spaces for an
    /// over-advancer whose mid-emission peak would cross the right edge, and
    /// that can fire on a line whose visible cells all fit. So the corpus
    /// here adds clusters that over-advance on Terminal.app, cut at every
    /// point including the ones where the substitution triggers.
    @Test("The Terminal.app clip is byte-identical to its walk at every cut")
    func terminalAppMatchesExactWalk() {
        let inputs = corpus + [
            // Over-advancers: skin tone (claims 2, advances 4), a keycap, a
            // tag flag, and one sitting at the very end of a line that fits.
            "ok 🤙🏽 done",
            "\u{1B}[32m🤙🏽\u{1B}[0m  ",
            "1️⃣ 2️⃣ 3️⃣",
            "🏴󠁧󠁢󠁳󠁣󠁴󠁿 flag",
            "aaaaaaaa🤙🏽",
            "🖥️ ❤️ ⚠️ mixed",
            // Bordered rows — the shape the fast path exists for.
            "│ plain ascii row │",
            "┌──────────────┐",
            "│ 日本語 │",
            "│ 🤙🏽 │",
        ]
        for string in inputs {
            let width = string.strippedLength
            for cut in 0...(width + 2) {
                let walk = string.exactAnsiAwarePrefixForTerminalAppWithWidth(visibleCount: cut)
                let fast = string.ansiAwarePrefixForTerminalAppWithWidth(visibleCount: cut)
                #expect(
                    walk.prefix == fast.prefix && walk.visibleWidth == fast.visibleWidth,
                    """
                    cut \(cut) of \(string.debugDescription): \
                    walk \(walk.prefix.debugDescription) (\(walk.visibleWidth)) \
                    vs fast \(fast.prefix.debugDescription) (\(fast.visibleWidth))
                    """)
            }
        }
    }

    /// A hand-written corpus proves the shapes someone thought of. This one
    /// proves the shapes nobody did: 4,000 lines assembled from the alphabet
    /// the byte-wise clip has to make decisions about — ASCII text and
    /// controls, SGR sequences of every parameter form, private-marker and
    /// malformed CSIs, hyperlinks, `ESC ( B`, a bare `ESC`, wide glyphs,
    /// combining marks and over-advancers — cut at every point.
    ///
    /// Deterministic: a fixed seed and a hand-rolled generator, so a failure
    /// names an input that can be pasted straight into the corpus above and a
    /// passing run means the same thing tomorrow.
    @Test("A seeded fuzz of mixed lines is byte-identical to the walk")
    func fuzzMatchesExactWalk() {
        let pieces = [
            "a", "bc", "def ", "  ", "\t", "\u{07}", "\u{7F}", "x",
            "\u{1B}[0m", "\u{1B}[m", "\u{1B}[31m", "\u{1B}[38;5;200m",
            "\u{1B}[38;2;10;20;30m", "\u{1B}[1;4;7m", "\u{1B}[0 q", "\u{1B}[?25l",
            "\u{1B}[2J", "\u{1B}[31", "\u{1B}", "\u{1B}(B",
            "\u{1B}]8;;https://e.co\u{1B}\\", "\u{1B}]8;;\u{1B}\\",
            "日", "本語", "🤙🏽", "👨‍👩‍👧‍👦", "❤️", "A\u{0308}", "\u{1F3FD}",
        ]
        var seed: UInt64 = 0x5715_2025
        func next(_ bound: Int) -> Int {
            // xorshift64*, so the sequence is fixed and independent of the
            // platform's `SystemRandomNumberGenerator`.
            seed ^= seed >> 12
            seed ^= seed << 25
            seed ^= seed >> 27
            return Int((seed &* 0x2545_F491_4F6C_DD1D) >> 33) % bound
        }
        for _ in 0..<4_000 {
            var line = ""
            for _ in 0..<next(8) { line += pieces[next(pieces.count)] }
            let width = line.strippedLength
            for cut in 0...(width + 2) {
                let walk = line.exactAnsiAwarePrefixWithWidth(visibleCount: cut)
                let plain = line.ansiAwarePrefixWithWidth(visibleCount: cut)
                let known = line.ansiAwarePrefixWithWidth(
                    visibleCount: cut, knownVisibleWidth: width)
                #expect(
                    walk.prefix == plain.prefix && walk.visibleWidth == plain.visibleWidth,
                    "cut \(cut) of \(line.debugDescription): plain path diverged")
                #expect(
                    walk.prefix == known.prefix && walk.visibleWidth == known.visibleWidth,
                    "cut \(cut) of \(line.debugDescription): known-width path diverged")
                let appWalk = line.exactAnsiAwarePrefixForTerminalAppWithWidth(visibleCount: cut)
                let appFast = line.ansiAwarePrefixForTerminalAppWithWidth(visibleCount: cut)
                #expect(
                    appWalk.prefix == appFast.prefix
                        && appWalk.visibleWidth == appFast.visibleWidth,
                    "cut \(cut) of \(line.debugDescription): Terminal.app path diverged")
            }
        }
    }

    @Test("A cut past the width returns the string unchanged")
    func noCutNeeded() {
        let line = "\u{1B}[32mok\u{1B}[0m  "
        let width = line.strippedLength
        let (prefix, visibleWidth) = line.ansiAwarePrefixWithWidth(
            visibleCount: width + 5, knownVisibleWidth: width)
        #expect(prefix == line)
        #expect(visibleWidth == width)
    }
}
