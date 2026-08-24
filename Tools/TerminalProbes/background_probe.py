#!/usr/bin/env python3
"""Terminal output-behaviour probe: does a cell the CURSOR skipped keep the
background colour in force?

The question behind it: an under-advancing cluster (a VS-16 emoji, an SF
Symbol) paints two cells and advances the cursor by one, so the app emits
CUF(1) to put the cursor at the glyph's visual end. CUF moves without
painting — so inside a coloured run the skipped cell keeps whatever was
already in it, and a highlighted row shows a hole in the middle of its emoji.

Four strategies are drawn, each on a coloured background run, so a screenshot
says which of them paints both cells. Cursor columns are measured by DSR at
the same time, so the ADVANCE of each strategy is known too — a strategy that
paints correctly and lands in the wrong column is no use.

Run INSIDE the terminal under test; writes JSON to $PROBE_OUT
(default ./background_probe.json) and leaves the card on screen for a
screenshot. `PROBE_WIDE=1` draws the rows double-width (DECDWL) — same cell
model, twice the pixels, which is what makes a one-cell hole readable off a
screen capture.
"""
import json, os, sys, termios, time, tty

# The cluster under test, and a couple of others from the same family.
CLUSTERS = {
    "vs16_gear": "⚙️",
    "vs16_screen": "\U0001F5A5️",
    "sf_pua": "\U00100038",
}

RUN = 8

BG = "\x1b[48;5;21m"      # saturated blue: no terminal's default is near it,
                           # so an unpainted cell cannot be mistaken for a painted one
FG = "\x1b[38;5;15m"
RESET = "\x1b[0m"


def strategies(cluster):
    """name -> the bytes to emit for one cluster inside a coloured run."""
    return {
        # What the compensation does today.
        "cuf_after": cluster + "\x1b[1C",
        # Paint the two cells first, step back over them, then draw the glyph.
        # The cells already carry the background; the glyph overwrites the
        # first, and the second keeps the paint the cursor never returns to.
        "paint_then_backtrack": "  " + "\x1b[2D" + cluster + "\x1b[1C",
        # The same, without stepping forward afterwards, to separate the two
        # halves of the question (painting from landing).
        "paint_then_backtrack_noskip": "  " + "\x1b[2D" + cluster,
        # ECH (CSI n X) erases n cells from the cursor WITHOUT moving it. If
        # the terminal erases to the current background — as EL does, and as
        # ECMA-48 leaves to the implementation — this paints the cells the
        # glyph will cover while adding no visible characters to the line,
        # which is what keeps every width measurement downstream honest.
        "ech_then_glyph": "\x1b[2X" + cluster + "\x1b[1C",
        # No compensation at all — the control.
        "bare": cluster,
    }


def write_results(out_path, results):
    env_keys = ["TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "COLORTERM",
                "LC_TERMINAL", "LC_TERMINAL_VERSION", "TMUX"]
    env = {k: os.environ.get(k) for k in env_keys if os.environ.get(k) is not None}
    env["_PROBE_SCREEN"] = "alternate" if os.environ.get("PROBE_ALT") == "1" else "primary"
    with open(out_path, "w") as f:
        json.dump({"env": env, "advances": results}, f, indent=1, sort_keys=True)


def Character_needs_compensation(cluster):
    """Whether this probe should compensate the cluster — i.e. whether the
    host under test under-advances it. Measured above; hardcoded here to the
    VS-16 / PUA families, which is all this comparison uses."""
    return "\uFE0F" in cluster or any(ord(c) >= 0x100000 for c in cluster)


def cursor_col(fd):
    os.write(1, b"\x1b[6n")
    buf = b""
    while not buf.endswith(b"R"):
        buf += os.read(fd, 1)
    inner = buf[buf.rfind(b"\x1b[") + 2 : -1]
    _row, col = inner.split(b";")
    return int(col)


def main():
    out_path = os.environ.get("PROBE_OUT", "background_probe.json")
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    wide = os.environ.get("PROBE_WIDE") == "1"
    # The alternate screen is where an app actually lives, and at least one
    # terminal advances some clusters differently there — so a measurement
    # taken on the primary screen is a measurement of somewhere the app is not.
    use_alt = os.environ.get("PROBE_ALT") == "1"
    hold = float(os.environ.get("PROBE_HOLD", "0"))
    results = {}
    try:
        tty.setraw(fd)
        if use_alt:
            os.write(1, b"\x1b[?1049h")
        os.write(1, b"\x1b[2J\x1b[H")
        os.write(1, ("background paint probe — " + os.environ.get("TERM_PROGRAM", "?")
                     + "\r\n\r\n").encode())
        os.write(1, b"           |....|....|....|....|....|....|....|\r\n")
        for label, cluster in CLUSTERS.items():
            for name, emission in strategies(cluster).items():
                # A RUN of clusters, not one: an unpainted cell is a single
                # cell, which no screenshot zoom can settle on its own. Eight
                # of them in a row turn the same defect into stripes — solid
                # fill means every cell was painted, a comb means every second
                # one was skipped, and either is unmistakable at any size.
                os.write(1, b"\r\x1b[2K")
                # DECDWL: twice the pixels per cell, for the screenshot. It
                # changes nothing about the cell MODEL — the measurement below
                # is the same either way — and a one-cell hole is otherwise
                # too small to read off a screen capture with any confidence.
                if wide:
                    os.write(1, b"\x1b#6")
                os.write(1, f"{label[:9]:>9} ".encode())
                os.write(1, (BG + FG).encode())
                os.write(1, b"[")
                start = cursor_col(fd)
                os.write(1, (emission * RUN).encode())
                end = cursor_col(fd)
                os.write(1, b"]" + RESET.encode())
                os.write(1, f"  {name}\r\n".encode())
                results[f"{label}/{name}"] = {
                    "advance": (end - start) / RUN, "run": RUN}
        os.write(1, b"\r\n")
        os.write(1, (BG + FG + "  reference: solid fill, no cluster  " + RESET).encode())
        os.write(1, b"\r\n\r\n")

        # Does the compensated cluster leave the text AFTER it in the same
        # column as a cluster that needs no compensation? A glyph that spills
        # outside its cells is a painting artifact nothing can fix; text that
        # lands in the wrong column is a layout bug, and the two look alike on
        # a screen. The bar is the answer: aligned bars mean the layout is
        # right.
        for label, cluster in [("compensated", "⚙️"), ("native 2-cell", "📁"),
                               ("plain ASCII", "ab")]:
            emission = (
                strategies(cluster)["ech_then_glyph"]
                if Character_needs_compensation(cluster) else cluster)
            os.write(1, f"\r\x1b[2K{label:>14} ".encode())
            os.write(1, (BG + FG).encode())
            os.write(1, emission.encode())
            os.write(1, b"|" + RESET.encode())
            os.write(1, b" after\r\n")
        write_results(out_path, results)
        # Held on the alternate screen so there is something to photograph:
        # leaving it restores the primary buffer and the card goes with it.
        # After the results are on disk, so a reader does not have to wait out
        # the hold to see them.
        if hold > 0:
            time.sleep(hold)
        if use_alt:
            os.write(1, b"\x1b[?1049l")
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    print(f"written: {out_path}")


main()
