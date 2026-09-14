#!/usr/bin/env python3
"""Measure how fast a page's animations ACTUALLY step, against what they ask for.

    animation_rate.py BIN [seconds] [--page spinners] [--warm 3] [--cols 140] [--rows 50]

Launches the app on a page (default: the Example's Spinners catalogue), decodes
its output with `pyte`, and records the moment every cell's character changes.
Adjacent animating cells on a row are one animation (a `.bouncing` track is nine
cells; an emoji spinner's second cell never changes). For each, it prints the
median interval between changes, and — when the word to its right names a
`SpinnerStyle` — that style's nominal interval, read from `Spinner.swift` so
the table cannot drift from the source, and the ratio of the two.

A ratio of 1.00 is a spinner stepping at its own rate. The same ratio well above
1 on EVERY style is a slow clock rather than slow spinners: the animation clock
losing time at each wake, not any one run asking for the wrong duration.

The nominal is the style's STANDARD interval: a literal in seconds, or
`AnimationClock.seconds(forTicks: n)`, read as n/60 s. A page that sets no speed
runs at `IndicatorAnimationSpeed.automatic`, which moves none of the standard
intervals, so on the Spinners page at its default speed every row should read
1.00.

Only CHARACTER changes are seen. A colour-only animation (a focused control's
breath, a faded tint) changes no cell's character and is invisible here, which
is also why a breathing focus ring does not pollute the spinner rows.

**pyte truncates at VS-16.** It abandons the rest of a write at a U+FE0F (width
0, combining class 0, no draw branch matches), so a row carrying an
emoji-presentation cluster such as ⚙️ looks truncated whatever the app sent —
see `Tools/Smoke/raw_probe.py`, which decodes nothing and is the tool for
anything involving those. None of the built-in spinner frames carries one; a
custom sequence might, and its row would then read wrong.

**pyte's character widths are not the app's either.** On the Spinners page the
`clock` spinner's faces shift the rest of their row on some frames, which shows
up as extra regions on that row with no name, a median of a few milliseconds
and no nominal (`nan`), and pulls `clock`'s own median down. Those rows are the
harness, not the app; they are left out of the summary line.

Needs `pyte`, like `page_open.py` and `Tools/Smoke/tui_walk.py`. The child runs
with `TUIKIT_CONFIG_DIR` set to a fresh temporary directory, removed afterwards;
the run is bounded by an alarm, and the child's process group is killed and
reaped on the way out.
"""
import argparse, fcntl, os, pathlib, pty, re, select, shutil, signal, statistics, struct, tempfile, termios, time
import pyte

parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
parser.add_argument("binary")
parser.add_argument("seconds", nargs="?", type=float, default=12.0, help="seconds measured")
parser.add_argument("--page", default="spinners", help="launch with `--page NAME`")
parser.add_argument("--warm", type=float, default=3.0, help="seconds ignored at startup")
parser.add_argument("--cols", type=int, default=140)
parser.add_argument("--rows", type=int, default=50)
parser.add_argument("--min-changes", type=int, default=12, help="fewer changes than this is not an animation")
args = parser.parse_args()


def nominal_intervals():
    """`SpinnerStyle.interval`, in ms, by case name — parsed from the source."""
    source = pathlib.Path(__file__).resolve().parents[2] / "Sources/TUIkit/Views/Spinner.swift"
    try:
        text = source.read_text()
    except OSError:
        return {}
    body = re.search(r"var interval: TimeInterval \{(.*?)\n    \}", text, re.S)
    if not body:
        return {}
    cases = re.findall(
        r"case \.(\w+)(?:\(.*?\))?: return (?:AnimationClock\.seconds\(forTicks: (\d+)\)|([0-9.]+))",
        body.group(1))
    return {name: int(ticks) * 1000 / 60 if ticks else float(seconds) * 1000
            for name, ticks, seconds in cases}


class Timeout(Exception):
    pass


def on_alarm(signum, frame):
    raise Timeout("animation_rate.py: run exceeded its time bound")


signal.signal(signal.SIGALRM, on_alarm)
signal.alarm(int(args.seconds + args.warm + 30))

config_dir = tempfile.mkdtemp(prefix="tuikit-animation-rate-")
pid, fd = pty.fork()
if pid == 0:
    env = dict(os.environ, TERM="xterm-256color", TUIKIT_CONFIG_DIR=config_dir,
               COLUMNS=str(args.cols), LINES=str(args.rows))
    os.execve(args.binary, [args.binary, "--page", args.page], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", args.rows, args.cols, 0, 0))

screen = pyte.Screen(args.cols, args.rows)
stream = pyte.ByteStream(screen)
changes = {}  # (row, col) -> [time of each change]
previous = None
start = time.monotonic()
try:
    while time.monotonic() - start < args.seconds + args.warm:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if not ready:
            continue
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        # Answer a cursor-position query, so startup does not wait on one.
        if b"\x1b[6n" in data:
            os.write(fd, b"\x1b[1;1R")
        now = time.monotonic() - start
        stream.feed(data)
        snapshot = [[screen.buffer[y][x].data for x in range(args.cols)] for y in range(args.rows)]
        if previous is not None and now > args.warm:
            for y in range(args.rows):
                if snapshot[y] != previous[y]:
                    for x in range(args.cols):
                        if snapshot[y][x] != previous[y][x]:
                            changes.setdefault((y, x), []).append(now)
        previous = snapshot
finally:
    signal.alarm(0)
    try:
        os.killpg(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass
    shutil.rmtree(config_dir, ignore_errors=True)

if previous is None:
    raise SystemExit("no output from the child")

nominal = nominal_intervals()
animating = sorted(cell for cell, times in changes.items() if len(times) >= args.min_changes)
# Adjacent animating cells on one row are one animation.
regions = []
for y, x in animating:
    if regions and regions[-1][0] == y and x - regions[-1][2] <= 1:
        regions[-1][2] = x
    else:
        regions.append([y, x, x])

print(f"{'row':>3} {'col':>3}  {'name':<18} {'changes':>7} {'median ms':>9} {'nominal':>7} {'ratio':>6}")
ratios = []
for y, first, last in regions:
    instants = sorted({t for x in range(first, last + 1) for t in changes.get((y, x), [])})
    gaps = [b - a for a, b in zip(instants, instants[1:])]
    if not gaps:
        continue
    median = statistics.median(gaps) * 1000
    words = "".join(previous[y][last + 1:]).split()
    name = re.sub(r"\(.*", "", words[0]) if words else "?"
    expected = nominal.get(name)
    ratio = median / expected if expected else None
    if ratio is not None:
        ratios.append(ratio)
    print(f"{y:>3} {first:>3}  {name:<18} {len(instants):>7} {median:>9.1f} "
          f"{expected if expected else float('nan'):>7.0f} {ratio if ratio else float('nan'):>6.2f}")
if ratios:
    print(f"median ratio {statistics.median(ratios):.3f} over {len(ratios)} named animations "
          f"(min {min(ratios):.3f}, max {max(ratios):.3f})")
