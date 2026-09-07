#!/usr/bin/env bash
#
# The PTY half of the CI smoke test: drive both apps through a real terminal.
#
# `Stress --selfcheck` (run separately, on every CI lane including Windows)
# proves the render stack produces output, but it never opens a terminal. The
# crash classes that only appear in the interactive render loop — the
# 2026-07-17 debug-build stack overflow being the canonical one — are invisible
# to it and to the 3,000+ unit tests. This script is that net.
#
# POSIX only: tui_walk.py uses pty/termios/fcntl. A Windows equivalent needs
# ConPTY and does not exist yet, so the Windows lanes run --selfcheck alone.
#
# Usage: Tools/Smoke/ci-pty-smoke.sh [quick|full] [build-dir]
#
#   quick  (default) — a shallow walk, ~1 minute. Cheap enough to run on every
#                      CI lane, which is the point: an interactive-only crash
#                      that is specific to one Swift version or architecture
#                      still gets caught.
#   full             — every menu item, ~2 minutes. One lane per OS runs this.
#
# The split exists because tui_walk settles 0.25s after every keystroke, so the
# walk is bounded by keystrokes rather than by anything the app does. It used to
# return the cursor to the top between items, which made that cost grow with the
# SQUARE of the item count (34 items ~1,100 keystrokes, six minutes); it now
# carries on from where the page was opened, which is linear (~70 keystrokes,
# two minutes). The quick/full split is kept anyway: `quick` is a minute on
# every lane, and nine lanes of `full` would still be twenty minutes of runner
# time for the same signal.

set -euo pipefail

DEPTH="${1:-quick}"
BUILD_DIR="${2:-.build/debug}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
VENV="${TMPDIR:-/tmp}/tuikit-smoke-venv"

# `full` asks each app how many pages it has rather than carrying a literal.
# The literals drifted: Stress gained two scenarios and `STRESS_ITEMS` stayed at
# 19, so CI walked 19 of 21 and the `menus` and `kitchensink` pages went
# unsmoked for weeks. `quick` is a deliberately shallow walk, so its counts are
# literals on purpose.
case "$DEPTH" in
    quick) EXAMPLE_ITEMS=12; STRESS_ITEMS=6 ;;
    full)  EXAMPLE_ITEMS=""; STRESS_ITEMS="" ;;
    *)     echo "usage: $0 [quick|full] [build-dir]" >&2; exit 2 ;;
esac

# pyte is the screen reconstructor; a venv keeps this working on distros that
# mark the system Python externally-managed (PEP 668), which Ubuntu 24.04 does.
if [ ! -x "$VENV/bin/python" ]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --disable-pip-version-check pyte
fi

# Never the developer's — or the runner's — real preferences.
export TUIKIT_CONFIG_DIR="${TUIKIT_CONFIG_DIR:-${TMPDIR:-/tmp}/tuikit-smoke-config}"

# Item counts are entries in each app's top-level menu. An empty count means
# "ask the app": `Example --pages` prints `DemoPage.allCases.count` and
# `Stress --help` lists its scenario ids, both from the registry that defines
# them, so neither can fall behind the menu it describes.
page_count() {
    local binary="$1"
    case "$binary" in
        Example) "$REPO/$BUILD_DIR/Example" --pages ;;
        Stress)  "$REPO/$BUILD_DIR/Stress" --help | tail -1 | tr ',' '\n' | grep -c . ;;
    esac
}

walk() {
    local binary="$1" count="$2"
    if [ ! -x "$REPO/$BUILD_DIR/$binary" ]; then
        echo "error: $BUILD_DIR/$binary not built" >&2
        return 1
    fi
    if [ -z "$count" ]; then
        count="$(page_count "$binary")"
        # A derivation that silently yields nothing would walk zero items and
        # pass, which is the failure this replaced.
        case "$count" in
            ''|*[!0-9]*|0) echo "error: could not read $binary's page count" >&2; return 1 ;;
        esac
    fi
    echo "── PTY walk ($DEPTH): $binary, $count items ──"
    "$VENV/bin/python" "$HERE/tui_walk.py" "$REPO/$BUILD_DIR/$binary" "$count" --settle 0.5
}

cd "$REPO"
walk Example "$EXAMPLE_ITEMS"
walk Stress  "$STRESS_ITEMS"

# Two checks on the terminal handshake, both cheap (a couple of seconds each)
# and both guarding ORDERING that no type can enforce: the host must be
# identified, and mode 2027 negotiated, before RenderLoop is built, because its
# FrameDiffWriter freezes the advance model at construction. A unit test cannot
# see that; only a live run can. They ran nowhere until now.
echo "── identity: detection reaches the compensation ──"
"$VENV/bin/python" "$HERE/identity_smoke.py" "$REPO/$BUILD_DIR/Example"

echo "── mode 2027: pinned when needed, and only then ──"
"$VENV/bin/python" "$HERE/mode_pin_smoke.py" "$REPO/$BUILD_DIR/Example"

# A different class of check, and the only one that needs TWO processes: does a
# setting written in one launch come back in the next? The framework's storage
# layer has unit tests; what they cannot say is whether an app's own keys
# round-trip through a real exit. ~11 s, and `full` only — `quick` runs on
# every lane and is budgeted at about a minute.
#
# Its own config directory, NOT the exported one above: the probe's whole
# method is a fresh directory against a reused one, and it must not inherit a
# directory the walks have already written to.
if [ "$DEPTH" = "full" ]; then
    echo "── persistence: settings survive a relaunch ──"
    "$VENV/bin/python" "$HERE/persistence_probe.py" --binary "$REPO/$BUILD_DIR/Example"
fi

echo "PTY smoke ($DEPTH): both apps survived."
