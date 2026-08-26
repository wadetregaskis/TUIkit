#!/usr/bin/env python3
"""Terminal IDENTITY probe: asks the terminal who it is, over escape sequences
rather than environment variables.

Why this exists: `TERM_PROGRAM` is how TUIkit recognises its host, and ssh does
not forward it (OpenSSH sends `LANG` and `LC_*` only). A TUIkit app reached over
ssh therefore sees an unidentified terminal and applies NO cursor-advance
compensation, which shifts every row carrying an under-advancing cluster — the
exact class of bug `Documentation/Terminal-compatibility.md` exists to record.
An escape query has no such problem: it is answered by the terminal itself, at
the far end of however many hops.

Each query is FENCED with a DSR cursor-position request (`ESC[6n`), which every
terminal answers. Reading until the DSR reply arrives means an unanswered query
reports an empty answer instead of blocking forever — the interesting result for
Terminal.app, which answers no XTVERSION.

Run INSIDE the terminal under test, once per terminal you have. Writes JSON to
$PROBE_OUT (default: ./identity_probe.json) and a summary to the screen.
"""
import json, os, select, sys, termios, tty

# Each query, and what its reply looks like. The reply is whatever arrives
# before the fence's DSR answer, so the terminator is documentation, not code.
QUERIES = [
    ("DA1", b"\x1b[c", "Primary Device Attributes — ESC[?…c"),
    ("DA2", b"\x1b[>c", "Secondary Device Attributes — ESC[>…c"),
    ("DA3", b"\x1b[=c", "Tertiary Device Attributes — DCS!|…ST"),
    ("XTVERSION", b"\x1b[>0q", "Terminal name and version — DCS>|…ST"),
    ("XTGETTCAP_TN", b"\x1bP+q544e\x1b\\", "terminfo 'TN' (terminal name) — DCS…ST"),
]

FENCE = b"\x1b[6n"          # answered by every terminal: ESC[<row>;<col>R
FENCE_TIMEOUT = 1.5         # seconds to wait for the fence before giving up


def ask(fd, query):
    """Send `query`, then the fence, and return everything that came back before
    the fence's reply. `None` if even the fence went unanswered."""
    os.write(fd, query + FENCE)
    buf = b""
    while True:
        ready, _, _ = select.select([fd], [], [], FENCE_TIMEOUT)
        if not ready:
            return None
        buf += os.read(fd, 1024)
        # The fence's reply is the last CSI ending in 'R'.
        if buf.endswith(b"R") and b"\x1b[" in buf:
            break
    cut = buf.rfind(b"\x1b[")
    return buf[:cut]


def render(raw):
    """A reply as printable text, with the C0/C1 controls spelled out."""
    if raw is None:
        return "<no answer — even the fence timed out>"
    if raw == b"":
        return "<silent>"
    out = ""
    for byte in raw:
        if byte == 0x1B:
            out += "<ESC>"
        elif byte < 0x20 or byte == 0x7F:
            out += f"<{byte:02X}>"
        else:
            out += chr(byte)
    return out


ENV_KEYS = [
    "TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "COLORTERM",
    "TERM_SESSION_ID", "ITERM_SESSION_ID", "LC_TERMINAL", "LC_TERMINAL_VERSION",
    "TMUX", "TMUX_PANE", "GHOSTTY_RESOURCES_DIR", "WARP_TERMINAL_SESSION_UUID",
    "SSH_CONNECTION", "SSH_TTY", "__CFBundleIdentifier",
]


def main():
    out_path = os.environ.get("PROBE_OUT", "identity_probe.json")
    fd = sys.stdin.fileno()
    if not os.isatty(fd):
        sys.exit("identity_probe: stdin is not a terminal — run this IN the terminal under test")
    old = termios.tcgetattr(fd)
    answers = {}
    try:
        tty.setraw(fd)
        for name, query, _ in QUERIES:
            answers[name] = ask(fd, query)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    env = {k: os.environ.get(k) for k in ENV_KEYS if os.environ.get(k) is not None}
    record = {
        "environment": env,
        "answers": {
            name: {
                "query": query.decode("latin-1").replace("\x1b", "<ESC>"),
                "reply": render(answers[name]),
                "raw": answers[name].decode("latin-1") if answers[name] else "",
                "what": what,
            }
            for name, query, what in QUERIES
        },
    }
    with open(out_path, "w") as f:
        json.dump(record, f, indent=2, ensure_ascii=False)

    print(f"TERM_PROGRAM = {env.get('TERM_PROGRAM', '<unset>')}"
          f"    TERM = {env.get('TERM', '<unset>')}"
          f"    over ssh: {'yes' if 'SSH_TTY' in env else 'no'}")
    for name, _, what in QUERIES:
        print(f"  {name:<13} {render(answers[name])}")
        print(f"  {'':<13} ({what})")
    print(f"\nwritten to {out_path}")


if __name__ == "__main__":
    main()
