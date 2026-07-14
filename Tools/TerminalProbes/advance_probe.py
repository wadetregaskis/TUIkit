#!/usr/bin/env python3
"""Terminal output-behaviour probe: measures the CURSOR ADVANCE of a battery
of grapheme clusters using DSR (ESC[6n), and dumps the environment.
Writes JSON to $PROBE_OUT (default: ./advance_probe.json). Run INSIDE the
terminal under test."""
import json, os, sys, termios, tty

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
    "braille": "\u28FF",
    "powerline": "\uE0B0",                      # BMP PUA powerline
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
        for name, cluster in BATTERY.items():
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

    env_keys = [
        "TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "COLORTERM",
        "TERM_SESSION_ID", "ITERM_SESSION_ID", "ITERM_PROFILE",
        "LC_TERMINAL", "LC_TERMINAL_VERSION", "TMUX", "TMUX_PANE",
        "COLORFGBG", "TERMINFO_DIRS", "__CFBundleIdentifier",
    ]
    env = {k: os.environ.get(k) for k in env_keys if os.environ.get(k) is not None}
    env["_PROBE_SCREEN"] = "alternate" if use_alt else "primary"
    with open(out_path, "w") as f:
        json.dump({"env": env, "advances": results}, f, indent=1, sort_keys=True)

main()
