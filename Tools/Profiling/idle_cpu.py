#!/usr/bin/env python3
"""Measure a PTY TUI app's idle cost: CPU time and render output (bytes) over a
no-input window on a static screen.

The render loop should do nothing while nothing changes, so a static screen with
no input must approach 0% CPU and 0 bytes/s of render output. This is the probe
behind the "demand-driven animation clocks" work (see git log).

    swift build -c release --product TUIkitExample -Xswiftc -g
    BIN="$(swift build -c release --product TUIkitExample --show-bin-path)/TUIkitExample"
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
        os.write(master, keys.encode().decode("unicode_escape").encode("latin-1"))
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
