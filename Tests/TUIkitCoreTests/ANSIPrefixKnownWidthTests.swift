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
