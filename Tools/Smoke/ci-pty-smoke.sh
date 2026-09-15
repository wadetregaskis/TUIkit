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
#   full             — every menu item, plus the persistence probe and the
#                      faded-palette sweep: ~11.5 minutes measured, of which the
#                      sweep is 7.25. One lane per OS runs this.
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

# The same class, for the colour exchange: the terminal's colours are asked
# once, with the request its host needs, and published before RenderLoop draws
# its first frame. Five short runs, about twenty seconds (18.7 s measured).
echo "── colours: asked before the first frame ──"
"$VENV/bin/python" "$HERE/colour_query_smoke.py" "$REPO/$BUILD_DIR/Example"

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

# Last, because it is far and away the most expensive thing here — 7 min 15 s of
# the 11 min 23 s `full` now measures, against about four for everything above,
# and everything above gives its signal in seconds.
#
# A different failure class again: a paint site that hands a TRANSLUCENT colour
# straight to the ANSI emitter trips the assertion in `Color+ANSICodes.swift`,
# which in a debug build is a trap. Six such sites shipped past the whole unit
# suite and past three re-counts of the ledger meant to list them, because every
# one of those re-read the same list (§68 of `Documentation/Opacity as
# composition.md`). Only running the app finds the site nobody wrote down.
#
# NOT a walk, and that distinction is the whole reason this is a second script
# rather than `walk Example … ` with the fade exported. A walk was tried: with
# one of those six fixes reverted on purpose it reported every page alive, while
# the sweep trapped on six. `tui_walk.py` steps a menu, and a `Picker`'s selected
# marker is not painted until the pop-up is OPENED — a walk that only navigates
# cannot see a control that has to be opened, so under a fade it proves only that
# the pages draw at rest. The sweep pokes each page, and runs one process per
# page so that a trap (which kills the app) reports the whole inventory instead
# of only the first one.
#
# Run through the venv's interpreter for one interpreter across `Tools/Smoke`,
# though unlike the walk this one needs no `pyte` and would run under any
# `python3`.
if [ "$DEPTH" = "full" ]; then
    "$VENV/bin/python" "$HERE/faded_palette_sweep.py" "$BUILD_DIR"
fi

echo "PTY smoke ($DEPTH): both apps survived."
