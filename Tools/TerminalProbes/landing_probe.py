#!/usr/bin/env python3
"""Measure where the character AFTER a cluster actually lands.

Every other probe here measures what the terminal *says*. `advance_probe.py`
reads the cursor back with DSR, and DSR is a report, not paint: a terminal that
shapes a row as a text run can put the next glyph somewhere its own cursor
arithmetic never mentions. That gap is where this project's rendering bugs have
lived, and reading a screenshot by eye is how it kept failing to close them.

So this measures what an eye would measure, and hands the reading to a program.
For each cluster it prints

    <cluster><MARKER>

where MARKER is two cells of solid background colour, and lets the terminal put
the marker wherever it thinks the cursor now is. A screenshot then says which
column the marker is in. That column is the **landing** — the cell the next
character occupies, which is the number the layout has to agree with.

Three numbers come out of a run, and they are three different things:

  * `advance`  — DSR. What the terminal says the cursor did.
  * `landing`  — measured here, from pixels. Where the next character is drawn.
  * `reserve`  — `--wrap`. The smallest row budget the cluster does not wrap
                 out of, found by writing it that far from the right edge and
                 watching the row number change. What the layout must claim, or
                 text wraps early.

## Running it

Inside the terminal under test, from `Tools/TerminalProbes`:

    PROBE_OUT=/tmp/landing.json PROBE_SHOT=/tmp/shot python3 landing_probe.py --wrap

It draws one cluster per row — never two, because a cluster that over-advances
further than anyone predicted would otherwise put its marker in the next
cluster's slot and be overwritten by it — pages through the corpus, and
screenshots each page itself. Then:

    python3 landing_analyze.py /tmp/landing.json -o data/<host>.json

Without `PROBE_SHOT` it holds each page on screen for `PROBE_HOLD` seconds
instead, for capturing by hand or from another process.

The terminal needs no particular size (the probe pages to fit) but it does need
an opaque window and no background image: the analyser matches an exact colour,
and a translucent window blends it with whatever is behind.
"""
import json
import os
import subprocess
import sys
import termios
import time
import tty

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.join(HERE, "data", "width-corpus.json")

# Rows 1 and 2 carry the calibration marks and a caption; the last row carries
# the third mark. Clusters start at row 3.
FIRST_ROW = 3
CALIBRATION_COLUMN = 71

# 256-palette rather than truecolor: Apple Terminal has no 24-bit colour, and a
# marker it renders approximately is a marker the analyser cannot match
# exactly. Both indices are pure corners of the 6x6x6 cube.
# Four cells, not one: the analyser measures the marker's RIGHT edge, because
# a wide glyph's ink reaches into the cell the marker starts in and makes its
# left edge unreadable. Nothing is drawn after the marker, so its right edge is
# clean whatever the glyph did.
MARKER_CELLS = 4
MARKER = "\x1b[48;5;201m" + " " * MARKER_CELLS + "\x1b[0m"  # bright magenta
CALIBRATION_CELLS = 2
CALIBRATION = ("\x1b[48;5;46m" + " " * CALIBRATION_CELLS
               + "\x1b[48;5;201m" + " " * CALIBRATION_CELLS + "\x1b[0m")


def load_corpus():
    with open(CORPUS) as handle:
        document = json.load(handle)
    for entry in document["clusters"]:
        spelled = "".join(chr(int(s[2:], 16)) for s in entry["scalars"])
        if spelled != entry["text"]:
            raise SystemExit(f"{entry['id']}: `text` and `scalars` disagree")
    return document["clusters"]


class Terminal:
    """Raw-mode access to the controlling terminal."""

    def __enter__(self):
        self.fd = os.open("/dev/tty", os.O_RDWR)
        self.saved = termios.tcgetattr(self.fd)
        tty.setraw(self.fd)
        return self

    def __exit__(self, *_):
        termios.tcsetattr(self.fd, termios.TCSADRAIN, self.saved)
        os.close(self.fd)

    def write(self, text):
        os.write(self.fd, text.encode())

    def report(self):
        """`CSI 6n` — (row, column), both 1-based."""
        os.write(self.fd, b"\x1b[6n")
        buffer = b""
        while not buffer.endswith(b"R"):
            buffer += os.read(self.fd, 1)
        row, column = buffer.split(b"[")[1][:-1].split(b";")
        return int(row), int(column)

    def size(self):
        """(rows, columns), asked of the terminal rather than the environment."""
        self.write("\x1b[s\x1b[999;999H")
        rows, columns = self.report()
        self.write("\x1b[u")
        return rows, columns


# A marker placed at a column the probe chose, with no cluster in front of it.
# The analyser must read this column back exactly; if it cannot, its grid is
# wrong and every other number on the page is wrong with it. A measurement that
# cannot check itself is how this project has repeatedly convinced itself of
# things that were not so.
SELF_CHECK_ROW = 2
SELF_CHECK_COLUMN = 40

# A second copy of each cluster, on a row of its OWN, so the analyser can
# measure how many cells the glyph INKS.
#
# Its own row, and not simply further along the same one, because the
# displacement being measured is row-wide: on a row already carrying 🤙🏽,
# Apple Terminal paints an absolute `CUP` to column 50 at column 48. Every
# later column on the row inherits the whole accumulated error, which is
# exactly the bug — and exactly why the second copy cannot share the row with
# the first. Measuring ink against the marker instead is worse still: it can
# then never exceed the landing it is supposed to be checking, which is how a
# first version produced a perfect agreement that proved nothing.
INK_CELLS = 8


def draw_page(terminal, entries, last_row):
    """One cluster per row, each followed by its marker. Returns the cells."""
    terminal.write("\x1b[0m\x1b[2J\x1b[H")
    for row in (1, last_row):
        terminal.write(f"\x1b[{row};1H{CALIBRATION}")
    terminal.write(f"\x1b[1;{CALIBRATION_COLUMN}H{CALIBRATION}")
    terminal.write(f"\x1b[{SELF_CHECK_ROW};{SELF_CHECK_COLUMN}H{MARKER}")

    cells = []
    for index, entry in enumerate(entries):
        row = FIRST_ROW + index * 2
        terminal.write(f"\x1b[{row};1H")
        terminal.write(entry["text"])
        # DSR here, between the cluster and the marker: the same reading
        # `advance_probe.py` takes, recorded alongside the landing so the two
        # can be compared rather than confused.
        _, after = terminal.report()
        terminal.write(MARKER)
        terminal.write(f"\x1b[{row + 1};1H")
        terminal.write(entry["text"])
        cells.append({
            "id": entry["id"],
            "class": entry["class"],
            "row": row,
            "ink_row": row + 1,
            "column": 1,
            "advance": after - 1,
        })
    return cells


def capture(terminal, path, sync):
    """Get a screenshot of the page now on screen, into `path`.

    Two ways, and which one is available is a property of the machine rather
    than of the terminal.

    `PROBE_SYNC` is the reliable one: the probe writes `<page>.ready`, waits for
    `<page>.done`, and something else does the capturing. Preferred, because
    the terminal running this probe is usually the *worst* process to take the
    screenshot from — macOS asks it to confirm direct screen access, and the
    permission dialog appears **over the terminal**, covering the very columns
    being measured. That is not a hypothetical: it hid the calibration mark at
    column 71 for five runs, and the analyser correctly refused every one of
    them rather than calibrating off half a window.

    Otherwise the probe captures for itself, after raising its window with the
    portable `CSI 5 t` and, if `PROBE_ACTIVATE` names an application, bringing
    that forward.
    """
    if sync:
        ready = f"{path}.ready"
        done = f"{path}.done"
        for stale in (ready, done):
            if os.path.exists(stale):
                os.remove(stale)
        with open(ready, "w") as handle:
            handle.write(path)
        deadline = time.time() + 120
        while time.time() < deadline:
            if os.path.exists(done):
                return
            time.sleep(0.2)
        raise SystemExit(f"nothing captured {path} within 120s")

    terminal.write("\x1b[5t")
    application = os.environ.get("PROBE_ACTIVATE")
    if application:
        subprocess.run(
            ["osascript", "-e", f'tell application "{application}" to activate'],
            capture_output=True, timeout=15)
    time.sleep(0.6)
    subprocess.run(["screencapture", "-x", path], check=True)


# Enough room for the calibration marks and a useful number of clusters per
# page. Asked for with `CSI 8 ; rows ; columns t`; a terminal that declines is
# not a problem as long as it is already big enough.
WANTED_ROWS = 44
WANTED_COLUMNS = 100


def measure_landings(terminal, clusters, shot_prefix, hold, sync):
    terminal.write("\x1b[?1049h")
    rows, columns = terminal.size()
    if columns < CALIBRATION_COLUMN + 2 or rows < FIRST_ROW + 3:
        terminal.write(f"\x1b[8;{WANTED_ROWS};{WANTED_COLUMNS}t")
        time.sleep(0.5)
        rows, columns = terminal.size()
    if columns < CALIBRATION_COLUMN + 2 or rows < FIRST_ROW + 3:
        terminal.write("\x1b[?1049l")
        raise SystemExit(f"need at least {CALIBRATION_COLUMN + 2}x{FIRST_ROW + 3}, "
                         f"have {columns}x{rows} — and the terminal did not "
                         f"resize when asked. Make the window bigger.")

    per_page = (rows - FIRST_ROW - 1) // 2
    pages, cells = [], []
    for start in range(0, len(clusters), per_page):
        batch = clusters[start:start + per_page]
        last_row = FIRST_ROW + len(batch) * 2
        page_cells = draw_page(terminal, batch, last_row)
        index = len(pages)
        if shot_prefix:
            # Let the screen settle before capturing: a terminal that draws
            # asynchronously can still be a frame behind its own DSR replies.
            time.sleep(1.0)
            path = f"{shot_prefix}-p{index}.png"
            capture(terminal, path, sync)
        else:
            path = None
            time.sleep(hold)
        for cell in page_cells:
            cell["page"] = index
        pages.append({"index": index, "last_row": last_row, "screenshot": path})
        cells.extend(page_cells)

    terminal.write("\x1b[?1049l")
    return {"pages": pages, "cells": cells,
            "grid": {"first_row": FIRST_ROW,
                     "calibration_column": CALIBRATION_COLUMN,
                     "marker_cells": MARKER_CELLS,
                     "calibration_cells": CALIBRATION_CELLS,
                     "self_check_row": SELF_CHECK_ROW,
                     "self_check_column": SELF_CHECK_COLUMN,
                     "ink_cells": INK_CELLS,
                     "marker_palette": 201, "calibration_palette": 46}}


def measure_reserves(terminal, clusters):
    """The smallest row budget each cluster does not wrap out of.

    Written `budget` cells from the right edge; if the row number changes, the
    terminal wanted more than `budget`. A wrap is a state the terminal enters,
    not a number it reports, so this is the one reading that cannot be a lie
    about something else.
    """
    terminal.write("\x1b[?1049h\x1b[0m\x1b[2J\x1b[H")
    rows, columns = terminal.size()
    reserves = {}
    for entry in clusters:
        found = None
        for budget in range(1, 15):
            terminal.write(f"\x1b[{rows // 2};{columns - budget + 1}H")
            row_before, _ = terminal.report()
            terminal.write(entry["text"])
            row_after, _ = terminal.report()
            terminal.write("\x1b[2J")
            if row_after == row_before:
                found = budget
                break
        reserves[entry["id"]] = found
    terminal.write("\x1b[?1049l")
    return reserves


def stamp():
    keys = ("TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERMINFO",
            "LC_TERMINAL", "LC_TERMINAL_VERSION", "TMUX", "COLORTERM")
    return {
        "env": {k: os.environ[k] for k in keys if k in os.environ},
        "date": time.strftime("%Y-%m-%d %H:%M:%S %z"),
        "screen": "alternate",
    }


def main():
    output = os.environ.get("PROBE_OUT")
    if not output:
        raise SystemExit("set PROBE_OUT to the manifest path")
    shot_prefix = os.environ.get("PROBE_SHOT")
    sync = os.environ.get("PROBE_SYNC") is not None
    hold = int(os.environ.get("PROBE_HOLD", "20"))
    clusters = load_corpus()

    with Terminal() as terminal:
        document = measure_landings(terminal, clusters, shot_prefix, hold, sync)
        if "--wrap" in sys.argv:
            reserves = measure_reserves(terminal, clusters)
            for cell in document["cells"]:
                cell["reserve"] = reserves.get(cell["id"])

    document["stamp"] = stamp()
    with open(output, "w") as handle:
        json.dump(document, handle, indent=1, sort_keys=True)
    print(f"manifest -> {output} "
          f"({len(document['cells'])} cells over {len(document['pages'])} pages)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
