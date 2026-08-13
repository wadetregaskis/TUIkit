//  🖥️ TUIKit — Terminal UI Kit for Swift
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
