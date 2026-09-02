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

// MARK: - Combining marks

/// The sibling of the bidi-control suite above, found the same way and wrong
/// for the same reason: a hand-written list of blocks that named five of the
/// dozens Unicode actually has.
///
/// A mark that measures one cell makes its line measure wider than it paints,
/// so everything after it on the row lands short — and unlike an exotic
/// codepoint nobody types, these are ordinary text. Hebrew with points and
/// Arabic with vowels are most religious, pedagogical and poetic writing in
/// both languages, and `Tools/TerminalProbes/bidi_card.py` draws them.
@Suite("Combining marks take no cells")
struct CombiningMarkWidthTests {

    /// One mark per script that the old block list missed, named so a failure
    /// says which writing system broke.
    private static let marks: [(String, UInt32)] = [
        ("Hebrew segol", 0x0592), ("Hebrew sheva", 0x05B0), ("Hebrew dagesh", 0x05BC),
        ("Arabic fatha", 0x064E), ("Arabic small high seen", 0x06D6),
        ("Arabic hamza above", 0x0654),
        ("Cyrillic titlo", 0x0483), ("Cyrillic psili", 0x0486),
        ("Syriac qushshaya", 0x0741), ("Samaritan", 0x0816),
        ("Devanagari udatta", 0x0951), ("Bengali candrabindu", 0x0981),
        ("Thai mai ek", 0x0E48), ("Lao", 0x0EC8),
        ("Tibetan", 0x0F82), ("Myanmar", 0x1037),
        ("Ethiopic gemination", 0x135F), ("Khmer", 0x17DD),
        ("Balinese", 0x1B6B), ("Vedic", 0x1CD0),
        ("Coptic", 0x2CEF), ("Cyrillic ext-A", 0x2DE0),
        ("CJK tone mark", 0x302A), ("Kana voicing", 0x3099),
        ("Greek musical", 0x1D242),
    ]

    @Test("each mark on its own measures zero")
    func marksAreZeroWidth() {
        for (name, value) in Self.marks {
            guard let scalar = Unicode.Scalar(value) else {
                Issue.record("\(name) is not a scalar")
                continue
            }
            let width = scalar.loneTerminalWidth
            #expect(width == 0, "\(name) (U+\(String(value, radix: 16, uppercase: true))) measured \(width)")
        }
    }

    /// The two that sit INSIDE the East-Asian-Wide ranges, which is why a
    /// block list could not have caught them: U+302A…U+302D and U+3099/U+309A
    /// are surrounded by genuinely two-cell ideographs.
    @Test("the marks buried in the CJK ranges are not two cells")
    func cjkMarksAreNotWide() {
        for value: UInt32 in [0x302A, 0x302B, 0x302C, 0x302D, 0x3099, 0x309A] {
            #expect(Unicode.Scalar(value)?.loneTerminalWidth == 0)
        }
        // Their neighbours still are, so the fix took a mark and not a range.
        #expect(Unicode.Scalar(0x3029)?.loneTerminalWidth == 2)
        #expect(Unicode.Scalar(0x309B)?.loneTerminalWidth == 2)
    }

    /// A **spacing** combining mark does advance, and must not be swept up:
    /// this is why the rule is `Mn`/`Me` and not "anything Unicode calls a
    /// mark".
    @Test("a spacing combining mark still takes its cell")
    func spacingMarksStillAdvance() {
        #expect(Unicode.Scalar(0x093E)?.loneTerminalWidth == 1, "Devanagari aa matra")
        #expect(Unicode.Scalar(0x0BBE)?.loneTerminalWidth == 1, "Tamil aa matra")
    }

    /// The cluster path, which is a different function and had the same hole:
    /// a base carrying only non-advancing marks is exactly as wide as the base.
    @Test("a pointed letter is as wide as the letter")
    func pointedLettersMeasureTheirBase() {
        #expect("\u{5D0}\u{05B7}".strippedLength == 1, "aleph with patah")
        #expect("\u{5D0}\u{05B7}\u{05BC}".strippedLength == 1, "…and a dagesh too")
        #expect("\u{0628}\u{064E}".strippedLength == 1, "beh with fatha")
        #expect("\u{3053}\u{3099}".strippedLength == 2, "a kana keeps its two cells")
    }

    /// The line-level consequence, which is the defect itself: a word of
    /// pointed Hebrew measured wider than it paints, so a bordered row
    /// containing one drew its right edge short.
    @Test("a line of pointed text measures its letters")
    func pointedLineMeasuresItsLetters() {
        // בְּרֵאשִׁית — six letters, eleven scalars.
        let word = "\u{5D1}\u{05B0}\u{05BC}\u{5E8}\u{05B5}\u{5D0}\u{5E9}\u{05B4}\u{05C1}\u{5D9}\u{5EA}"
        #expect(word.strippedLength == 6)
    }
}

/// The generated table against the source it was generated from.
///
/// `combiningMarkRanges` exists only because asking
/// `Unicode.Scalar.Properties.generalCategory` on the width path cost a
/// measured 2–3% on four Stress scenarios. That makes it an optimisation, and
/// an optimisation that can disagree with the thing it replaces is a bug
/// waiting for a toolchain update — Swift ships a new Unicode version and a
/// newly-assigned mark starts measuring one cell in whatever script got it.
///
/// So the table is not trusted: it is checked, against every codepoint.
@Suite("Combining-mark table")
struct CombiningMarkRangeTests {

    private static func isMark(_ value: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(value) else { return false }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark: return true
        default: return false
        }
    }

    @Test("agrees with the standard library for every codepoint")
    func tableMatchesUnicode() {
        var mismatches: [UInt32] = []
        for value: UInt32 in 0...0x10FFFF where
            Character.isNonAdvancingMark(value) != Self.isMark(value)
        {
            mismatches.append(value)
            if mismatches.count >= 8 { break }
        }
        let listed = mismatches.map { "U+" + String($0, radix: 16, uppercase: true) }
        #expect(
            mismatches.isEmpty,
            "regenerate with Tools/GenerateCombiningMarks/generate.swift — \(listed)")
    }

    /// The two comparisons that take the common answer. If either bound were
    /// wrong the search would be skipped for real marks, which the sweep above
    /// would catch — this says WHY it is safe, so a future edit to the bounds
    /// has something to fail against.
    @Test("the floor and ceiling bracket every range")
    func boundsBracketTheTable() {
        #expect(combiningMarkRanges.first?.0 == combiningMarkFloor)
        #expect(combiningMarkRanges.last?.1 == combiningMarkCeiling)
        #expect(!Character.isNonAdvancingMark(combiningMarkFloor - 1))
        #expect(Character.isNonAdvancingMark(combiningMarkFloor))
        #expect(Character.isNonAdvancingMark(combiningMarkCeiling))
        #expect(!Character.isNonAdvancingMark(combiningMarkCeiling + 1))
    }

    /// Sorted and disjoint, or the binary search can walk past a range that
    /// contains the value.
    @Test("the ranges are sorted and do not overlap")
    func tableIsSearchable() {
        for (previous, next) in zip(combiningMarkRanges, combiningMarkRanges.dropFirst()) {
            #expect(previous.0 <= previous.1)
            #expect(previous.1 < next.0, "ranges overlap or are out of order")
        }
    }
}
