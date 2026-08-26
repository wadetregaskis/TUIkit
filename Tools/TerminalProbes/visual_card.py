#!/usr/bin/env python3
"""Prints a static alignment card: each row is |<c>|<c>|<c>|X with a ruler.
A cluster that paints the 2 cells TUIkit claims puts every X in the same
column; one that paints more pushes X right, one that paints less pulls it
left, and three copies make a one-cell error a three-cell one.

This is the PAINT probe, and it is the authority. `advance_probe.py` measures
with DSR, which is a cursor *report* — on Terminal.app the report and the
paint disagree for ZWJ sequences (DSR says 5, 8, 11; the glyphs paint 2 and
the row does not shear). A DSR advance that disagrees with the claim is a
hypothesis about rendering; this card is how it gets confirmed before anyone
compensates for it. See Documentation/Terminal-compatibility.md,
"ZWJ: where DSR lies".

Run INSIDE the terminal under test and look at the X column.
"""
import sys, time

rows = [
    ("ruler",        "12"),
    ("cjk",          "中"),
    # VS-16 and bare pictographs — paint 2, under-advance on some hosts.
    ("vs16_pencil",  "✏️"),
    ("vs16_heart",   "❤️"),
    ("vs16_screen",  "🖥️"),
    ("bare_screen",  "\U0001F5A5"),
    ("emoji_thumbs", "👍"),
    # Skin tones — over-advance; the output path strips them.
    ("skin_thumbs",  "👍🏽"),
    ("skin_fist",    "✊🏻"),
    ("skin_point_up", "☝🏽"),
    ("sf_pua",       "\U00100038"),
    # Chrome.
    ("blocks",       "██"),
    ("halfpair",     "▐▌"),
    # Non-emoji scalars in the pictographic planes. These paint ONE cell on
    # every measured host; TUIkit claimed 2 until 2026-08-26, so their X sat
    # three columns right of the ruler's.
    ("mahjong",      "\U0001F000"),
    ("domino",       "\U0001F060"),
    ("card",         "\U0001F0A1"),
    ("legacy_block", "\U0001FB00"),
    ("alchemical",   "\U0001F700"),
    ("chess",        "\U0001FA00"),
    ("encl_ideo",    "\U0001F200"),
    # ZWJ. Terminal.app, iTerm2, Ghostty and tmux compose these into 2 cells;
    # Warp draws the components, so its X runs far right. The class the DSR
    # numbers get wrong.
    ("zwj_astronaut", "\U0001F469‍\U0001F680"),
    ("zwj_family4",  "\U0001F468‍\U0001F469‍\U0001F467‍\U0001F466"),
    ("zwj_heartfire", "❤️‍\U0001F525"),
    ("zwj_rainbow",  "\U0001F3F3️‍\U0001F308"),
    # Flags: regional-indicator pairs and tag sequences.
    ("flag_us",      "\U0001F1FA\U0001F1F8"),
    ("flag_lone_ri", "\U0001F1E6"),
    ("tag_england",  "\U0001F3F4\U000E0067\U000E0062\U000E0065\U000E006E\U000E0067\U000E007F"),
]

print("0123456789012345678901234567890")
for name, cluster in rows:
    print(f"|{cluster}|{cluster}|{cluster}|X  {name}")
print("END-OF-CARD (window stays 60s)")
sys.stdout.flush()
time.sleep(60)
