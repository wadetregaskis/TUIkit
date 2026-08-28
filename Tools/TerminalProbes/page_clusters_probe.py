#!/usr/bin/env python3
"""Measure the advance of every distinct cluster an APP ACTUALLY DRAWS.

`advance_probe.py` measures a hand-picked battery. This measures what a real
page puts on screen, which is a different question and a better one: the
battery only contains what somebody already thought to doubt.

Run in two steps.

1.  Off the terminal, capture what the app emits and extract its clusters:

        python3 page_clusters_probe.py --extract FRAME.bin CLUSTERS.json

    where FRAME.bin is the raw bytes the app wrote (capture it under a PTY;
    `Tools/Smoke/raw_probe.py` does this, or see the docstring below).

2.  INSIDE the terminal under test, measure them:

        CLUSTERS=CLUSTERS.json PROBE_OUT=OUT.json python3 page_clusters_probe.py

    Then compare OUT.json against the host's model. Any cluster where they
    differ is a row that shears on that terminal.

## Why this exists

Checking rows for self-consistency does NOT find these. The framework and the
model share the same numbers, so a model that is wrong about the terminal
produces rows that add up perfectly and still render wrong — verified: with
Warp's Plane-16 case removed, every row still summed to the terminal width
while every SF Symbol sheared a cell. Only a measurement against the terminal
separates "consistent" from "correct".

Found this way on 2026-08-26, none of them visible to the unit tests:

  * Warp gave every SF Symbol 2 where the terminal gives 1 — the only one of
    the five models with no Plane-16 case. The Example emoji page drew its SF
    Symbols panel with the right border displaced and the scrollbar jammed
    against it.
  * Ghostty merges a BMP text-presentation base and its skin-tone modifier
    into ONE cell (☝🏻 ✌🏼 ✍🏽 ⛹🏾), not two.
  * iTerm2 advances 1 for a ZWJ sequence whose first segment carries VS-16
    (❤️‍🔥 🏳️‍🌈). The base's plane is not the discriminator.
"""
import argparse
import json
import os
import re
import sys


def extract(frame_path, out_path):
    """Every distinct non-ASCII cluster in a captured frame."""
    raw = open(frame_path, "rb").read().decode("utf8", "replace")
    text = re.sub(r"\x1b\[[?>=]?[0-9;]*[ -/]*[@-~]", "", raw)
    text = re.sub(r"\x1b[\]P][^\x07\x1b]*(\x07|\x1b\\)?", "", text)

    def joins(character):
        value = ord(character)
        # Combining marks (including U+20E3 COMBINING ENCLOSING KEYCAP —
        # its omission dropped every keycap an app drew: the ASCII base fell
        # out and the marks surfaced as bogus one-scalar "clusters"),
        # selectors, ZWJ, Fitzpatrick modifiers, and tag scalars.
        return (0x0300 <= value <= 0x036F or 0x20D0 <= value <= 0x20FF
                or value in (0x200D, 0xFE0F, 0xFE0E)
                or 0x1F3FB <= value <= 0x1F3FF or 0xE0000 <= value <= 0xE007F)

    def is_ri(character):
        return 0x1F1E6 <= ord(character) <= 0x1F1FF

    clusters, index = [], 0
    while index < len(text):
        end = index + 1
        if is_ri(text[index]):
            # Regional indicators PAIR: a run of four is two flags back to
            # back, not one cluster (treating RI as a generic joiner glued
            # adjacent flags together).
            if end < len(text) and is_ri(text[end]):
                end += 1
        elif ord(text[index]) > 0x7F or (end < len(text) and joins(text[end])):
            # An ASCII scalar can START a cluster when the next scalar joins
            # (keycaps: "1" + FE0F + 20E3).
            while end < len(text) and joins(text[end]):
                end += 1
                # A joiner binds whatever follows it into the same cluster.
                if text[end - 1] == "‍" and end < len(text):
                    end += 1
        cluster = text[index:end]
        if any(ord(c) > 0x7F for c in cluster) and "\n" not in cluster:
            clusters.append(cluster)
        index = end

    seen, unique = set(), []
    for cluster in clusters:
        if cluster not in seen:
            seen.add(cluster)
            unique.append(cluster)
    json.dump(unique, open(out_path, "w"))
    print(f"{len(unique)} distinct non-ASCII clusters -> {out_path}")


def measure():
    """Advance of each cluster, measured on the terminal running this."""
    import termios
    import tty

    clusters = json.load(open(os.environ["CLUSTERS"]))

    def cursor_column(fd):
        os.write(fd, b"\x1b[6n")
        buf = b""
        while not buf.endswith(b"R"):
            buf += os.read(fd, 1)
        return int(buf.split(b"[")[1][:-1].split(b";")[1])

    fd = os.open("/dev/tty", os.O_RDWR)
    saved = termios.tcgetattr(fd)
    tty.setraw(fd)
    out = {}
    try:
        # Alternate screen: where apps run, and where several hosts differ.
        os.write(fd, b"\x1b[?1049h\x1b[2J\x1b[H")
        for cluster in clusters:
            os.write(fd, b"\r\x1b[2K")
            before = cursor_column(fd)
            os.write(fd, cluster.encode())
            after = cursor_column(fd)
            # Keyed by codepoint with a separator: "%04X" alone is ambiguous
            # once a scalar needs five digits.
            key = "-".join("%X" % ord(c) for c in cluster)
            out[key] = after - before
        os.write(fd, b"\x1b[?1049l")
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        os.close(fd)
    json.dump(out, open(os.environ["PROBE_OUT"], "w"), indent=1, sort_keys=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--extract", nargs=2, metavar=("FRAME", "CLUSTERS"))
    args = parser.parse_args()
    if args.extract:
        extract(*args.extract)
        return 0
    if not os.environ.get("CLUSTERS") or not os.environ.get("PROBE_OUT"):
        parser.error("set CLUSTERS and PROBE_OUT, or pass --extract")
    measure()
    return 0


if __name__ == "__main__":
    sys.exit(main())
