//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalWidthCorpus.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The width corpus

/// The curated grapheme clusters every width question in this project is asked
/// about — the same list, in the same order, as
/// `Tools/TerminalProbes/data/width-corpus.json`.
///
/// It exists twice on purpose and is pinned to stay identical
/// (`WidthCorpusParityTests`): the Python probes measure the JSON on real
/// terminals, and this Swift copy is what the tests, the conservation suite
/// and the `TerminalClientQuirks` app iterate — so a measurement always
/// answers a question something asks, and the app shows exactly the clusters
/// the probes measured. A hand-picked battery only contains what somebody
/// already thought to doubt; the corpus is deliberately wider than the known
/// defects, which is how it keeps finding pre-existing ones (Apple Terminal's
/// tag-flag drift, Warp's 🪉).
import Foundation  // `String(format:)` / `trimmingCharacters` — stated, not borrowed from a sibling file (SE-0444)

package enum TerminalWidthCorpus {

    package struct Entry: Sendable, Identifiable, CustomStringConvertible {
        /// Stable key — the name a probe records its measurement under.
        package let id: String
        /// The defect class this exemplifies. Terminals are wrong by class,
        /// not by character.
        package let category: String
        /// The cluster itself.
        package let text: String

        /// The single `Character` — every entry is one grapheme cluster.
        package var character: Character { Character(text) }

        public var description: String { "\(id) (\(category))" }

        /// The cluster as codepoints, for a bug report.
        package var codepoints: String {
            text.unicodeScalars
                .map { String(format: "U+%04X", $0.value) }
                .joined(separator: " ")
        }
    }

    /// Every entry, in corpus order.
    package static let all: [Entry] = [
        Entry(id: "ascii_a", category: "ascii", text: "\u{61}"),
        Entry(id: "ascii_bracket", category: "ascii", text: "\u{5D}"),
        Entry(id: "cjk_han", category: "cjk", text: "\u{6F22}"),
        Entry(id: "hangul", category: "cjk", text: "\u{D55C}"),
        Entry(id: "halfwidth_kana", category: "cjk", text: "\u{FF71}"),
        Entry(id: "fullwidth_latin_a", category: "cjk", text: "\u{FF21}"),
        Entry(id: "watch", category: "wide_symbol", text: "\u{231A}"),
        Entry(id: "hourglass", category: "wide_symbol", text: "\u{231B}"),
        Entry(id: "fast_forward", category: "wide_symbol", text: "\u{23E9}"),
        Entry(id: "rewind", category: "wide_symbol", text: "\u{23EA}"),
        Entry(id: "up_double", category: "wide_symbol", text: "\u{23EB}"),
        Entry(id: "down_double", category: "wide_symbol", text: "\u{23EC}"),
        Entry(id: "alarm", category: "wide_symbol", text: "\u{23F0}"),
        Entry(id: "hourglass_flowing", category: "wide_symbol", text: "\u{23F3}"),
        Entry(id: "vs16_desktop", category: "vs16_pictograph", text: "\u{1F5A5}\u{FE0F}"),
        Entry(id: "vs16_shield", category: "vs16_pictograph", text: "\u{1F6E1}\u{FE0F}"),
        Entry(id: "vs16_heart", category: "vs16_pictograph", text: "\u{2764}\u{FE0F}"),
        Entry(id: "vs16_pencil", category: "vs16_pictograph", text: "\u{270F}\u{FE0F}"),
        Entry(id: "vs16_warning", category: "vs16_pictograph", text: "\u{26A0}\u{FE0F}"),
        Entry(id: "vs16_gear", category: "vs16_pictograph", text: "\u{2699}\u{FE0F}"),
        Entry(id: "vs16_wavy_dash", category: "vs16_wide_exception", text: "\u{3030}\u{FE0F}"),
        Entry(id: "vs16_part_alt", category: "vs16_wide_exception", text: "\u{303D}\u{FE0F}"),
        Entry(id: "vs16_congrat", category: "vs16_wide_exception", text: "\u{3297}\u{FE0F}"),
        Entry(id: "vs16_secret", category: "vs16_wide_exception", text: "\u{3299}\u{FE0F}"),
        Entry(id: "bare_desktop", category: "bare_pictograph", text: "\u{1F5A5}"),
        Entry(id: "bare_shield", category: "bare_pictograph", text: "\u{1F6E1}"),
        Entry(id: "bare_joystick", category: "bare_pictograph", text: "\u{1F579}"),
        Entry(id: "vs15_black_square", category: "vs15_chrome", text: "\u{2B1B}\u{FE0E}"),
        Entry(id: "vs15_white_square", category: "vs15_chrome", text: "\u{2B1C}\u{FE0E}"),
        Entry(id: "call_me", category: "default_emoji", text: "\u{1F919}"),
        Entry(id: "partying", category: "default_emoji", text: "\u{1F973}"),
        Entry(id: "grinning", category: "default_emoji", text: "\u{1F600}"),
        Entry(id: "wave", category: "default_emoji", text: "\u{1F44B}"),
        Entry(id: "fire", category: "default_emoji", text: "\u{1F525}"),
        Entry(id: "crossing", category: "default_emoji", text: "\u{1F6B8}"),
        Entry(id: "telephone", category: "default_emoji", text: "\u{1F4DE}"),
        Entry(id: "flute", category: "recent_emoji", text: "\u{1FA88}"),
        Entry(id: "harp", category: "recent_emoji", text: "\u{1FA89}"),
        Entry(id: "shovel", category: "recent_emoji", text: "\u{1FA8F}"),
        Entry(id: "leafless_tree", category: "recent_emoji", text: "\u{1FABE}"),
        Entry(id: "fingerprint", category: "recent_emoji", text: "\u{1FAC6}"),
        Entry(id: "root_vegetable", category: "recent_emoji", text: "\u{1FADC}"),
        Entry(id: "splatter", category: "recent_emoji", text: "\u{1FADF}"),
        Entry(id: "face_bags", category: "recent_emoji", text: "\u{1FAE9}"),
        Entry(id: "moose", category: "recent_emoji", text: "\u{1FACE}"),
        Entry(id: "pink_heart", category: "recent_emoji", text: "\u{1FA77}"),
        Entry(id: "lone_ri_a", category: "regional_indicator", text: "\u{1F1E6}"),
        Entry(id: "flag_us", category: "flag_pair", text: "\u{1F1FA}\u{1F1F8}"),
        Entry(id: "flag_au", category: "flag_pair", text: "\u{1F1E6}\u{1F1FA}"),
        Entry(id: "flag_scotland", category: "tag_flag", text: "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"),
        Entry(id: "keycap_one", category: "keycap", text: "\u{31}\u{FE0F}\u{20E3}"),
        Entry(id: "keycap_hash", category: "keycap", text: "\u{23}\u{FE0F}\u{20E3}"),
        Entry(id: "keycap_bare", category: "keycap_bare", text: "\u{31}\u{20E3}"),
        Entry(id: "sf_symbol_low", category: "pua16", text: "\u{100038}"),
        Entry(id: "sf_symbol_mid", category: "pua16", text: "\u{101867}"),
        Entry(id: "sf_symbol_high", category: "pua16", text: "\u{102328}"),
        Entry(id: "tone_call_me", category: "skin_tone_smp", text: "\u{1F919}\u{1F3FD}"),
        Entry(id: "tone_thumbsup", category: "skin_tone_smp", text: "\u{1F44D}\u{1F3FC}"),
        Entry(id: "tone_wave", category: "skin_tone_smp", text: "\u{1F44B}\u{1F3FF}"),
        Entry(id: "tone_boy", category: "skin_tone_smp", text: "\u{1F468}\u{1F3FD}"),
        Entry(id: "tone_pray", category: "skin_tone_smp", text: "\u{1F64F}\u{1F3FC}"),
        Entry(id: "tone_fist", category: "skin_tone_bmp_wide", text: "\u{270A}\u{1F3FB}"),
        Entry(id: "tone_basketball", category: "skin_tone_bmp_wide", text: "\u{26F9}\u{1F3FE}"),
        Entry(id: "tone_point_up", category: "skin_tone_bmp_narrow", text: "\u{261D}\u{1F3FB}"),
        Entry(id: "tone_victory", category: "skin_tone_bmp_narrow", text: "\u{270C}\u{1F3FC}"),
        Entry(id: "tone_writing", category: "skin_tone_bmp_narrow", text: "\u{270D}\u{1F3FD}"),
        Entry(id: "tone_point_up_vs16", category: "skin_tone_vs16_base", text: "\u{261D}\u{FE0F}\u{1F3FD}"),
        Entry(id: "tone_victory_vs16", category: "skin_tone_vs16_base", text: "\u{270C}\u{FE0F}\u{1F3FC}"),
        Entry(id: "tone_lifter_vs16", category: "skin_tone_vs16_smp", text: "\u{1F3CB}\u{FE0F}\u{1F3FD}"),
        Entry(id: "zwj_astronaut", category: "zwj", text: "\u{1F469}\u{200D}\u{1F680}"),
        Entry(id: "zwj_family4", category: "zwj", text: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"),
        Entry(id: "zwj_heart_fire", category: "zwj", text: "\u{2764}\u{FE0F}\u{200D}\u{1F525}"),
        Entry(id: "zwj_rainbow_flag", category: "zwj", text: "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}"),
        Entry(id: "zwj_pirate_flag", category: "zwj", text: "\u{1F3F4}\u{200D}\u{2620}\u{FE0F}"),
        Entry(id: "zwj_farmer", category: "zwj", text: "\u{1F9D1}\u{200D}\u{1F33E}"),
        Entry(id: "zwj_red_hair", category: "zwj", text: "\u{1F469}\u{200D}\u{1F9B0}"),
        Entry(id: "zwj_broken_chain", category: "zwj", text: "\u{26D3}\u{FE0F}\u{200D}\u{1F4A5}"),
        Entry(id: "zwj_astronaut_tone", category: "zwj_skin_tone", text: "\u{1F469}\u{1F3FD}\u{200D}\u{1F680}"),
        Entry(id: "combining_acute", category: "combining", text: "\u{65}\u{301}"),
        Entry(id: "combining_stack", category: "combining", text: "\u{65}\u{301}\u{308}\u{327}"),
        // The complex-script rows, added 2026-09-04 and NOT YET MEASURED on any
        // host — see `TerminalLedgerConformanceTests.awaitingLandingMeasurement`
        // and the "Complex scripts" section of
        // `Documentation/Terminal-compatibility.md` for the command that
        // measures them. They exist because the corpus was emoji-only, so the
        // one question the width rule cannot answer — what a cluster of three
        // or more ADVANCING scalars costs — had no sample to ask it of.
        Entry(id: "conjunct_deva_ksha", category: "indic_conjunct", text: "\u{915}\u{94D}\u{937}"),
        Entry(id: "conjunct_deva_stra", category: "indic_conjunct", text: "\u{938}\u{94D}\u{924}\u{94D}\u{930}"),
        Entry(id: "conjunct_deva_shtra", category: "indic_conjunct", text: "\u{937}\u{94D}\u{91F}\u{94D}\u{930}"),
        Entry(id: "conjunct_deva_stri", category: "indic_conjunct", text: "\u{938}\u{94D}\u{924}\u{94D}\u{930}\u{940}"),
        Entry(id: "conjunct_bengali_ksha", category: "indic_conjunct", text: "\u{995}\u{9CD}\u{9B7}"),
        Entry(id: "conjunct_telugu_ksha", category: "indic_conjunct", text: "\u{C15}\u{C4D}\u{C37}"),
        // NOT the conjuncts they are half of: க்ஷ, ಕ್ಷ and ក្ក are each TWO
        // grapheme clusters, because GB9c's `InCB=Linker` set covers only six
        // scripts and Tamil, Kannada and Khmer are not among them. The
        // virama-final half-form is the whole cluster, and it is the row.
        Entry(id: "virama_tamil_sa", category: "virama_final", text: "\u{BB8}\u{BCD}"),
        Entry(id: "virama_kannada_ka", category: "virama_final", text: "\u{C95}\u{CCD}"),
        Entry(id: "virama_khmer_ka", category: "virama_final", text: "\u{1780}\u{17D2}"),
        Entry(id: "matra_deva_i", category: "spacing_vowel_sign", text: "\u{915}\u{93F}"),
        Entry(id: "matra_deva_o", category: "spacing_vowel_sign", text: "\u{915}\u{94B}"),
        Entry(id: "matra_deva_au", category: "spacing_vowel_sign", text: "\u{915}\u{94C}"),
        Entry(id: "matra_deva_i_anusvara", category: "spacing_vowel_sign", text: "\u{915}\u{93F}\u{902}"),
        Entry(id: "matra_tamil_aa", category: "spacing_vowel_sign", text: "\u{BB0}\u{BBE}"),
        Entry(id: "matra_khmer_aa", category: "spacing_vowel_sign", text: "\u{1780}\u{17B6}"),
        Entry(id: "nukta_deva_qa", category: "nukta", text: "\u{915}\u{93C}"),
        Entry(id: "nukta_deva_rra", category: "nukta", text: "\u{921}\u{93C}"),
        Entry(id: "chillu_malayalam_atomic", category: "chillu", text: "\u{D7B}"),
        Entry(id: "chillu_malayalam_zwj", category: "chillu", text: "\u{D28}\u{D4D}\u{200D}"),
        Entry(id: "thai_tone", category: "thai_lao", text: "\u{E01}\u{E48}"),
        Entry(id: "thai_vowel_tone", category: "thai_lao", text: "\u{E01}\u{E34}\u{E49}"),
        Entry(id: "thai_sara_am", category: "thai_lao", text: "\u{E01}\u{E33}"),
        Entry(id: "lao_vowel_tone", category: "thai_lao", text: "\u{E81}\u{EB5}\u{EC8}"),
        Entry(id: "tibetan_subjoined", category: "tibetan_stack", text: "\u{F40}\u{F90}"),
        Entry(id: "tibetan_subjoined_vowel", category: "tibetan_stack", text: "\u{F40}\u{F90}\u{F74}"),
        // The PRESENTATION form, not the لا spelling a keyboard produces: that
        // is U+0644 U+0627, two letters and so two grapheme clusters, which
        // this list cannot hold a row for. Shaping is the renderer's business;
        // what the corpus can ask is what one cluster costs.
        Entry(id: "arabic_lam_alef", category: "arabic", text: "\u{FEFB}"),
        Entry(id: "arabic_harakat", category: "arabic", text: "\u{628}\u{64E}"),
        Entry(id: "arabic_shadda_harakat", category: "arabic", text: "\u{628}\u{651}\u{64E}"),
        Entry(id: "hebrew_hiriq", category: "hebrew_points", text: "\u{5D1}\u{5B4}"),
        Entry(id: "hebrew_dagesh_qamats", category: "hebrew_points", text: "\u{5D1}\u{5BC}\u{5B8}"),
        Entry(id: "hangul_jamo_lvt", category: "hangul_jamo", text: "\u{1112}\u{1161}\u{11AB}"),
        Entry(id: "hangul_jamo_lv", category: "hangul_jamo", text: "\u{1112}\u{1161}"),
        Entry(id: "latin_zwj", category: "format_control", text: "\u{61}\u{200D}"),
        Entry(id: "latin_zwnj", category: "format_control", text: "\u{61}\u{200C}"),
        Entry(id: "bidi_lrm", category: "format_control", text: "\u{200E}"),
        Entry(id: "bidi_rlm", category: "format_control", text: "\u{200F}"),
        Entry(id: "key_escape", category: "chrome_key", text: "\u{238B}"),  // ⎋ Shortcut.escape
        Entry(id: "key_return", category: "chrome_key", text: "\u{21B5}"),  // ↵ Shortcut.enter — reported 2 cells in Ghostty
        Entry(id: "key_return_symbol", category: "chrome_key", text: "\u{23CE}"),  // ⏎ Shortcut.returnKey
        Entry(id: "key_tab", category: "chrome_key", text: "\u{21E5}"),  // ⇥ Shortcut.tab
        Entry(id: "key_backtab", category: "chrome_key", text: "\u{21E4}"),  // ⇤ Shortcut.shiftTab
        Entry(id: "key_backspace", category: "chrome_key", text: "\u{232B}"),  // ⌫ Shortcut.backspace
        Entry(id: "key_delete", category: "chrome_key", text: "\u{2326}"),  // ⌦ Shortcut.delete
        Entry(id: "key_space", category: "chrome_key", text: "\u{2423}"),  // ␣ Shortcut.space
        Entry(id: "key_arrow_up", category: "chrome_key", text: "\u{2191}"),  // ↑ Shortcut.arrowUp — EAW Ambiguous
        Entry(id: "key_arrow_down", category: "chrome_key", text: "\u{2193}"),  // ↓ Shortcut.arrowDown — EAW Ambiguous
        Entry(id: "key_arrow_left", category: "chrome_key", text: "\u{2190}"),  // ← Shortcut.arrowLeft — EAW Ambiguous
        Entry(id: "key_arrow_right", category: "chrome_key", text: "\u{2192}"),  // → Shortcut.arrowRight — EAW Ambiguous
        Entry(id: "key_shift", category: "chrome_key", text: "\u{21E7}"),  // ⇧ Shortcut.shift — EAW Ambiguous
        Entry(id: "key_control", category: "chrome_key", text: "\u{2303}"),  // ⌃ Shortcut.control
        Entry(id: "key_option", category: "chrome_key", text: "\u{2325}"),  // ⌥ Shortcut.option
        Entry(id: "key_command", category: "chrome_key", text: "\u{2318}"),  // ⌘ Shortcut.command
        Entry(id: "chrome_left_tri", category: "chrome_glyph", text: "\u{25C0}"),  // ◀ TerminalSymbols.leftArrow — EAW Ambiguous
        Entry(id: "chrome_right_tri", category: "chrome_glyph", text: "\u{25B6}"),  // ▶ TerminalSymbols.rightArrow / disclosureCollapsed
        Entry(id: "chrome_down_tri", category: "chrome_glyph", text: "\u{25BC}"),  // ▼ TerminalSymbols.disclosureExpanded
        Entry(id: "chrome_up_tri", category: "chrome_glyph", text: "\u{25B2}"),  // ▲ TerminalSymbols.toneCurveStop
        Entry(id: "chrome_radio_on", category: "chrome_glyph", text: "\u{25CF}"),  // ● TerminalSymbols.radioSelected / maskBullet
        Entry(id: "chrome_radio_off", category: "chrome_glyph", text: "\u{25EF}"),  // ◯ TerminalSymbols.radioUnselected
        Entry(id: "chrome_radio_dis", category: "chrome_glyph", text: "\u{25CC}"),  // ◌ TerminalSymbols.radioDisabledUnselected
        Entry(id: "chrome_full_block", category: "chrome_glyph", text: "\u{2588}"),  // █ track fill — EAW Ambiguous
        Entry(id: "chrome_left_half", category: "chrome_glyph", text: "\u{258C}"),  // ▌ field cap — EAW Ambiguous
        Entry(id: "chrome_right_half", category: "chrome_glyph", text: "\u{2590}"),  // ▐ field cap
        Entry(id: "chrome_shade", category: "chrome_glyph", text: "\u{2592}"),  // ▒ track groove — EAW Ambiguous
        Entry(id: "chrome_box_h", category: "chrome_glyph", text: "\u{2500}"),  // ─ border — EAW Ambiguous
        Entry(id: "chrome_box_v", category: "chrome_glyph", text: "\u{2502}"),  // │ border — EAW Ambiguous
    ]

    /// Entries of one category.
    package static func entries(in category: String) -> [Entry] {
        all.filter { $0.category == category }
    }

    /// One line on what goes wrong with each category — the prose half, which
    /// lives here rather than in the JSON because it describes measured
    /// terminal behaviour, and the measurements are Swift-side ledgers.
    package static let categoryNotes: [String: String] = [
        "ascii": "One cell everywhere. The control.",
        "cjk": "East Asian wide, fullwidth or halfwidth: agreed on by every measured host.",
        "wide_symbol": "BMP scalars with emoji presentation (⌚ ⏰) — 2 cells despite the plane.",
        "vs16_pictograph": "Base + U+FE0F: painted 2, internal advance 1 on Apple Terminal and iTerm2's alternate screen.",
        "vs16_wide_exception": "VS-16 on an East-Asian-Wide base — advances its full 2; Warp gives it 3.",
        "bare_pictograph": "Selector-less SMP pictograph: painted 2 via emoji fallback, advanced 1.",
        "vs15_chrome": "Text presentation forced (⬛︎). Ghostty under-advances; TUIkit draws toggles with these.",
        "default_emoji": "Plain emoji-presentation SMP emoji. Usually agreed on.",
        "recent_emoji": "Recent Unicode additions — where a host's width tables lag the toolchain's (Warp gives 🪉 one cell, 🪈 two).",
        "regional_indicator": "Half a flag: painted 2, advanced 1 on Apple Terminal, Warp and tmux.",
        "flag_pair":
            "Two regional indicators. Internal advance matches the claim everywhere "
                + "measured, but Apple Terminal paints the next character in the flag's second cell.",
        "tag_flag": "🏴 plus tag scalars. Apple Terminal's internal column advances 2 + one per tag (Scotland: 8) while painting 2.",
        "keycap":
            "Base + U+FE0F + U+20E3. Under-advances on iTerm2; paints short of its advance on Apple Terminal.",
        "keycap_bare":
            "Base + U+20E3 with NO selector: claimed 1 (the base's own width). "
                + "The compatibility table records Apple Terminal advancing it 2.",
        "pua16": "Plane-16 Private Use Area — SF Symbols. Painted 2 where the font exists, advanced 1 on every measured host.",
        "skin_tone_smp":
            "Fitzpatrick modifier on an SMP base (🤙🏽). Apple Terminal: internal 4, paints 2 — the two-counter divergence.",
        "skin_tone_bmp_wide": "Fitzpatrick on a BMP emoji-presentation base (✊🏻): internal 4, paints 2 on Apple Terminal.",
        "skin_tone_bmp_narrow": "Fitzpatrick on a BMP text-presentation base (☝🏻): internal 3, paints 1 on Apple Terminal.",
        "skin_tone_vs16_base":
            "VS-16-promoted base plus modifier (☝️🏽): raw, a different answer on every host; "
            + "since 2026-08-28 the walks strip the redundant selector, so only the raw models differ.",
        "skin_tone_vs16_smp":
            "The SMP flavour (🏋️🏽): a text-presentation SMP base, promoted then toned — "
                + "outside every by-plane rule, so it gets its own row.",
        "zwj":
            "ZWJ sequence. Apple Terminal composes the glyph while its internal column decomposes (👨‍👩‍👧‍👦: 11 vs 2); Warp decomposes both.",
        "zwj_skin_tone": "A skin-toned segment inside a ZWJ sequence (👩🏽‍🚀) — both rules at once.",
        "indic_conjunct":
            "C + virama + C (+ virama + C) fused into ONE cluster by GB9c, plus a matra. "
                + "UNMEASURED: the cluster rule answers a flat 2 while the per-scalar rule "
                + "prices स्त्र at 3 and स्त्री at 4, and nothing has yet asked a terminal.",
        "virama_final":
            "The half-form alone (ஸ், ಕ್, ក្). GB9c's linker set is six scripts, so Tamil, "
                + "Kannada and Khmer conjuncts break INTO these — a shear here is per half. "
                + "UNMEASURED.",
        "spacing_vowel_sign":
            "Base + Mc matra (कि को कौ ரீ កា), which the per-scalar rule says advances and "
                + "the cluster rule prices at 2. The two coincide at exactly two advancing "
                + "scalars, which is why nothing has caught the divergence. UNMEASURED.",
        "nukta":
            "Base + U+093C, a non-advancing Mn that changes the glyph. Should be the base's "
                + "own width. UNMEASURED.",
        "chillu":
            "Malayalam chillu, atomic (ൻ) and spelled with a ZWJ (ന്‍) — the same letter, "
                + "one scalar or three, and the ZWJ spelling reaches the emoji-shaped joiner "
                + "path with no emoji in it. UNMEASURED.",
        "thai_lao":
            "A base carrying stacked Mn vowels and tone marks, plus sara am (a SPACING "
                + "vowel). The classic wcwidth-zero-mark case. UNMEASURED.",
        "tibetan_stack":
            "A head letter with a subjoined consonant, and one with a vowel on top — a "
                + "three-scalar vertical stack in one cell. UNMEASURED.",
        "arabic":
            "The lam-alef ligature as its presentation form, and a letter carrying harakat "
                + "(one mark, and shadda + fatha). Shaping is the renderer's; the cluster is "
                + "one cell. UNMEASURED.",
        "hebrew_points":
            "A letter with a vowel point, and with dagesh + vowel — two Mn marks inside one "
                + "cell, in a right-to-left run. UNMEASURED.",
        "hangul_jamo":
            "한 spelled as conjoining jamo (L+V+T and L+V) rather than the precomposed "
                + "U+D55C the corpus already carries: same syllable, three scalars or two, "
                + "and the jamo are the multi-scalar case that coincides with 2. UNMEASURED.",
        "format_control":
            "A letter carrying a ZWJ or ZWNJ (which is what pasted Arabic or Indic text and "
                + "a truncated emoji both leave), and the bidi marks alone. All zero-width "
                + "extras: the cluster is its base, and a lone mark is nothing. UNMEASURED.",
        "chrome_key":
            "The keyboard symbols the status bar draws — ⎋ ↵ ⇥ ⌫ ⌘ and the arrows. "
                + "The framework claims one cell for every one of them and had never "
                + "measured any: half are East Asian AMBIGUOUS, which is a terminal "
                + "SETTING rather than a property of the character, and ↵ (U+21B5, EAW "
                + "Neutral, so 1 by every wcwidth) was reported painting 2 in Ghostty — "
                + "which ate the space before the label beside it. UNMEASURED.",
        "chrome_glyph":
            "The drawing glyphs the framework's own controls are made of — borders, "
                + "track fills, field caps, radio indicators, disclosure and stepper "
                + "triangles. Same claim and the same gap as `chrome_key`, and a wider "
                + "blast radius: a border glyph measured wrong moves every cell of every "
                + "row inside it. Most are East Asian AMBIGUOUS. UNMEASURED.",
        "combining":
            "Base + combining mark(s) (NFD é, and one with three stacked): one cell, "
                + "agreed everywhere — the marks are Mn and advance nothing.",
    ]
}
