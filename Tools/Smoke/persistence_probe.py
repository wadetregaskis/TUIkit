#!/usr/bin/env python3
"""Do the app's own `@AppStorage` settings survive a relaunch?

The framework's storage layer has unit tests; what those cannot say is whether
an app's settings actually round-trip — whether the key a view writes is the
key it reads on the next launch, and whether anything is flushed before the
process exits. That needs two processes and a config directory that outlives
the first, which is what this does.

The subject is the track-style editor (the Slider and Progress pages share
one), and specifically its "Colour gradient" toggle: it defaults to off, it is
one keypress to flip, and its state is legible on screen.

Three runs, because two cannot tell "it persisted" from "it always looks like
that":

  1. a FRESH config directory — the toggle reads its default;
  2. flip it, quit, and relaunch on the SAME directory — it reads flipped;
  3. a fresh directory again — it reads the default once more.

Run 3 is the control. Without it a view that ignored its stored value and
always drew "on" would pass.

Usage:  persistence_probe.py [--binary PATH] [--keep]
Exit 0 if the setting persisted and the control held, 1 otherwise.
"""
import argparse
import fcntl
import os
import pty
import select
import shutil
import struct
import sys
import termios
import time

import pyte

COLS, ROWS = 110, 34

# The Sliders page, counted down the main menu (which omits the menu itself).
SLIDERS_MENU_INDEX = 13

# The toggle's English label, from `component.trackEditor.gradient`.
TOGGLE_LABEL = "Colour gradient"

# What a `Toggle` draws when it is on, and when it is off.
CHECKED, UNCHECKED = "■", "□"


class App:
    """One run of the Example, on a config directory the caller owns."""

    def __init__(self, binary, config_dir):
        self.screen = pyte.Screen(COLS, ROWS)
        self.stream = pyte.ByteStream(self.screen)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.environ["TUIKIT_CONFIG_DIR"] = config_dir
            os.environ["TERM"] = "xterm-256color"
            os.execv(binary, [binary])
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))

    def drain(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select([self.fd], [], [], 0.02)
            if not ready:
                continue
            try:
                self.stream.feed(os.read(self.fd, 65536))
            except OSError:
                return

    def key(self, sequence, wait=0.2):
        os.write(self.fd, sequence)
        self.drain(wait)

    def line_containing(self, text):
        for index, line in enumerate(self.screen.display):
            if text in line:
                return index, line
        return None, None

    def to_track_editor(self):
        """Launch → the Sliders page, scrolled to the editor's toggles."""
        self.drain(1.5)
        self.key(b"\x1b[B" * SLIDERS_MENU_INDEX, 0.5)
        self.key(b"\r", 1.2)
        # Tab through the page until the toggle is on screen. The editor is
        # well below the fold, and tabbing is what scrolls it into view.
        for _ in range(40):
            row, _ = self.line_containing(TOGGLE_LABEL)
            if row is not None:
                return row
            self.key(b"\t", 0.12)
        return None

    def click(self, column, row, wait=0.35):
        for suffix in (b"M", b"m"):
            os.write(self.fd, b"\x1b[<0;%d;%d%s" % (column + 1, row + 1, suffix))
            self.drain(0.05)
        self.drain(wait)

    def quit(self):
        # Escape first: `q` quits from the MENU, and on a page it is a
        # character — which a focused text field would happily accept.
        self.key(b"\x1b", 0.4)
        self.key(b"q", 0.6)
        # `waitpid`, NOT `kill(pid, 0)`: an exited child of this process is a
        # zombie until it is reaped, and signalling a zombie SUCCEEDS. The
        # first version of this probe used `kill` and reported a cleanly
        # exiting app as "still running" every time. `tui_walk.py` has always
        # got this right; this is why.
        for _ in range(60):
            finished, _ = os.waitpid(self.pid, os.WNOHANG)
            if finished == self.pid:
                return True
            time.sleep(0.05)
        self.kill()
        return False

    def kill(self):
        try:
            os.kill(self.pid, 9)
        except ProcessLookupError:
            pass
        try:
            os.waitpid(self.pid, 0)
        except ChildProcessError:
            pass


def toggle_is_on(app, row):
    """Whether the toggle at `row` is checked.

    Read from the FIRST box on the line, not from "is there a checked box
    anywhere on it": the editor puts several toggles on one row, and the ones
    after this are not the subject.
    """
    line = app.screen.display[row]
    marks = [c for c in line if c in (CHECKED, UNCHECKED)]
    return bool(marks) and marks[0] == CHECKED


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", default=".build/debug/Example")
    parser.add_argument("--keep", action="store_true", help="leave the config dirs behind")
    args = parser.parse_args()

    base = os.path.join(os.environ.get("TMPDIR", "/tmp"), f"tuikit-persistence-{os.getpid()}")
    shared = os.path.join(base, "shared")
    control = os.path.join(base, "control")
    os.makedirs(shared, exist_ok=True)
    os.makedirs(control, exist_ok=True)
    failures = []

    try:
        # 1. Fresh directory: the default.
        app = App(args.binary, shared)
        row = app.to_track_editor()
        if row is None:
            print(f"!! never found {TOGGLE_LABEL!r} on the Sliders page")
            app.kill()
            return 2
        before = toggle_is_on(app, row)
        print(f"run 1 (fresh)   line {row}: {app.screen.display[row].strip()[:60]!r}")
        if before:
            failures.append("the toggle did not start at its default (off)")

        # 2. Flip it with the POINTER. Tabbing until the label appears finds
        #    the row, not the focus — the label scrolls into view several
        #    controls before it is the focused one — and a Space that lands in
        #    a text field types a space instead.
        column = app.screen.display[row].index(UNCHECKED)
        app.click(column, row)
        after = toggle_is_on(app, row)
        print(f"run 1 (flipped) line {row}: {app.screen.display[row].strip()[:60]!r}")
        if not after:
            failures.append("Space did not flip the toggle, so nothing was stored")
        clean = app.quit()
        if not clean:
            failures.append("the app did not exit on `q`; storage may not have been flushed")

        # 3. Same directory: it must come back flipped.
        app = App(args.binary, shared)
        row = app.to_track_editor()
        restored = row is not None and toggle_is_on(app, row)
        print(f"run 2 (same)    line {row}: "
              f"{app.screen.display[row].strip()[:60]!r}" if row is not None else "run 2: not found")
        if not restored:
            failures.append("the setting did not survive the relaunch")
        app.kill()

        # 4. The control: a fresh directory must read the default again, or
        #    run 3 proves nothing about storage.
        app = App(args.binary, control)
        row = app.to_track_editor()
        fresh = row is not None and toggle_is_on(app, row)
        print(f"run 3 (control) line {row}: "
              f"{app.screen.display[row].strip()[:60]!r}" if row is not None else "run 3: not found")
        if fresh:
            failures.append("a FRESH config directory also read as flipped — "
                            "the view is not reading its stored value at all")
        app.kill()
    finally:
        if not args.keep:
            shutil.rmtree(base, ignore_errors=True)

    print()
    for failure in failures:
        print(f"FAIL: {failure}")
    if not failures:
        print("PASS: the setting persisted across a relaunch, and a fresh directory did not")
    return 1 if failures else 0


sys.exit(main())
