#!/usr/bin/env python3
"""Terminal output-behaviour probe: what colour does this terminal ACTUALLY
paint when we ask for one?

Every ANSI colour we emit is a NAME, not a colour. `SGR 31` says "red", and
what the user sees is whatever their colour scheme assigns to slot 1 — which
they are free to make green. TUIkit carries xterm's conventional RGB table
(`ANSIColor.rgbValues`) and derives real decisions from it: the WCAG contrast
floor, and the nearest-entry search that quantises a truecolor value down for a
256-colour terminal. Both are only as true as that table.

This asks the terminal instead, with the queries it is obliged to answer:

  * `OSC 4 ; n ; ? ST`  — what RGB is palette entry n? Asked for 0–15 (the ANSI
    names), a sample of the 6×6×6 cube, and a sample of the greyscale ramp.
  * `OSC 10 ; ? ST` / `OSC 11 ; ? ST` — the default foreground and background,
    which is what `SGR 39` / `SGR 49` paint and what `Color.default` means.

A terminal that answers with something other than xterm's table has a scheme
loaded, and every number derived from the table is approximate for that user.
A terminal that does not answer at all is recorded as `null` — silence is a
finding too, since it means an app can never know.

There is no query for 24-bit colour: `SGR 38;2;r;g;b` names the colour exactly
and a terminal has nothing to look up. That does not make it exact on screen —
see the `renders_truecolor_literally` block, which paints known values for
comparison against the numbers requested.

Run INSIDE the terminal under test; writes JSON to $PROBE_OUT (default
./palette_probe.json).
"""
import json, os, re, select, sys, termios, tty

# The sixteen ANSI names, then a sample of the cube and the ramp — enough to
# tell "the scheme touched the names" (the common case) from "the scheme
# touched everything" (xterm allows it; few schemes do).
INDICES = list(range(16)) + [52, 124, 196, 46, 21, 231] + [232, 240, 255]

# What xterm assigns, for the 16 that TUIkit's own table covers. Sourced from
# `ANSIColor.rgbValues`, so a mismatch here IS the mismatch that matters.
XTERM = {
    0: (0, 0, 0), 1: (205, 0, 0), 2: (0, 205, 0), 3: (205, 205, 0),
    4: (0, 0, 238), 5: (205, 0, 205), 6: (0, 205, 205), 7: (229, 229, 229),
    8: (127, 127, 127), 9: (255, 0, 0), 10: (0, 255, 0), 11: (255, 255, 0),
    12: (92, 92, 255), 13: (255, 0, 255), 14: (0, 255, 255), 15: (255, 255, 255),
}

REPLY = re.compile(r"rgb:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+)")


def scaled(component: str) -> int:
    """`rgb:` components are 1–4 hex digits at that many nibbles of precision."""
    value = int(component, 16)
    return round(value * 255 / (16 ** len(component) - 1))


def ask(fd, query: str, timeout: float = 0.35):
    """Writes an OSC query and reads its reply, or `None` if none arrives."""
    os.write(1, query.encode())
    buf = b""
    while True:
        ready, _, _ = select.select([fd], [], [], timeout)
        if not ready:
            break
        buf += os.read(fd, 64)
        # Both terminators are legal, and terminals disagree about which to use.
        if buf.endswith(b"\x07") or buf.endswith(b"\x1b\\"):
            break
    match = REPLY.search(buf.decode("utf-8", "replace"))
    if not match:
        return None
    return [scaled(part) for part in match.groups()]


def main():
    out_path = os.environ.get("PROBE_OUT", "palette_probe.json")
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    result = {"palette": {}, "default_foreground": None, "default_background": None}
    try:
        tty.setraw(fd)
        for index in INDICES:
            result["palette"][index] = ask(fd, f"\x1b]4;{index};?\x07")
        result["default_foreground"] = ask(fd, "\x1b]10;?\x07")
        result["default_background"] = ask(fd, "\x1b]11;?\x07")
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    answered = [i for i in INDICES if result["palette"][i] is not None]
    differing = {
        i: {"reported": result["palette"][i], "xterm": list(XTERM[i])}
        for i in XTERM
        if result["palette"].get(i) is not None and result["palette"][i] != list(XTERM[i])
    }
    env_keys = ["TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "COLORTERM",
                "LC_TERMINAL", "LC_TERMINAL_VERSION", "TMUX"]
    result["env"] = {k: os.environ.get(k) for k in env_keys if os.environ.get(k)}
    result["answers_osc4"] = len(answered) > 0
    result["differs_from_xterm"] = differing

    with open(out_path, "w") as handle:
        json.dump(result, handle, indent=1, sort_keys=True)

    print(f"answered {len(answered)} of {len(INDICES)} palette queries")
    if not answered:
        print("  → this terminal does not report its palette; an app cannot know it")
    elif differing:
        print(f"  → {len(differing)} of the 16 ANSI names differ from xterm's table:")
        for index, pair in sorted(differing.items()):
            print(f"     {index:3d}  reported {tuple(pair['reported'])}"
                  f"  xterm {tuple(pair['xterm'])}")
    else:
        print("  → the 16 ANSI names match xterm's table exactly")
    print(f"default fg {result['default_foreground']}, bg {result['default_background']}")
    print(f"written to {out_path}")


main()
