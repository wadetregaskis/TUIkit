#!/usr/bin/env python3
"""Walk a TUIkit app's menu in a real PTY, visiting every item and checking
the process stays alive and keeps painting.

Usage:
  tui_walk.py <binary> <item-count> [--per-item KEYS] [--cols N] [--rows N]
              [--scale N]

Visits item i (for i in 0..<count) as: Down×i, Enter, wait, [KEYS], Esc.
KEYS is a comma list of: down, up, enter, esc, tab, space, or wait<seconds>,
each optionally repeated as `down*5`. The child runs with an isolated
TUIKIT_CONFIG_DIR (never the user's real preferences) and TERM=xterm-256color.

Exit code: 0 if the app survived every visit, 1 otherwise (the failing item
index and final screen are printed). This is the standing regression net for
crash classes unit tests cannot see — e.g. the Deep Recursion debug-build
stack overflow of 2026-07-17, which only manifested in the interactive
render loop, in a specific build state, and never under --selfcheck.
"""
import argparse
import fcntl
import os
import pty
import select
import struct
import sys
import termios
import time

import pyte

SEQUENCES = {
    "down": "\x1b[B", "up": "\x1b[A", "left": "\x1b[D", "right": "\x1b[C",
    "enter": "\r", "esc": "\x1b", "tab": "\t", "space": " ",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    parser.add_argument("count", type=int)
    parser.add_argument("--per-item", default="down*3,up")
    parser.add_argument("--from-top", action="store_true",
                        help="return the menu cursor to the top between items "
                             "(the original O(n^2) walk, kept as the check on "
                             "the incremental one)")
    parser.add_argument("--cols", type=int, default=140)
    parser.add_argument("--rows", type=int, default=42)
    parser.add_argument("--scale", type=int, default=0)
    parser.add_argument("--settle", type=float, default=1.0)
    parser.add_argument("--paint-timeout", type=float, default=10.0,
                        help="how long the app may take to act on a keystroke "
                             "before the walk calls it stuck (see settled_change); "
                             "only a failing walk, and the Down at the bottom of "
                             "the menu, ever waits it out")
    args = parser.parse_args()

    screen = pyte.Screen(args.cols, args.rows)
    stream = pyte.ByteStream(screen)
    config_dir = os.path.join(
        os.environ.get("TMPDIR", "/tmp"), "tuikit-smoke-config")

    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TUIKIT_CONFIG_DIR"] = config_dir
        os.environ["TERM"] = "xterm-256color"
        if args.scale:
            os.environ["TUIKIT_STRESS_SCALE"] = str(args.scale)
        os.execv(args.binary, [args.binary])

    fcntl.ioctl(fd, termios.TIOCSWINSZ,
                struct.pack("HHHH", args.rows, args.cols, 0, 0))

    def alive() -> bool:
        finished, _ = os.waitpid(pid, os.WNOHANG)
        return finished == 0

    def pump(seconds: float) -> bool:
        end = time.time() + seconds
        ok = True
        while time.time() < end:
            readable, _, _ = select.select([fd], [], [], 0.1)
            if fd in readable:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    ok = False
                    break
                if not data:
                    ok = False
                    break
                stream.feed(data)
        return ok and alive()

    def send(token: str) -> bool:
        if token.startswith("wait"):
            return pump(float(token[4:]))
        reps = 1
        if "*" in token:
            token, count = token.split("*")
            reps = int(count)
        for _ in range(reps):
            os.write(fd, SEQUENCES[token].encode())
            if not pump(0.25):
                return False
        return True

    def dump_screen() -> None:
        for index, line in enumerate(screen.display):
            text = line.rstrip()
            if text:
                print(f"{index:3}| {text}")

    def snapshot() -> tuple:
        """What the terminal is showing, as a comparable value.

        Colour and reverse-video are part of it, not decoration. `screen
        .display` is text only, and a menu highlight that moves by recolouring
        a row — which is what the Example's does, having no marker glyph —
        changes not one character of it. Compared on text alone the walk
        concluded the cursor had not moved, and stopped after a single item
        believing it had reached the end of a thirty-five item menu.
        """
        return tuple(
            tuple(
                (cell.data, cell.fg, cell.bg, cell.reverse, cell.bold)
                for cell in (screen.buffer[y][x] for x in range(screen.columns))
            )
            for y in range(screen.lines)
        )

    def layout() -> tuple:
        """What the screen shows, without the colours it is breathing through.

        The text, and which rows are singled out: a row whose cells' fills
        match no other row's is the highlighted one. A menu's cursor row
        BREATHES — its fill steps between two colours every few frames — so a
        full snapshot changes whether or not a Down moved anything, and read
        that way the walk never found the bottom of the menu: it walked 40
        "items" of the Example's 34, re-opening the last page six times. Which
        row is singled out does not change while it breathes, and does when the
        cursor moves.
        """
        signatures = [
            frozenset((cell.bg, cell.reverse) for cell in (screen.buffer[y][x] for x in range(screen.columns)))
            for y in range(screen.lines)
        ]
        counts = {}
        for signature in signatures:
            counts[signature] = counts.get(signature, 0) + 1
        singled = tuple(y for y, signature in enumerate(signatures) if counts[signature] == 1)
        return (tuple(screen.display), singled)

    def settled_change(before: tuple, look=None) -> bool:
        """Whether the screen has changed since `before`, waiting to be sure.

        `send` pumps a fixed quarter second, which is plenty to deliver a
        keystroke and not always enough for the app to finish repainting: the
        Example's menu answered a Down more slowly than that, and a snapshot
        taken on the quarter second looked identical to the one before it. Read
        as "nothing moved" that is a walk which stops at the first item and
        calls it the end of the menu — which is exactly what it did.

        So an unchanged screen is a question, not an answer, and it is asked
        again until `--paint-timeout` runs out. **Polled to a deadline, not
        asked once more**, because one more look is still a fixed window and a
        fixed window is still a race the slowest page can lose: `Stress`'s
        Gradients page needs between 1.25 s and 1.75 s for its first paint in a
        DEBUG build, and the smoke's `--settle 0.5` gave it 1.25 s, so the walk
        called a page that paints perfectly well "stopped painting". The
        threshold sat right where the machine's speed decided the answer.

        Only the negative path waits, so this costs nothing on the
        item-by-item walk: a Down that moved and an Enter that opened both
        return on the first look. The one place that legitimately sees no
        change is the bottom of the menu, which pays the deadline once, at the
        end of the walk.
        """
        look = look or snapshot
        end = time.time() + args.paint_timeout
        while True:
            if look() != before:
                return True
            if time.time() >= end:
                return False
            # A dead child will never repaint, so stop looking rather than
            # burning the whole deadline — the caller's own `ok` reports it.
            if not pump(min(args.settle, end - time.time())):
                return look() != before

    if not pump(1.5):
        print("FAIL: app died before the menu appeared")
        dump_screen()
        return 1

    def title() -> str:
        """The title row: the menu's own while the menu shows, a page's while
        one does — what says which of the two the app is showing."""
        return screen.display[1]

    def waited(condition, since: float) -> tuple:
        """Polls `condition` to the paint deadline: whether it came true, and
        how long after `since` (the keystroke) it had."""
        start = since
        end = time.time() + args.paint_timeout
        while not condition():
            if time.time() >= end or not pump(min(0.05, end - time.time())):
                return condition(), time.time() - start
        return True, time.time() - start

    def steady_title() -> str:
        """The title row once it has held still for 0.3 s (to the paint
        deadline): a frame can reach the terminal split across reads, and a
        slow app's title row read mid-frame is half of one."""
        end = time.time() + args.paint_timeout
        seen = title()
        while time.time() < end:
            if not pump(0.3):
                break
            if title() == seen:
                break
            seen = title()
        return seen

    # The menu's title row, learned on the first return from a page rather
    # than read before the first Enter: until something redraws them, the
    # first rows hold the graphics probe's reply, which pyte draws as text —
    # and under load the app may not have redrawn them for seconds.
    menu_title = None

    walked = 0
    for item in range(args.count):
        ok = True
        # ONE Down per item, not `item` of them: escaping a page leaves the menu
        # cursor on the row it was opened from, so the walk carries on from
        # there. That makes it O(n) keystrokes instead of O(n^2) — at 35 items
        # and a 0.25 s settle, ~70 rather than ~1,200, and the Example's walk
        # went from six minutes to two. `--from-top` restores the old walk; the
        # two were compared page-title for page-title over the whole menu (see
        # `tui_screens.py`, which captures the titles) before this became the
        # default.
        #
        # Whether the LAST of those Downs moved anything is how the walk knows
        # it has reached the bottom of the menu, so `count` can be an upper
        # bound instead of an exact tally that goes stale. It is the exact
        # tally that failed: CI walked 19 of Stress's 21 scenarios, having
        # never been raised when two were added, so the `menus` and
        # `kitchensink` pages were silently not smoked at all.
        downs = item if args.from_top else min(item, 1)
        moved = item == 0
        for index in range(downs):
            before = layout()
            ok = ok and send("down")
            if index == downs - 1:
                moved = settled_change(before, look=layout)

        # Opening the page must show the page — its title on the title row,
        # where the menu's was. That is worth asserting on every item rather
        # than trusting the process to be alive, because `alive()` is true of
        # an app that has wedged and stopped drawing — the whole hang/livelock
        # class used to walk green. It is also what tells a wedged app apart
        # from the end of the menu: both leave the screen unchanged after a
        # Down, and only one of them still opens a page here.
        #
        # The title row and nothing looser. A walk that took ANY change of
        # screen for the page opening (a breathing cursor row, the previous Esc
        # landing late) could drift out of step with the app — send the next
        # item's keys into a page it had not left, and blame an Enter for what
        # an Esc failed to do. It did exactly that on every Linux lane for three
        # days (2026-09-29 to 10-01), reporting "Enter changed nothing" at the
        # item AFTER the page the app had gone deaf on (a stdin source that
        # cancelled itself; see `StdinArrivalNotifier.handleReadable`). The
        # latencies are printed so a slow lane says how slow, and a deaf app is
        # not mistaken for one: CI's answer in ~300 ms.
        showing = title()
        sent = time.time()
        ok = ok and send("enter")
        opened, open_latency = waited(lambda: title() != showing, since=sent)
        page_title = steady_title()
        for token in args.per_item.split(","):
            if token:
                ok = ok and send(token)
        # Esc, and nothing more until the menu is back. A lone ESC and a key
        # sent after it are two keystrokes only if the app reads them apart; an
        # app still busy with the page it is leaving reads them together, and
        # `ESC ESC [ B` is Alt+Down, not Esc then Down (2026-09-29, four lanes;
        # reproduced here by writing ESC ESC [ A at once). What says the Esc
        # was read is the menu's title back on the title row — not any change
        # of screen, which a blinking caret makes whether or not the Esc was
        # read.
        sent = time.time()
        ok = ok and send("esc")
        if menu_title is None:
            back, back_latency = waited(lambda: title() != page_title, since=sent)
            menu_title = steady_title()
        else:
            back, back_latency = waited(lambda: title() == menu_title, since=sent)
        if args.from_top:
            # Return the selection to the top for the next item's Down-walk.
            for _ in range(item):
                ok = ok and send("up")
        if not ok:
            print(f"FAIL: app died while visiting item {item}")
            dump_screen()
            return 1
        if not opened:
            print(f"FAIL: app stopped painting at item {item} — Enter showed no page in {open_latency:.1f}s")
            dump_screen()
            return 1
        if not back:
            print(f"FAIL: Esc did not return to the menu from item {item} in {back_latency:.1f}s")
            dump_screen()
            return 1
        if not moved:
            # The Down before this visit changed nothing and the app is
            # demonstrably still painting, so the cursor was already on the
            # last row: this visit re-opened the previous page and is not a
            # new item. Worth the couple of seconds it cost — re-opening it is
            # what proved the app was still painting rather than wedged.
            print(f"reached the end of the menu after {walked} items", flush=True)
            break
        walked += 1
        print(f"ok item {item}  (opened in {open_latency * 1000:.0f} ms, back in {back_latency * 1000:.0f} ms)", flush=True)

    os.write(fd, b"q")
    pump(0.3)
    try:
        os.kill(pid, 9)
    except ProcessLookupError:
        pass
    os.waitpid(pid, 0)
    print(f"walked {walked} items: all alive")
    return 0


if __name__ == "__main__":
    sys.exit(main())
