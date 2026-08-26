#!/usr/bin/env python3
"""The provenance every probe result needs to still mean something later.

A measurement is only interpretable together with the conditions it was taken
under, and this project has now been bitten twice by conditions that were not
recorded:

  * **Screen buffer.** iTerm2 and Warp advance some clusters differently on the
    primary and alternate screens. A number without `screen` is ambiguous, and
    an early iTerm2 model built from primary-screen readings declared the host
    free of a quirk it has.
  * **DEC mode 2027.** Every Ghostty number in the compatibility document was
    taken with grapheme clustering on — Ghostty's default, so never wrong, but
    never checked. Resetting it moves six of eleven measured classes, and the
    mode persists across processes, so a probe run can silently land in the
    other regime.

Both are now stamped, along with the date and the versions, so a result can be
re-read years later and either trusted or discarded on its own evidence.

**These stamps describe DSR advances.** DSR is a cursor *report*, and on Apple
Terminal it disagrees with the paint for ZWJ sequences — it claims 5, 8, 11
while the glyph composes into 2 cells and the row does not shear. So an advance
recorded here that disagrees with TUIkit's width claim is a hypothesis about
rendering, not a finding; confirm it with `visual_card.py` before compensating.
See Documentation/Terminal-compatibility.md, "ZWJ: where DSR lies".
"""
import datetime
import os
import platform
import select
import subprocess

ENV_KEYS = [
    "TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "COLORTERM",
    "TERM_SESSION_ID", "ITERM_SESSION_ID", "ITERM_PROFILE",
    "LC_TERMINAL", "LC_TERMINAL_VERSION", "TMUX", "TMUX_PANE",
    "COLORFGBG", "TERMINFO", "TERMINFO_DIRS", "__CFBundleIdentifier",
    "GHOSTTY_RESOURCES_DIR", "WT_SESSION", "KONSOLE_VERSION", "VTE_VERSION",
    "KITTY_PID", "ALACRITTY_SOCKET", "WEZTERM_PANE",
]

# DECRQM is `CSI ? Ps $ p` — a private-parameter marker AND an intermediate
# byte, which is exactly the shape Apple Terminal's parser refuses to consume:
# it prints the final `p`. In a probe that is worse than cosmetic, because the
# stray glyph moves the cursor and corrupts every DSR reading after it. So the
# question is asked only of hosts measured to swallow it.
_DECRQM_UNSAFE_TERM_PROGRAMS = {"Apple_Terminal"}


def _query_mode(fd, mode):
    """DECRPM value for `mode`, or None (silent, or unsafe to ask)."""
    if os.environ.get("TERM_PROGRAM") in _DECRQM_UNSAFE_TERM_PROGRAMS:
        return "not asked (Apple Terminal prints this query's final byte)"
    os.write(fd, b"\x1b[?%d$p\x1b[6n" % mode)     # fenced by DSR, which all answer
    got = b""
    while select.select([fd], [], [], 0.4)[0]:
        got += os.read(fd, 1024)
        if got.endswith(b"R"):
            break
    marker = b"\x1b[?%d;" % mode
    at = got.find(marker)
    if at < 0:
        return None                                # silent: no DECRQM here
    rest = got[at + len(marker):]
    digits = b""
    for byte in rest:
        if 0x30 <= byte <= 0x39:
            digits += bytes([byte])
        else:
            break
    if not digits:
        return None
    return {0: "not recognised", 1: "set", 2: "reset",
            3: "permanently set", 4: "permanently reset"}.get(int(digits), int(digits))


def _macos_app_version(bundle_path):
    try:
        return subprocess.run(
            ["defaults", "read", os.path.join(bundle_path, "Contents/Info.plist"),
             "CFBundleVersion"],
            capture_output=True, text=True, timeout=5).stdout.strip() or None
    except Exception:
        return None


def stamp(fd, probe, use_alt):
    """Provenance for one probe run. `fd` must already be in raw mode."""
    out = {
        "probe": probe,
        "measured": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "screen": "alternate" if use_alt else "primary",
        "os": f"{platform.system()} {platform.release()}",
        "machine": platform.machine(),
        "env": {k: os.environ.get(k) for k in ENV_KEYS if os.environ.get(k) is not None},
        # The precondition every Ghostty number depends on.
        "mode_2027_grapheme_clustering": _query_mode(fd, 2027),
        "method": "DSR cursor report — confirm any disagreement with visual_card.py",
    }
    if platform.system() == "Darwin":
        version = _macos_app_version("/System/Applications/Utilities/Terminal.app")
        if out["env"].get("TERM_PROGRAM") == "Apple_Terminal" and version:
            out["terminal_app_build"] = version
        try:
            out["os"] = "macOS " + subprocess.run(
                ["sw_vers", "-productVersion"], capture_output=True, text=True,
                timeout=5).stdout.strip()
        except Exception:
            pass
    return out
