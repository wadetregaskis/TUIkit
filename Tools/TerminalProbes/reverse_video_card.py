#!/usr/bin/env python3
"""Prints a card for what SGR 7 (reverse video) PAINTS here, for a person to judge by eye.

This measures nothing and records nothing. It draws each reverse-video case
next to a hand-swapped reference: the same colours with foreground and
background exchanged explicitly, with no SGR 7. Then it parks the cursor over a
reversed cell, so you can also see how the host draws its cursor there.

Whether SGR 7 is SAFE to send is a different question, and a cursor report
answers it: every spelling on this card printed nothing and advanced text
exactly as plain text on Apple Terminal, iTerm2, Warp, GNU screen and tmux on
2026-09-14. What a reversed cell looks like no report can say, which is why
this is a card.

Run it INSIDE the terminal under test, in a window at least 96 columns wide:

    python3 reverse_video_card.py              # keys 1-6 move the cursor, q quits
    python3 reverse_video_card.py --no-query   # skip the OSC 10/11 default-colour query
    python3 reverse_video_card.py --hold 20    # no keys: park on target 1, exit after 20 s

What each row asks is printed under it. The rows marked "extra" were not among
the spellings the cursor check sent; they are here because they are cheap to
look at.

Reading the card:

  * Rows B, D and E have an exact reference: left and right should be the same
    cell colours if the host swaps foreground and background for SGR 7.
  * Rows A and C reverse the DEFAULT colours, which SGR cannot name. Their
    reference is built from the host's own OSC 10/11 answer, spelled as 24-bit
    colour. With no answer (GNU screen, for one) those rows show no reference.
    A host without 24-bit colour quantises the reference, so compare with care.
  * Warp: `appearance.text.enforce_minimum_contrast` defaults to
    `only_named_colors`, which lightens a foreground named as one of the
    sixteen when Warp judges it illegible. So under Warp a left/right mismatch
    in the named rows (B, E) may come from that setting, not from SGR 7. Read
    the setting's value and record it; do not change it for the card.
  * Under tmux or GNU screen you see the multiplexer's rendering, drawn through
    the outer terminal.

Record what you saw, with the host, its version and its colour profile or
theme, in Documentation/Terminal-compatibility.md, "Reverse video (SGR 7)".

The terminal is restored on exit: SGR reset, cursor shown, termios put back.
Nothing else is changed (no cursor shape, no modes, no colours set on the host).
The only query is OSC 10/11, fenced by CSI 5n.
"""
import argparse
import os
import re
import select
import termios
import time
import tty

ESC = "\x1b"
CSI = ESC + "["
RESET = CSI + "0m"
SAMPLE = " Ab 0123 "            # 9 cells, ASCII only, so no width question
LABEL_COL = 3
REV_COL = 50
REF_COL = 66
MIN_COLUMNS = 96                # the longest text line, not just the swatches
OSC_REPLY = re.compile(
    rb"\x1b\]1([01]);rgb:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+)(?:\x07|\x1b\\)")


def to8(hexdigits):
    return round(int(hexdigits, 16) * 255 / (16 ** len(hexdigits) - 1))


def query_default_colours(fd):
    """(fg, bg) as 8-bit triples from OSC 10/11, or None for either one not answered.
    Fenced by CSI 5n, which every measured host answers, so silence costs one read."""
    os.write(fd, b"\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b[5n")
    got = b""
    deadline = time.monotonic() + 0.6
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], max(0.0, deadline - time.monotonic()))
        if not ready:
            break
        got += os.read(fd, 4096)
        if b"\x1b[0n" in got:
            break
    colours = {}
    for match in OSC_REPLY.finditer(got):
        colours[match.group(1)] = tuple(to8(match.group(n)) for n in (2, 3, 4))
    return colours.get(b"0"), colours.get(b"1")


def at(row, col):
    return "%s%d;%dH" % (CSI, row, col)


def parse_arguments():
    parser = argparse.ArgumentParser(description="SGR 7 reverse-video card, judged by eye.")
    parser.add_argument("--no-query", action="store_true",
                        help="do not ask OSC 10/11; rows A and C then have no reference")
    parser.add_argument("--hold", type=float, metavar="SECONDS",
                        help="read no keys: park on target 1 and exit after SECONDS")
    return parser.parse_args()


def main():
    arguments = parse_arguments()
    no_query = arguments.no_query
    hold = arguments.hold

    fd = os.open("/dev/tty", os.O_RDWR)
    saved = termios.tcgetattr(fd)
    out = []
    end_row = 1

    def emit(text):
        out.append(text)

    try:
        tty.setraw(fd)
        fg, bg = (None, None) if no_query else query_default_colours(fd)
        try:
            columns = os.get_terminal_size(fd).columns
        except OSError:
            columns = 0

        def swapped_default(bold):
            if fg is None or bg is None:
                return None
            return ("1;" if bold else "") + "38;2;%d;%d;%d;48;2;%d;%d;%d" % (bg + fg)

        rows = [
            ("A", "ESC[7m  (default colours)", "7", swapped_default(False),
             "Ground in the default FOREGROUND colour, glyphs in the default BACKGROUND?"),
            ("B", "ESC[7;31;44m", "7;31;44", "34;41",
             "Left identical to right (the reference is ESC[34;41m)?"),
            ("C", "ESC[7;1m  (bold)", "7;1", swapped_default(True),
             "Compared with row A, does bold change the ground, the glyphs, or neither?"),
            ("D", "ESC[7;38;2;10;20;30;48;2;200;200;200m",
             "7;38;2;10;20;30;48;2;200;200;200", "38;2;200;200;200;48;2;10;20;30",
             "Left identical to right (the reference swaps the two 24-bit colours)?"),
            ("E", "extra: ESC[7;1;31;44m  (bold, named)", "7;1;31;44", "1;34;41",
             "Left identical to right? A difference is the host's bold treatment."),
        ]

        emit(RESET + CSI + "?25h" + CSI + "H" + CSI + "2J")
        emit(at(1, LABEL_COL) + "SGR 7 reverse-video card: judge by eye; nothing is recorded")
        emit(at(2, LABEL_COL) + "host: TERM_PROGRAM=%s %s  TERM=%s%s%s" % (
            os.environ.get("TERM_PROGRAM", "?"), os.environ.get("TERM_PROGRAM_VERSION", ""),
            os.environ.get("TERM", "?"),
            "  (inside tmux)" if os.environ.get("TMUX") else "",
            "  (inside GNU screen)" if os.environ.get("STY") else ""))
        if no_query:
            colour_line = "default colours: not asked (--no-query); rows A and C have no reference"
        elif fg is None or bg is None:
            colour_line = ("default colours: OSC 10 %s, OSC 11 %s; rows A and C have no reference"
                           % ("answered" if fg else "silent", "answered" if bg else "silent"))
        else:
            colour_line = "default colours from the host: OSC 10 fg %s, OSC 11 bg %s" % (fg, bg)
        emit(at(3, LABEL_COL) + colour_line)
        if columns and columns < MIN_COLUMNS:
            emit(at(4, LABEL_COL) + "window is %d columns; widen it to at least %d" % (
                columns, MIN_COLUMNS))
        emit(at(5, REV_COL) + "reversed" + at(5, REF_COL) + "reference")

        targets = {}
        row = 7
        for key, label, rev, ref, question in rows:
            emit(at(row, LABEL_COL) + key + "  " + label)
            emit(at(row, REV_COL) + CSI + rev + "m" + SAMPLE + RESET)
            if ref is None:
                emit(at(row, REF_COL) + "(no reference)")
            else:
                emit(at(row, REF_COL) + CSI + ref + "m" + SAMPLE + RESET)
            emit(at(row + 1, LABEL_COL + 3) + question)
            targets.setdefault(key, (row, REV_COL + 1))
            if key == "B":
                targets["B-ref"] = (row, REF_COL + 1)
            row += 3

        # F: erase to end of line while reversed. Only the label precedes it on
        # its line, so the erased tail is everything right of the sample.
        emit(at(row, LABEL_COL) + "F  extra: ESC[7m, text, then ESC[K")
        emit(at(row, REV_COL) + CSI + "7m" + SAMPLE + CSI + "K" + RESET)
        emit(at(row + 1, LABEL_COL + 3)
             + "Do the erased cells right of the sample take the reversed ground, or stay plain?")
        targets["F-tail"] = (row, REV_COL + len(SAMPLE) + 3)
        row += 3

        emit(at(row, LABEL_COL) + "G  extra: ESC[7m ... ESC[27m ...")
        emit(at(row, REV_COL) + CSI + "7m" + SAMPLE + CSI + "27m" + SAMPLE + RESET)
        emit(at(row + 1, LABEL_COL + 3) + "Left half reversed, right half plain?")
        row += 3

        emit(at(row, LABEL_COL) + "H  after ESC[0m")
        emit(at(row, REV_COL) + CSI + "7;31;44m" + CSI + "0m" + SAMPLE)
        emit(at(row + 1, LABEL_COL + 3) + "Plain, with no colour or reverse left over?")
        row += 3

        keyed = [("1", "A"), ("2", "B"), ("3", "B-ref"), ("4", "C"), ("5", "D"), ("6", "F-tail")]
        emit(at(row, LABEL_COL) + "Cursor targets: 1 = A reversed 'A'   2 = B reversed 'A'   "
             "3 = B reference 'A'")
        emit(at(row + 1, LABEL_COL) + "                4 = C reversed 'A'   5 = D reversed 'A'   "
             "6 = F erased tail")
        emit(at(row + 2, LABEL_COL) + "Is the cursor visible over a reversed cell, and does the "
             "cell under it stay readable?")
        emit(at(row + 4, LABEL_COL) + "Warp: enforce_minimum_contrast (default only_named_colors) "
             "may lighten a named")
        emit(at(row + 5, LABEL_COL) + "      foreground, so a mismatch in rows B or E may be that "
             "setting, not SGR 7.")
        status_row = row + 7
        end_row = row + 9
        keys_line = ("keys: 1-6 park the cursor, q quits" if hold is None
                     else "no keys: parked on target 1, exiting in %gs" % hold)
        emit(at(status_row, LABEL_COL) + keys_line)

        def park(number):
            name = dict(keyed)[number]
            r, c = targets[name]
            return at(status_row + 1, LABEL_COL) + CSI + "K" + "cursor on target %s (%s)" % (
                number, name) + at(r, c)

        emit(park("1"))
        os.write(fd, "".join(out).encode())

        if hold is not None:
            time.sleep(hold)
        else:
            while True:
                key = os.read(fd, 1)
                if key in (b"q", b"Q", b"\x03", b"\x04"):
                    break
                number = key.decode("latin-1")
                if number in dict(keyed):
                    os.write(fd, park(number).encode())
    finally:
        os.write(fd, (RESET + CSI + "?25h" + at(end_row, 1)).encode())
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        os.close(fd)
    print()


if __name__ == "__main__":
    main()
