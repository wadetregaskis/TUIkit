#!/usr/bin/env python3
"""Sweep the 1FA70-1FAFF emoji block (+ controls) through DSR in the current
terminal: which recent emoji does this host's width table not know?
Fully automatic - the JSON is the result; the screen just shows a summary.
"""
import json, os, termios, tty

E = "\x1b"

SWEEP = [int(x, 16) for x in """
1FA70 1FA71 1FA72 1FA73 1FA74 1FA75 1FA76 1FA77 1FA78 1FA79 1FA7A 1FA7B 1FA7C
1FA80 1FA81 1FA82 1FA83 1FA84 1FA85 1FA86 1FA87 1FA88 1FA89 1FA8F 1FA90 1FA91
1FA92 1FA93 1FA94 1FA95 1FA96 1FA97 1FA98 1FA99 1FA9A 1FA9B 1FA9C 1FA9D 1FA9E
1FA9F 1FAA0 1FAA1 1FAA2 1FAA3 1FAA4 1FAA5 1FAA6 1FAA7 1FAA8 1FAA9 1FAAA 1FAAB
1FAAC 1FAAD 1FAAE 1FAAF 1FAB0 1FAB1 1FAB2 1FAB3 1FAB4 1FAB5 1FAB6 1FAB7 1FAB8
1FAB9 1FABA 1FABB 1FABC 1FABD 1FABE 1FABF 1FAC0 1FAC1 1FAC2 1FAC3 1FAC4 1FAC5
1FAC6 1FACE 1FACF 1FAD0 1FAD1 1FAD2 1FAD3 1FAD4 1FAD5 1FAD6 1FAD7 1FAD8 1FAD9
1FADA 1FADB 1FADC 1FADF 1FAE0 1FAE1 1FAE2 1FAE3 1FAE4 1FAE5 1FAE6 1FAE7 1FAE8
1FAE9 1FAF0 1FAF1 1FAF2 1FAF3 1FAF4 1FAF5 1FAF6 1FAF7 1FAF8
1F600 1F6DC
""".split()]

fd = os.open("/dev/tty", os.O_RDWR)
saved = termios.tcgetattr(fd)
tty.setraw(fd)

def write(t): os.write(fd, t.encode())

def report():
    os.write(fd, b"\x1b[6n")
    b = b""
    while not b.endswith(b"R"):
        b += os.read(fd, 1)
    r, c = b.split(b"[")[1][:-1].split(b";")
    return int(r), int(c)

out = {"program": os.environ.get("TERM_PROGRAM", "?"), "advances": {}}
try:
    write(f"{E}[8;30;100t{E}[?1049h{E}[?25l{E}[2J{E}[H")
    write("Recent-emoji sweep (automatic)...\r\n")
    for v in SWEEP:
        write(f"{E}[20;1H{E}[K")
        _, before = report()
        write(chr(v))
        _, after = report()
        out["advances"][f"{v:X}"] = after - before
    write(f"{E}[20;1H{E}[K")
    narrow = [k for k, a in out["advances"].items() if a == 1]
    write(f"{E}[3;1HDone: {len(out['advances'])} scalars, advance 1 for: {' '.join(narrow) or 'none'}\r\n")
    write("q = quit\r\n")
    if "PROBE_OUT" in os.environ:
        with open(os.environ["PROBE_OUT"], "w") as f:
            json.dump(out, f, indent=1)
    while os.read(fd, 1) not in (b"q", b"\x03"):
        pass
    write(f"{E}[?25h{E}[?1049l")
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, saved)
    os.close(fd)
