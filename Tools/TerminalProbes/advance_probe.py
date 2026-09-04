#!/usr/bin/env python3
"""Terminal output-behaviour probe: measures the CURSOR ADVANCE of a battery
of grapheme clusters using DSR (ESC[6n), and dumps the environment.
Writes JSON to $PROBE_OUT (default: ./advance_probe.json). Run INSIDE the
terminal under test."""
import json, os, sys, termios, tty

import probe_stamp

BATTERY = {
    # ASCII / controls
    "ascii_a": "a",
    # East Asian wide
    "cjk": "中",                      # 中
    # VS-16 pictographic (Bug A battery: Terminal.app paints 2 advances 1)
    "vs16_screen": "\U0001F5A5️",     # 🖥️
    "vs16_shield": "\U0001F6E1️",     # 🛡️
    "vs16_phone": "☎️",          # ☎️
    "vs16_pencil": "✏️",         # ✏️
    "vs16_heart": "❤️",          # ❤️
    "vs16_wavydash": "〰️",       # 〰️
    "vs16_part_alt": "〽️",       # 〽️
    # Bare text-presentation pictographs
    "bare_pencil": "✏",
    "bare_heart": "❤",
    "bare_screen": "\U0001F5A5",
    "bare_point_up": "☝",             # ☝
    # Emoji-presentation singles (incl. BMP watch/hourglass class)
    "emoji_thumbs": "\U0001F44D",          # 👍
    "emoji_fist": "✊",                # ✊
    "watch": "⌚",                     # ⌚
    "hourglass": "⌛",                 # ⌛
    "ffwd": "⏩",                      # ⏩
    "alarm": "⏰",                     # ⏰
    # Fitzpatrick
    "skin_thumbs": "\U0001F44D\U0001F3FD",     # 👍🏽
    "skin_fist": "✊\U0001F3FB",           # ✊🏻
    "skin_point_up": "☝\U0001F3FD",       # ☝🏽
    "skin_point_vs16": "☝️\U0001F3FD",
    "skin_standalone": "\U0001F3FD",           # 🏽
    # ZWJ + flags + keycap
    "zwj_astronaut": "\U0001F469‍\U0001F680",   # 👩‍🚀
    "zwj_skin": "\U0001F469\U0001F3FD‍\U0001F680",
    "flag_us": "\U0001F1FA\U0001F1F8",     # 🇺🇸
    "keycap_1": "1️⃣",           # 1️⃣
    # VS-15 text presentation on an emoji-default base
    "vs15_bigsquare": "⬛︎",      # ⬛︎
    "vs15_whitesquare": "⬜︎",    # ⬜︎
    # Chrome glyphs
    "fullblock2": "██",          # ██
    "halfpair": "▐▌",            # ▐▌
    "box_h": "─",                     # ─
    "shade_med": "▒",                 # ▒
    "sq_filled": "■",                 # ■
    # SF Symbols PUA (0.circle, from the generated table)
    "sf_pua": "\U00100038",
    # Decomposed é (NFD)
    "nfd_e": "é",
}

BATTERY.update({
    # SMP text-presentation pictographs (Emoji=Yes, Emoji_Presentation=No),
    # BARE — no VS-16. Same Unicode class as the BMP ✏ ❤ ☝ above, which
    # terminalWidth claims 1; these it claims 2 (via its blanket
    # 0x1F000–0x1FBFF range rule), so the whole family is a claim-vs-advance
    # discrepancy worth tracking per terminal.
    "bare_smp_shield": "\U0001F6E1",
    "bare_smp_joystick": "\U0001F579",
    "bare_smp_spider": "\U0001F577",
    "bare_smp_film": "\U0001F39E",
    "bare_smp_cityscape": "\U0001F3D9",
    # And the same six WITH VS-16, which must stay 2 — the contrast row.
    "vs16_smp_shield": "\U0001F6E1️",
    "vs16_smp_joystick": "\U0001F579️",
    # Non-emoji symbols inside that same blanket range (EAW Neutral).
    "domino": "\U0001F060",
    "playing_card": "\U0001F0A1",
    "lone_ri": "\U0001F1E6",                    # lone regional indicator
    "keycap_hash": "#\uFE0F\u20E3",
    "keycap_star": "*\uFE0F\u20E3",
    "keycap_0": "0\uFE0F\u20E3",
    "keycap_bare": "1\u20E3",                  # no VS16
    "pua_lower": "\U00101867",                  # another SF symbol
    # Renamed from "pua_bmp_sf" 2026-08-28 (which also carried a dead
    # `if False` arm): U+102446 is Plane-16 PUA, not BMP — the committed
    # records up to that date hold the measurement under the old, wrong name.
    "pua16_second": "\U00102446",
    "zwj_heart_fire": "\u2764\uFE0F\u200D\U0001F525",  # ❤️‍🔥
    "vs16_umbrella": "\u2602\uFE0F",           # ☂️
    "vs16_check": "\u2714\uFE0F",              # ✔️
    # BMP Miscellaneous Symbols with VS-16 — the family a file list reaches
    # for as icons, and the one a reported `.swiftlint.yml` row was drawn with.
    "vs16_gear": "\u2699\uFE0F",               # ⚙️
    "bare_gear": "\u2699",                     # ⚙
    "vs16_scissors": "\u2702\uFE0F",           # ✂️
    "vs16_hammer_pick": "\u2692\uFE0F",        # ⚒️
    "vs16_warning": "\u26A0\uFE0F",            # ⚠️
    "braille": "\u28FF",
    "powerline": "\uE0B0",                      # BMP PUA powerline
})

BATTERY.update({
    # The vs16-tone class siblings added to the width corpus 2026-08-28: the
    # normalization treatment generalizes from tone_point_up_vs16
    # (skin_point_vs16 above) to the whole class, and these rows test the
    # generalization -- a second BMP member, and the SMP flavour no by-plane
    # rule covers.
    "skin_victory_vs16": "\u270C\uFE0F\U0001F3FC",
    "skin_lifter_vs16": "\U0001F3CB\uFE0F\U0001F3FD",
    # The NORMALIZED form of the row above -- what the walks emit for it --
    # and a text-presentation SMP base + tone, outside every by-plane rule.
    "skin_lifter_bare": "\U0001F3CB\U0001F3FD",
    # Unicode 16.0's seven emoji singletons (Warp's 15.1 width table advances
    # each 1 against the 2-cell claim -- recent_emoji_sweep.py, 2026-08-28),
    # plus the Unicode 15.0 neighbour for the boundary.
    "u16_harp": "\U0001FA89",
    "u16_shovel": "\U0001FA8F",
    "u16_leafless_tree": "\U0001FABE",
    "u16_fingerprint": "\U0001FAC6",
    "u16_root_vegetable": "\U0001FADC",
    "u16_splatter": "\U0001FADF",
    "u16_face_bags": "\U0001FAE9",
    "u15_flute": "\U0001FA88",
})

BATTERY.update({
    # The complex-script rows added to the width corpus 2026-09-04, with the
    # SAME ids, because DSR is the half of the measurement that needs no
    # screenshot and no Screen Recording grant -- so this battery can answer
    # the advance question for them today, on any host, while the landing
    # halves wait for `landing_probe.py` (which reads the corpus and so already
    # carries every row below; nothing needs adding there).
    #
    # The question they exist to settle: `Character.terminalWidth` answers a
    # flat 2 for any cluster carrying width-adding extras, while the framework's
    # own per-scalar rule prices the scalars individually, and from THREE
    # advancing scalars on the two disagree (see ComplexScriptWidthTests). No
    # host has been measured on any of it, so the rule must not be changed until
    # these rows have numbers.
    #
    # GB9c conjuncts: two, three and four advancing scalars in ONE cluster.
    "conjunct_deva_ksha": "\u0915\u094D\u0937",
    "conjunct_deva_stra": "\u0938\u094D\u0924\u094D\u0930",
    "conjunct_deva_shtra": "\u0937\u094D\u091F\u094D\u0930",
    "conjunct_deva_stri": "\u0938\u094D\u0924\u094D\u0930\u0940",
    "conjunct_bengali_ksha": "\u0995\u09CD\u09B7",
    "conjunct_telugu_ksha": "\u0C15\u0C4D\u0C37",
    # The half-forms GB9c does NOT fuse -- Tamil, Kannada and Khmer are outside
    # its `InCB=Linker` set, so their conjuncts break into these.
    "virama_tamil_sa": "\u0BB8\u0BCD",
    "virama_kannada_ka": "\u0C95\u0CCD",
    "virama_khmer_ka": "\u1780\u17D2",
    # Spacing (Mc) vowel signs: the per-scalar rule says they advance.
    "matra_deva_i": "\u0915\u093F",
    "matra_deva_o": "\u0915\u094B",
    "matra_deva_au": "\u0915\u094C",
    "matra_deva_i_anusvara": "\u0915\u093F\u0902",
    "matra_tamil_aa": "\u0BB0\u0BBE",
    "matra_khmer_aa": "\u1780\u17B6",
    # Non-advancing marks that change the glyph.
    "nukta_deva_qa": "\u0915\u093C",
    "nukta_deva_rra": "\u0921\u093C",
    # The same Malayalam letter, atomic and spelled with a ZWJ.
    "chillu_malayalam_atomic": "\u0D7B",
    "chillu_malayalam_zwj": "\u0D28\u0D4D\u200D",
    # Stacked marks, and a SPACING vowel (sara am).
    "thai_tone": "\u0E01\u0E48",
    "thai_vowel_tone": "\u0E01\u0E34\u0E49",
    "thai_sara_am": "\u0E01\u0E33",
    "lao_vowel_tone": "\u0E81\u0EB5\u0EC8",
    "tibetan_subjoined": "\u0F40\u0F90",
    "tibetan_subjoined_vowel": "\u0F40\u0F90\u0F74",
    # RTL: a presentation-form ligature, and letters carrying harakat/points.
    "arabic_lam_alef": "\uFEFB",
    "arabic_harakat": "\u0628\u064E",
    "arabic_shadda_harakat": "\u0628\u0651\u064E",
    "hebrew_hiriq": "\u05D1\u05B4",
    "hebrew_dagesh_qamats": "\u05D1\u05BC\u05B8",
    # The same syllable as the corpus's precomposed U+D55C, as conjoining jamo.
    "hangul_jamo_lvt": "\u1112\u1161\u11AB",
    "hangul_jamo_lv": "\u1112\u1161",
    # Zero-width extras on their own or on a letter -- what pasted text leaves.
    "latin_zwj": "a\u200D",
    "latin_zwnj": "a\u200C",
    "bidi_lrm": "\u200E",
    "bidi_rlm": "\u200F",
    # Fullwidth Latin and a three-mark NFD stack, the two rows added to
    # existing corpus classes on the same date.
    "fullwidth_latin_a": "\uFF21",
    "combining_stack": "e\u0301\u0308\u0327",
})

BATTERY.update({
    # The framework's OWN chrome, added to the width corpus 2026-09-04 with the
    # same ids. Every one of these is claimed 1 cell by `terminalWidth` and none
    # had ever been measured on any host — which is a wide gap, because unlike
    # an emoji in someone's data these are drawn by TUIkit itself, in every
    # status bar, border, scrollbar, slider and radio group it renders.
    #
    # Two reasons to doubt the claim. Fifteen of them are East Asian AMBIGUOUS,
    # whose width is a terminal SETTING and not a property of the character. And
    # ↵ (U+21B5) is EAW *Neutral* — 1 cell by every wcwidth there is — yet was
    # reported painting 2 in Ghostty, eating the space before the label beside
    # it in the status bar. If that reproduces here it is a font/host width
    # decision no Unicode table predicts, and the only way to know which hosts
    # do it is to ask them.
    "key_escape": "\u238B",  # ⎋ Shortcut.escape
    "key_return": "\u21B5",  # ↵ Shortcut.enter — reported 2 cells in Ghostty
    "key_return_symbol": "\u23CE",  # ⏎ Shortcut.returnKey
    "key_tab": "\u21E5",  # ⇥ Shortcut.tab
    "key_backtab": "\u21E4",  # ⇤ Shortcut.shiftTab
    "key_backspace": "\u232B",  # ⌫ Shortcut.backspace
    "key_delete": "\u2326",  # ⌦ Shortcut.delete
    "key_space": "\u2423",  # ␣ Shortcut.space
    "key_arrow_up": "\u2191",  # ↑ Shortcut.arrowUp — EAW Ambiguous
    "key_arrow_down": "\u2193",  # ↓ Shortcut.arrowDown — EAW Ambiguous
    "key_arrow_left": "\u2190",  # ← Shortcut.arrowLeft — EAW Ambiguous
    "key_arrow_right": "\u2192",  # → Shortcut.arrowRight — EAW Ambiguous
    "key_shift": "\u21E7",  # ⇧ Shortcut.shift — EAW Ambiguous
    "key_control": "\u2303",  # ⌃ Shortcut.control
    "key_option": "\u2325",  # ⌥ Shortcut.option
    "key_command": "\u2318",  # ⌘ Shortcut.command
    "chrome_left_tri": "\u25C0",  # ◀ TerminalSymbols.leftArrow — EAW Ambiguous
    "chrome_right_tri": "\u25B6",  # ▶ TerminalSymbols.rightArrow / disclosureCollapsed
    "chrome_down_tri": "\u25BC",  # ▼ TerminalSymbols.disclosureExpanded
    "chrome_up_tri": "\u25B2",  # ▲ TerminalSymbols.toneCurveStop
    "chrome_radio_on": "\u25CF",  # ● TerminalSymbols.radioSelected / maskBullet
    "chrome_radio_off": "\u25EF",  # ◯ TerminalSymbols.radioUnselected
    "chrome_radio_dis": "\u25CC",  # ◌ TerminalSymbols.radioDisabledUnselected
    "chrome_full_block": "\u2588",  # █ track fill — EAW Ambiguous
    "chrome_left_half": "\u258C",  # ▌ field cap — EAW Ambiguous
    "chrome_right_half": "\u2590",  # ▐ field cap
    "chrome_shade": "\u2592",  # ▒ track groove — EAW Ambiguous
    "chrome_box_h": "\u2500",  # ─ border — EAW Ambiguous
    "chrome_box_v": "\u2502",  # │ border — EAW Ambiguous
})

def cursor_col(fd):
    os.write(fd, b"\x1b[6n")
    buf = b""
    while not buf.endswith(b"R"):
        buf += os.read(fd, 1)
    # ESC [ row ; col R
    inner = buf[buf.rfind(b"\x1b[") + 2 : -1]
    row, col = inner.split(b";")
    return int(col)

def modifier_base_battery(path):
    """--modifier-bases FILE: replace the battery with base+U+1F3FD rows for
    every codepoint listed in FILE (hex, whitespace-separated), plus two
    calibration controls. This is the tmux keep-set question: which bases does
    the compositor merge into the 2-cell claim, and which does it detach? The
    file should come from the toolchain's own Emoji_Modifier_Base enumeration
    (swift -e over isEmojiModifierBase), because that is the set the strip
    predicate can actually test at runtime."""
    with open(path) as handle:
        points = [int(token, 16) for token in handle.read().split()]
    battery = {"ascii_a": "a", "cjk": "\u4E2D"}
    for point in points:
        battery["tonebase_%04X" % point] = chr(point) + "\U0001F3FD"
    return battery

def main():
    out_path = os.environ.get("PROBE_OUT", "advance_probe.json")
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    results = {}
    use_alt = os.environ.get("PROBE_ALT") == "1"
    try:
        tty.setraw(fd)
        if use_alt:
            os.write(1, b"\x1b[?1049h\x1b[2J\x1b[H")
        # Before the battery: the stamp asks DECRQM, and a reply arriving mid
        # battery would be read as part of a cursor report.
        provenance = probe_stamp.stamp(fd, "advance_probe.py", use_alt)
        battery = BATTERY
        if "--modifier-bases" in sys.argv:
            battery = modifier_base_battery(
                sys.argv[sys.argv.index("--modifier-bases") + 1])
        for name, cluster in battery.items():
            os.write(1, b"\r\x1b[2K")           # column 1, clear line
            start = cursor_col(fd)
            os.write(1, cluster.encode())
            end = cursor_col(fd)
            results[name] = {
                "cluster": " ".join(f"U+{ord(c):04X}" for c in cluster),
                "advance": end - start,
            }
        os.write(1, b"\r\x1b[2K")
        if use_alt:
            os.write(1, b"\x1b[?1049l")
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    with open(out_path, "w") as f:
        json.dump({"stamp": provenance, "advances": results}, f, indent=1, sort_keys=True)

if __name__ == "__main__":
    main()
