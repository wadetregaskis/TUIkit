#!/usr/bin/env python3
"""Every problem cluster × every rendering strategy, measured in one run.

The question this answers: for each cluster the corpus knows terminals disagree
about, which emission strategies WORK on the terminal running this probe — and
in which of the specific ways the others fail. One run produces the whole truth
table, so a decision ("what should TUIkit emit for skin tones on this host")
is read off a table instead of assembled from one-off experiments.

## The strategies

Built per cluster from its RAW advance measured live on this terminal — not
from a model — so the probe works identically on a terminal nobody has
measured before:

  raw        the cluster verbatim
  cuf        cluster + CUF(claim − advance)          [advance < claim]
  ech_cuf    ECH(claim) + cluster + CUF(…)           [advance < claim]
  cub        cluster + CUB(advance − claim)          [advance > claim]
  cub_cuf    cluster + CUB(advance − claim + 1) + CUF(1)
  strip      the modifier removed (Fitzpatrick classes; VS-16 restored on
             text-presentation bases, mirroring `withSkinToneFallback`)
  zwnj       ZWNJ inserted before the modifier / after each ZWJ
  sep_scrc   DECSC+DECRC (ESC 7 ESC 8) inserted at the same points
  sep_sgr    a foreground-reasserting SGR inserted at the same points
  cup_place  the parts written at absolute columns (base, CUP, modifier)

The detach candidates (zwnj / sep_* / cup_place) exist because a terminal that
PAINTS a composed cluster narrower than it advances cannot be fixed by moves
alone: `CUF` shifts paint and internal equally, and `CUB` was measured to make
Apple Terminal re-render the cluster as its bare base — the modifier survives
in no position. Rendering the parts as separate glyphs (iTerm2's native
behaviour) is the only shape where both counters can agree AND the modifier
stays visible; these strategies try to force that shape.

## What is measured

Phase A — DSR only, works headless:
  * net advance of the emission (internal column),
  * whether a row written to the FULL terminal width wraps (the row number is
    the one thing DSR reports faithfully; a wrapped row is the
    white-cells-at-the-end defect),
  * the final internal column of that full-width row.

Phase B — pixels, only when a display is attached (`PROBE_SHOT`, optionally
`PROBE_SYNC` — see `landing_probe.py` for why capture belongs OUTSIDE the
terminal under test):
  * where the next character PAINTS (marker method),
  * how many cells the glyph inks,
  * reference glyphs (composed, stripped, bare base, lone modifier) rendered
    in the same run, same font, same grid — so `matrix_analyze.py` classifies
    each cell's APPEARANCE by nearest-reference pixel match: composed,
    stripped, detached, or other. No human reads a screenshot.

## Running

Inside the terminal under test, from `Tools/TerminalProbes`:

    PROBE_OUT=/tmp/matrix.json python3 matrix_probe.py            # phase A only
    PROBE_OUT=/tmp/matrix.json PROBE_SHOT=/tmp/mx PROBE_SYNC=1 \\
        python3 matrix_probe.py                                    # both phases

then, when screenshots were taken:

    python3 matrix_analyze.py /tmp/matrix.json -o data/<host>-matrix.json

`--classes a,b,c` restricts to the named corpus classes; the default is every
cluster in the corpus.
"""
import argparse
import json
import os
import sys
import time

from landing_probe import Terminal, capture, stamp

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.join(HERE, "data", "width-corpus.json")

ZWNJ = "‌"
SC_RC = "\x1b7\x1b8"
SGR_SEP = "\x1b[39m"
MARKER_CELLS = 4
MARKER = "\x1b[48;5;201m" + " " * MARKER_CELLS + "\x1b[0m"
CALIBRATION = "\x1b[48;5;46m  \x1b[48;5;201m  \x1b[0m"

# The cells the layout would claim for the cluster — the composed baseline.
NARROW_CLASSES = {"ascii", "combining"}


def claim_for(entry):
    if entry["class"] in NARROW_CLASSES or entry["id"] == "halfwidth_kana":
        return 1
    return 2


def load_corpus(class_filter):
    with open(CORPUS) as handle:
        document = json.load(handle)
    entries = []
    for entry in document["clusters"]:
        spelled = "".join(chr(int(s[2:], 16)) for s in entry["scalars"])
        if spelled != entry["text"]:
            raise SystemExit(f"{entry['id']}: `text` and `scalars` disagree")
        if class_filter and entry["class"] not in class_filter:
            continue
        entries.append(entry)
    return entries


def split_parts(text):
    """(base, modifier) for a Fitzpatrick cluster, or (None, None)."""
    base, modifier = [], []
    for character in text:
        if 0x1F3FB <= ord(character) <= 0x1F3FF:
            modifier.append(character)
        else:
            base.append(character)
    if modifier and base:
        return "".join(base), "".join(modifier)
    return None, None


def stripped_form(entry):
    """What `withSkinToneFallback` would emit, keyed by corpus class."""
    base, _ = split_parts(entry["text"])
    if base is None:
        return None
    # Text-presentation bases render 1 cell bare; the strip restores VS-16 so
    # the glyph keeps its 2-cell emoji form (the old walk's rule).
    if entry["class"] == "skin_tone_bmp_narrow" and "️" not in base:
        return base + "️"
    return base


def with_insertion(text, separator):
    """`separator` before each Fitzpatrick modifier and after each ZWJ."""
    out = []
    for character in text:
        if 0x1F3FB <= ord(character) <= 0x1F3FF:
            out.append(separator)
        out.append(character)
        if character == "‍":
            out.append(separator)
    return "".join(out)


def strategies_for(entry, raw_advance, claim):
    """Every applicable (name, payload_or_marker) for this cluster.

    `payload` is what to write; the `cup_place` marker is handled by the row
    writer because it needs the row number.
    """
    text = entry["text"]
    scalars = [ord(c) for c in text]
    multi = len(scalars) > 1
    has_modifier = any(0x1F3FB <= v <= 0x1F3FF for v in scalars) and split_parts(text)[0]
    has_zwj = 0x200D in scalars

    out = [("raw", text)]
    if raw_advance < claim:
        shortfall = claim - raw_advance
        out.append(("cuf", text + f"\x1b[{shortfall}C"))
        out.append(("ech_cuf", f"\x1b[{claim}X" + text + f"\x1b[{shortfall}C"))
    if raw_advance > claim:
        back = raw_advance - claim
        out.append(("cub", text + f"\x1b[{back}D"))
        out.append(("cub_cuf", text + f"\x1b[{back + 1}D\x1b[1C"))
    elif multi and raw_advance == claim:
        # Net-zero nudge: the candidate for clusters whose internal column is
        # right but whose paint lands short (flags, keycaps on some hosts).
        out.append(("cub_cuf", text + "\x1b[1D\x1b[1C"))

    if has_modifier:
        stripped = stripped_form(entry)
        if stripped:
            out.append(("strip", stripped))
    if has_modifier or has_zwj:
        out.append(("zwnj", with_insertion(text, ZWNJ)))
        out.append(("sep_scrc", with_insertion(text, SC_RC)))
        out.append(("sep_sgr", with_insertion(text, SGR_SEP)))
    if has_modifier:
        out.append(("cup_place", None))
    return out


def measure_dsr(terminal, entries):
    """Phase A: advance + full-width wrap for every (cluster, strategy)."""
    rows, width = terminal.size()
    results = []
    for entry in entries:
        claim = claim_for(entry)
        # The cluster's own advance on THIS terminal, from which the
        # strategies are built.
        terminal.write("\x1b[0m\x1b[2J\x1b[5;1H")
        terminal.write(entry["text"])
        _, after = terminal.report()
        raw_advance = after - 1

        for name, payload in strategies_for(entry, raw_advance, claim):
            terminal.write("\x1b[2J\x1b[5;1H   ")
            if payload is None:  # cup_place: the parts at absolute columns
                base, modifier = split_parts(entry["text"])
                terminal.write(base)
                terminal.write(f"\x1b[5;{3 + claim + 1}H")
                terminal.write(modifier)
                effective = None
            else:
                terminal.write(payload)
                effective = payload
            _, mid = terminal.report()
            advance = mid - 1 - 3
            # Full-width wrap, twice: budgeted at the COMPOSED claim (what the
            # layout claims today) and at the strategy's OWN advance (what the
            # layout would claim if it adopted this strategy — the question a
            # detach strategy exists to answer). A strategy is layout-viable
            # when the self-budgeted row does not wrap.
            fill = width - 3 - claim - 1
            terminal.write(" " * max(0, fill) + "|")
            end_row, end_col = terminal.report()
            wrapped_at_claim = end_row != 5

            terminal.write("\x1b[2J\x1b[5;1H   ")
            if payload is None:
                base, modifier = split_parts(entry["text"])
                terminal.write(base)
                terminal.write(f"\x1b[5;{3 + claim + 1}H")
                terminal.write(modifier)
            else:
                terminal.write(payload)
            self_fill = width - 3 - advance - 1
            terminal.write(" " * max(0, self_fill) + "|")
            self_row, self_col = terminal.report()

            results.append({
                "id": entry["id"], "class": entry["class"], "claim": claim,
                "raw_advance": raw_advance, "strategy": name,
                "advance": advance,
                "wrapped_at_claim": wrapped_at_claim,
                "final_col_at_claim": end_col,
                "wrapped_at_advance": self_row != 5,
                "final_col_at_advance": self_col,
                "emission": effective,
            })
    return results, width


def draw_pixel_pages(terminal, entries, shot_prefix, sync):
    """Phase B: labelled rows with markers + ink rows + reference glyphs."""
    rows, width = terminal.size()
    per_page = (rows - 4) // 2

    # References first: every distinct glyph the classifier compares against.
    reference_rows = []
    seen = set()
    for entry in entries:
        text = entry["text"]
        candidates = [("ref_raw", entry["id"], text)]
        stripped = stripped_form(entry)
        if stripped and stripped != text:
            candidates.append(("ref_strip", entry["id"], stripped))
        base, modifier = split_parts(text)
        if base:
            candidates.append(("ref_base", entry["id"], base))
            candidates.append(("ref_mod", entry["id"], modifier))
        for kind, cid, glyph in candidates:
            key = (kind, glyph)
            if key not in seen:
                seen.add(key)
                reference_rows.append({"kind": kind, "id": cid, "text": glyph})

    test_rows = []
    for entry in entries:
        claim = claim_for(entry)
        terminal.write("\x1b[0m\x1b[2J\x1b[5;1H")
        terminal.write(entry["text"])
        _, after = terminal.report()
        raw_advance = after - 1
        base, modifier = split_parts(entry["text"])
        stripped = stripped_form(entry)
        for name, payload in strategies_for(entry, raw_advance, claim):
            test_rows.append({"id": entry["id"], "class": entry["class"],
                              "claim": claim, "strategy": name,
                              "payload": payload, "text": entry["text"],
                              # The part texts ride along so the analyzer can
                              # resolve references BY GLYPH: reference rows are
                              # deduplicated per (kind, glyph), so an id-keyed
                              # lookup missed every cluster whose modifier had
                              # already been drawn for an earlier one.
                              "base": base, "modifier": modifier,
                              "stripped": stripped})

    pages, cells = [], []
    queue = [("ref", row) for row in reference_rows] + [("test", row) for row in test_rows]
    for start in range(0, len(queue), per_page):
        batch = queue[start:start + per_page]
        terminal.write("\x1b[0m\x1b[2J")
        last_row = 3 + len(batch) * 2
        for r in (1, last_row):
            terminal.write(f"\x1b[{r};1H{CALIBRATION}")
        terminal.write(f"\x1b[1;71H{CALIBRATION}")

        row_number = 3
        page_cells = []
        for kind, row in batch:
            terminal.write(f"\x1b[{row_number};1H")
            if kind == "ref":
                terminal.write(row["text"])
                page_cells.append({"kind": row["kind"], "id": row["id"],
                                   "text": row["text"], "row": row_number})
            else:
                if row["payload"] is None:  # cup_place
                    base, modifier = split_parts(row["text"])
                    terminal.write(base)
                    # Adjacent: the base occupies columns 1..claim, so the
                    # modifier goes at claim+1 — phase A's 3-column gutter
                    # produced the same adjacency, and an earlier +1 here made
                    # the classifier judge the probe's own gap as "detached".
                    terminal.write(f"\x1b[{row_number};{row['claim'] + 1}H")
                    terminal.write(modifier)
                else:
                    terminal.write(row["payload"])
                _, after = terminal.report()
                terminal.write(MARKER)
                # The ink copy on its OWN row (a displaced row displaces
                # everything after it, including an ink copy — measured).
                terminal.write(f"\x1b[{row_number + 1};1H")
                if row["payload"] is None:
                    base, modifier = split_parts(row["text"])
                    terminal.write(base)
                    terminal.write(f"\x1b[{row_number + 1};{row['claim'] + 1}H")
                    terminal.write(modifier)
                else:
                    terminal.write(row["payload"])
                page_cells.append({"kind": "test", "id": row["id"],
                                   "class": row["class"], "claim": row["claim"],
                                   "strategy": row["strategy"],
                                   "row": row_number, "ink_row": row_number + 1,
                                   "advance": after - 1})
            row_number += 2

        index = len(pages)
        path = f"{shot_prefix}-p{index}.png"
        time.sleep(0.8)
        capture(terminal, path, sync)
        for cell in page_cells:
            cell["page"] = index
        pages.append({"index": index, "last_row": last_row, "screenshot": path})
        cells.extend(page_cells)
    return {"pages": pages, "cells": cells,
            "grid": {"marker_cells": MARKER_CELLS, "calibration_cells": 2}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--classes", default=None,
                        help="comma-separated corpus classes (default: all)")
    arguments = parser.parse_args()
    output = os.environ.get("PROBE_OUT")
    if not output:
        raise SystemExit("set PROBE_OUT to the output path")
    class_filter = set(arguments.classes.split(",")) if arguments.classes else None
    entries = load_corpus(class_filter)
    shot_prefix = os.environ.get("PROBE_SHOT")

    with Terminal() as terminal:
        terminal.write("\x1b[?1049h")
        try:
            dsr, width = measure_dsr(terminal, entries)
            document = {"stamp": stamp(), "terminal_width": width, "dsr": dsr}
            if shot_prefix:
                document["pixels"] = draw_pixel_pages(
                    terminal, entries, shot_prefix,
                    os.environ.get("PROBE_SYNC") is not None)
        finally:
            terminal.write("\x1b[?1049l")

    with open(output, "w") as handle:
        json.dump(document, handle, indent=1, sort_keys=True)

    viable = sum(1 for r in dsr if not r["wrapped_at_advance"])
    conserving = sum(1 for r in dsr
                     if r["advance"] == r["claim"] and not r["wrapped_at_claim"])
    print(f"{len(dsr)} (cluster, strategy) cells; "
          f"{conserving} conserve the composed claim, "
          f"{viable} are layout-viable at their own advance"
          + ("" if shot_prefix else " (DSR phase only — no display captures)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
