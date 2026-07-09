//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ComplexGraphemeWidthTests.swift
//
//  Terminal-cell width of complex grapheme clusters — the corpus the
//  WideCharBoundarySweep's single-scalar emoji didn't cover: ZWJ sequences,
//  regional-indicator flags, skin-tone modifiers, keycaps, FE0F emoji, and —
//  the one that was wrong — DECOMPOSED (NFD) accented letters.
//
//  A base letter carrying only combining marks (e + U+0301 = "é" in NFD) is
//  one grapheme that occupies ONE cell; the width code forced it to 2 by
//  treating any non-variation-selector extra scalar as a wide sequence. macOS
//  hands filenames back in NFD, so `Text(filename)`, List rows and Table
//  cells with accented names drifted every border and truncated wrong. Fixed
//  by recognising combining marks / ZWJ / tags as width-neutral extras, so
//  the cluster keeps its base width; genuine sequences (ZWJ emoji, flags,
//  skin tones) still measure 2.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Complex grapheme cluster width")
struct ComplexGraphemeWidthTests {
    @Test("Decomposed (NFD) accented letters are one cell")
    func nfdAccentedIsOneCell() {
        #expect("e\u{0301}".strippedLength == 1, "NFD é")
        #expect("a\u{0300}".strippedLength == 1, "NFD à")
        #expect("o\u{0302}".strippedLength == 1, "NFD ô")
        #expect("n\u{0303}".strippedLength == 1, "NFD ñ")
        #expect("\u{00E9}".strippedLength == 1, "composed é (single scalar)")
        #expect("cafe\u{0301}".strippedLength == 4, "café in NFD")
        #expect("re\u{0301}sume\u{0301}".strippedLength == 6, "résumé in NFD")
        // The single-Character width agrees.
        #expect(Character("e\u{0301}").terminalWidth == 1)
    }

    @Test("Genuine wide clusters still measure two cells")
    func wideClustersStillTwo() {
        for s in ["👨‍👩‍👧‍👦", "👩‍❤️‍👨", "🇺🇸", "🇯🇵", "👍🏽", "👋🏻", "1️⃣", "❤️", "🏴‍☠️"] {
            #expect(s.strippedLength == 2, "'\(s)' should be 2 cells, got \(s.strippedLength)")
        }
    }

    @Test("A CJK base carrying a combining mark stays two cells")
    func cjkPlusCombining() {
        #expect("中\u{0301}".strippedLength == 2)
    }

    @Test("Truncation keeps NFD text intact and never overflows")
    func truncationNFD() {
        let s = "cafe\u{0301} re\u{0301}sume\u{0301}"  // "café résumé", NFD
        for target in 0...(s.strippedLength + 2) {
            let t = s.truncatedToWidth(target)
            #expect(t.strippedLength <= target, "trunc(\(target)) overflowed: '\(t)' (\(t.strippedLength))")
        }
    }

    @Test("Text renders NFD and emoji clusters within the offered width")
    func textWithinWidth() {
        for w in 1...12 {
            for s in ["cafe\u{0301} \u{00E9}clair", "👨‍👩‍👧‍👦 family", "flags 🇺🇸🇯🇵"] {
                let buf = renderToBuffer(Text(s), context: makeBareRenderContext(width: w, height: 4))
                for line in buf.lines {
                    #expect(line.strippedLength <= w, "Text('\(s)')@w\(w): '\(line.stripped)' = \(line.strippedLength)")
                }
            }
        }
    }
}
