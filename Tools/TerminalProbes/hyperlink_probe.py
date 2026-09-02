#!/usr/bin/env python3
"""OSC 8 hyperlink probe: is it SAFE to emit here, and does the host honour it?

Two different questions, and only the first one an escape sequence can answer.

**Safe** is measurable, and it is the one that decides whether TUIkit may emit
the sequence at all. An OSC is `ESC ] … ST`, and a terminal that has an OSC
parser consumes the whole thing whether or not it implements the command —
costing nothing, painting nothing. A terminal WITHOUT one prints the payload as
text: a URL sprayed across the row, the cursor left wherever that ended, and
every subsequent write on the row landing in the wrong column. That difference
is visible to DSR: print a known-width label wrapped in OSC 8, ask where the
cursor is, and compare against the same label printed bare. Same column means
the sequence was swallowed; further right means it was printed.

**Honoured** — the link is clickable, the host shows the URL on hover — is not
measurable from inside. No query reports it, no reply distinguishes a terminal
that stored the URL from one that discarded it, and the affordance is a mouse
gesture the application never sees (⌘-click and hover are handled by the
terminal above the mouse-reporting protocol, which is the whole point of the
feature). So the probe prints a card for a human to look at, and records their
answer beside the measurement rather than pretending to have derived it.

The distinction matters because the two answers license different things. A
host that SWALLOWS is one TUIkit can emit to unconditionally — nothing is lost
if the link is inert. A host that PRINTS must be excluded by name, and that
exclusion is a correctness requirement, not a nicety.

`unknown_osc` is the control for the safety half: a command number no terminal
implements. A host that swallows that swallows any OSC, so its OSC 8 result is
a property of its parser rather than of its hyperlink support — which is what
makes "safe" a claim about the class rather than about this one sequence.

Run INSIDE the terminal under test. Writes JSON to $PROBE_OUT (default
./hyperlink_probe.json) and prints the card. **Both screen buffers are
measured every time**, rather than either being selected by an environment
variable as the other probes do it: iTerm2 and Warp are already known to
diverge between the two, an app draws on the ALTERNATE one, and a safety
result that happens to have been taken on the primary would license an
emission nobody measured. Two rows cost one extra pass.
"""
import json, os, select, sys, termios, tty

import probe_stamp

URL = "https://example.com/tuikit"
LABEL = "LINK"                      # 4 cells, all ASCII: width is not in question

BEL = "\x07"
ST = "\x1b\\"


def spellings():
    """Every emission worth distinguishing, as (id, bytes, visible width, what)."""
    def link(url, text, terminator, params=""):
        return (f"\x1b]8;{params};{url}{terminator}"
                f"{text}"
                f"\x1b]8;;{terminator}")
    return [
        ("control", LABEL, len(LABEL),
         "the label alone — the column every other row is compared against"),
        ("bel", link(URL, LABEL, BEL), len(LABEL),
         "OSC 8 terminated with BEL (xterm's older, more widely accepted form)"),
        ("st", link(URL, LABEL, ST), len(LABEL),
         "OSC 8 terminated with ST (ESC \\) — the form the specification gives"),
        ("st_id", link(URL, LABEL, ST, params="id=tuikit-1"), len(LABEL),
         "…with an id= parameter, which is how one link spans several rows"),
        ("close_only", f"\x1b]8;;{ST}{LABEL}", len(LABEL),
         "a bare close with no link open — what a clipped row could emit"),
        ("unknown_osc", f"\x1b]987;nothing-implements-this{ST}{LABEL}", len(LABEL),
         "an OSC command NO terminal implements: does this host swallow any OSC?"),
    ]


def cursor_column(fd):
    """DSR (`ESC[6n`) — the column the cursor is in, 1-based, or None."""
    os.write(fd, b"\x1b[6n")
    got = b""
    while select.select([fd], [], [], 1.5)[0]:
        got += os.read(fd, 1024)
        if got.endswith(b"R"):
            break
    else:
        return None
    try:
        body = got[got.rfind(b"\x1b[") + 2:-1]
        return int(body.split(b";")[1])
    except (IndexError, ValueError):
        return None


def measure(fd, use_alt):
    """Print each spelling on its own fresh row and DSR the column after it."""
    results = {}
    if use_alt:
        os.write(fd, b"\x1b[?1049h")
    for name, emission, visible, what in spellings():
        os.write(fd, b"\r\x1b[2K")                 # column 1, row cleared
        os.write(fd, emission.encode())
        column = cursor_column(fd)
        os.write(fd, b"\r\x1b[2K")
        results[name] = {
            "what": what,
            "visible_cells": visible,
            "expected_column_if_swallowed": visible + 1,
            "measured_column": column,
            "swallowed": None if column is None else column == visible + 1,
            "bytes": emission.replace("\x1b", "<ESC>").replace("\x07", "<BEL>"),
        }
    if use_alt:
        os.write(fd, b"\x1b[?1049l")
    return results


def card():
    """The human half: what a person has to look at, because no query says it."""
    print("\n  OSC 8 hyperlink card — what the terminal does with a real link\n")
    for terminator, label in ((BEL, "BEL-terminated"), (ST, "ST-terminated")):
        print(f"    {label:<16} "
              f"\x1b]8;;{URL}{terminator}"
              f"\x1b[4;34mexample.com/tuikit\x1b[0m"
              f"\x1b]8;;{terminator}")
    print(f"\n    with an id=      "
          f"\x1b]8;id=tuikit-card;{URL}{ST}"
          f"\x1b[4;34msplit across\x1b[0m\x1b]8;;{ST}"
          f"  …and  "
          f"\x1b]8;id=tuikit-card;{URL}{ST}"
          f"\x1b[4;34mtwo runs\x1b[0m\x1b]8;;{ST}"
          f"   (one link if honoured: hovering either should light both)")
    print("""
  Three things to answer by looking, none of which a query reports:

    1. Is the URL VISIBLE as text anywhere above? If so this host has no OSC
       parser and TUIkit must never emit the sequence here.
    2. Does hovering a label show the URL, and does ⌘-click (or ctrl-click,
       or plain click) open it? That is "honoured".
    3. Do the two `id=` runs highlight TOGETHER on hover? That is the id
       parameter working, which is what lets one link survive a line break.
""")


def main():
    out_path = os.environ.get("PROBE_OUT", "hyperlink_probe.json")
    fd = sys.stdin.fileno()
    if not os.isatty(fd):
        sys.exit("hyperlink_probe: stdin is not a terminal — run this IN the terminal under test")

    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        stamp = probe_stamp.stamp(fd, "hyperlink_probe", use_alt=False)
        screens = {"primary": measure(fd, use_alt=False),
                   "alternate": measure(fd, use_alt=True)}
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    record = dict(stamp)
    record["screen"] = "both"
    record["url"] = URL
    record["measurements"] = screens
    record["honoured"] = "unmeasured — see the card; fill this in by hand"
    with open(out_path, "w") as f:
        json.dump(record, f, indent=2, ensure_ascii=False)

    for screen, results in screens.items():
        control = results["control"]["measured_column"]
        print(f"\n  {screen} screen")
        print(f"  {'spelling':<14} {'column':>7}  verdict")
        for name, result in results.items():
            column = result["measured_column"]
            verdict = ("no DSR answer" if column is None
                       else "swallowed" if result["swallowed"]
                       else f"PRINTED — {column - control} stray cells")
            print(f"  {name:<14} {str(column):>7}  {verdict}")
    card()
    print(f"  written to {out_path}")


if __name__ == "__main__":
    main()
