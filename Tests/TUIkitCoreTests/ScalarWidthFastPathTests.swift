//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScalarWidthFastPathTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkitCore

// Guards for the scalar-level width fast paths: measuring a line without asking
// the standard library to segment it into grapheme clusters. The fast paths are
// only sound because of two claims, and each test below pins one of them
// against an independent oracle rather than against a hand-written table.

// MARK: - The stand-alone-cluster allow-list

@Suite("Standalone-cluster allow-list")
struct StandaloneClusterScalarTests {

    /// Every scalar the allow-list admits must genuinely stand alone: it must
    /// not fuse with a neighbour on either side, nor with a copy of itself.
    ///
    /// Those three probes cover every grapheme rule that can suppress a break:
    /// a following `Extend`/`SpacingMark`/`ZWJ`/jamo-V/T shows up as fusing
    /// *after* a plain base, a `Prepend` as fusing *before* one, and the
    /// pairwise rules that need two of a kind (regional-indicator flags,
    /// jamo-L runs) as fusing with itself. The oracle is the standard library's
    /// own segmentation — `String.count` counts `Character`s.
    ///
    /// A scalar wrongly *excluded* from the list only costs speed. A scalar
    /// wrongly *included* would silently mis-measure text, so this sweeps the
    /// whole of Unicode rather than a sample.
    @Test("every admitted scalar breaks against a base, a prepend position and itself")
    func admittedScalarsAlwaysBreak() {
        let base: Unicode.Scalar = "A"
        var checked = 0
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }  // skips surrogates
            guard Character.isStandaloneClusterScalar(value) else { continue }
            checked += 1

            #expect(
                String(String.UnicodeScalarView([base, scalar])).count == 2,
                "U+\(String(value, radix: 16, uppercase: true)) fuses onto a preceding base")
            #expect(
                String(String.UnicodeScalarView([scalar, base])).count == 2,
                "U+\(String(value, radix: 16, uppercase: true)) fuses onto a following base")
            #expect(
                String(String.UnicodeScalarView([scalar, scalar])).count == 2,
                "U+\(String(value, radix: 16, uppercase: true)) fuses with itself")
        }
        // Sanity: the list is not accidentally empty (which would pass vacuously
        // while quietly disabling every fast path it gates).
        #expect(checked > 100_000)
    }

    @Test("the scalars that can combine are all excluded")
    func combiningScalarsAreExcluded() {
        let dangerous: [UInt32] = [
            0x0301,  // combining acute
            0x0300,  // combining grave
            0x200D,  // ZWJ
            0xFE0F, 0xFE0E,  // variation selectors
            0x1F3FB, 0x1F3FF,  // Fitzpatrick skin-tone modifiers
            0x1F1E6, 0x1F1FF,  // regional indicators (flags)
            0x1100, 0x1161, 0x11A8,  // Hangul jamo L / V / T
            0xAC00,  // precomposed Hangul syllable (LV — a T jamo may follow)
            0x0903,  // Devanagari sign visarga (SpacingMark)
            0x0600,  // Arabic number sign (Prepend)
            0x000D, 0x000A,  // CR, LF
            0x0E33,  // Thai sara am
            0x0483,  // Cyrillic combining titlo
        ]
        for value in dangerous {
            #expect(
                !Character.isStandaloneClusterScalar(value),
                "U+\(String(value, radix: 16, uppercase: true)) must not be admitted")
        }
    }
}

// MARK: - Per-scalar width

@Suite("Unicode.Scalar.loneTerminalWidth")
struct LoneScalarWidthTests {

    /// The per-scalar width must agree with the full `Character` width for
    /// every single-scalar cluster in Unicode — that equivalence is what lets
    /// the run scanners bypass segmentation without changing any measurement.
    @Test("agrees with Character.terminalWidth for every single-scalar cluster")
    func matchesCharacterWidthEverywhere() {
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            #expect(
                scalar.loneTerminalWidth == Character(scalar).terminalWidth,
                "U+\(String(value, radix: 16, uppercase: true))")
        }
    }
}

// MARK: - strippedLength

@Suite("strippedLength fast paths")
struct StrippedLengthFastPathTests {

    /// Independent oracle: `ansiSegments()` splits a string the same way (it
    /// drops complete CSI sequences and clusters each visible run on its own),
    /// but does it by materialising every `Character`. Summing those widths is
    /// the slow, obvious implementation the fast paths must agree with.
    private func oracle(_ text: String) -> Int {
        text.ansiSegments().reduce(0) { total, segment in
            switch segment {
            case .ansi: return total
            case .visible(let character): return total + character.terminalWidth
            }
        }
    }

    @Test(
        "matches a per-Character oracle",
        arguments: [
            // Pure ASCII — the byte fast path.
            "", "hello", "hello world  ", "\u{7F}\u{01}tab\ttab",
            // Styled ASCII — the byte fast path, through the CSI state machine.
            "\u{1B}[31mred\u{1B}[0m", "\u{1B}[1;38;5;42mstyled\u{1B}[0m tail",
            "\u{1B}[?25lhidden cursor", "\u{1B}[2 qbar cursor",
            // Framework chrome — the box-drawing fast path.
            "┌──────┐", "│ Item │", "├──┼──┤", "▏▎▍▌▋▊▉█", "░▒▓█",
            "\u{1B}[34m│\u{1B}[0m label \u{1B}[34m│\u{1B}[0m",
            // Wide text.
            "日本語テキスト", "한국어", "ＦＵＬＬＷＩＤＴＨ",
            "\u{1B}[32m日本語\u{1B}[0m ascii",
            // Clusters that must fall back to real segmentation.
            "🤙🏽 waves", "👨‍👩‍👧‍👦 family", "🇬🇧🇯🇵 flags", "e\u{0301}cole", "1\u{FE0F}\u{20E3} keycap",
            "🖥️ screen", "〰️ wavy", "\u{1B}[31m🤙🏽\u{1B}[0m",
            // A modifier immediately after an SGR terminator must stay visible.
            "\u{1B}[31m\u{1F3FB}\u{1B}[0m", "\u{1B}[0m\u{0301}",
            // Malformed / truncated escapes.
            "\u{1B}", "\u{1B}[", "\u{1B}[31", "\u{1B}X", "\u{1B}\u{1B}[31mx",
            "\u{1B}[31\u{1B}[0mx", "a\u{1B}[\u{07}b",
        ])
    func matchesOracle(text: String) {
        #expect(text.strippedLength == oracle(text))
    }

    /// The ASCII fast path and the general scalar path must agree wherever
    /// both apply — a non-breaking space is measured identically to a plain
    /// one, so appending it flips the input off the ASCII path without
    /// changing the width of anything before it.
    @Test("the ASCII fast path agrees with the general path")
    func asciiPathAgreesWithGeneralPath() {
        let asciiCases = [
            "plain", "\u{1B}[31mred\u{1B}[0m", "a\u{1B}[1mb\u{1B}[0mc",
            "\u{1B}[38;2;10;20;30mtruecolor\u{1B}[0m", "\u{1B}[Kerase",
        ]
        for text in asciiCases {
            let general = text + "\u{00A0}"  // NBSP: one cell, but not ASCII
            #expect(text.asciiStrippedLength() == text.strippedLength)
            #expect(general.asciiStrippedLength() == nil)
            #expect(general.strippedLength == text.strippedLength + 1)
        }
    }

    @Test("stripped still returns the visible text")
    func strippedKeepsVisibleText() {
        #expect("\u{1B}[31mred\u{1B}[0m".stripped == "red")
        #expect("\u{1B}[34m│\u{1B}[0m x".stripped == "│ x")
        #expect("\u{1B}[31m\u{1F3FB}\u{1B}[0m".stripped == "\u{1F3FB}")
        #expect("no escapes".stripped == "no escapes")
    }
}

// MARK: - Pictographic-plane width

@Suite("Pictographic-plane width")
struct PictographicPlaneWidthTests {

    /// Only two things in U+1F000…U+1FBFF are two cells wide: an emoji, which
    /// macOS font fallback paints from Apple Color Emoji, and the Enclosed
    /// Ideographic Supplement, which is genuinely East Asian Wide.
    ///
    /// The rule claimed 2 for the WHOLE range until 2026-08-26, so mahjong,
    /// dominoes, playing cards, alchemical symbols, chess, arrows, ornamental
    /// dingbats, the Enclosed Alphanumeric Supplement and Symbols for Legacy
    /// Computing all reserved a cell they never painted, and every row
    /// containing one sheared. Measured over all 1361 assigned non-emoji
    /// scalars in the range on Terminal.app 455.1 and Ghostty 1.3.1, which
    /// agreed on every one: 1312 advance 1, and the 49 that advance 2 are
    /// exactly U+1F200…U+1F2FF.
    @Test("Non-emoji pictographic scalars are one cell, wide ideographs two")
    func nonEmojiPictographsAreNarrow() {
        for value in UInt32(0x1F000)...UInt32(0x1FBFF) {
            guard let scalar = Unicode.Scalar(value),
                scalar.properties.generalCategory != .unassigned
            else { continue }
            let properties = scalar.properties
            let isWideIdeographic = (0x1F200...0x1F2FF).contains(value)
            let isEmoji = properties.isEmoji || properties.isEmojiPresentation
            let expected = isWideIdeographic || isEmoji ? 2 : 1
            #expect(
                scalar.loneTerminalWidth == expected,
                "U+\(String(value, radix: 16, uppercase: true)) \(scalar)")
        }
    }

    /// Spot checks in the vocabulary the measurements were taken in, so a
    /// regression names the block it broke rather than a bare codepoint.
    @Test(
        "The blocks that were claimed wide and are not",
        arguments: [
            ("\u{1F000}", 1, "🀀 mahjong"),
            ("\u{1F060}", 1, "🁠 domino"),
            ("\u{1F0A1}", 1, "🂡 playing card"),
            ("\u{1F172}", 1, "🅲 Enclosed Alphanumeric Supplement"),
            ("\u{1F650}", 1, "🙐 ornamental dingbat"),
            ("\u{1F700}", 1, "🜀 alchemical"),
            ("\u{1F800}", 1, "🠀 Supplemental Arrows-C"),
            ("\u{1FA00}", 1, "🨀 chess"),
            ("\u{1FB00}", 1, "🬀 Symbols for Legacy Computing"),
            ("\u{1F200}", 2, "🈀 Enclosed Ideographic Supplement — genuinely wide"),
            ("\u{1F004}", 2, "🀄 the one mahjong tile that IS an emoji"),
            ("\u{1F0CF}", 2, "🃏 the one playing card that IS an emoji"),
            ("\u{1F5A5}", 2, "🖥 bare pictograph — Emoji=Yes, painted by fallback"),
            ("\u{1F44D}", 2, "👍 emoji presentation"),
        ] as [(String, Int, String)])
    func blockSpotChecks(text: String, expected: Int, what: String) {
        #expect(Character(text).terminalWidth == expected, "\(what)")
    }
}

// MARK: - Zero-width format controls

/// The bidi controls are `Default_Ignorable_Code_Point` with no advance: they
/// tell a renderer how to ORDER what is around them and occupy nothing
/// themselves. They were measured as one cell each, so a line carrying one —
/// as text pasted from a bidirectional document does — measured a cell wider
/// than it drew and every column after it was placed wrong.
@Suite("Bidi controls take no cells")
struct BidiControlWidthTests {

    /// Every explicit directional formatting character, by name.
    private static let controls: [(String, UInt32)] = [
        ("LRM", 0x200E), ("RLM", 0x200F), ("ALM", 0x061C),
        ("LRE", 0x202A), ("RLE", 0x202B), ("PDF", 0x202C),
        ("LRO", 0x202D), ("RLO", 0x202E),
        ("LRI", 0x2066), ("RLI", 0x2067), ("FSI", 0x2068), ("PDI", 0x2069),
    ]

    @Test("each control on its own measures zero")
    func controlsAreZeroWidth() {
        for (name, value) in Self.controls {
            let text = String(Unicode.Scalar(value)!)
            #expect(text.strippedLength == 0, "\(name) (U+\(String(value, radix: 16))) measured \(text.strippedLength)")
        }
    }

    @Test("a control between letters does not widen the line")
    func controlsDoNotWidenText() {
        for (name, value) in Self.controls {
            let control = String(Unicode.Scalar(value)!)
            #expect("a\(control)b".strippedLength == 2, "\(name) widened \"ab\"")
        }
    }

    /// The case this was found for: forcing a Hebrew letter to lay out
    /// left-to-right wraps it in LRO … PDF, which must cost nothing. Three
    /// visible characters, five scalars.
    @Test("an LTR-forced Hebrew letter measures its one cell")
    func overriddenHebrewMeasuresOneCell() {
        let wrapped = "a\u{202D}\u{5D0}\u{202C}b"
        #expect(wrapped.strippedLength == 3)
        #expect("\u{5D0}".strippedLength == 1, "the letter itself is one cell")
    }
}
