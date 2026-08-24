#!/usr/bin/env python3
"""Terminal output-behaviour probe: does a FULL-WIDTH row carrying an
under-advancing cluster still end where the arithmetic says it does?

`background_probe.py` settles the two questions a short line can ask — does a
compensated cluster paint both its cells, and does the text after it land in
the right column. Both come out right, and a report of a row rendering one cell
short survived them. What neither asks is the case an app actually draws: a row
padded to the terminal's exact width, where a cluster that consumes more line
budget than it claims has nowhere to put the excess.

`FrameDiffWriter.repaintRightEdge` documents that shape for one family already —
"the emoji apparently consumes 2 phantom cells of line budget that
`strippedLength` doesn't track, causing the line to wrap" — so this probe asks
it directly, for the VS-16 family and each compensation strategy.

Method: park the cursor at a known row, emit exactly `columns` cells of content
(one cluster plus padding), then DSR. A row that behaved has the cursor at the
last column of the SAME row; one that wrapped reports the next row; one that
came up short reports a smaller column. The reference rows — a native two-cell
emoji and plain ASCII — say what "behaved" looks like on this host.

Run INSIDE the terminal under test; writes JSON to $PROBE_OUT (default
./row_probe.json) and leaves the rows on screen for a screenshot.
`PROBE_ALT=1` runs on the alternate screen, which is where an app lives.
`PROBE_HOLD=n` keeps the picture up for n seconds afterwards.
"""
import json, os, sys, termios, time, tty

# Each case: a label, the cluster, and whether it is one the app compensates.
CASES = [
    ("vs16_gear", "⚙️", True),
    ("vs16_screen", "\U0001F5A5️", True),
    ("native_2cell", "📁", False),
    ("plain_ascii", "ab", False),
]

# How many cells short of the right edge the measurement is taken. The cursor
# CLAMPS at the last column, so a row measured at the edge reports the same
# number whether it spent its budget exactly or overspent — which is the whole
# question. Four is enough to see an overspend of one or two.
MARGIN = 4

BG = "\x1b[48;5;22m"  # a dark green, as a selected row's highlight is
FG = "\x1b[38;5;46m"
RESET = "\x1b[0m"


def emissions(cluster, compensate):
    """name -> the bytes for one cluster, with each compensation strategy."""
    if not compensate:
        return {"none": cluster}
    return {
        # What the compensation did before 2026-08-23.
        "cuf_after": cluster + "\x1b[1C",
        # What it does now: erase the two cells in the current background
        # (which paints them without writing a visible character), draw the
        # glyph over the first, then step past the second.
        "ech_then_glyph": "\x1b[2X" + cluster + "\x1b[1C",
        # No compensation at all — the control, and what a host TUIkit has no
        # advance model for receives.
        "bare": cluster,
    }


def cursor_position(fd):
    os.write(1, b"\x1b[6n")
    buf = b""
    while not buf.endswith(b"R"):
        buf += os.read(fd, 1)
    inner = buf[buf.rfind(b"\x1b[") + 2 : -1]
    row, col = inner.split(b";")
    return int(row), int(col)


def terminal_size():
    import fcntl, struct
    packed = fcntl.ioctl(1, termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0))
    rows, cols, _, _ = struct.unpack("HHHH", packed)
    return rows, cols


def write_results(out_path, columns, results):
    env_keys = ["TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "COLORTERM",
                "LC_TERMINAL", "LC_TERMINAL_VERSION", "TMUX"]
    env = {k: os.environ.get(k) for k in env_keys if os.environ.get(k) is not None}
    env["_PROBE_SCREEN"] = "alternate" if os.environ.get("PROBE_ALT") == "1" else "primary"
    with open(out_path, "w") as f:
        json.dump({"env": env, "columns": columns, "rows": results}, f, indent=1, sort_keys=True)


def main():
    out_path = os.environ.get("PROBE_OUT", "row_probe.json")
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    use_alt = os.environ.get("PROBE_ALT") == "1"
    hold = float(os.environ.get("PROBE_HOLD", "0"))
    _, columns = terminal_size()
    results = {}
    try:
        tty.setraw(fd)
        if use_alt:
            os.write(1, b"\x1b[?1049h")
        os.write(1, b"\x1b[2J\x1b[H")
        os.write(1, (f"full-row probe — {os.environ.get('TERM_PROGRAM', '?')}"
                     f" — {columns} columns\r\n\r\n").encode())
        row = 4
        for label, cluster, compensate in CASES:
            for name, emission in emissions(cluster, compensate).items():
                # The row is built to claim EXACTLY `columns` cells: a two-cell
                # label gutter, the cluster (claiming 2, or its own width for
                # ASCII), and spaces for the rest. Anything the host spends
                # beyond that shows up in the DSR below.
                claimed = 2 if compensate or cluster == "📁" else len(cluster)
                tag = f"{label[:11]:<11} {name[:14]:<14}"
                # Padded to MARGIN cells short of the edge, and the row filled
                # afterwards. The cursor clamps at the last column, so a row
                # measured at the edge reports the same number whatever it
                # spent — which is exactly the difference being looked for.
                pad = columns - MARGIN - len(tag) - 1 - claimed
                os.write(1, f"\x1b[{row};1H\x1b[2K".encode())
                os.write(1, (BG + FG).encode())
                os.write(1, tag.encode())
                os.write(1, b" ")
                os.write(1, emission.encode())
                os.write(1, (" " * max(0, pad)).encode())
                at_row, at_col = cursor_position(fd)
                # …and only NOW fill to the edge, so the row on screen is the
                # full-width one the question is about.
                os.write(1, (" " * MARGIN).encode())
                os.write(1, RESET.encode())
                results[f"{label}/{name}"] = {
                    "endRow": at_row, "endColumn": at_col,
                    "wrapped": at_row != row,
                    # One past the last cell written, for a row that spent
                    # exactly what it claimed.
                    "expectedColumn": columns - MARGIN + 1,
                }
                row += 1
        os.write(1, f"\x1b[{row + 1};1H".encode())
        write_results(out_path, columns, results)
        if hold:
            time.sleep(hold)
    finally:
        if use_alt:
            os.write(1, b"\x1b[?1049l")
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


main()
