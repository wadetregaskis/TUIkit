#!/usr/bin/env python3
"""Prints a static alignment card: each row is |<cluster>|X with a ruler.
A correctly-advancing 2-cell cluster puts every X in the same column."""
import sys, time
rows = [
    ("ruler",      "12"),
    ("cjk",        "中"),
    ("vs16_pencil","✏️"),
    ("vs16_heart", "❤️"),
    ("vs16_screen","🖥️"),
    ("emoji_thumbs","👍"),
    ("skin_thumbs","👍🏽"),
    ("skin_fist",  "✊🏻"),
    ("sf_pua",     "\U00100038"),
    ("blocks",     "██"),
    ("halfpair",   "▐▌"),
]
print("0123456789012345678901234567890")
for name, cluster in rows:
    print(f"|{cluster}|X  {name}")
print("END-OF-CARD (window stays 60s)")
sys.stdout.flush()
time.sleep(60)
