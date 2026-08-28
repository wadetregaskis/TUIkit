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
    "pua_bmp_sf": "\U000F0000" if False else "\U00102446",
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
