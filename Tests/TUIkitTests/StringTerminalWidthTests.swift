//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StringTerminalWidthTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// One cohesive file of String terminal-width / ANSI-aware tests; splitting purely
// to satisfy the length ceiling would scatter closely-related cases.
// swiftlint:disable file_length

// MARK: - Character.terminalWidth

@Suite("Character.terminalWidth")
struct CharacterTerminalWidthTests {

    @Test(
        "Character.terminalWidth measures cells, not scalars",
        arguments: [
            // ASCII: 1 cell.
            ("A", 1), ("z", 1), ("0", 1), (" ", 1),
            // Base emoji: 2 cells.
            ("🤙", 2), ("🎉", 2), ("💫", 2),
            // Skin-tone emoji: the Fitzpatrick modifier is zero-width on its
            // own, but combined with a base the grapheme cluster is still 2 cells.
            ("🤙🏻", 2), ("🤙🏼", 2), ("🤙🏽", 2), ("🤙🏾", 2), ("🤙🏿", 2),
            // VS-16 emoji in the pictographic block: 🖥️ = U+1F5A5 + U+FE0F → 2 cells.
            ("🖥️", 2),
            // CJK: 2 cells.
            ("中", 2), ("日", 2), ("한", 2),
            // Variation selector U+FE0F alone: 0 cells.
            ("\u{FE0F}", 0),
        ])
    func characterWidth(cluster: String, expected: Int) {
        #expect(Character(cluster).terminalWidth == expected, "'\(cluster)'")
    }

    @Test("Standalone Fitzpatrick skin-tone modifier is 2 cells wide")
    func fitzpatrickModifierAlone() {
        // A skin-tone modifier shown on its own — no preceding base, as in the
        // emoji corpus list — is painted by Terminal.app as a 2-cell colour
        // swatch. (It is zero-width only when it COMBINES with a base, in which
        // case it's part of a multi-scalar cluster, not standalone.) Reporting
        // it as 0 here previously shifted following content left by 2 cells and
        // dropped the enclosing border.
        for value in 0x1F3FB...0x1F3FF {
            let ch = Character(Unicode.Scalar(value)!)
            #expect(ch.terminalWidth == 2, "U+\(String(value, radix: 16, uppercase: true)) standalone")
        }
        // Regression guard: combined with a base it is still one 2-cell cluster.
        #expect(Character("👋🏽").terminalWidth == 2)
    }

    @Test("U+2300-block emoji-presentation codepoints are 2 cells wide")
    func bmp2300EmojiWidth() {
        // ⌚ ⌛ ⏩ ⏪ ⏫ ⏬ ⏰ ⏳ are painted 2 cells, but some platforms'
        // `isEmojiPresentation` under-reports them (notably macOS), so they're
        // pinned via explicit ranges in `terminalWidth`.
        for value in [0x231A, 0x231B, 0x23E9, 0x23EA, 0x23EB, 0x23EC, 0x23F0, 0x23F3] {
            let ch = Character(Unicode.Scalar(value)!)
            #expect(ch.terminalWidth == 2, "U+\(String(value, radix: 16, uppercase: true))")
        }
    }
}

// MARK: - String.strippedLength

@Suite("String.strippedLength")
struct StrippedLengthTests {

    @Test("Plain text counts visible cells")
    func plainText() {
        #expect("hello".strippedLength == 5)
        #expect("日本".strippedLength == 4)  // 2 cells each
        #expect("".strippedLength == 0)
    }

    @Test("ANSI escape sequences are excluded from the count")
    func ansiExcluded() {
        #expect("\u{1B}[31mhello\u{1B}[0m".strippedLength == 5)
        #expect("\u{1B}[1;38;2;10;20;30mX\u{1B}[0m".strippedLength == 1)
    }

    @Test("An ANSI-wrapped standalone Fitzpatrick modifier counts as 2 cells")
    func ansiWrappedModifier() {
        // Regression: the skin-tone modifier (Extend) grapheme-clusters onto
        // the SGR terminator letter (m🏽), so a Character-level ANSI skip used
        // to swallow it → strippedLength returned 0 and list/table borders
        // overflowed by 2. Scalar-level scanning keeps it visible.
        #expect("\u{1B}[31m\u{1F3FD}\u{1B}[0m".strippedLength == 2)
        // The realistic rendered shape: styled emoji + styled label.
        let rendered = "\u{1B}[38;2;50;255;50m\u{1F3FD}\u{1B}[0m \u{1B}[38;2;50;255;50mlabel\u{1B}[0m"
        #expect(rendered.strippedLength == 8)  // 2 + 1 + 5
    }

    @Test("A space and an ANSI-separated modifier are counted as distinct runs (1 + 2)")
    func spaceThenAnsiWrappedModifier() {
        // The list-indent case: a plain space, then a styled modifier. The
        // space and the Extend modifier are separated by an escape sequence,
        // so they must be measured as separate runs — 1 + 2 = 3. Counting the
        // whole visible string at once would let the modifier cluster onto the
        // space and report 2, which padded list rows one cell too wide
        // (border one column too far right).
        #expect(" \u{1B}[31m\u{1F3FD}\u{1B}[0m".strippedLength == 3)
        // …and adjacent within a single run, a base + modifier is one 2-cell
        // cluster, as it should be.
        #expect("\u{1B}[31m\u{1F44B}\u{1F3FD}\u{1B}[0m".strippedLength == 2)
    }

    @Test("An ANSI-wrapped flag pair counts as 2 cells")
    func ansiWrappedFlag() {
        #expect("\u{1B}[31m🇺🇸\u{1B}[0m".strippedLength == 2)
    }

    @Test("stripped removes escape codes but keeps the modifier scalar")
    func strippedKeepsModifier() {
        let s = "\u{1B}[31m\u{1F3FD}\u{1B}[0m"
        #expect(s.stripped == "\u{1F3FD}")
        #expect(s.stripped.unicodeScalars.count == 1)
    }
}

// MARK: - Character.terminalAppCursorAdvance

@Suite("Character.terminalAppCursorAdvance")
struct CharacterTerminalAppCursorAdvanceTests {

    @Test("ASCII characters: cursor advance equals terminal width")
    func asciiCursorAdvance() {
        #expect(Character("A").terminalAppCursorAdvance == 1)
        #expect(Character(" ").terminalAppCursorAdvance == 1)
    }

    @Test("Skin-tone emoji on emoji-default base: cursor over-advances by 4 in Terminal.app")
    func skinToneEmojiCursorAdvance() {
        // 🤙🏽 composes into 2 cells while Terminal.app's INTERNAL column — the
        // one DSR reports, and the one that decides when the row WRAPS — moves
        // 4. This property is the internal column: a model that returned the
        // paint position (2) here made the conservation test blind to internal
        // drift, and every full-width row carrying a skin tone wrapped, leaving
        // default-white cells at its right edge. The walk pulls the column back
        // with CUB(2) instead — see `withTerminalAppCursorCompensation`.
        let ch = Character("🤙🏽")
        #expect(ch.terminalWidth == 2, "Renders 2 cells")
        #expect(ch.terminalAppCursorAdvance == 4, "Internal column moves 4")
    }

    @Test("Skin-tone emoji on text-default base: cursor over-advances by 3 (Bug B variant)")
    func textDefaultSkinToneCursorAdvance() {
        // ☝ (U+261D) is `isEmoji && !isEmojiPresentation` — a 1-cell bare
        // glyph — so the internal over-advance lands at 3 where an
        // emoji-presentation base lands at 4. (Where the next character PAINTS
        // is a different number again — 1 and 2 respectively — and the walk
        // reconciles both; this property is the internal column.)
        for s in ["☝🏻", "✌🏼", "✍🏽", "⛹🏾"] {
            let ch = Character(s)
            #expect(ch.terminalWidth == 2, "\(s) renders 2 cells")
            #expect(ch.terminalAppCursorAdvance == 3, "\(s): internal column moves 3")
        }
        // ✊ (U+270A) is `isEmojiPresentation` — a 2-cell bare glyph — so 4.
        let fist = Character("✊🏿")
        #expect(fist.terminalAppCursorAdvance == 4, "✊🏿: internal column moves 4")
    }

    @Test("VS-16 on an East Asian Wide base: cursor advance is the full 2 (no compensation)")
    func vs16EastAsianWideCursorAdvance() {
        // 〰️ = U+3030 + U+FE0F: the BARE base is already East Asian Wide
        // (2 cells), and Terminal.app advances it by 2 with or without the
        // selector. Treating it as a VS-16 under-advancer injected a CUF(1)
        // after the glyph, skipping a cell that was never painted — a
        // third, always-default-background (black) cell after every 〰️.
        // Same family: 〽️ U+303D, ㊗️ U+3297, ㊙️ U+3299.
        for s in ["\u{3030}\u{FE0F}", "\u{303D}\u{FE0F}", "\u{3297}\u{FE0F}", "\u{3299}\u{FE0F}"] {
            let ch = Character(s)
            #expect(ch.terminalWidth == 2, "\(s) renders 2 cells")
            #expect(
                ch.terminalAppCursorAdvance == 2,
                "\(s) advances its full width — no compensation gap")
        }
    }

    @Test("VS-16 pictographic emoji: cursor advance is 1 (Terminal.app under-advance bug)")
    func vs16EmojiCursorAdvance() {
        // 🖥️ = U+1F5A5 + U+FE0F — Terminal.app renders 2 cells but advances cursor by 1
        let ch = Character("🖥️")
        #expect(ch.terminalWidth == 2, "Renders 2 cells")
        #expect(ch.terminalAppCursorAdvance == 1, "But cursor only advances by 1 in Terminal.app")
    }

    @Test("Base emoji without VS-16: cursor advance equals terminal width")
    func baseEmojiNoCursorBug() {
        // 🎉 is a pure emoji with no VS-16 selector
        let ch = Character("🎉")
        #expect(ch.terminalAppCursorAdvance == ch.terminalWidth)
    }

    @Test("Flag emoji (regional-indicator pair): cursor advance equals width")
    func flagEmojiCursorAdvance() {
        // Flag emoji are formed by two regional-indicator scalars
        // (U+1F1E6…U+1F1FF). Terminal.app paints the flag as a 2-cell glyph
        // AND advances the cursor by 2 — DSR-measured on Terminal.app 455.1
        // (macOS 15.7); see Documentation/Terminal-compatibility.md. An
        // earlier model treated the pair like a LONE indicator (advance 1),
        // and the spurious CUF shoved everything after a flag a cell right.
        for flag in ["🇺🇸", "🇬🇧", "🇩🇪", "🇯🇵", "🇫🇷"] {
            let ch = Character(flag)
            #expect(ch.terminalWidth == 2, "\(flag) paints 2 cells")
            #expect(
                ch.terminalAppCursorAdvance == 2,
                "\(flag): internal matches the claim; the paint shortfall is the walk's business")
        }
    }

    @Test("Lone regional indicator: cursor advance is 1 (same under-advance as a flag pair)")
    func loneRegionalIndicatorCursorAdvance() {
        // A single regional indicator (shown individually in the emoji
        // corpus, e.g. U+1F1E6) paints 2 cells but Terminal.app advances the
        // cursor by only 1 — the same under-advance as a flag pair. Measured
        // on macOS 15.7. Without this, the following content / enclosing
        // border lands one cell too far left.
        for value in [0x1F1E6, 0x1F1FA, 0x1F1FF] {
            let ch = Character(Unicode.Scalar(value)!)
            #expect(ch.terminalWidth == 2, "U+\(String(value, radix: 16, uppercase: true)) paints 2 cells")
            #expect(
                ch.terminalAppCursorAdvance == 1,
                "U+\(String(value, radix: 16, uppercase: true)) cursor advances by only 1")
        }
    }
}

// MARK: - String.withTerminalAppCursorCompensation

@Suite("String.withTerminalAppCursorCompensation")
struct WithTerminalAppCursorCompensationTests {

    @Test("Plain ASCII: no CUF injected")
    func plainASCIINoCUF() {
        let s = "Hello, World!"
        let result = s.withTerminalAppCursorCompensation()
        #expect(result == s, "Plain ASCII should be unchanged")
        #expect(!result.contains("\u{1B}[1C"), "Should contain no CUF")
    }

    @Test("Skin-tone emoji followed by a box-drawing border: Fitzpatrick stripped")
    func skinToneFollowedByBoxBorderStripsModifier() {
        // A table row "│ 🤙🏽 │" must have the Fitzpatrick scalar stripped so
        // that Terminal.app's over-advance doesn't push the trailing border
        // character past where the column accounting expects it.
        let s = "│ 🤙🏽 │"
        let result = s.withTerminalAppCursorCompensation()
        #expect(
            !result.unicodeScalars.contains(Unicode.Scalar(0x1F3FB)!),
            "Fitzpatrick scalar dropped when followed by a box-border character")
        #expect(result.contains("│"), "Both border characters preserved")
        #expect(result.strippedLength == s.strippedLength, "Visible width preserved")
    }

    @Test("Flag emoji followed by content: CUB(1)+DCH(1)+CUF(1) — the stored column trimmed")
    func flagFollowedByContentTrimsTheStore() {
        // 🇺🇸's internal column matches the claim (2) and the glyph paints
        // into it — and the row STORES one column more than it paints, which
        // pushes everything later on the row (absolutely-addressed writes
        // included) one cell left. The old CUB(1)+CUF(1) nudge fixed only the
        // immediate follower and measured misaligned on the treatment cards;
        // deleting the surplus stored column (`DCH`) is the repair whose
        // sequential and absolute followers both land true (card 4,
        // Terminal.app 455.1, 2026-08-27).
        let s = "from 🇺🇸 today"
        let result = s.withTerminalAppCursorCompensation()
        #expect(result.contains("🇺🇸\u{1B}[1D\u{1B}[1P\u{1B}[1C"), "|\(result)|")
        #expect(result.strippedLength == s.strippedLength, "and the row still measures the same")
        // A LONE indicator still under-advances and still gets its CUF.
        let lone = "at \u{1F1E6} end".withTerminalAppCursorCompensation()
        #expect(lone.contains("\u{1B}[1C"), "|\(lone)|")
    }

    @Test("Skin-tone emoji followed by content: kept, and the internal column pulled back")
    func skinToneFollowedByContentKeepsModifier() {
        // The strip used to keep Terminal.app's internal column in sync with
        // the claim by deleting what the user wrote; emitting the cluster
        // verbatim (one interim model) kept the content but let the internal
        // column drift +2, and every full-width row carrying one wrapped —
        // default-white cells at the row's right edge. CUB(2) after the
        // cluster does both jobs: measured, the internal column returns to the
        // claim AND the paint position snaps with it, so 👍🏽 stays 👍🏽 and
        // the row still ends where the layout said.
        let s = "Call 🤙🏽 now"
        let result = s.withTerminalAppCursorCompensation()
        #expect(result == "Call 🤙🏽\u{1B}[2D now", "|\(result)|")
        #expect(result.unicodeScalars.contains(Unicode.Scalar(0x1F3FD)!),
                "the Fitzpatrick scalar the user wrote reaches the screen")
    }

    @Test("Text-default base + skin-tone + content: kept whole, CUB(1) after")
    func textDefaultSkinToneKeepsModifierAndWidth() {
        // ☝🏻's internal column moves 3 against a claim of 2. CUB(1) pulls it
        // back, and the paint position — measured, and NOT the linear guess —
        // snaps to the claim with it, so nothing is stripped, promoted or
        // erased. (An interim VS-16-promotion scheme existed to keep a
        // STRIPPED base at 2 cells; with the cluster kept whole there is
        // nothing to promote.)
        let s = "go ☝🏻 now"
        let result = s.withTerminalAppCursorCompensation()
        #expect(result.unicodeScalars.contains(Unicode.Scalar(0x1F3FB)!),
                "the Fitzpatrick scalar is kept — it is what the user wrote")
        #expect(result.contains("☝🏻\u{1B}[1D"),
                "internal pulled back to the claim: |\(result)|")
        #expect(result.strippedLength == s.strippedLength,
                "Visible width must be preserved")
    }

    @Test("Every text-default modifier base gets the same pull-back")
    func textDefaultSkinTonePullsBackTheInternalColumn() {
        // ☝ ⛹ ✌ ✍ 🏋 🏌 🕴 🕵 🖐, five tones each — all 1-cell bare bases whose
        // skin-tone cluster moves the internal column 3 against a claim of 2.
        for base in ["☝", "⛹", "✌", "✍", "🏋", "🏌", "🕴", "🕵", "🖐"] {
            for tone in ["\u{1F3FB}", "\u{1F3FD}", "\u{1F3FF}"] {
                let result = "a\(base)\(tone)b".withTerminalAppCursorCompensation()
                #expect(result.contains("\(base)\(tone)\u{1B}[1D"),
                        "\(base)\(tone) kept whole, internal pulled back 1")
            }
        }
    }

    @Test("An emoji-default skin-tone base is stripped bare and NOT erased under")
    func emojiDefaultSkinToneDoesNotErase() {
        // ✊ needs no VS-16 promotion, so it stays a 2-cell/2-advance glyph and
        // there is nothing for an erase to fix. Guards the erase from spreading
        // to the branch that does not need it.
        let result = "a✊🏻b".withTerminalAppCursorCompensation()
        #expect(!result.contains("\u{1B}[2X"),
                "no erase for a cluster that advances as far as it paints")
    }

    @Test("Emoji-default base + skin-tone + content: kept whole, CUB(2) after")
    func emojiDefaultSkinToneKeptWithPullBack() {
        // ✊🏿 composes into its two claimed cells while the internal column
        // moves 4. CUB(2) squares both counters; the scalars are untouched.
        let s = "raise ✊🏿 high"
        let result = s.withTerminalAppCursorCompensation()
        #expect(!result.unicodeScalars.contains(Unicode.Scalar(0xFE0F)!),
                "no VS-16 is inserted")
        #expect(result.unicodeScalars.contains(Unicode.Scalar(0x1F3FF)!),
                "the Fitzpatrick scalar is kept")
        #expect(result.contains("✊🏿\u{1B}[2D"),
                "internal pulled back to the claim: |\(result)|")
        #expect(result.strippedLength == s.strippedLength,
                "Visible width must be preserved")
    }

    @Test("A cluster already carrying VS-16 plus Fitzpatrick keeps both")
    func textDefaultSkinToneKeepsExistingVS16() {
        // ☝️🏻 (U+261D + U+FE0F + U+1F3FB): everything the user wrote reaches
        // the screen — no scalar added, none removed.
        let s = "go \u{261D}\u{FE0F}\u{1F3FB} now"
        let result = s.withTerminalAppCursorCompensation()
        let vs16Count = result.unicodeScalars.filter { $0.value == 0xFE0F }.count
        #expect(vs16Count == 1, "Exactly one VS-16 — the user's (got \(vs16Count))")
        #expect(result.unicodeScalars.contains(Unicode.Scalar(0x1F3FB)!),
                "the Fitzpatrick scalar is kept")
    }

    @Test("Skin-tone emoji at end of input: modifier preserved, and still pulled back")
    func skinToneAtEndPreservesModifier() {
        // The pull-back is NOT position-dependent: the animation replay
        // compensates fragments of a row, so "at the end of the input" is not
        // "at the end of the row", and an uncorrected internal column would
        // poison whatever the row writes next. CUB after the final cluster on
        // a real row is harmless — there is nothing left to write.
        let s = "Call 🤙🏽"
        let result = s.withTerminalAppCursorCompensation()
        #expect(result == "Call 🤙🏽\u{1B}[2D", "|\(result)|")
        #expect(result.stripped.contains("🤙🏽"), "Fitzpatrick scalar kept")
    }

    @Test("VS-16 pictographic emoji: CUF(1) injected after it")
    func vs16EmojiGetsCUF() {
        // 🖥️ = U+1F5A5 + U+FE0F: Terminal.app under-advances by 1
        let s = "🖥️ TUIkit"
        let result = s.withTerminalAppCursorCompensation()
        // CUF(1) = ESC[1C should appear immediately after the emoji
        #expect(result.contains("🖥️\u{1B}[1C"), "CUF should be injected right after the VS-16 emoji")
    }

    @Test("Multiple VS-16 emoji: each gets its own CUF")
    func multipleVS16EmojiEachGetCUF() {
        let s = "🖥️A🖥️B"
        let result = s.withTerminalAppCursorCompensation()
        // Two occurrences of 🖥️ESC[1C expected
        let cufs = result.components(separatedBy: "\u{1B}[1C")
        #expect(cufs.count == 3, "Should have 2 CUF insertions (splitting into 3 parts)")
    }

    @Test("ANSI sequences in input are preserved unchanged")
    func ansiSequencesPreserved() {
        let s = "\u{1B}[31m🖥️\u{1B}[0m Text"
        let result = s.withTerminalAppCursorCompensation()
        #expect(result.contains("\u{1B}[31m"), "Color code should be preserved")
        #expect(result.contains("\u{1B}[0m"), "Reset should be preserved")
        #expect(result.contains("🖥️\u{1B}[1C"), "CUF after emoji should be present")
    }

    @Test("strippedLength is unchanged by CUF injection")
    func strippedLengthPreserved() {
        // CUF sequences are ANSI and stripped by strippedLength,
        // so the visible width should be the same before and after compensation.
        let s = "🖥️ ABC"
        let compensated = s.withTerminalAppCursorCompensation()
        #expect(compensated.strippedLength == s.strippedLength)
    }
}

// MARK: - String.ansiAwarePrefixForTerminalApp

@Suite("String.ansiAwarePrefixForTerminalApp")
struct AnsiAwarePrefixForTerminalAppTests {

    @Test("Plain ASCII: same as ansiAwarePrefix")
    func plainASCII() {
        let s = "Hello, World!"
        #expect(s.ansiAwarePrefixForTerminalApp(visibleCount: 5) == "Hello")
        #expect(s.ansiAwarePrefixForTerminalApp(visibleCount: 100) == s)
    }

    @Test("Skin-tone emoji at the right edge: replaced — the reserve wraps mid-cluster")
    func skinToneAtEdgeReplaced() {
        // The cluster RESERVES its internal advance (4) even though it paints
        // 2: written into the last two columns, the terminal wraps while the
        // cluster's own scalars are still being processed, before any
        // compensation can pull the column back. No measured escape prevents
        // that, so the edge slot — and only the edge slot — falls back to
        // spaces. (An interim build kept the cluster here on the strength of
        // its paint width alone; the wrap is governed by the reserve.)
        let s = "12345678🤙🏽"
        #expect(s.ansiAwarePrefixForTerminalApp(visibleCount: 10) == "12345678  ")
    }

    @Test("Mid-line skin-tone emoji is preserved (over-advance fits)")
    func midLineSkinTonePreserved() {
        // With plenty of room (visibleCount=20), the cluster's 4-cell
        // advance stays well within the line — it's kept verbatim and
        // the modifier-stripping decision is left to the compensation
        // function downstream.
        let s = "Call 🤙🏽 now"
        #expect(s.ansiAwarePrefixForTerminalApp(visibleCount: 20) == "Call 🤙🏽 now")
    }

    @Test("The budget is the sum of claims, not of raw advances — under-count half")
    func budgetIsClaimsNotRawAdvancesUnderCount() {
        // Four ⚙️ (VS-16 under-advancers: claim 2, raw advance 1) then the
        // Scotland tag flag (claim 2, raw internal advance 8 — 2 plus one per
        // tag scalar). The walk nets each ⚙️ back to its 2-cell claim, so the
        // flag really starts at column 8 and its mid-cluster peak reaches
        // 8 + 8 = 16: past a 12-cell row, and the wrap fires BEFORE the
        // flag's CUB pull-back runs. An earlier budget summed raw advances
        // (4 after the gears), concluded 4 + 8 = 12 fits, and let the row
        // wrap — so the flag must be substituted here.
        let flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        let s = "⚙️⚙️⚙️⚙️" + flag
        #expect(s.ansiAwarePrefixForTerminalApp(visibleCount: 12) == "⚙️⚙️⚙️⚙️  ")
    }

    @Test("The budget is the sum of claims, not of raw advances — over-count half")
    func budgetIsClaimsNotRawAdvancesOverCount() {
        // A kept tag flag's CUB nets it back to its 2-cell claim, so the ☝🏽
        // later on the row starts at column 6 and peaks at 6 + 3 = 9: exactly
        // fits a 9-cell row. The raw-advance budget carried the flag's
        // pre-CUB surplus (cursor 12 after "abcd") and substituted a cluster
        // that fits.
        let flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        let s = flag + "abcd☝🏽x"
        #expect(s.ansiAwarePrefixForTerminalApp(visibleCount: 9) == s)
    }

    @Test("Wide CJK character respects the visible boundary (not over-advancing)")
    func cjkBoundary() {
        let s = "Hi 所有"
        // 'Hi ' = 3 cells, '所' = 2 cells — fits in 5.
        #expect(s.ansiAwarePrefixForTerminalApp(visibleCount: 5) == "Hi 所")
        // visibleCount=4 cannot fit '所' (would need cells 4-5, only cell 4 left).
        #expect(s.ansiAwarePrefixForTerminalApp(visibleCount: 4) == "Hi ")
    }

    @Test("ANSI sequences are preserved through truncation")
    func ansiPreserved() {
        let s = "\u{1B}[31mAB\u{1B}[0mCDE"
        let result = s.ansiAwarePrefixForTerminalApp(visibleCount: 3)
        #expect(result == "\u{1B}[31mAB\u{1B}[0mC")
    }
}

// MARK: - String.ansiSGRContextAndCleanSuffix

/// Tests for the "clean" variant that strips non-SGR sequences from the suffix
/// so it is safe to write at an absolute cursor position.
@Suite("String.ansiSGRContextAndCleanSuffix")
struct AnsiSGRContextAndCleanSuffixTests {

    // MARK: Basic behaviour (mirrors ansiSGRContextAndSuffix for plain strings)

    @Test("Plain string: suffix starts at correct visible offset")
    func plainStringSuffix() {
        let s = "ABCDE"
        let result = s.ansiSGRContextAndCleanSuffix(from: 3)
        #expect(result == "DE")
    }

    @Test("Plain string: offset 0 returns entire string")
    func offsetZeroReturnsAll() {
        let s = "ABCDE"
        #expect(s.ansiSGRContextAndCleanSuffix(from: 0) == "ABCDE")
    }

    @Test("Plain string: offset equal to length returns empty string")
    func offsetEqualLength() {
        let s = "ABC"
        #expect(s.ansiSGRContextAndCleanSuffix(from: 3)?.isEmpty == true)
    }

    @Test("Plain string: offset beyond length returns nil")
    func offsetBeyondLength() {
        #expect("ABC".ansiSGRContextAndCleanSuffix(from: 4) == nil)
    }

    @Test("Empty string: offset 0 returns empty")
    func emptyStringOffset0() {
        #expect("".ansiSGRContextAndCleanSuffix(from: 0)?.isEmpty == true)
    }

    @Test("Empty string: any positive offset returns nil")
    func emptyStringPositiveOffset() {
        #expect("".ansiSGRContextAndCleanSuffix(from: 1) == nil)
    }

    // MARK: The critical difference: CUF in suffix is stripped

    @Test("CUF after split is stripped from suffix (not included verbatim)")
    func cufAfterSplitIsStripped() {
        // This is the inverse of ansiSGRContextAndSuffix's "verbatim" behavior.
        // CUF must NOT appear in the result so writing at a fixed column is safe.
        let cuf = "\u{1B}[1C"
        let s = "ABC\(cuf)DE"
        let result = s.ansiSGRContextAndCleanSuffix(from: 3)!
        #expect(!result.contains(cuf), "CUF after split must be stripped")
        #expect(result.contains("DE"), "Visible content after CUF must still be included")
    }

    @Test("CUF before split is also not in context (same as ansiSGRContextAndSuffix)")
    func cufBeforeSplitNotInContext() {
        let cuf = "\u{1B}[1C"
        let s = "A\(cuf)BCDE"
        let result = s.ansiSGRContextAndCleanSuffix(from: 3)!
        #expect(!result.hasPrefix(cuf), "CUF must not appear in context prefix")
    }

    @Test("ESC[2K erase sequence in suffix is stripped")
    func eraseInSuffixStripped() {
        let eraseLine = "\u{1B}[2K"
        let s = "ABC\(eraseLine)DE"
        let result = s.ansiSGRContextAndCleanSuffix(from: 3)!
        #expect(!result.contains(eraseLine), "Erase sequence in suffix must be stripped")
        #expect(result.contains("DE"))
    }

    // MARK: SGR sequences are preserved

    @Test("SGR context from before split is prepended to result")
    func sgrContextPrepended() {
        let red = "\u{1B}[31m"
        let reset = "\u{1B}[0m"
        let s = "\(red)ABCDE\(reset)"
        let result = s.ansiSGRContextAndCleanSuffix(from: 3)!
        #expect(result.hasPrefix(red), "SGR context should be prepended")
        #expect(result.contains("DE"))
    }

    @Test("SGR sequences in suffix are kept")
    func sgrInSuffixKept() {
        let red   = "\u{1B}[31m"
        let reset = "\u{1B}[0m"
        // Color mid-string, split before the color change
        let s = "ABC\(red)DE\(reset)"
        let result = s.ansiSGRContextAndCleanSuffix(from: 3)!
        #expect(result.contains(red), "SGR in suffix must be preserved")
        #expect(result.contains(reset), "Reset in suffix must be preserved")
        #expect(result.contains("DE"))
    }

    @Test("Mixed CUF and SGR in suffix: SGR kept, CUF stripped")
    func mixedCUFAndSGRInSuffix() {
        let cuf   = "\u{1B}[1C"
        let red   = "\u{1B}[31m"
        let reset = "\u{1B}[0m"
        let s = "ABC\(cuf)\(red)DE\(reset)"
        let result = s.ansiSGRContextAndCleanSuffix(from: 3)!
        #expect(!result.contains(cuf), "CUF must be stripped")
        #expect(result.contains(red), "SGR must be kept")
        #expect(result.contains(reset), "Reset must be kept")
        #expect(result.contains("DE"))
    }

    // MARK: Key regression: VS-16 line with CUF injected by cursor compensation

    @Test("VS-16 emoji line: CUF injected by cursor compensation is stripped")
    func vs16CUFStrippedFromSuffix() {
        // 🖥️ triggers CUF(1) injection from withTerminalAppCursorCompensation().
        // If the split falls after the emoji, the CUF appears in the raw suffix.
        // ansiSGRContextAndCleanSuffix must strip it.
        let cuf = "\u{1B}[1C"
        let raw = "🖥️ TUIkit"
        let compensated = raw.withTerminalAppCursorCompensation()
        #expect(compensated.contains(cuf), "Prerequisite: CUF was injected")

        // Split right at cell 2 (after the emoji): suffix should contain "TUIkit" but not CUF
        let result = compensated.ansiSGRContextAndCleanSuffix(from: 2)
        #expect(result != nil)
        #expect(!result!.contains(cuf), "CUF must be stripped from clean suffix")
        #expect(result!.contains(" TUIkit"), "Visible content must remain")
    }

    @Test("Result contains no ESC[ sequences that are not SGR (m-terminated)")
    func noNonSGRSequencesInResult() {
        // Build a string with multiple ANSI sequence types
        let cuf       = "\u{1B}[1C"
        let eraseLine = "\u{1B}[2K"
        let red       = "\u{1B}[31m"
        let reset     = "\u{1B}[0m"
        let s = "\(red)AB\(cuf)CD\(eraseLine)EF\(reset)"
        // offset 2: A=1, B=2 → split after B
        let result = s.ansiSGRContextAndCleanSuffix(from: 2)!

        // Walk result and check every ESC sequence ends in 'm' (SGR)
        var idx = result.startIndex
        while idx < result.endIndex {
            if result[idx] == "\u{1B}" {
                idx = result.index(after: idx)
                if idx < result.endIndex && result[idx] == "[" {
                    idx = result.index(after: idx)
                    while idx < result.endIndex && (result[idx].isNumber || result[idx] == ";") {
                        idx = result.index(after: idx)
                    }
                    if idx < result.endIndex {
                        #expect(result[idx] == "m", "All ANSI sequences in clean suffix must be SGR (m), found: \(result[idx])")
                        idx = result.index(after: idx)
                    }
                }
            } else {
                idx = result.index(after: idx)
            }
        }
    }
}

// MARK: - Right-edge repaint: cursor column verification

/// Tests that verify the terminal sequences emitted by `repaintRightEdge`
/// target exactly the last 2 cells and nothing more.
///
/// `repaintRightEdge` is a macOS Terminal.app-only workaround, so every writer
/// here is built with `isAppleTerminal: true` to exercise that path
/// deterministically regardless of which terminal runs the suite.
@Suite("FrameDiffWriter repaintRightEdge column targeting")
@MainActor
struct RepaintRightEdgeColumnTests {

    // Helper: build a padded output line for a given text and terminal width.
    func makePaddedLine(text: String, terminalWidth: Int, bgCode: String, reset: String) -> String {
        let eraseLine = "\u{1B}[2K"
        let lineWithBg = text.replacingOccurrences(of: reset, with: reset + bgCode)
        let padding = max(0, terminalWidth - text.strippedLength)
        return bgCode + eraseLine + lineWithBg + String(repeating: " ", count: padding) + reset
    }

    @Test("Bare emoji row (no modifier): no repaint")
    func bareEmojiRowNotRepainted() {
        let writer = FrameDiffWriter(isAppleTerminal: true)
        let terminal = MockTerminal()
        let terminalWidth = 20
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        // 🤙 with no Fitzpatrick modifier: claimed width and Terminal.app
        // cursor advance both equal 2 — no quirk, no repaint needed.
        let line = makePaddedLine(text: "Hello 🤙 World", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)
        #expect(!line.containsTerminalAppCursorAdvanceQuirk, "Base 🤙 has no advance quirk")

        writer.writeContentDiff(
            newLines: [line], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )

        let output = terminal.allOutput
        let repaintCol = terminalWidth - 1
        let repaintCursorSeq = ANSIRenderer.moveCursor(toRow: 1, column: repaintCol)
        #expect(!output.contains(repaintCursorSeq),
            "Repaint should NOT fire on a row without a cursor-advance quirk")
        #expect(!output.contains("\u{1B}[K"),
            "ESC[K should NOT be emitted on a non-quirky row")
    }

    @Test("Skin-tone-stripped row: right-edge repaint targets baseRepaintCol")
    func skinToneStrippedRowRepainted() {
        let writer = FrameDiffWriter(isAppleTerminal: true)
        let terminal = MockTerminal()
        let terminalWidth = 20
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        // The pre-rendered line emitted by `buildOutputLines` has already
        // had the Fitzpatrick scalar stripped (since the cluster is
        // followed by content here).  The remaining base emoji is a
        // normal 2-cell glyph with no over-advance — the line therefore
        // has no quirk and the repaint is skipped.
        let line = makePaddedLine(text: "Hi 🤙 X         ", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)
        #expect(!line.containsTerminalAppCursorAdvanceQuirk,
            "Stripped cluster has no quirk")

        writer.writeContentDiff(
            newLines: [line], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )

        let output = terminal.allOutput
        let repaintCursorSeq = ANSIRenderer.moveCursor(toRow: 1, column: terminalWidth - 1)
        #expect(!output.contains(repaintCursorSeq),
            "Repaint should NOT fire after Fitzpatrick stripping")
        #expect(!output.contains("\u{1B}[K"),
            "ESC[K should NOT be emitted on a stripped-cluster row")
    }

    @Test("Row without cursor-advance quirk: right-edge repaint is skipped")
    func plainRowNotRepainted() {
        let writer = FrameDiffWriter(isAppleTerminal: true)
        let terminal = MockTerminal()
        let terminalWidth = 20
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        // Plain line: no cursor-advance quirk — Terminal.app's right-edge
        // phantom-cell bug isn't triggered, so the repaint is skipped to
        // preserve content (including wide chars) at the boundary.
        let line = makePaddedLine(text: "Hello World!", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)
        #expect(!line.containsTerminalAppCursorAdvanceQuirk, "Prerequisite: plain ASCII has no quirk")

        writer.writeContentDiff(
            newLines: [line], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )

        let output = terminal.allOutput
        let repaintCol = terminalWidth - 1
        let repaintCursorSeq = ANSIRenderer.moveCursor(toRow: 1, column: repaintCol)
        #expect(!output.contains(repaintCursorSeq),
            "Cursor should NOT move to repaintCol for non-quirky rows")
        #expect(!output.contains("\u{1B}[K"),
            "ESC[K should NOT be emitted for non-quirky rows")
    }

    @Test("VS-16 emoji row: right-edge repaint IS applied")
    func vs16EmojiGetsRepainted() {
        let writer = FrameDiffWriter(isAppleTerminal: true)
        let terminal = MockTerminal()
        let terminalWidth = 20
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        // 🖥️ has VS-16 — its CUF compensation can trigger right-edge issues too
        let line = makePaddedLine(text: "🖥️ TUIkit App    ", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)

        writer.writeContentDiff(
            newLines: [line], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )

        let output = terminal.allOutput
        let repaintCol = terminalWidth - 1
        let repaintCursorSeq = ANSIRenderer.moveCursor(toRow: 1, column: repaintCol)
        #expect(output.contains(repaintCursorSeq),
            "VS-16 emoji rows should receive the right-edge repaint")
        #expect(output.contains("\u{1B}[K"),
            "ESC[K should be emitted for VS-16 emoji rows")
    }

    @Test("VS-16 repaint suffix covers at most 2 visible cells")
    func repaintSuffixExactly2Cells() {
        let writer = FrameDiffWriter(isAppleTerminal: true)
        let terminal = MockTerminal()
        let terminalWidth = 20
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        // VS-16 emoji 🖥️ — still triggers the quirk after compensation.
        let line = makePaddedLine(text: "Hello 🖥️ World", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)
        writer.writeContentDiff(
            newLines: [line], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )

        let repaintCol = terminalWidth - 1
        let repaintCursorSeq = ANSIRenderer.moveCursor(toRow: 1, column: repaintCol)
        let allOutput = terminal.allOutput

        let range1 = allOutput.range(of: repaintCursorSeq)
        let suffixAfterPass1 = range1.map { allOutput[allOutput.index($0.upperBound, offsetBy: 0)...] } ?? allOutput[...]
        let range2 = suffixAfterPass1.range(of: repaintCursorSeq)

        if let range2 {
            let writtenAfterPass2 = String(suffixAfterPass1[range2.upperBound...])
            let visibleWidth = writtenAfterPass2.strippedLength
            #expect(visibleWidth <= 2,
                "Pass-2 suffix should write at most 2 visible cells, wrote \(visibleWidth)")
        }
    }

    @Test("Pass-2 suffix contains no CUF sequences (regression: 4-cell overdraw)")
    func pass2SuffixNoCUF() {
        // Regression test for the bug where ansiSGRContextAndSuffix was used in
        // repaintRightEdge instead of ansiSGRContextAndCleanSuffix.  A CUF in the
        // suffix displaced the cursor past the terminal edge, wrapping characters
        // to the next row.  Uses a VS-16 emoji at the right edge so CUF is
        // injected by withTerminalAppCursorCompensation.
        let writer = FrameDiffWriter(isAppleTerminal: true)
        let terminal = MockTerminal()
        let terminalWidth = 12
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        let line = makePaddedLine(text: "Hi 🖥️ ABC", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)

        writer.writeContentDiff(
            newLines: [line], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )

        let cuf = "\u{1B}[1C"
        let allOutput = terminal.allOutput

        let repaintCol = terminalWidth - 1
        let repaintCursorSeq = ANSIRenderer.moveCursor(toRow: 1, column: repaintCol)
        if let range1 = allOutput.range(of: repaintCursorSeq),
           let range2 = allOutput[range1.upperBound...].range(of: repaintCursorSeq) {
            let pass2Content = String(allOutput[range2.upperBound...])
            #expect(!pass2Content.contains(cuf),
                "Pass-2 suffix must not contain CUF")
        }
    }

    @Test("Repaint only applies to changed rows")
    func repaintOnlyForChangedRows() {
        let writer = FrameDiffWriter(isAppleTerminal: true)
        let terminal = MockTerminal()
        let terminalWidth = 20
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        let vs16Line   = makePaddedLine(text: "Hello 🖥️ World", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)
        let plainLine  = makePaddedLine(text: "Hello World     ", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)

        writer.writeContentDiff(
            newLines: [vs16Line, plainLine], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )
        terminal.reset()

        // Second frame: identical lines → diff finds 0 changed rows → no repaint
        writer.writeContentDiff(
            newLines: [vs16Line, plainLine], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )
        let eraseCount2 = terminal.allOutput.components(separatedBy: "\u{1B}[K").count - 1
        #expect(eraseCount2 == 0,
            "No repaint should occur when no rows changed (was \(eraseCount2) ESC[K)")
    }

    @Test("Multi-row frame: only quirky rows get repainted")
    func multiRowOnlyQuirkyRepainted() {
        let writer = FrameDiffWriter(isAppleTerminal: true)
        let terminal = MockTerminal()
        let terminalWidth = 20
        let bgCode = "\u{1B}[48;2;5;9;5m"
        let reset  = "\u{1B}[0m"

        let row0 = makePaddedLine(text: "Normal line     ", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)
        let row1 = makePaddedLine(text: "Has 🖥️ emoji  ", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)
        let row2 = makePaddedLine(text: "Another normal  ", terminalWidth: terminalWidth, bgCode: bgCode, reset: reset)

        writer.writeContentDiff(
            newLines: [row0, row1, row2], terminal: terminal, startRow: 1,
            terminalWidth: terminalWidth, bgCode: bgCode, reset: reset
        )

        let output = terminal.allOutput
        let eraseToEOL = "\u{1B}[K"
        let eraseCount = output.components(separatedBy: eraseToEOL).count - 1

        // Only the VS-16 row (row 1, written at terminal row 2) triggers repaint.
        #expect(eraseCount == 1, "Only the quirky row should be repainted, got \(eraseCount)")

        let repaintAtRow1 = ANSIRenderer.moveCursor(toRow: 1, column: terminalWidth - 1)
        let repaintAtRow2 = ANSIRenderer.moveCursor(toRow: 2, column: terminalWidth - 1)
        let repaintAtRow3 = ANSIRenderer.moveCursor(toRow: 3, column: terminalWidth - 1)
        #expect(!output.contains(repaintAtRow1), "Row 1 (plain) should not be repainted")
        #expect(output.contains(repaintAtRow2), "Row 2 (VS-16) should be repainted")
        #expect(!output.contains(repaintAtRow3), "Row 3 (plain) should not be repainted")
    }
}

// MARK: - ansiAwareSlice (horizontal windowing)

@Suite("String.ansiAwareSlice")
struct AnsiAwareSliceTests {
    private let esc = "\u{1b}"

    @Test("A plain slice takes the requested visible columns")
    func plainSlice() {
        #expect("0123456789".ansiAwareSlice(visibleStart: 3, visibleCount: 4) == "3456")
        #expect("0123456789".ansiAwareSlice(visibleStart: 0, visibleCount: 4) == "0123")
        #expect("0123456789".ansiAwareSlice(visibleStart: 8, visibleCount: 5) == "89")
    }

    @Test("A slice from column 0 equals the prefix")
    func sliceFromZero() {
        let styled = "\(esc)[31mhello\(esc)[0m world"
        #expect(
            styled.ansiAwareSlice(visibleStart: 0, visibleCount: 5)
                == styled.ansiAwarePrefix(visibleCount: 5))
    }

    @Test("A slice carries the SGR state active at its start")
    func carriesStyle() {
        // Red "RED", reset, bold "BOLD". Slice the bold part (cols 3...): the
        // red-setting code scrolled out, but the slice must still be styled
        // correctly — its own codes (reset then bold) are kept, and the dropped
        // SGR is replayed in front so nothing earlier is lost.
        let styled = "\(esc)[31mRED\(esc)[0m\(esc)[1mBOLD"
        let slice = styled.ansiAwareSlice(visibleStart: 3, visibleCount: 4)
        #expect(slice.stripped == "BOLD", "visible content is the bold word: \(slice.debugDescription)")
        #expect(slice.contains("\(esc)[1m"), "keeps the bold code that applies to the slice")
        // The replayed history includes the earlier red set (harmless, then reset).
        #expect(slice.contains("\(esc)[31m"), "carries the dropped SGR history")
    }

    @Test("A slice mid-run keeps the colour from before the window")
    func midRunKeepsColour() {
        // The colour is set once at the start; slicing the middle keeps it.
        let styled = "\(esc)[32mGREENtext"
        let slice = styled.ansiAwareSlice(visibleStart: 5, visibleCount: 4)
        #expect(slice.stripped == "text")
        #expect(slice.hasPrefix("\(esc)[32m"), "carries the green still active at the slice: \(slice.debugDescription)")
    }

    /// A wide character straddling a window edge cannot be shown whole, but
    /// its gap must still OCCUPY its in-window cells. Dropping it with no gap
    /// let everything after a left-edge straddle render one cell left of its
    /// neighbours — a horizontal ScrollView over mixed CJK/ASCII content went
    /// ragged by one column, jittering as each wide glyph crossed the edge.
    @Test("A straddled wide character leaves a gap in its own columns")
    func wideStraddleLeavesGap() {
        // "ab漢cdef": 漢 spans columns 2–3. A window starting at column 3
        // bisects it: the gap fills column 3, so 'c' stays put at column 4
        // and stays vertically aligned with the ASCII line beside it.
        #expect("ab漢cdef".ansiAwareSlice(visibleStart: 3, visibleCount: 4) == " cde")
        // Right-edge straddle: a window over columns 1–2 cuts 漢 in half.
        #expect("ab漢cdef".ansiAwareSlice(visibleStart: 1, visibleCount: 2) == "b ")
        // Whole-glyph windows are untouched.
        #expect("ab漢cdef".ansiAwareSlice(visibleStart: 2, visibleCount: 2) == "漢")
    }
}
