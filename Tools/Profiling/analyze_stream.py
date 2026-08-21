#!/usr/bin/env python3
"""
Attribute the bytes a TUIkit app wrote to a terminal.

`drive.py --dump OUT.ansi` captures the raw stream; this splits it into the
three things it can be — styling (SGR), positioning and erasing (other CSI),
and the cells themselves — and reports how much of the styling was NECESSARY,
by replaying the stream through a minimal terminal model and asking, at each
SGR, whether the state it establishes differs from the state already in force.

The necessary figure is a FLOOR, not a target: it assumes an oracle that knows
the terminal's state everywhere, which the renderer does not (a span writing
into a row it did not write last frame cannot know what is under it). The gap
between emitted and necessary is what the render path could in principle
close.

Usage:
    analyze_stream.py OUT.ansi [OUT2.ansi ...]
"""
import re
import sys

CSI = re.compile(rb"\x1b\[([0-?]*)([ -/]*)([@-~])")


def analyse(path):
    data = open(path, "rb").read()
    sgr_bytes = sgr_count = other_bytes = other_count = 0
    redundant_bytes = redundant_count = 0
    state = None  # the parameter list in force, as the terminal sees it
    for match in CSI.finditer(data):
        length = len(match.group(0))
        if match.group(3) == b"m":
            sgr_bytes += length
            sgr_count += 1
            params = match.group(1)
            netted = net(state, params)
            if netted == state:
                redundant_bytes += length
                redundant_count += 1
            state = netted
        else:
            other_bytes += length
            other_count += 1
    escape_bytes = sgr_bytes + other_bytes
    cells = len(data) - escape_bytes
    print(f"{path}")
    print(f"  total          {len(data):>10,}")
    print(f"  cells          {cells:>10,}  ({100*cells/len(data):5.1f}%)")
    print(f"  SGR            {sgr_bytes:>10,}  ({100*sgr_bytes/len(data):5.1f}%)  "
          f"{sgr_count:,} escapes")
    print(f"    of which redundant {redundant_bytes:>6,}  "
          f"({100*redundant_bytes/max(1,sgr_bytes):5.1f}% of SGR)  {redundant_count:,} escapes")
    print(f"  cursor/erase   {other_bytes:>10,}  ({100*other_bytes/len(data):5.1f}%)  "
          f"{other_count:,} escapes")
    return len(data), sgr_bytes, redundant_bytes


def net(state, params):
    """The parameter set a terminal would be left in. Deliberately crude — it
    models a reset and otherwise accumulates — because the question here is
    'did this escape change anything', not 'what exactly does it mean'."""
    codes = params.split(b";") if params else [b"0"]
    if state is None:
        state = {}
    else:
        state = dict(state)
    index = 0
    while index < len(codes):
        code = codes[index] or b"0"
        if code == b"0":
            state = {}
        elif code in (b"38", b"48"):
            span = 3 if index + 1 < len(codes) and codes[index + 1] == b"5" else 5
            state["fg" if code == b"38" else "bg"] = b";".join(codes[index:index + span])
            index += span
            continue
        elif code == b"39":
            state.pop("fg", None)
        elif code == b"49":
            state.pop("bg", None)
        elif code.isdigit() and 30 <= int(code) <= 37 or code.isdigit() and 90 <= int(code) <= 97:
            state["fg"] = code
        elif code.isdigit() and 40 <= int(code) <= 47 or code.isdigit() and 100 <= int(code) <= 107:
            state["bg"] = code
        elif code in (b"22", b"23", b"24", b"25", b"27", b"28", b"29", b"21"):
            for on in {b"22": (b"1", b"2"), b"23": (b"3",), b"24": (b"4",),
                       b"25": (b"5", b"6"), b"27": (b"7",), b"28": (b"8",),
                       b"29": (b"9",), b"21": (b"1",)}[code]:
                state.pop(on, None)
        else:
            state[code] = True
        index += 1
    return state


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    for path in sys.argv[1:]:
        analyse(path)
