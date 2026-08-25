#!/usr/bin/env python3
"""Measure a PTY TUI app's idle cost: CPU time and render output (bytes) over a
no-input window on a static screen.

The render loop should do nothing while nothing changes, so a static screen with
no input must approach 0% CPU and 0 bytes/s of render output. This is the probe
behind the "demand-driven animation clocks" work (see git log).

    swift build -c release --product Example -Xswiftc -g
    BIN="$(swift build -c release --product Example --show-bin-path)/Example"
    python3 Tools/Profiling/idle_cpu.py "$BIN" [settle_s] [window_s] [keys]

`keys` (optional) is sent after the settle delay to drive to another screen
first (e.g. "0" for the example's Spinners page); escapes like \\t and \\x1b are
interpreted. With no keys, it measures the initial screen.

Output: `CPU x.x%  bytes/s N` over the window. A static screen → ~0 / 0; an
animating screen (spinner, focused pulse, text cursor) → non-zero, continuously.
"""
import os, pty, sys, time, signal, threading, struct, fcntl, termios

binary = sys.argv[1]
settle = float(sys.argv[2]) if len(sys.argv) > 2 else 2.5
window = float(sys.argv[3]) if len(sys.argv) > 3 else 5.0
keys = sys.argv[4] if len(sys.argv) > 4 else ""

master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
pid = os.fork()
if pid == 0:  # child: become the controlling tty for `binary`
    try:
        os.close(master)
        os.setsid()
        fcntl.ioctl(slave, getattr(termios, "TIOCSCTTY", 0x20007461), 0)
        os.dup2(slave, 0); os.dup2(slave, 1); os.dup2(slave, 2)
        if slave > 2:
            os.close(slave)
        env = dict(os.environ); env["TERM"] = "xterm-256color"
        os.execve(binary, [binary], env)
    except Exception:
        pass
    os._exit(127)
os.close(slave)

received = {"bytes": 0}
stop = threading.Event()
def drain():  # read child output so it never blocks on a full pipe
    while not stop.is_set():
        try:
            d = os.read(master, 65536)
            if not d:
                break
            received["bytes"] += len(d)
        except OSError:
            break
threading.Thread(target=drain, daemon=True).start()

def keystrokes(data):
    """`data` split into one escape sequence or one byte at a time.

    An escape sequence has to travel whole — split across two writes it reaches
    the parser as a stray ESC and then as text — so ESC runs to the final byte
    of a CSI (`@` through `~`), or covers just the next byte for the two-byte
    forms (ESC O P, Alt-key).
    """
    index = 0
    while index < len(data):
        if data[index] != 0x1B or index + 1 >= len(data):
            yield data[index : index + 1]
            index += 1
            continue
        end = index + 1
        if data[end] in b"[O":
            end += 1
            while end < len(data) and not (0x40 <= data[end] <= 0x7E):
                end += 1
        yield data[index : end + 1]
        index = end + 1


def cputime_secs(p):
    out = __import__("subprocess").check_output(["ps", "-o", "cputime=", "-p", str(p)]).decode().strip()
    days = 0
    if "-" in out:
        ds, out = out.split("-", 1); days = int(ds)
    secs = 0.0
    for part in out.split(":"):
        secs = secs * 60 + float(part)
    return secs + days * 86400

try:
    time.sleep(settle)
    if keys:
        # One keystroke at a time, with a beat between them. Written as a single
        # burst they arrive in one read, and an app that renders per keystroke
        # then coalesces the lot into one frame — which is fine for "press 0 to
        # reach the spinners page" and wrong for anything whose later keys
        # depend on what the earlier ones drew (a Tab walk, or a mouse click at
        # a position that scrolling put there).
        for stroke in keystrokes(keys.encode().decode("unicode_escape").encode("latin-1")):
            os.write(master, stroke)
            time.sleep(0.12)
        time.sleep(1.2)
    t0, b0 = cputime_secs(pid), received["bytes"]
    time.sleep(window)
    t1, b1 = cputime_secs(pid), received["bytes"]
    print(f"CPU {(t1 - t0) / window * 100:4.1f}%   bytes/s {int((b1 - b0) / window):7d}   "
          f"(over {window:.0f}s, keys={keys!r})")
finally:
    stop.set()
    try:
        os.kill(pid, signal.SIGTERM); time.sleep(0.2); os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass
