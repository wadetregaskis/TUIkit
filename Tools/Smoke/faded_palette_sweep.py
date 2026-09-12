#!/usr/bin/env python3
"""Open every page of `Example` under a translucent palette, one process each.

A paint site that hands a translucent colour straight to the ANSI emitter trips
the assertion in `Color+ANSICodes.swift`, which in a debug build is a trap. Six
such sites were found this way (see §68 of `Documentation/Opacity as
composition.md`), none of which any audit of the list had ever had — a unit test
only covers the sites somebody thought of, and every re-count of those re-read
the same list.

Three things make this find what `ci-pty-smoke.sh` does not, and they are the
whole point of a separate script:

* **It pokes.** `tui_walk.py` steps a menu (`down*3,up` per item), and a
  `Picker`'s selected-value marker is not painted until the pop-up is OPENED. A
  walk that only navigates cannot see a control that has to be opened: run under
  the same fade, against a build with one of those fixes reverted on purpose, the
  walk reported every page alive and this sweep trapped on six.
* **One process per page.** A trap kills the app, so a single walk reports the
  FIRST bad page and stops. Sweeping separately gets the whole inventory in one
  run, which is what turns six traps into six fixes rather than six rounds.
* **stderr on its own pipe.** The walk reconstructs a screen with `pyte`, and a
  multi-line Swift backtrace interleaves into unreadable columns through it. Kept
  separate, it is verbatim — and the frame that matters is the first one that is
  neither the emitter nor generic layout, which is the paint site.

`ci-pty-smoke.sh full` runs this last, after the checks that answer in seconds,
because it is 7 min 15 s of the 11 min 23 s that `full` now measures — nearly all
of it settling between keystrokes, at 12% CPU. Worth running by hand after
touching a paint site rather than waiting for CI.

The system `python3` is enough: this reads raw bytes and reconstructs no screen,
so unlike `tui_walk.py` it needs no `pyte` and no virtualenv.

Usage: Tools/Smoke/faded_palette_sweep.py [build-dir] [alpha]
"""
import os
import pty
import re
import select
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TRAP = re.compile(r"(Assertion failed: [^\n]+|Fatal error: [^\n]+|Precondition failed: [^\n]+)")
FRAME = re.compile(r"(\S+)\s+\+ \d+ in Example at " + re.escape(REPO) + r"/(\S+\.swift:\d+)")
# Neither the emitter that trapped nor the layout that got there: the paint site.
NOT_THE_SITE = (
    "Color+ANSICodes", "ANSIRenderer", "Renderable.swift", "ChildInfo.swift",
    "HStack.swift", "VStack.swift", "ZStack.swift",
)
# Enough of a poke to draw what a page only shows once touched: a menu opened, a
# control focused, a value stepped. Not a substitute for the walk — a companion.
POKES = (b"\t", b"\t", b" ", b"\x1b[B", b" ", b"\x1b[C", b"\t", b" ", b"\x1b[A")


def visit(binary, index, alpha, config_root):
    """Open page `index`, poke it, and return (trap message, paint-site frames)."""
    master, slave = pty.openpty()
    error_read, error_write = os.pipe()
    process = subprocess.Popen(
        [binary], stdin=slave, stdout=slave, stderr=error_write,
        env={
            **os.environ,
            "TERM": "xterm-256color",
            # Never the developer's real preferences, and one directory per page so
            # a page that writes settings cannot steer the next one.
            "TUIKIT_CONFIG_DIR": os.path.join(config_root, f"page-{index}"),
            "TUIKIT_EXAMPLE_PALETTE_ALPHA": str(alpha),
            "SWIFT_BACKTRACE": "enable=yes,interactive=no",
        })
    os.close(slave)
    os.close(error_write)

    def settle(seconds):
        deadline = time.time() + seconds
        while time.time() < deadline:
            ready, _, _ = select.select([master], [], [], 0.05)
            if master in ready:
                try:
                    if not os.read(master, 65536):
                        return
                except OSError:
                    return

    try:
        settle(1.6)
        for _ in range(index):
            os.write(master, b"\x1b[B")
            settle(0.10)
        os.write(master, b"\r")
        settle(1.6)
        for key in POKES:
            os.write(master, key)
            settle(0.28)
        settle(1.2)
    except OSError:
        pass  # The app died; its stderr is read below.

    try:
        os.close(master)
    except OSError:
        pass
    try:
        process.wait(timeout=4)
    except subprocess.TimeoutExpired:
        # A page that did NOT trap is still running, which is the healthy case.
        process.kill()
        process.wait()

    chunks = []
    while True:
        try:
            block = os.read(error_read, 65536)
        except OSError:
            break
        if not block:
            break
        chunks.append(block)
    os.close(error_read)
    errors = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", b"".join(chunks).decode("utf-8", "replace"))
    trap = TRAP.search(errors)
    frames = [
        f"{location}  {function}" for function, location in FRAME.findall(errors)
        if not any(skip in location for skip in NOT_THE_SITE)
    ]
    return (trap.group(1) if trap else None), frames[:2]


def main():
    build_dir = sys.argv[1] if len(sys.argv) > 1 else ".build/debug"
    alpha = sys.argv[2] if len(sys.argv) > 2 else "0.5"
    binary = os.path.join(REPO, build_dir, "Example")
    if not os.access(binary, os.X_OK):
        print(f"error: {build_dir}/Example not built", file=sys.stderr)
        return 1
    # The app's own page registry, so this cannot fall behind the menu it walks —
    # the drift `ci-pty-smoke.sh` had when it carried the counts as literals. A
    # derivation that silently yielded nothing would sweep zero pages and pass,
    # which is the failure that replaced, so it is checked rather than trusted.
    counted = subprocess.run([binary, "--pages"], capture_output=True, text=True).stdout.strip()
    if not counted.isdigit() or int(counted) == 0:
        print(f"error: could not read Example's page count (got {counted!r})", file=sys.stderr)
        return 1
    pages = int(counted)
    config_root = os.path.join(os.environ.get("TMPDIR", "/tmp"), "tuikit-faded-sweep")
    print(f"── faded palette sweep: {pages} pages at alpha {alpha} ──")
    failures = 0
    for index in range(pages):
        trap, frames = visit(binary, index, alpha, config_root)
        if trap:
            failures += 1
            print(f"TRAP  page {index}: {trap}")
            for frame in frames:
                print(f"          {frame}")
        else:
            print(f"ok    page {index}")
        sys.stdout.flush()
    print(
        f"faded palette sweep: {failures} of {pages} pages trapped."
        if failures else f"faded palette sweep: all {pages} pages survived.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
